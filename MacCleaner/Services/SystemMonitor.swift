import Foundation
import Darwin
import IOKit
import IOKit.ps
import SystemConfiguration

final class SystemMonitor: ObservableObject {
    @Published var memory: MemoryInfo = .init(total: 0, used: 0, free: 0, wired: 0, compressed: 0, cached: 0)
    @Published var cpu: CPUInfo = .init(totalUsage: 0, coreUsages: [], processorCount: 0)
    @Published var disks: [DiskInfo] = []
    @Published var topProcesses: [AppProcessInfo] = []
    @Published var processNodes: [ProcessNode] = []
    @Published var windows: [WindowInfo] = []
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var ramHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var fans: [FanInfo] = []
    @Published var thermal: ThermalInfo = ThermalInfo()
    @Published var thermalHistory: [(date: Date, cpu: Double, soc: Double, battery: Double)] = []
    @Published var battery: BatteryInfo = BatteryInfo()
    @Published var network: NetworkInfo = NetworkInfo()
    @Published var networkHistory: [(down: Double, up: Double)] = Array(repeating: (down: 0, up: 0), count: 60)
    @Published var gpuUsage: Double = 0
    @Published var gpuHistory: [Double] = Array(repeating: 0, count: 60)

    private var timer: Timer?
    private var prevCPUInfo: processor_info_array_t?
    private var prevCPUCount: mach_msg_type_number_t = 0
    private var prevNetworkSample: (interfaceName: String, received: UInt64, sent: UInt64, date: Date)?
    private var cachedPrimaryNetworkInterface: (name: String, refreshedAt: Date)?
    private var cachedExternalBatteryDevices: (devices: [BatteryDeviceInfo], refreshedAt: Date)?
    private var isRefreshInFlight = false

