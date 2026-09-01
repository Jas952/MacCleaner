import Foundation
import IOKit

// MARK: - Chip detection

private let isAppleSilicon: Bool = {
    var val = 0
    var size = MemoryLayout<Int>.size
    sysctlbyname("hw.optional.arm64", &val, &size, nil, 0)
    return val != 0
}()

// MARK: - SMC keys

private struct SMCKey {
    static let fanCount      = "FNum"
    static let fanActualRPM  = "F%dAc"
    static let fanMinRPM     = "F%dMn"
    static let fanMaxRPM     = "F%dMx"
    static let fanTargetRPM  = "F%dTg"
    static let fanSafeRPM    = "F%dSf"
    static let fanMode       = "FS! "
    // Apple Silicon exposes the same fan data keys through AppleSMC, but the
    // mode key is firmware-dependent. Probe both spellings at runtime.
    static let appleSiliconModeUpper = "F%dMd"
    static let appleSiliconModeLower = "F%dmd"
    static let appleSiliconForceTest = "Ftst"
    static let cpuTemp       = "TC0P"
    static let cpuDieTemp    = "TC0D"
    static let gpuTemp       = "TG0P"
    static let batteryTemp   = "TB0T"
    static let socTemp       = "Tpcd"
    static let cpuProximity  = "TCP0"
}

// MARK: - Models

struct FanInfo: Identifiable {
    let id: Int
    var actualRPM: Int
    let minRPM: Int
    let maxRPM: Int
    let safeRPM: Int
    var targetRPM: Int

    var percentOfMax: Double {
        guard maxRPM > 0 else { return 0 }
        return Double(actualRPM) / Double(maxRPM)
    }
    var label: String { id == 0 ? "Left Side" : "Right Side" }
}

/// Decodes the numeric formats returned by AppleSMC. Apple Silicon fan keys
/// use native little-endian IEEE-754 floats, while Intel fan keys commonly use
/// big-endian 14.2 fixed point (`fpe2`).
enum SMCNumericDecoder {
    static func decode(dataType: String, bytes: [UInt8]) -> Float {
        guard !bytes.isEmpty else { return 0 }
        switch dataType {
        case "flt ":
            guard bytes.count >= 4 else { return 0 }
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Float(bitPattern: bits)
            return value.isFinite ? value : 0
        case "fpe2":
            guard bytes.count >= 2 else { return 0 }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Float(raw) / 4
        case "ui8 ":
            return Float(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return 0 }
            return Float(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return 0
        }
    }
}

enum SensorCategory: String {
    case airflow  = "Airflow"
    case cpuCore  = "CPU Cores"
    case soc      = "SoC / GPU"
    case storage  = "Storage"
    case battery  = "Battery"
    case other    = "Other"
}

struct SensorReading: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let category: SensorCategory
}

struct ThermalInfo {
    var cpuTemp: Double          = 0
    var gpuTemp: Double          = 0
    var batteryTemp: Double      = 0
    var socTemp: Double          = 0
    var sensors: [SensorReading] = []
}

// MARK: - Legacy SMC I/O

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

