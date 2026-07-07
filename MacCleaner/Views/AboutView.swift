import SwiftUI
import IOKit
import AppKit

// MARK: - Hardware info helpers

struct HardwareInfo {
    static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static var macModelName: String {
        // Map model identifier to marketing name
        let id = macModel
        let map: [(String, String)] = [
            ("Mac16,", "MacBook Pro (M4)"),
            ("Mac15,6", "MacBook Pro 14\" (M3 Pro)"),
            ("Mac15,7", "MacBook Pro 16\" (M3 Pro)"),
            ("Mac15,8", "MacBook Pro 14\" (M3 Max)"),
            ("Mac15,9", "MacBook Pro 16\" (M3 Max)"),
            ("Mac15,3", "MacBook Pro 14\" (M3)"),
            ("Mac15,", "MacBook Pro (M3)"),
            ("Mac14,5", "MacBook Pro 14\" (M2 Max)"),
            ("Mac14,6", "MacBook Pro 16\" (M2 Max)"),
            ("Mac14,9", "MacBook Pro 14\" (M2 Pro)"),
            ("Mac14,10","MacBook Pro 16\" (M2 Pro)"),
            ("Mac14,", "MacBook Pro (M2)"),
            ("MacBookPro18,", "MacBook Pro (M1 Pro/Max)"),
            ("MacBookPro17,", "MacBook Pro 13\" (M1)"),
            ("Mac14,2", "MacBook Air (M2)"),
            ("Mac15,12","MacBook Air 13\" (M3)"),
            ("Mac15,13","MacBook Air 15\" (M3)"),
            ("MacBookAir10,", "MacBook Air (M1)"),
            ("Mac14,3", "Mac mini (M2)"),
            ("Mac14,12","Mac mini (M2 Pro)"),
            ("Macmini9,1","Mac mini (M1)"),
            ("Mac13,1", "Mac Studio (M1 Max)"),
            ("Mac13,2", "Mac Studio (M1 Ultra)"),
            ("Mac14,13","Mac Studio (M2 Max)"),
            ("Mac14,14","Mac Studio (M2 Ultra)"),
            ("iMac21,", "iMac (M1)"),
            ("iMac24,", "iMac (M3)"),
            ("MacPro7,1","Mac Pro"),
        ]
        for (prefix, name) in map {
            if id.hasPrefix(prefix) { return name }
        }
        return id
    }