    /// Tick counter: expensive tasks run less often than CPU/RAM sampling.
    private var refreshTick: Int = 0
    private static let refreshInterval: TimeInterval = 15.0
    private static let sensorInterval = 4       // every 60 seconds
    private static let processInterval = 7      // every 105 seconds; force refresh in process-heavy screens
    private static let batteryInterval = 20     // every 5 minutes
    private static let externalBatteryInterval = 120 // every 30 minutes; system_profiler is expensive
    private static let networkInterfaceCacheTTL: TimeInterval = 60
    private static let externalBatteryCacheTTL: TimeInterval = 30 * 60

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
        if let prev = prevCPUInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
    }

    func refresh(forceProcesses: Bool = false, forceSensors: Bool = false) {
        guard !isRefreshInFlight else { return }
        isRefreshInFlight = true
        refreshTick += 1

        // ── Light work (Mach kernel APIs — sub-millisecond, safe on main) ──
        let mem = fetchMemory()
        let cpuInfo = fetchCPU()
        let networkInfo = fetchNetwork()

        // ── Determine what else to fetch ──
        let runSensors = forceSensors || (refreshTick > 1 && refreshTick % Self.sensorInterval == 0)
        let runProcesses = forceProcesses || refreshTick == 1 || (refreshTick > 1 && refreshTick % Self.processInterval == 0)
        let runDisks = refreshTick == 1 || runProcesses
        let runBattery = refreshTick == 1 || refreshTick % Self.batteryInterval == 0
        let runExternalBattery = refreshTick > 1 && refreshTick % Self.externalBatteryInterval == 0
        let runGPU = runSensors

        // ── Heavy work on background thread ──
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var thermalResult: ThermalInfo?
            var fansResult: [FanInfo]?
            var disksResult: [DiskInfo]?
            var nodesResult: [ProcessNode]?
            var windowsResult: [WindowInfo]?
            var batteryResult: BatteryInfo?
            var gpuResult: Double?

            if runSensors {
                thermalResult = SMCService.shared.readThermal()
                fansResult = SMCService.shared.readFans()
            }

            if runDisks {
                disksResult = self.fetchDisks()
            }

            if runBattery {
                batteryResult = self.fetchBattery(includeExternalDevices: runExternalBattery)
            }

            if runGPU {
                gpuResult = self.fetchGPUUsage()
            }

            if runProcesses {
                // Single call to fetchWindows — reused for both processNodes and windows
                let wins = ProcessTreeService.fetchWindows()
                windowsResult = wins
                // Single /bin/ps call — replaces both fetchTopProcesses and fetchFlatProcesses
                nodesResult = ProcessTreeService.fetchFlatProcesses(cachedWindows: wins)
            }

            // ── Batch update on main thread (single objectWillChange) ──
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isRefreshInFlight = false

                // Suppress individual objectWillChange until the end
                // by assigning everything, then the last assignment triggers the update.
                // Unfortunately SwiftUI fires per-property, so we group fast assignments.

                self.memory = mem
                self.cpu = cpuInfo
                self.network = networkInfo

                if let disks = disksResult { self.disks = disks }
                if let nodes = nodesResult {
                    self.processNodes = nodes
                    // Derive topProcesses from processNodes — no second /bin/ps!
                    self.topProcesses = nodes
                        .sorted { $0.cpuUsage > $1.cpuUsage }
                        .prefix(15)
                        .map { AppProcessInfo(id: $0.id, name: $0.name, cpuUsage: $0.cpuUsage, memoryBytes: $0.memoryBytes) }
                }
                if let wins = windowsResult { self.windows = wins }
                if let batt = batteryResult { self.battery = batt }

                self.cpuHistory.append(cpuInfo.totalUsage)
                if self.cpuHistory.count > 60 { self.cpuHistory.removeFirst() }
                self.ramHistory.append(mem.usedPercent)
                if self.ramHistory.count > 60 { self.ramHistory.removeFirst() }
                self.networkHistory.append((down: networkInfo.downloadBytesPerSecond, up: networkInfo.uploadBytesPerSecond))
                if self.networkHistory.count > 60 { self.networkHistory.removeFirst() }

                if let gpuUtil = gpuResult {
                    self.gpuUsage = gpuUtil
                    self.gpuHistory.append(gpuUtil)
                    if self.gpuHistory.count > 60 { self.gpuHistory.removeFirst() }
                }

                if let thermalResult {
                    self.thermal = thermalResult
                }
                if let thermalResult, thermalResult.cpuTemp > 0 {
                    self.thermalHistory.append((date: Date(), cpu: thermalResult.cpuTemp, soc: thermalResult.socTemp, battery: thermalResult.batteryTemp))
                    if self.thermalHistory.count > 120 { self.thermalHistory.removeFirst() }  // 6 min max (was 1200 = 1 hour!)
                }

                if let fansResult { self.fans = fansResult }
            }
        }
    }

    // MARK: - Memory

    private func fetchMemory() -> MemoryInfo {
        let total = Foundation.ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryInfo(total: total, used: 0, free: total, wired: 0, compressed: 0, cached: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize

        let used = wired + active + compressed
        let cached = inactive + speculative

        return MemoryInfo(
            total: total,
            used: used,
            free: free,
            wired: wired,
            compressed: compressed,
            cached: cached
        )
    }

    // MARK: - CPU

    private func fetchCPU() -> CPUInfo {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCPUInfo)
        guard err == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return CPUInfo(totalUsage: 0, coreUsages: [], processorCount: Int(numCPUsU))
        }

        let numCPUs = Int(numCPUsU)
        var coreDiffs: [(user: Double, system: Double, nice: Double, idle: Double, all: Double)] = []
        var maxDiffAll: Double = 0

        for i in 0..<numCPUs {
            let base = Int32(CPU_STATE_MAX) * Int32(i)
            let user    = Double(UInt32(bitPattern: cpuInfo[Int(base) + Int(CPU_STATE_USER)]))
            let system  = Double(UInt32(bitPattern: cpuInfo[Int(base) + Int(CPU_STATE_SYSTEM)]))
            let nice    = Double(UInt32(bitPattern: cpuInfo[Int(base) + Int(CPU_STATE_NICE)]))
            let idle    = Double(UInt32(bitPattern: cpuInfo[Int(base) + Int(CPU_STATE_IDLE)]))

            var prevUser   = 0.0
            var prevSystem = 0.0
            var prevNice   = 0.0
            var prevIdle   = 0.0

            if let prev = prevCPUInfo {
                prevUser   = Double(UInt32(bitPattern: prev[Int(base) + Int(CPU_STATE_USER)]))
                prevSystem = Double(UInt32(bitPattern: prev[Int(base) + Int(CPU_STATE_SYSTEM)]))
                prevNice   = Double(UInt32(bitPattern: prev[Int(base) + Int(CPU_STATE_NICE)]))
                prevIdle   = Double(UInt32(bitPattern: prev[Int(base) + Int(CPU_STATE_IDLE)]))
            }

            let diffUser   = user   - prevUser
            let diffSystem = system - prevSystem
            let diffNice   = nice   - prevNice
            let diffIdle   = idle   - prevIdle
            let diffAll    = diffUser + diffSystem + diffNice + diffIdle

            coreDiffs.append((user: diffUser, system: diffSystem, nice: diffNice, idle: diffIdle, all: diffAll))
            if diffAll > maxDiffAll { maxDiffAll = diffAll }
        }

        var usages: [Double] = []
        var totalUsed = 0.0
        var totalAll = 0.0

        for diff in coreDiffs {
            // FIX: Use maxDiffAll as the baseline to prevent the Apple Silicon sleep bug
            // where sleeping cores don't increment ticks and falsely report 100% due to division by a tiny diffAll.
            let active = diff.all - diff.idle
            let usage = maxDiffAll > 0 ? active / maxDiffAll : 0
            usages.append(max(0, min(1, usage)))
            totalUsed += active
            totalAll  += diff.all
        }

        if let prev = prevCPUInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev),
                          vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        prevCPUInfo  = cpuInfo
        prevCPUCount = numCPUInfo

        let totalUsage = totalAll > 0 ? totalUsed / totalAll : 0
        return CPUInfo(totalUsage: max(0, min(1, totalUsage)), coreUsages: usages, processorCount: numCPUs)
    }

    // MARK: - Disks

    private func fetchDisks() -> [DiskInfo] {
        let fm = FileManager.default
        guard let vols = fm.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey
        ], options: [.skipHiddenVolumes]) else { return [] }

        return vols.compactMap { url -> DiskInfo? in
            guard let vals = try? url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ]) else { return nil }

            let total = UInt64(vals.volumeTotalCapacity ?? 0)
            guard total > 0 else { return nil }

            let free = UInt64(vals.volumeAvailableCapacityForImportantUsage ?? Int64(vals.volumeAvailableCapacity ?? 0))
            let used = total > free ? total - free : 0
            let name = vals.volumeName ?? url.lastPathComponent

            return DiskInfo(
                mountPoint: url.path,
                volumeName: name,
                total: total,
                used: used,
                free: free
            )
        }
    }

    // MARK: - Battery

    private func fetchBattery(includeExternalDevices: Bool) -> BatteryInfo {
        var info = BatteryInfo()
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return info }

        var devices: [BatteryDeviceInfo] = []

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            let type = desc[kIOPSTypeKey] as? String ?? ""
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maxCapacity > 0 ? Int((Double(current) / Double(maxCapacity) * 100).rounded()) : current
            let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let rawName = desc[kIOPSNameKey] as? String ?? (type == kIOPSInternalBatteryType ? "MacBook" : "Device")
            let name = Self.cleanBatteryDeviceName(rawName)

            if current > 0 || maxCapacity > 0 {
                devices.append(BatteryDeviceInfo(
                    id: "\(name)-\(type)",
                    name: name,
                    type: type,
                    chargePercent: max(0, min(100, percent)),
                    isCharging: isCharging
                ))
            }

            guard type == kIOPSInternalBatteryType else { continue }

            info.chargePercent = max(0, min(100, percent))
            // Note: IOPSMaxCapacityKey is usually 100 (percentage), not mAh. We'll fetch real mAh later.
            info.isCharging    = isCharging
            info.isPluggedIn   = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if let tr = desc[kIOPSTimeToEmptyKey] as? Int, tr > 0 { info.timeRemaining = tr }
            else if let tr = desc[kIOPSTimeToFullChargeKey] as? Int, tr > 0 { info.timeRemaining = tr }
            else { info.timeRemaining = -1 }
        }
        let internalIDs = Set(devices.map(\.id))
        if includeExternalDevices {
            let externalDevices = fetchExternalBatteryDevices(existingIDs: internalIDs)
            cachedExternalBatteryDevices = (externalDevices, Date())
            devices.append(contentsOf: externalDevices)
        } else if let cachedExternalBatteryDevices,
                  Date().timeIntervalSince(cachedExternalBatteryDevices.refreshedAt) < Self.externalBatteryCacheTTL {
            devices.append(contentsOf: cachedExternalBatteryDevices.devices.filter { !internalIDs.contains($0.id) })
        }
        info.devices = devices

        // Detailed data from IORegistry (AppleSmartBattery)
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery"))
        if service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            func intProp(_ key: String) -> Int {
                (IORegistryEntryCreateCFProperty(service, key as CFString,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
            }
            info.cycleCount      = intProp("CycleCount")
            info.designCapacity  = intProp("DesignCapacity")
            info.currentCapacity = intProp("AppleRawCurrentCapacity")
            let nominal = intProp("NominalChargeCapacity")
            info.maxCapacity = nominal > 0 ? nominal : intProp("AppleRawMaxCapacity")
            let rawVolt = intProp("Voltage")        // mV
            let rawAmp  = intProp("InstantAmperage") // mA signed
            info.voltage  = Double(rawVolt) / 1000.0
            info.amperage = Double(Int32(truncatingIfNeeded: rawAmp)) / 1000.0
            let rawTemp   = intProp("Temperature")   // 0.01 °C
            info.temperature = Double(rawTemp) / 100.0
        }
        return info
    }

    private func fetchExternalBatteryDevices(existingIDs: Set<String>) -> [BatteryDeviceInfo] {
        var devices = fetchAccessoryBatteryDevices(existingIDs: existingIDs)
        let knownIDs = existingIDs.union(devices.map(\.id))
        devices.append(contentsOf: fetchBluetoothBatteryDevices(existingIDs: knownIDs))
        return devices
    }

    private func fetchAccessoryBatteryDevices(existingIDs: Set<String>) -> [BatteryDeviceInfo] {
        guard let data = runProcessData(
            executable: "/usr/sbin/ioreg",
            arguments: ["-r", "-k", "BatteryPercent", "-l"],
            timeout: 3
        ) else { return [] }
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return [] }

        var devices: [BatteryDeviceInfo] = []
        var name: String?
        var percent: Int?

        func flush() {
            guard let batteryPercent = percent, batteryPercent >= 0 else {
                name = nil
                percent = nil
                return
            }
            let resolvedName = Self.cleanBatteryDeviceName(name)
            guard resolvedName != "Internal Battery" else {
                name = nil
                percent = nil
                return
            }
            let id = "accessory-\(resolvedName)"
            if !existingIDs.contains(id), !devices.contains(where: { $0.id == id }) {
                devices.append(BatteryDeviceInfo(
                    id: id,
                    name: resolvedName,
                    type: "Accessory",
                    chargePercent: max(0, min(100, batteryPercent)),
                    isCharging: false
                ))
            }
            name = nil
            percent = nil
        }

        for line in output.components(separatedBy: .newlines) {
            if line.contains("+-o ") || line.contains("|-o ") {
                flush()
            }
            if let value = Self.quotedIORegValue(in: line, key: "Product") ??
                Self.quotedIORegValue(in: line, key: "DeviceName") ??
                Self.quotedIORegValue(in: line, key: "Name") {
                name = value
            }
            if let value = Self.integerIORegValue(in: line, key: "BatteryPercent") {
                percent = value
            }
        }
        flush()

        return devices
    }

    private func fetchBluetoothBatteryDevices(existingIDs: Set<String>) -> [BatteryDeviceInfo] {
        guard let data = runProcessData(
            executable: "/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-json"],
            timeout: 8
        ) else { return [] }
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var devices: [BatteryDeviceInfo] = []
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for deviceEntry in connected {
                for (deviceName, value) in deviceEntry {
                    guard let info = value as? [String: Any] else { continue }
                    let cleanName = Self.cleanBatteryDeviceName(deviceName)
                    appendBluetoothBatteryDevice(
                        named: cleanName,
                        suffix: nil,
                        key: "device_batteryLevel",
                        info: info,
                        existingIDs: existingIDs,
                        into: &devices
                    )
                    appendBluetoothBatteryDevice(
                        named: cleanName,
                        suffix: "L",
                        key: "device_batteryLevelLeft",
                        info: info,
                        existingIDs: existingIDs,
                        into: &devices
                    )
                    appendBluetoothBatteryDevice(
                        named: cleanName,
                        suffix: "R",
                        key: "device_batteryLevelRight",
                        info: info,
                        existingIDs: existingIDs,
                        into: &devices
                    )
                    appendBluetoothBatteryDevice(
                        named: cleanName,
                        suffix: "Case",
                        key: "device_batteryLevelCase",
                        info: info,
                        existingIDs: existingIDs,
                        into: &devices
                    )
                }
            }
        }
        return devices
    }

    private func runProcessData(executable: String, arguments: [String], timeout: TimeInterval) -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in semaphore.signal() }

        do {
            try task.run()
        } catch {
            return nil
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            return nil
        }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    private func appendBluetoothBatteryDevice(
        named name: String,
        suffix: String?,
        key: String,
        info: [String: Any],
        existingIDs: Set<String>,
        into devices: inout [BatteryDeviceInfo]
    ) {
        guard let raw = info[key] as? String,
              let percent = Self.percentValue(from: raw)
        else { return }

        let displayName = suffix.map { "\(name) \($0)" } ?? name
        let id = "bluetooth-\(displayName)"
        guard !existingIDs.contains(id), !devices.contains(where: { $0.id == id }) else { return }

        devices.append(BatteryDeviceInfo(
            id: id,
            name: displayName,
            type: "Bluetooth",
            chargePercent: max(0, min(100, percent)),
            isCharging: false
        ))
    }

    private static func quotedIORegValue(in line: String, key: String) -> String? {
        let marker = "\"\(key)\" = \""
        guard let range = line.range(of: marker) else { return nil }
        let suffix = line[range.upperBound...]
        guard let end = suffix.firstIndex(of: "\"") else { return nil }
        return String(suffix[..<end])
    }

    private static func integerIORegValue(in line: String, key: String) -> Int? {
        let marker = "\"\(key)\" = "
        guard let range = line.range(of: marker) else { return nil }
        let suffix = line[range.upperBound...]
        let number = suffix.prefix { $0.isNumber }
        return Int(number)
    }

    private static func percentValue(from raw: String) -> Int? {
        let digits = raw.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        guard !digits.isEmpty else { return nil }
        return Int(String(String.UnicodeScalarView(digits)))
    }

    private static func cleanBatteryDeviceName(_ rawName: String?) -> String {
        let raw = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return "Accessory" }
        if raw.lowercased().contains("internal") { return "MacBook" }
        if raw.range(of: #"^Internal-\d+$"#, options: .regularExpression) != nil { return "MacBook" }
        if raw.lowercased().contains("apple raw current capacity") { return "MacBook" }
        return raw
            .replacingOccurrences(of: "Bluetooth Device", with: "Accessory")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Network

    private func fetchNetwork() -> NetworkInfo {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return NetworkInfo()
        }
        defer { freeifaddrs(interfaces) }

        var totals: [String: (received: UInt64, sent: UInt64, address: String)] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let flags = current.pointee.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0, (flags & UInt32(IFF_LOOPBACK)) == 0,
                  let namePointer = current.pointee.ifa_name,
                  let addressPointer = current.pointee.ifa_addr
            else { continue }

            let name = String(cString: namePointer)
            let family = Int32(addressPointer.pointee.sa_family)

            if family == AF_LINK, let dataPointer = current.pointee.ifa_data {
                let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                var entry = totals[name] ?? (0, 0, "N/A")
                entry.received += UInt64(data.ifi_ibytes)
                entry.sent += UInt64(data.ifi_obytes)
                totals[name] = entry
            } else if family == AF_INET {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    addressPointer,
                    socklen_t(addressPointer.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    var entry = totals[name] ?? (0, 0, "N/A")
                    entry.address = String(cString: host)
                    totals[name] = entry
                }
            }
        }

        let now = Date()
        let preferredInterface = cachedPrimaryNetworkInterfaceName(now: now)
        let primary = preferredInterface.flatMap { name in
            totals[name].map { (key: name, value: $0) }
        } ?? totals.max(by: { left, right in
            (left.value.received + left.value.sent) < (right.value.received + right.value.sent)
        })

        guard let primary else {
            return NetworkInfo()
        }

        var download = 0.0
        var upload = 0.0
        if let previous = prevNetworkSample, previous.interfaceName == primary.key {
            let elapsed = max(0.1, now.timeIntervalSince(previous.date))
            download = Double(primary.value.received >= previous.received ? primary.value.received - previous.received : 0) / elapsed
            upload = Double(primary.value.sent >= previous.sent ? primary.value.sent - previous.sent : 0) / elapsed
        }
        prevNetworkSample = (primary.key, primary.value.received, primary.value.sent, now)

        return NetworkInfo(
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload,
            interfaceName: primary.key,
            address: primary.value.address,
            totalReceived: primary.value.received,
            totalSent: primary.value.sent
        )
    }

    private func cachedPrimaryNetworkInterfaceName(now: Date) -> String? {
        if let cachedPrimaryNetworkInterface,
           now.timeIntervalSince(cachedPrimaryNetworkInterface.refreshedAt) < Self.networkInterfaceCacheTTL {
            return cachedPrimaryNetworkInterface.name
        }

        let interfaceName = Self.primaryNetworkInterfaceName()
        if let interfaceName {
            cachedPrimaryNetworkInterface = (interfaceName, now)
        }
        return interfaceName
    }

    private static func primaryNetworkInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MacCleaner.SystemMonitor" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let interfaceName = value["PrimaryInterface"] as? String,
              !interfaceName.isEmpty
        else {
            return nil
        }

        return interfaceName
    }

    // MARK: - GPU Utilization

    private func fetchGPUUsage() -> Double {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var entry: io_registry_entry_t = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            guard let props = { () -> NSDictionary? in
                var dict: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
                return dict?.takeRetainedValue() as NSDictionary?
            }() else { continue }

            guard let perfStats = props["PerformanceStatistics"] as? NSDictionary else { continue }

            // Try "Device Utilization %" first (Apple Silicon), then "GPU Activity(%)"
            if let util = perfStats["Device Utilization %"] as? NSNumber {
                return min(max(Double(util.doubleValue) / 100.0, 0), 1)
            }
            if let util = perfStats["GPU Activity(%)"] as? NSNumber {
                return min(max(Double(util.doubleValue) / 100.0, 0), 1)
            }
            // Fallback: calculate from busy/idle cycles
            if let busy = perfStats["GPU Core Utilization"] as? NSNumber {
                return min(max(Double(busy.doubleValue) / 100.0, 0), 1)
            }
        }
        return 0
    }
}