// Exact 80-byte layout matching Apple's SMCParamStruct. Keeping the nested
// structs is significant: flattening these fields changes Swift's alignment
// and shifts `data8`/`bytes`, making every hardware read appear empty.
private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPowerLimitData()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) = (
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_WRITE_BYTES: UInt8 = 6
private let SMC_CMD_READ_KEYINFO: UInt8 = 9

// MARK: - SMCService

final class SMCService {
    static let shared = SMCService()
    static let protocolDataStride = MemoryLayout<SMCKeyData>.stride
    private var conn: io_connect_t = 0
    private(set) var isOpen = false

    private init() { open() }
    deinit { close() }

    private func open() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        isOpen = result == kIOReturnSuccess
    }

    private func close() {
        if isOpen { IOServiceClose(conn) }
    }

    // MARK: - Read

    func readFans() -> [FanInfo] {
        if isAppleSilicon {
            return readAppleSiliconFans()
        }
        guard isOpen else { return [] }
        var count = readUInt8(key: SMCKey.fanCount)
        if count == 0 { count = readUInt8(key: "FpNm") }
        guard count > 0 else { return [] }
        var fans: [FanInfo] = []
        for i in 0..<Int(count) {
            let actual = readNumeric(key: String(format: SMCKey.fanActualRPM, i))
            let min    = readNumeric(key: String(format: SMCKey.fanMinRPM, i))
            let max    = readNumeric(key: String(format: SMCKey.fanMaxRPM, i))
            let safe   = readNumeric(key: String(format: SMCKey.fanSafeRPM, i))
            let target = readNumeric(key: String(format: SMCKey.fanTargetRPM, i))
            fans.append(FanInfo(id: i,
                                actualRPM: Int(actual),
                                minRPM: Int(min),
                                maxRPM: max > 0 ? Int(max) : 6000,
                                safeRPM: Int(safe),
                                targetRPM: Int(target)))
        }
        return fans
    }

    /// Reads real Apple Silicon fan telemetry. Do not infer fan presence from
    /// the model identifier: that produced false fans on new machines and
    /// fabricated RPM values in the UI. `FNum`/`FpNm` are the hardware source
    /// of truth; if the firmware does not expose them, the correct result is
    /// an empty list (monitoring unavailable), not a placeholder.
    private func readAppleSiliconFans() -> [FanInfo] {
        guard isOpen else { return [] }
        var count = readUInt8(key: SMCKey.fanCount)
        if count == 0 { count = readUInt8(key: "FpNm") }
        guard count > 0, count < 16 else { return [] }

        return (0..<Int(count)).compactMap { i in
            let actualKey = String(format: SMCKey.fanActualRPM, i)
            let actual = readNumeric(key: actualKey)
            let max = readNumeric(key: String(format: SMCKey.fanMaxRPM, i))
            let min = readNumeric(key: String(format: SMCKey.fanMinRPM, i))
            let safe = readNumeric(key: String(format: SMCKey.fanSafeRPM, i))
            let target = readNumeric(key: String(format: SMCKey.fanTargetRPM, i))
            // A missing actual-RPM key means this is not a usable fan record.
            guard readKey(key: actualKey) != nil else { return nil }
            return FanInfo(id: i, actualRPM: Int(actual), minRPM: Int(min),
                           maxRPM: max > 0 ? Int(max) : 1,
                           safeRPM: Int(safe), targetRPM: Int(target))
        }
    }

    func readFansAsync(completion: @escaping ([FanInfo]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let fans = self.readFans()
            DispatchQueue.main.async { completion(fans) }
        }
    }

    func readThermal() -> ThermalInfo {
        if isAppleSilicon {
            return HIDThermalReader.shared.read()
        }
        guard isOpen else { return ThermalInfo() }
        var t = ThermalInfo()
        let cpu1 = readSP78(key: SMCKey.cpuTemp)
        let cpu2 = readSP78(key: SMCKey.cpuDieTemp)
        t.cpuTemp     = max(cpu1, cpu2)
        t.gpuTemp     = readSP78(key: SMCKey.gpuTemp)
        t.batteryTemp = readSP78(key: SMCKey.batteryTemp)
        t.socTemp     = readSP78(key: SMCKey.socTemp)
        return t
    }

    // MARK: - Legacy Intel writes

    // Apple Silicon writes are intentionally excluded from this class. They
    // must go through FanControlXPCClient -> MacCleanerFanHelper so the main
    // process never attempts restricted SMC writes without the helper.

    @discardableResult
    func setFanTarget(fanIndex: Int, rpm: Int) -> Bool {
        guard !isAppleSilicon, isOpen, fanIndex >= 0, fanIndex < 16,
              (0...20_000).contains(rpm) else { return false }
        let key = String(format: SMCKey.fanTargetRPM, fanIndex)
        return writeFPE2(key: key, value: Float(rpm))
    }

    @discardableResult
    func setFanAutoMode() -> Bool {
        guard !isAppleSilicon, isOpen else { return false }
        return writeUInt16(key: SMCKey.fanMode, value: 0)
    }

    @discardableResult
    func setFanManualMode(fanIndex: Int) -> Bool {
        guard !isAppleSilicon, isOpen, fanIndex >= 0, fanIndex < 16 else { return false }
        let currentMode = readUInt16(key: SMCKey.fanMode)
        let newMode = currentMode | UInt16(1 << fanIndex)
        return writeUInt16(key: SMCKey.fanMode, value: newMode)
    }

    // MARK: - Raw SMC I/O

    private func callSMC(input: inout SMCKeyData, output: inout SMCKeyData) -> Bool {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = withUnsafeMutablePointer(to: &input) { inp in
            withUnsafeMutablePointer(to: &output) { out in
                IOConnectCallStructMethod(conn,
                                         KERNEL_INDEX_SMC,
                                         inp, inputSize,
                                         out, &outputSize)
            }
        }
        return result == kIOReturnSuccess
    }

    private func readKey(key: String) -> SMCKeyData? {
        var inputInfo = SMCKeyData()
        var outputInfo = SMCKeyData()
        inputInfo.key = fourCharCode(key)
        inputInfo.data8 = SMC_CMD_READ_KEYINFO
        guard callSMC(input: &inputInfo, output: &outputInfo) else { return nil }

        var inputData = SMCKeyData()
        var outputData = SMCKeyData()
        inputData.key = fourCharCode(key)
        inputData.keyInfo.dataSize = outputInfo.keyInfo.dataSize
        inputData.data8 = SMC_CMD_READ_BYTES
        guard callSMC(input: &inputData, output: &outputData) else { return nil }
        // Preserve the type discovered by READ_KEYINFO for format-aware decode.
        outputData.keyInfo = outputInfo.keyInfo
        return outputData
    }

    private func readUInt8(key: String) -> UInt8 {
        guard let data = readKey(key: key) else { return 0 }
        return data.bytes.0
    }

    private func readUInt16(key: String) -> UInt16 {
        guard let data = readKey(key: key) else { return 0 }
        return UInt16(data.bytes.0) << 8 | UInt16(data.bytes.1)
    }

    private func readFPE2(key: String) -> Float {
        guard let data = readKey(key: key) else { return 0 }
        let raw = UInt16(data.bytes.0) << 8 | UInt16(data.bytes.1)
        return Float(raw) / 4.0
    }

    private func readNumeric(key: String) -> Float {
        guard let data = readKey(key: key) else { return 0 }
        return SMCNumericDecoder.decode(
            dataType: fourCharString(data.keyInfo.dataType),
            bytes: [data.bytes.0, data.bytes.1, data.bytes.2, data.bytes.3]
        )
    }

    private func fourCharString(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private func readSP78(key: String) -> Double {
        guard let data = readKey(key: key) else { return 0 }
        let i16 = Int16(bitPattern: UInt16(data.bytes.0) << 8 | UInt16(data.bytes.1))
        return Double(i16) / 256.0
    }

    private func writeFPE2(key: String, value: Float) -> Bool {
        let raw = UInt16(value * 4.0)
        var input = SMCKeyData()
        var output = SMCKeyData()
        var infoInput = SMCKeyData()
        var infoOutput = SMCKeyData()
        infoInput.key = fourCharCode(key)
        infoInput.data8 = SMC_CMD_READ_KEYINFO
        guard callSMC(input: &infoInput, output: &infoOutput) else { return false }
        input.key = fourCharCode(key)
        input.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        input.data8 = SMC_CMD_WRITE_BYTES
        input.bytes.0 = UInt8((raw >> 8) & 0xFF)
        input.bytes.1 = UInt8(raw & 0xFF)
        return callSMC(input: &input, output: &output)
    }

    private func writeUInt16(key: String, value: UInt16) -> Bool {
        var input = SMCKeyData()
        var output = SMCKeyData()
        var infoInput = SMCKeyData()
        var infoOutput = SMCKeyData()
        infoInput.key = fourCharCode(key)
        infoInput.data8 = SMC_CMD_READ_KEYINFO
        guard callSMC(input: &infoInput, output: &infoOutput) else { return false }
        input.key = fourCharCode(key)
        input.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        input.data8 = SMC_CMD_WRITE_BYTES
        input.bytes.0 = UInt8((value >> 8) & 0xFF)
        input.bytes.1 = UInt8(value & 0xFF)
        return callSMC(input: &input, output: &output)
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        var code: UInt32 = 0
        let padded = string.padding(toLength: 4, withPad: " ", startingAt: 0)
        for char in padded.utf8 {
            code = (code << 8) | UInt32(char)
        }
        return code
    }
}

// MARK: - Apple Silicon HID Thermal Reader
// Uses IOHIDEventSystemClient (private API, accessed via dlopen)
// Same technique used by iStatMenus, Macs Fan Control, etc.

private typealias HIDCreateFn     = @convention(c) (CFAllocator?) -> CFTypeRef
private typealias HIDSetMatchFn   = @convention(c) (CFTypeRef, CFDictionary) -> Void
private typealias HIDCopyServicesFn = @convention(c) (CFTypeRef) -> CFArray?
private typealias HIDCopyPropFn   = @convention(c) (CFTypeRef, CFString) -> CFTypeRef?
private typealias HIDCopyEventFn  = @convention(c) (CFTypeRef, Int32, Double, Int32) -> CFTypeRef?
private typealias HIDEventValueFn = @convention(c) (CFTypeRef, Int32) -> Double

private let kHIDEventTypeTemperature: Int32 = 15
private let kHIDUsagePageAppleVendor: Int32  = 0xFF00
private let kHIDUsageAppleVendorSensor: Int32 = 0x0005

final class HIDThermalReader {
    static let shared = HIDThermalReader()

    private var hidCreate:     HIDCreateFn?
    private var hidSetMatch:   HIDSetMatchFn?
    private var hidCopyServices: HIDCopyServicesFn?
    private var hidCopyProp:   HIDCopyPropFn?
    private var hidCopyEvent:  HIDCopyEventFn?
    private var hidEventValue: HIDEventValueFn?
    private var loaded = false

    private init() { load() }

    private func load() {
        // IOHIDEventSystemClient lives in IOKit.framework on macOS
        let paths = [
            "/System/Library/Frameworks/IOKit.framework/IOKit",
            "/System/Library/PrivateFrameworks/HID.framework/Versions/A/HID",
        ]
        var handle: UnsafeMutableRawPointer?
        for path in paths {
            handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD)
            if handle == nil { handle = dlopen(path, RTLD_LAZY) }
            if handle != nil { break }
        }
        // Also try the already-loaded process image
        if handle == nil { handle = dlopen(nil, RTLD_LAZY) }
        guard let h = handle else {
            print("[HIDThermalReader] dlopen failed")
            return
        }
        func sym<T>(_ name: String) -> T? {
            dlsym(h, name).map { unsafeBitCast($0, to: T.self) }
        }
        hidCreate       = sym("IOHIDEventSystemClientCreate")
        hidSetMatch     = sym("IOHIDEventSystemClientSetMatching")
        hidCopyServices = sym("IOHIDEventSystemClientCopyServices")
        hidCopyProp     = sym("IOHIDServiceClientCopyProperty")
        hidCopyEvent    = sym("IOHIDServiceClientCopyEvent")
        hidEventValue   = sym("IOHIDEventGetFloatValue")
        loaded = hidCreate != nil && hidCopyServices != nil && hidCopyEvent != nil && hidEventValue != nil
    }

    // Maps raw HID sensor names to human-readable labels + categories
    private func mapSensor(name: String, temp: Double, into t: inout ThermalInfo, dieTemps: inout [Double], devTemps: inout [Double]) {
        let n = name.lowercased()
        let (label, cat): (String, SensorCategory)

        if n.contains("tdie") {
            // tdie1..tdie10 → CPU Performance/Efficiency Cores
            let num = n.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first ?? 0
            label = "CPU Core \(num)"
            cat = .cpuCore
            dieTemps.append(temp)
        } else if n.contains("tdev") {
            let num = n.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first ?? 0
            // tdev1-4 ≈ efficiency cores, tdev5-8 ≈ performance/GPU
            label = num <= 4 ? "CPU Efficiency \(num)" : "SoC Block \(num)"
            cat = num <= 4 ? .cpuCore : .soc
            devTemps.append(temp)
        } else if n.contains("tcal") {
            label = "CPU Average"
            cat = .cpuCore
        } else if n.contains("gas gauge") || n.contains("battery") {
            label = "Battery"
            cat = .battery
            if t.batteryTemp == 0 { t.batteryTemp = temp }
        } else if n.contains("nand") || n.contains("ssd") || n.contains("flash") {
            label = "Storage (NAND)"
            cat = .storage
        } else if n.contains("airflow") || n.contains("left") {
            label = n.contains("left") ? "Airflow Left" : "Airflow Right"
            cat = .airflow
        } else {
            label = name
            cat = .other
        }

        // Deduplicate by label
        if !t.sensors.contains(where: { $0.name == label }) {
            t.sensors.append(SensorReading(name: label, value: temp, category: cat))
        }
    }

    func read() -> ThermalInfo {
        var t = ThermalInfo()
        guard loaded,
              let create = hidCreate,
              let setMatch = hidSetMatch,
              let copyServices = hidCopyServices,
              let copyProp = hidCopyProp,
              let copyEvent = hidCopyEvent,
              let eventValue = hidEventValue
        else {
            t = readViaPowermetrics()
            return t
        }

        let client = create(kCFAllocatorDefault)
        let matching = [
            "PrimaryUsagePage": kHIDUsagePageAppleVendor,
            "PrimaryUsage": kHIDUsageAppleVendorSensor
        ] as CFDictionary
        setMatch(client, matching)

        guard let services = copyServices(client) as? [CFTypeRef], !services.isEmpty else {
            t = readViaPowermetrics()
            return t
        }

        var dieTemps: [Double] = []
        var devTemps: [Double] = []

        for svc in services {
            let name = (copyProp(svc, "Product" as CFString) as? String) ?? ""
            guard let event = copyEvent(svc, kHIDEventTypeTemperature, -1, 0) else { continue }
            let temp = eventValue(event, 0x000F0000)
            guard temp > 1 && temp < 130 else { continue }
            mapSensor(name: name, temp: temp, into: &t, dieTemps: &dieTemps, devTemps: &devTemps)
        }

        // Sort sensors by category then name
        t.sensors.sort {
            if $0.category.rawValue != $1.category.rawValue { return $0.category.rawValue < $1.category.rawValue }
            return $0.name < $1.name
        }

        // Aggregate summary values
        if !dieTemps.isEmpty {
            t.cpuTemp = dieTemps.max() ?? 0
            t.socTemp = dieTemps.reduce(0, +) / Double(dieTemps.count)
        } else if !devTemps.isEmpty {
            t.cpuTemp = devTemps.max() ?? 0
        }
        if t.gpuTemp == 0, let gpuT = dieTemps.sorted().last {
            t.gpuTemp = gpuT
        }

        // Insert Airflow sensors from airflow reading (tdev7/tdev8 area)
        if let airL = devTemps.dropFirst(6).first {
            if !t.sensors.contains(where: { $0.name == "Airflow Left" }) {
                t.sensors.insert(SensorReading(name: "Airflow Left", value: airL, category: .airflow), at: 0)
            }
        }
        if let airR = devTemps.dropFirst(7).first {
            if !t.sensors.contains(where: { $0.name == "Airflow Right" }) {
                t.sensors.insert(SensorReading(name: "Airflow Right", value: airR, category: .airflow), at: 1)
            }
        }

        return t
    }

    // Fallback: returns empty — powermetrics requires sudo and blocks UI, skip it
    private func readViaPowermetrics() -> ThermalInfo {
        return ThermalInfo()
    }
}
