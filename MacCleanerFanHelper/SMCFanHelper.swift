import Foundation
import IOKit
import Security
import Darwin

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

// Exact 80-byte layout matching Apple's SMCParamStruct. Keeping the nested
// structs is significant: flattening these fields changes Swift's alignment
// and shifts `data8`/`bytes`, making every hardware read appear empty.
struct SMCKeyData {
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


@objc protocol MacCleanerFanHelperProtocol {
    func status(withReply reply: @escaping (Bool, String?) -> Void)
    func setManualRPM(_ rpm: Int, fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func setAutomatic(fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func setAllAutomatic(withReply reply: @escaping (Bool, String?) -> Void)
    func boostForTenSeconds(withReply reply: @escaping (Bool, String?) -> Void)
    func controlState(withReply reply: @escaping (Int, [NSNumber], String?) -> Void)
    func heartbeat(withReply reply: @escaping () -> Void)
}

struct FanError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

protocol FanSMC {
    func number(_ key: String) throws -> Float
    func writeByte(_ key: String, _ value: UInt8) throws
    func writeRPM(_ key: String, _ value: Int) throws
}

final class HardwareSMC: FanSMC {
    private var connection: io_connect_t = 0
    init() throws {
        guard MemoryLayout<SMCKeyData>.stride == 80 else { throw FanError("Invalid SMC layout.") }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw FanError("AppleSMC is unavailable.") }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == 0 else {
            throw FanError("Cannot open AppleSMC.")
        }
    }
    deinit { IOServiceClose(connection) }
    private func code(_ key: String) -> UInt32 { key.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    private func call(_ input: SMCKeyData) throws -> SMCKeyData {
        var input = input, output = SMCKeyData()
        var size = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, size, &output, &size)
        guard result == 0, output.result == 0, size == 80 else {
            throw FanError("SMC rejected the operation (\(result), \(output.result)).")
        }
        return output
    }
    private func info(_ key: String) throws -> SMCKeyInfo {
        var input = SMCKeyData(); input.key = code(key); input.data8 = 9
        let info = try call(input).keyInfo
        guard info.dataSize > 0, info.dataSize <= 32 else { throw FanError("Invalid SMC key: \(key).") }
        return info
    }
    func number(_ key: String) throws -> Float {
        let metadata = try info(key)
        var input = SMCKeyData(); input.key = code(key); input.data8 = 5
        input.keyInfo.dataSize = metadata.dataSize
        var output = try call(input)
        let bytes = withUnsafeBytes(of: &output.bytes) { Array($0.prefix(Int(metadata.dataSize))) }
        let value: Float
        switch (metadata.dataType, bytes.count) {
        case (code("flt "), 4):
            value = Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
        case (code("fpe2"), 2): value = Float(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case (code("ui8 "), 1): value = Float(bytes[0])
        default: throw FanError("Unsupported SMC format: \(key).")
        }
        guard value.isFinite else { throw FanError("Invalid SMC value: \(key).") }
        return value
    }
    private func write(_ key: String, bytes: [UInt8]) throws {
        let metadata = try info(key)
        guard metadata.dataSize == bytes.count else { throw FanError("SMC write size mismatch.") }
        var input = SMCKeyData(); input.key = code(key); input.data8 = 6
        input.keyInfo.dataSize = metadata.dataSize
        withUnsafeMutableBytes(of: &input.bytes) { $0.copyBytes(from: bytes) }
        _ = try call(input)
    }
    func writeByte(_ key: String, _ value: UInt8) throws { try write(key, bytes: [value]) }
    func writeRPM(_ key: String, _ value: Int) throws {
        let type = try info(key).dataType
        if type == code("flt ") {
            var bits = Float(value).bitPattern.littleEndian
            try write(key, bytes: withUnsafeBytes(of: &bits) { Array($0) })
        } else if type == code("fpe2"), (0...16_383).contains(value) {
            let bits = UInt16(value * 4)
            try write(key, bytes: [UInt8(bits >> 8), UInt8(bits & 255)])
        } else { throw FanError("Unsupported fan target format.") }
    }
}

/// Used only on Helper.queue. Every accepted manual operation has a lease;
/// the helper, not the UI, owns the ten-second deadline and rollback.
final class FanController {
    let smc: FanSMC
    var owner: UUID?
    var controlled: Set<Int> = []
    var targets: [Int: Int] = [:]
    var lease: Date?
    var boostDeadline: Date?
    var lastError: String?
    var forceTestEnabled = false
    var prepareRecovery: () throws -> Void = {}
    var clearRecovery: () -> Void = {}
    var now: () -> Date = Date.init
    var pause: () -> Void = { usleep(100_000) }
    init(smc: FanSMC) { self.smc = smc }

    func fans() throws -> [Int] {
        let count = try smc.number("FNum")
        guard count >= 1, count < 16, count.rounded() == count else { throw FanError("No supported fans found.") }
        return Array(0..<Int(count))
    }
    func modeKey(_ fan: Int) throws -> String {
        guard try fans().contains(fan) else { throw FanError("Invalid fan index.") }
        for key in ["F\(fan)Md", "F\(fan)md"] where (try? smc.number(key)) != nil { return key }
        throw FanError("Fan mode is unavailable.")
    }
    func bounds(_ fan: Int) throws -> ClosedRange<Int> {
        _ = try modeKey(fan)
        let low = try smc.number("F\(fan)Mn"), high = try smc.number("F\(fan)Mx")
        guard low > 0, high > low, high <= 20_000 else { throw FanError("Invalid fan RPM limits.") }
        return Int(ceil(low))...Int(floor(high))
    }
    func claim(_ session: UUID) throws {
        guard owner == nil || owner == session else { throw FanError("Another MacCleaner session controls the fans.") }
        if !forceTestEnabled {
            if let force = try? smc.number("Ftst"), force != 0 {
                throw FanError("Another app has enabled diagnostic fan control. Select Auto there first.")
            }
            for fan in try fans() where !controlled.contains(fan) {
                guard try smc.number(modeKey(fan)) != 1 else {
                    throw FanError("Another app controls the fans. Select Auto there first.")
                }
            }
        }
        try prepareRecovery()
        owner = session
        lease = now().addingTimeInterval(15)
    }
    private func writeManual(_ fan: Int, rpm: Int) throws {
        let key = try modeKey(fan)
        if let deadline = boostDeadline, now() >= deadline { throw FanError("Boost deadline reached.") }
        controlled.insert(fan) // rollback even if a later write/read fails
        do { try smc.writeByte(key, 1) } catch {
            guard try smc.number("Ftst") == 0 else { throw error }
            forceTestEnabled = true
            try smc.writeByte("Ftst", 1)
            var accepted = false
            // Thermal management can take 3–6 seconds to yield system mode 3.
            for _ in 0..<80 {
                pause()
                if let deadline = boostDeadline, now() >= deadline { break }
                if (try? smc.writeByte(key, 1)) != nil { accepted = true; break }
            }
            guard accepted else { throw FanError("Firmware did not release fan control.") }
        }
        try smc.writeRPM("F\(fan)Tg", rpm)
        for _ in 0..<20 {
            pause()
            if let deadline = boostDeadline, now() >= deadline { throw FanError("Boost deadline reached.") }
            if try smc.number(key) == 1, abs(try smc.number("F\(fan)Tg") - Float(rpm)) < 2 {
                targets[fan] = rpm
                return
            }
        }
        throw FanError("Fan target was not confirmed by the hardware.")
    }
    func manual(_ rpm: Int, fan: Int, session: UUID) throws {
        guard try bounds(fan).contains(rpm) else { throw FanError("Choose RPM within this fan’s minimum and maximum.") }
        guard boostDeadline == nil else { throw FanError("Wait for the boost to finish or select Auto.") }
        try claim(session)
        do { try writeManual(fan, rpm: rpm); lastError = nil }
        catch { try rollback(error) }
    }
    func boost(session: UUID) throws {
        guard boostDeadline == nil else { throw FanError("A boost is already running.") }
        let targets = try fans().map { ($0, try bounds($0).upperBound) }
        try claim(session)
        boostDeadline = now().addingTimeInterval(10)
        do {
            for (fan, rpm) in targets { try writeManual(fan, rpm: rpm) }
            lastError = nil
        } catch { try rollback(error) }
    }
    private func rollback(_ error: Error) throws {
        let recovery = restoreAll()
        lastError = error.localizedDescription + (recovery.map { " Auto restore failed: \($0)" } ?? " Auto restored.")
        throw FanError(lastError!)
    }
    @discardableResult func restoreAll() -> String? {
        var errors: [String] = []
        for fan in controlled.sorted() {
            do {
                let key = try modeKey(fan)
                // Firmware may already have restored system Auto (3), e.g. after sleep.
                // Do not issue a redundant write that firmware can reject in that state.
                let currentMode = try smc.number(key)
                if currentMode != 0 && currentMode != 3 { try smc.writeByte(key, 0) }
                var verified = false
                for _ in 0..<20 {
                    pause()
                    if try smc.number(key) != 1 { verified = true; break }
                }
                guard verified else { throw FanError("Fan \(fan) is still manual.") }
                controlled.remove(fan)
                targets.removeValue(forKey: fan)
            } catch { errors.append(error.localizedDescription) }
        }
        if forceTestEnabled {
            do {
                try smc.writeByte("Ftst", 0)
                var released = false
                for _ in 0..<20 {
                    pause()
                    if try smc.number("Ftst") == 0 { released = true; break }
                }
                guard released else { throw FanError("Ftst reset not confirmed.") }
                forceTestEnabled = false
            } catch { errors.append(error.localizedDescription) }
        }
        if errors.isEmpty { clearRecovery(); owner = nil; lease = nil; boostDeadline = nil; lastError = nil; return nil }
        // Keep the lease expired so the watchdog retries failed restoration.
        lease = .distantPast; boostDeadline = nil
        lastError = errors.joined(separator: " ")
        return lastError
    }
    func automatic(fan: Int, session: UUID) throws {
        guard owner == nil || owner == session else { throw FanError("Another session controls the fans.") }
        _ = try modeKey(fan)
        guard controlled.contains(fan) else {
            guard try smc.number(modeKey(fan)) != 1 else { throw FanError("Another app controls this fan. Select Auto there first.") }
            lastError = nil
            return
        }
        if boostDeadline != nil || controlled.count == 1 {
            if let error = restoreAll() { throw FanError(error) }; return
        }
        // Ftst is global on Apple Silicon. Release it safely, then restore the
        // remaining per-fan manual targets so one channel can return to Auto
        // without silently switching the other channel as well.
        if forceTestEnabled {
            let remainingTargets = targets.filter { $0.key != fan }
            if let error = restoreAll() { throw FanError(error) }
            guard !remainingTargets.isEmpty else { return }
            try claim(session)
            do {
                for (remainingFan, rpm) in remainingTargets.sorted(by: { $0.key < $1.key }) {
                    try writeManual(remainingFan, rpm: rpm)
                }
                lastError = nil
            } catch {
                try rollback(error)
            }
            return
        }
        let key = try modeKey(fan)
        let currentMode = try smc.number(key)
        if currentMode != 0 && currentMode != 3 { try smc.writeByte(key, 0) }
        for _ in 0..<20 {
            pause()
            if try smc.number(key) != 1 {
                controlled.remove(fan)
                targets.removeValue(forKey: fan)
                return
            }
        }
        throw FanError("Automatic mode was not confirmed.")
    }
    func tick() {
        if let deadline = boostDeadline, now() >= deadline { restoreAll() }
        else if let lease, now() >= lease { restoreAll() }
    }
    func heartbeat(_ session: UUID) {
        if owner == session, lease != .distantPast { lease = now().addingTimeInterval(15) }
    }
    func disconnected(_ session: UUID) { if owner == session { restoreAll() } }
    var secondsRemaining: Int { boostDeadline.map { max(0, Int(ceil($0.timeIntervalSince(now())))) } ?? 0 }
}

final class FanSession: NSObject, MacCleanerFanHelperProtocol {
    let id = UUID()
    let helper: Helper
    init(_ helper: Helper) { self.helper = helper }
    private func perform(_ reply: @escaping (Bool, String?) -> Void, _ operation: @escaping (FanController) throws -> Void) {
        helper.queue.async {
            do { try operation(self.helper.controller); reply(true, nil) }
            catch { reply(false, error.localizedDescription) }
        }
    }
    func status(withReply reply: @escaping (Bool, String?) -> Void) {
        perform(reply) { _ = try $0.fans() }
    }
    func setManualRPM(_ rpm: Int, fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void) {
        perform(reply) { try $0.manual(rpm, fan: fanIndex, session: self.id) }
    }
    func setAutomatic(fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void) {
        perform(reply) { try $0.automatic(fan: fanIndex, session: self.id) }
    }
    func setAllAutomatic(withReply reply: @escaping (Bool, String?) -> Void) {
        perform(reply) {
            guard $0.owner == nil || $0.owner == self.id else { throw FanError("Another session controls the fans.") }
            if $0.owner == nil {
                for fan in try $0.fans() {
                    guard try $0.smc.number($0.modeKey(fan)) != 1 else { throw FanError("Another app controls the fans. Select Auto there first.") }
                }
            }
            if let error = $0.restoreAll() { throw FanError(error) }
        }
    }
    func boostForTenSeconds(withReply reply: @escaping (Bool, String?) -> Void) {
        perform(reply) { try $0.boost(session: self.id) }
    }
    func controlState(withReply reply: @escaping (Int, [NSNumber], String?) -> Void) {
        helper.queue.async {
            reply(
                self.helper.controller.secondsRemaining,
                self.helper.controller.controlled.sorted().map(NSNumber.init(value:)),
                self.helper.controller.lastError
            )
        }
    }
    func heartbeat(withReply reply: @escaping () -> Void) {
        helper.queue.async { self.helper.controller.heartbeat(self.id); reply() }
    }
}

final class Helper: NSObject, NSXPCListenerDelegate {
    static let configPath = "/Library/PrivilegedHelperTools/com.maccleaner.fanhelper.client.plist"
    let queue = DispatchQueue(label: "com.maccleaner.fanhelper.control")
    let controller: FanController
    private let listener = NSXPCListener(machServiceName: "com.maccleaner.fanhelper")
    private var timer: DispatchSourceTimer?
    private var signals: [DispatchSourceSignal] = []
    private let requirement: String
    init(configuration: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: Self.configPath)
        guard (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o022 == 0,
              attributes[.type] as? FileAttributeType == .typeRegular,
              let config = NSDictionary(contentsOfFile: Self.configPath),
              let requirement = config["Requirement"] as? String else { throw FanError("Trusted client configuration is missing.") }
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else {
            throw FanError("Invalid client requirement.")
        }
        self.requirement = requirement
        controller = FanController(smc: try HardwareSMC())
        super.init()
        let marker = Self.configPath + ".active"
        controller.prepareRecovery = {
            try Data("manual".utf8).write(to: URL(fileURLWithPath: marker), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker)
        }
        controller.clearRecovery = { try? FileManager.default.removeItem(atPath: marker) }
        if FileManager.default.fileExists(atPath: marker) {
            controller.controlled = Set(try controller.fans())
            controller.forceTestEnabled = (try? controller.smc.number("Ftst")) == 1
            controller.restoreAll()
        }
    }
    func run() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.controller.tick() }
        timer.resume(); self.timer = timer
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler { [weak self] in
                let error = self?.controller.restoreAll()
                exit(error == nil ? 0 : 1)
            }
            source.resume(); signals.append(source)
        }
        listener.delegate = self; listener.resume()
        RunLoop.current.run()
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Enforced by XPC for every message, including ad-hoc cdhash identities.
        connection.setCodeSigningRequirement(requirement)
        let session = FanSession(self)
        connection.exportedInterface = NSXPCInterface(with: MacCleanerFanHelperProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak self] in self?.queue.async { self?.controller.disconnected(session.id) } }
        connection.interruptionHandler = { [weak self] in self?.queue.async { self?.controller.disconnected(session.id) } }
        connection.resume()
        return true
    }
}

#if !FAN_HELPER_TESTING
@main private struct MacCleanerFanHelperMain {
    static func main() {
        guard geteuid() == 0 else { fputs("Administrator privileges required.\n", stderr); exit(1) }
        do { let helper = try Helper(configuration: Helper.configPath); withExtendedLifetime(helper) { helper.run() } }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
#endif