// MARK: - Root Daemon Management

final class HelperManager: ObservableObject {
    static let shared = HelperManager()
    
    @Published var isInstalled: Bool = false
    @Published var isInstalling: Bool = false
    
    private init() {
        checkStatus()
    }
    
    func checkStatus() {
        guard let url = URL(string: "http://127.0.0.1:9099/processes") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isInstalled = (error == nil && data != nil)
            }
        }
        task.resume()
    }
    
    func installHelper(completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.main.async { self.isInstalling = true }
        
        DispatchQueue.global(qos: .utility).async {
            let daemonSource = """
            import Foundation
            import Network

            @_silgen_name("proc_pid_rusage")
            func proc_pid_rusage(_ pid: Int32, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer) -> Int32

            struct rusage_info_v4 {
                var ri_uuid: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
                var ri_user_time: UInt64 = 0
                var ri_system_time: UInt64 = 0
                var ri_pkg_idle_wkups: UInt64 = 0
                var ri_interrupt_wkups: UInt64 = 0
                var ri_pageins: UInt64 = 0
                var ri_wired_size: UInt64 = 0
                var ri_resident_size: UInt64 = 0
                var ri_phys_footprint: UInt64 = 0
                var ri_proc_start_abstime: UInt64 = 0
                var ri_proc_exit_abstime: UInt64 = 0
                var ri_child_user_time: UInt64 = 0
                var ri_child_system_time: UInt64 = 0
                var ri_child_pkg_idle_wkups: UInt64 = 0
                var ri_child_interrupt_wkups: UInt64 = 0
                var ri_child_pageins: UInt64 = 0
                var ri_child_elapsed_abstime: UInt64 = 0
                var ri_diskio_bytesread: UInt64 = 0
                var ri_diskio_byteswritten: UInt64 = 0
                var ri_cpu_time_qos_default: UInt64 = 0
                var ri_cpu_time_qos_maintenance: UInt64 = 0
                var ri_cpu_time_qos_background: UInt64 = 0
                var ri_cpu_time_qos_utility: UInt64 = 0
                var ri_cpu_time_qos_legacy: UInt64 = 0
                var ri_cpu_time_qos_user_initiated: UInt64 = 0
                var ri_cpu_time_qos_user_interactive: UInt64 = 0
                var ri_billed_system_time: UInt64 = 0
                var ri_serviced_system_time: UInt64 = 0
                var ri_logical_writes: UInt64 = 0
                var ri_lifetime_max_phys_footprint: UInt64 = 0
                var ri_instructions: UInt64 = 0
                var ri_cycles: UInt64 = 0
                var ri_billed_energy: UInt64 = 0
                var ri_serviced_energy: UInt64 = 0
                var ri_interval_max_phys_footprint: UInt64 = 0
                var ri_runnable_time: UInt64 = 0
            }

            struct ProcessInfoPayload: Codable {
                let pid: Int32
                let footprint: UInt64
                let diskRead: UInt64
                let diskWritten: UInt64
            }

            let RUSAGE_INFO_V4: Int32 = 4

            func fetchAllUsage() -> [ProcessInfoPayload] {
                let task = Process()
                task.launchPath = "/bin/ps"
                task.arguments = ["-axo", "pid"]
                let pipe = Pipe()
                task.standardOutput = pipe
                try? task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                guard let out = String(data: data, encoding: .utf8) else { return [] }
                
                var results: [ProcessInfoPayload] = []
                let lines = out.components(separatedBy: .newlines).dropFirst()
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, let pid = Int32(trimmed) else { continue }
                    
                    var ru = rusage_info_v4()
                    let ret = withUnsafeMutablePointer(to: &ru) { ptr in
                        proc_pid_rusage(pid, RUSAGE_INFO_V4, ptr)
                    }
                    if ret == 0 {
                        results.append(ProcessInfoPayload(
                            pid: pid,
                            footprint: ru.ri_phys_footprint,
                            diskRead: ru.ri_diskio_bytesread,
                            diskWritten: ru.ri_diskio_byteswritten
                        ))
                    }
                }
                return results
            }

            func processName(pid: Int32) -> String {
                let task = Process()
                task.launchPath = "/bin/ps"
                task.arguments = ["-p", "\\(pid)", "-o", "comm="]
                let pipe = Pipe()
                task.standardOutput = pipe
                try? task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }

            func isProtectedProcess(pid: Int32) -> Bool {
                if pid <= 1 { return true }
                let name = processName(pid: pid).lowercased()
                let protectedNames = [
                    "kernel_task", "launchd", "windowserver", "logd", "mds", "mds_stores",
                    "coreaudiod", "configd", "opendirectoryd", "diskarbitrationd"
                ]
                if protectedNames.contains(where: { name.contains($0) }) { return true }
                return name.hasPrefix("com.apple.security") ||
                    name.hasPrefix("com.apple.system") ||
                    name.hasPrefix("kernel")
            }

            func terminateProcess(pid: Int32) -> Bool {
                guard !isProtectedProcess(pid: pid) else { return false }
                if kill(pid, SIGTERM) == 0 { return true }
                Thread.sleep(forTimeInterval: 1.0)
                if kill(pid, 0) != 0 { return true }
                return kill(pid, SIGKILL) == 0
            }

            func handleRequest(request: String) -> Data? {
                if request.contains("GET /processes") {
                    let payload = fetchAllUsage()
                    if let jsonData = try? JSONEncoder().encode(payload) {
                        let responseStr = "HTTP/1.1 200 OK\\r\\nContent-Type: application/json\\r\\nContent-Length: \\(jsonData.count)\\r\\n\\r\\n"
                        var respData = responseStr.data(using: .utf8)!
                        respData.append(jsonData)
                        return respData
                    }
                } else if request.contains("POST /purge") {
                    let p = Process()
                    p.launchPath = "/usr/sbin/purge"
                    try? p.run()
                    p.waitUntilExit()
                    let responseStr = "HTTP/1.1 200 OK\\r\\nContent-Length: 2\\r\\n\\r\\nOK"
                    return responseStr.data(using: .utf8)
                } else if request.contains("POST /kill"), let urlStr = request.components(separatedBy: " ").dropFirst().first {
                    if let comps = URLComponents(string: urlStr),
                       let pidStr = comps.queryItems?.first(where: { $0.name == "pid" })?.value,
                       let pid = Int32(pidStr) {
                        if terminateProcess(pid: pid) {
                            let responseStr = "HTTP/1.1 200 OK\\r\\nContent-Length: 2\\r\\n\\r\\nOK"
                            return responseStr.data(using: .utf8)
                        }
                        let responseStr = "HTTP/1.1 403 Forbidden\\r\\nContent-Length: 0\\r\\n\\r\\n"
                        return responseStr.data(using: .utf8)
                    }
                }
                let responseStr = "HTTP/1.1 404 Not Found\\r\\nContent-Length: 0\\r\\n\\r\\n"
                return responseStr.data(using: .utf8)
            }

            func startServer() {
                let queue = DispatchQueue(label: "com.maccleaner.daemon.server")
                do {
                    let listener = try NWListener(using: .tcp, on: 9099)
                    listener.newConnectionHandler = { connection in
                        connection.start(queue: queue)
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                            if let data = data, let reqStr = String(data: data, encoding: .utf8) {
                                if let resp = handleRequest(request: reqStr) {
                                    connection.send(content: resp, completion: .contentProcessed { _ in
                                        connection.cancel()
                                    })
                                    return
                                }
                            }
                            connection.cancel()
                        }
                    }
                    listener.start(queue: queue)
                    print("MacCleanerDaemon started on port 9099")
                    dispatchMain()
                } catch {
                    print("Failed to start server: \\(error)")
                    exit(1)
                }
            }

            startServer()
            """
            
            let tempSource = FileManager.default.temporaryDirectory.appendingPathComponent("MacCleanerDaemon.swift")
            let tempBin = FileManager.default.temporaryDirectory.appendingPathComponent("MacCleanerDaemon")
            
            do {
                if FileManager.default.fileExists(atPath: tempSource.path) {
                    try FileManager.default.removeItem(at: tempSource)
                }
                try daemonSource.write(to: tempSource, atomically: true, encoding: .utf8)
                
                let compileTask = Process()
                compileTask.launchPath = "/usr/bin/swiftc"
                compileTask.arguments = [tempSource.path, "-o", tempBin.path]
                compileTask.launch()
                compileTask.waitUntilExit()
                
                if compileTask.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        completion(false, "Failed to compile the daemon.")
                    }
                    return
                }
                
                let plistStr = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>Label</key>
                    <string>com.maccleaner.daemon</string>
                    <key>ProgramArguments</key>
                    <array>
                        <string>/Library/PrivilegedHelperTools/com.maccleaner.daemon</string>
                    </array>
                    <key>RunAtLoad</key>
                    <true/>
                    <key>KeepAlive</key>
                    <true/>
                </dict>
                </plist>
                """
                
                let tempPlist = FileManager.default.temporaryDirectory.appendingPathComponent("com.maccleaner.daemon.plist")
                try plistStr.write(to: tempPlist, atomically: true, encoding: .utf8)
                
                let shellCmd = "mkdir -p /Library/PrivilegedHelperTools && cp '\(tempBin.path)' /Library/PrivilegedHelperTools/com.maccleaner.daemon && chown root:wheel /Library/PrivilegedHelperTools/com.maccleaner.daemon && chmod 755 /Library/PrivilegedHelperTools/com.maccleaner.daemon && cp '\(tempPlist.path)' /Library/LaunchDaemons/com.maccleaner.daemon.plist && chown root:wheel /Library/LaunchDaemons/com.maccleaner.daemon.plist && chmod 644 /Library/LaunchDaemons/com.maccleaner.daemon.plist && (launchctl unload /Library/LaunchDaemons/com.maccleaner.daemon.plist 2>/dev/null || true) && launchctl load -w /Library/LaunchDaemons/com.maccleaner.daemon.plist"
                
                let safeShellCmd = shellCmd
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                
                let script = "do shell script \"\(safeShellCmd)\" with administrator privileges"
                
                let osaScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("install_helper.applescript")
                try script.write(to: osaScriptURL, atomically: true, encoding: .utf8)
                
                let osaTask = Process()
                osaTask.launchPath = "/usr/bin/osascript"
                osaTask.arguments = [osaScriptURL.path]
                let errPipe = Pipe()
                osaTask.standardError = errPipe
                
                osaTask.launch()
                osaTask.waitUntilExit()
                
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                
                DispatchQueue.main.async {
                    self.isInstalling = false
                    if osaTask.terminationStatus == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.checkStatus()
                            completion(true, nil)
                        }
                    } else {
                        completion(false, "Failed (\(osaTask.terminationStatus)): \(errStr)")
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
}