    static var chipName: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let brand = String(cString: buf)
        if brand.isEmpty {
            // Apple Silicon — read from IORegistry
            let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/AppleARMPE/cpu0")
            if entry != IO_OBJECT_NULL {
                if let name = IORegistryEntryCreateCFProperty(entry, "chip-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    IOObjectRelease(entry)
                    let _ = name
                }
                IOObjectRelease(entry)
            }
            // Fallback: from model id
            let m = macModel
            if m.contains("Mac16") { return "Apple M4" }
            if m.contains("Mac15") { return "Apple M3" }
            if m.contains("Mac14") { return "Apple M2" }
            if m.contains("MacBookPro18") || m.contains("MacBookAir10") || m.contains("Macmini9") { return "Apple M1" }
            return "Apple Silicon"
        }
        return brand
    }

    static var ramGB: Int {
        Int(Foundation.ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    static var coreCount: (performance: Int, efficiency: Int) {
        var pCores = 0, eCores = 0
        var size = MemoryLayout<Int32>.size
        var val: Int32 = 0
        sysctlbyname("hw.perflevel0.physicalcpu", &val, &size, nil, 0)
        pCores = Int(val)
        val = 0
        sysctlbyname("hw.perflevel1.physicalcpu", &val, &size, nil, 0)
        eCores = Int(val)
        return (pCores, eCores)
    }

    static var osVersion: String {
        let v = Foundation.ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var osBuildNumber: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static var osName: String {
        let v = Foundation.ProcessInfo.processInfo.operatingSystemVersion
        switch v.majorVersion {
        case 15: return "Sequoia"
        case 14: return "Sonoma"
        case 13: return "Ventura"
        case 12: return "Monterey"
        default: return ""
        }
    }

    static var serialNumber: String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return "N/A" }
        defer { IOObjectRelease(platformExpert) }
        guard let serial = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String else { return "N/A" }
        return serial
    }

    static var bootDisk: (name: String, free: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        let vals = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let name = vals?.volumeName ?? "Macintosh HD"
        let total = UInt64(vals?.volumeTotalCapacity ?? 0)
        let avail = UInt64(vals?.volumeAvailableCapacity ?? 0)
        return (name, avail, total)
    }

    static var gpuCoreCount: Int {
        // Apple Silicon GPU cores from IORegistry
        let entry = IOServiceGetMatchingService(kIOMainPortDefault,
            IOServiceMatching("AGXAccelerator"))
        if entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            if let val = IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int { return val }
        }
        // Fallback from model id
        let m = macModel
        if m.contains("Mac15,8") || m.contains("Mac15,9") { return 40 }  // M3 Max
        if m.contains("Mac15,6") || m.contains("Mac15,7") { return 18 }  // M3 Pro
        if m.contains("Mac15,3") { return 10 }  // M3
        if m.contains("Mac14,5") || m.contains("Mac14,6") { return 38 }  // M2 Max
        if m.contains("Mac14,9") || m.contains("Mac14,10") { return 19 } // M2 Pro
        return 0
    }

    static var cpuArchitecture: String {
        let cores = coreCount
        if cores.performance > 0 && cores.efficiency > 0 {
            return "\(cores.performance)P + \(cores.efficiency)E cores"
        }
        return "ARM64 (Apple Silicon)"
    }

    static var displayInfo: String {
        #if canImport(AppKit)
        if let screen = NSScreen.main {
            let r = screen.frame
            let bs = screen.backingScaleFactor
            return "\(Int(r.width)) × \(Int(r.height)) @ \(Int(bs))×"
        }
        #endif
        return "N/A"
    }

    static var storageTypeLabel: String {
        // Read from IORegistry
        var iter: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IONVMeController"), &iter)
        let hasNVMe = IOIteratorNext(iter) != IO_OBJECT_NULL
        IOObjectRelease(iter)
        let bootDsk = bootDisk
        let totalGB = Int(bootDsk.total / 1_073_741_824)
        if hasNVMe { return "\(totalGB) GB NVMe SSD" }
        return "\(totalGB) GB SSD"
    }

    static var wifiInfo: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let m = String(cString: buf)
        if m.contains("Mac15") || m.contains("Mac16") { return "Wi-Fi 6E (802.11ax)" }
        if m.contains("Mac14") { return "Wi-Fi 6 (802.11ax)" }
        return "Wi-Fi 6 (802.11ax)"
    }

    static var bluetoothInfo: String { "Bluetooth 5.3" }

    static var portsInfo: String {
        let m = macModel
        if m.contains("Mac15,6") || m.contains("Mac15,7") || m.contains("Mac15,8") || m.contains("Mac15,9")
            || m.contains("Mac14,5") || m.contains("Mac14,6") || m.contains("Mac14,9") || m.contains("Mac14,10") {
            return "3× TB4 (USB4 40Gb/s) · HDMI · SDXC · MagSafe 3 · 3.5mm"
        }
        if m.contains("Mac15,3") {
            return "2× TB4 (USB4 40Gb/s) · HDMI · SDXC · MagSafe 3 · 3.5mm"
        }
        return "2× Thunderbolt / USB 4 · MagSafe 3 · 3.5mm"
    }

    static var displayResolution: String {
        #if canImport(AppKit)
        if let screen = NSScreen.main {
            let r = screen.frame
            return "\(Int(r.width)) × \(Int(r.height))"
        }
        #endif
        return "N/A"
    }

    static var uptime: String {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        let bootDate = Date(timeIntervalSince1970: Double(tv.tv_sec))
        let elapsed = Date().timeIntervalSince(bootDate)
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - AboutView

struct AboutView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var showSerial = false

    static func conditionLabel(cycles: Int) -> String {
        switch cycles {
        case 0..<300: return "Normal"
        case 300..<500: return "Good"
        case 500..<700: return "Fair"
        case 700..<900: return "Replace Soon"
        default: return cycles == 0 ? "Normal" : "Replace Now"
        }
    }

    static func conditionColor(cycles: Int) -> Color {
        switch cycles {
        case 0..<500: return .accentGreen
        case 500..<700: return .accentAmber
        default: return cycles == 0 ? .accentGreen : .accentRed
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // ── Hero ──────────────────────────────────────────────
                heroSection

                Rectangle().fill(Color.borderLight).frame(height: 1).padding(.horizontal, 32)

                // ── Specs grid ────────────────────────────────────────
                specsSection

                Rectangle().fill(Color.borderLight).frame(height: 1).padding(.horizontal, 32)

                // ── Storage ───────────────────────────────────────────
                storageSection

                Rectangle().fill(Color.borderLight).frame(height: 1).padding(.horizontal, 32)

                // ── Battery ──────────────────────────────────────────
                batterySection

                Rectangle().fill(Color.borderLight).frame(height: 1).padding(.horizontal, 32)

                // ── Hardware specs extended ──────────────────────────
                extendedSpecsSection
                    .padding(.bottom, 32)
            }
        }
        .background(Color.surfaceLight)
    }

    // MARK: Hero

    private var heroSection: some View {
        HStack(spacing: 32) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.textPrimaryLight.opacity(0.9), Color.textSecondaryLight.opacity(0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(HardwareInfo.macModelName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.textPrimaryLight)

                Text(HardwareInfo.macModel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)

                HStack(spacing: 6) {
                    Text("macOS \(HardwareInfo.osName)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                    Text("·").foregroundStyle(Color.textTertiaryLight)
                    Text(HardwareInfo.osVersion)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.accentBlue)
                    Text("(\(HardwareInfo.osBuildNumber))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiaryLight)
                    Text("Uptime: \(HardwareInfo.uptime)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
    }

    // MARK: Specs

    private var specsSection: some View {
        let cores = HardwareInfo.coreCount
        let coreStr = cores.performance > 0
            ? "\(cores.performance + cores.efficiency)-core (\(cores.performance)P + \(cores.efficiency)E)"
            : "\(Foundation.ProcessInfo.processInfo.processorCount)-core"
        let gpuCores = HardwareInfo.gpuCoreCount

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
            AboutSpecRow(icon: "cpu",          label: "Chip",          value: HardwareInfo.chipName)
            AboutSpecRow(icon: "memorychip",   label: "Unified Memory", value: "\(HardwareInfo.ramGB) GB")
            AboutSpecRow(icon: "bolt.fill",    label: "CPU Cores",     value: coreStr)
            AboutSpecRow(icon: "display",      label: "GPU Cores",     value: gpuCores > 0 ? "\(gpuCores)-core GPU" : "Integrated")
            AboutSpecRow(icon: "display",      label: "Display",       value: HardwareInfo.displayResolution)
            AboutSpecRow(icon: "internaldrive",label: "Neural Engine", value: "16-core")
            AboutSpecRow(icon: "number",       label: "Serial Number",
                         value: showSerial ? HardwareInfo.serialNumber : "•••••••••••••",
                         action: { showSerial.toggle() },
                         actionLabel: showSerial ? "Hide" : "Show")
            AboutSpecRow(icon: "calendar",     label: "macOS Build",   value: HardwareInfo.osBuildNumber)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: Storage

    private var storageSection: some View {
        let disk = HardwareInfo.bootDisk
        let usedPct = disk.total > 0 ? Double(disk.total - disk.free) / Double(disk.total) : 0
        let usedGB = Double(disk.total - disk.free) / 1_073_741_824
        let totalGB = Double(disk.total) / 1_073_741_824

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentBlue)
                Text(disk.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Spacer()
                Text(String(format: "%.0f GB free of %.0f GB", Double(disk.free)/1e9, totalGB))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
            }

            // Segmented storage bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.borderLight)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: usedPct > 0.9
                                    ? [.accentRed, .accentAmber]
                                    : [.accentBlue, Color.accentBlue.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * usedPct, height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                StorageLegend(color: .accentBlue, label: "Used",
                               value: String(format: "%.1f GB", usedGB))
                Spacer()
                StorageLegend(color: Color.borderLight, label: "Free",
                               value: String(format: "%.1f GB", Double(disk.free)/1e9))
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    // MARK: Battery

    private var batterySection: some View {
        let bat = monitor.battery
        let health = bat.healthPercent
        let healthColor: Color = health > 90 ? .accentGreen : health > 75 ? .accentAmber : .accentRed
        let chargeFrac = min(1.0, Double(bat.chargePercent) / 100.0)
        let chargeColor: Color = bat.chargePercent > 50 ? .accentGreen
            : bat.chargePercent > 20 ? .accentAmber : .accentRed

        return VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "battery.100.bolt")
                    .font(.system(size: 13))
                    .foregroundStyle(healthColor)
                Text("Battery")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(healthColor).frame(width: 6, height: 6)
                    Text(bat.healthLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(healthColor)
                }
            }

            // Charge bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(bat.isCharging ? "Charging" : bat.isPluggedIn ? "Connected" : "On Battery")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                    Spacer()
                    HStack(spacing: 4) {
                        if bat.isCharging {
                            Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(Color.accentAmber)
                        }
                        Text("\(bat.chargePercent)%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(chargeColor)
                        if bat.timeRemaining > 0 {
                            Text("· \(bat.timeRemaining / 60)h \(bat.timeRemaining % 60)m")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                        } else if bat.timeRemaining == -1 {
                            Text("· Calculating…")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                        }
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.borderLight).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(
                            LinearGradient(colors: [chargeColor, chargeColor.opacity(0.7)],
                                           startPoint: .leading, endPoint: .trailing)
                        ).frame(width: geo.size.width * chargeFrac, height: 8)
                    }
                }.frame(height: 8)
            }

            // Health + cycle grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                 GridItem(.flexible())], spacing: 10) {
                BatteryStatTile(label: "Health",
                    value: String(format: "%.1f%%", health),
                    sub: bat.healthLabel,
                    color: healthColor)
                BatteryStatTile(label: "Cycle Count",
                    value: bat.cycleCount > 0 ? "\(bat.cycleCount)" : "—",
                    sub: "of ~1000",
                    color: bat.cycleCount > 900 ? .accentRed : bat.cycleCount > 700 ? .accentAmber : .accentGreen)
                BatteryStatTile(label: "Capacity",
                    value: bat.maxCapacity > 0 ? "\(bat.maxCapacity) mAh" : "—",
                    sub: bat.designCapacity > 0 ? "Design: \(bat.designCapacity)" : "Design cap.",
                    color: .accentBlue)
            }

            // Electrical readings
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                 GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                BatteryStatTile(label: "Voltage",
                    value: bat.voltage > 0 ? String(format: "%.2f V", bat.voltage) : "—",
                    sub: "nominal 11.4V", color: Color.textSecondaryLight)
                BatteryStatTile(label: "Current",
                    value: bat.amperage != 0 ? String(format: "%.2f A", bat.amperage) : "—",
                    sub: bat.amperage < 0 ? "discharging" : "charging", color: Color.textSecondaryLight)
                BatteryStatTile(label: "Power",
                    value: bat.wattage > 0 ? String(format: "%.1f W", bat.wattage) : "—",
                    sub: "instantaneous", color: Color.textSecondaryLight)
                BatteryStatTile(label: "Temperature",
                    value: bat.temperature > 0 ? String(format: "%.1f°C", bat.temperature) : "—",
                    sub: bat.temperature > 40 ? "⚠ High" : "normal",
                    color: bat.temperature > 40 ? .accentRed : Color.textSecondaryLight)
            }

            // Battery Condition (based on cycles + health)
            let conditionLabel = Self.conditionLabel(cycles: bat.cycleCount)
            let conditionColor = Self.conditionColor(cycles: bat.cycleCount)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Battery Condition")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(conditionColor).frame(width: 5, height: 5)
                        Text(conditionLabel)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(conditionColor)
                    }
                }
                if bat.designCapacity > 0 && bat.maxCapacity > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.borderLight).frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(healthColor)
                                .frame(width: geo.size.width * (health / 100), height: 5)
                            Rectangle()
                                .fill(Color.accentRed.opacity(0.35))
                                .frame(width: geo.size.width * max(0, (100 - health) / 100), height: 5)
                                .offset(x: geo.size.width * (health / 100))
                        }
                    }.frame(height: 5)
                    HStack {
                        Text(String(format: "%.0f mAh remaining", Double(bat.maxCapacity)))
                            .font(.mono(8)).foregroundStyle(.textTertiary)
                        Spacer()
                        Text(String(format: "Design: %.0f mAh  ·  %.1f%% capacity", Double(bat.designCapacity), health))
                            .font(.mono(8)).foregroundStyle(.textTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    // MARK: Extended Specs

    private var extendedSpecsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 13)).foregroundStyle(.accent)
                Text("Full Specifications")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.textPrimary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 4)

            let specs: [(String, String, String)] = [
                ("cpu",           "Processor",          HardwareInfo.chipName),
                ("memorychip",    "Total Memory",       "\(HardwareInfo.ramGB) GB Unified Memory"),
                ("bolt.fill",     "CPU Architecture",   HardwareInfo.cpuArchitecture),
                ("display",       "Display",            HardwareInfo.displayInfo),
                ("internaldrive", "Storage",            HardwareInfo.storageTypeLabel),
                ("network",       "Wi-Fi",              HardwareInfo.wifiInfo),
                ("antenna.radiowaves.left.and.right", "Bluetooth", HardwareInfo.bluetoothInfo),
                ("cable.connector", "Ports",            HardwareInfo.portsInfo),
                ("speaker.wave.2","Audio",              "6‑speaker sound system"),
                ("camera",        "Camera",             "1080p FaceTime HD"),
                ("keyboard",      "Keyboard",           "Magic Keyboard with Touch ID"),
                ("clock",         "Uptime",             HardwareInfo.uptime),
                ("number",        "Serial Number",
                                  showSerial ? HardwareInfo.serialNumber : "•••••••••••••"),
                ("calendar",      "macOS Build",        HardwareInfo.osBuildNumber),
            ]

            ForEach(Array(specs.enumerated()), id: \.offset) { _, spec in
                HStack(spacing: 12) {
                    Image(systemName: spec.0)
                        .font(.system(size: 11))
                        .foregroundStyle(.accent.opacity(0.8))
                        .frame(width: 16)
                    Text(spec.1)
                        .font(.mono(10))
                        .foregroundStyle(.textTertiary)
                        .frame(width: 130, alignment: .leading)
                    Text(spec.2)
                        .font(.system(size: 12))
                        .foregroundStyle(.textPrimary)
                    if spec.1 == "Serial Number" {
                        Button(showSerial ? "Hide" : "Show") { showSerial.toggle() }
                            .font(.mono(8)).foregroundStyle(.accent).buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 8)
                .background(specs.firstIndex(where: { $0.1 == spec.1 }).map { $0 % 2 == 0 }
                    .map { $0 ? Color.surfaceElevated.opacity(0.3) : Color.clear } ?? Color.clear)
            }
        }
    }
}

// MARK: - Sub-components

private struct AboutSpecRow: View {
    let icon: String
    let label: String
    let value: String
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textPrimaryLight)
                    if let action = action, let lbl = actionLabel {
                        Button(lbl, action: action)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color.accentBlue)
                            .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct StorageLegend: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
            Text(value).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Color.textSecondaryLight)
        }
    }
}

private struct BatteryStatTile: View {
    let label: String
    let value: String
    let sub: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textSecondaryLight)
            Text(sub)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color.textTertiaryLight)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight))
    }
}
