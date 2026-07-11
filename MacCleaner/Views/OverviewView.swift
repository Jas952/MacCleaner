import SwiftUI

// MARK: - Dashboard (single-screen)

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var lastRefreshTime: Date = .distantPast
    @State private var detailProcess: ProcessNode? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ──────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dashboard")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        Text("Live metrics · Light data every 15s · deep data adapts to the visible screen")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                    Spacer()
                    Button {
                        let now = Date()
                        if now.timeIntervalSince(lastRefreshTime) >= 1.0 {
                            monitor.refresh(forceProcesses: true, forceSensors: true)
                            lastRefreshTime = now
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                            Text("Refresh")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .shadow(color: Color.shadowLight, radius: 4, x: 0, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderLight, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // ── Metric Cards Grid ────────────────
                LazyVGrid(columns: dashboardColumns, spacing: 14) {
                    DashboardMetricCard(
                        icon: "cpu",
                        label: "CPU",
                        value: String(format: "%.1f%%", monitor.cpu.totalUsage * 100),
                        subtitle: "Load \(cpuLoadValue) / \(monitor.cpu.processorCount) cores · \(cpuLoadLabel.lowercased())",
                        badge: temperatureBadge(monitor.thermal.cpuTemp),
                        progress: monitor.cpu.totalUsage,
                        color: cpuColor,
                        details: [
                            ("Load", cpuLoadValue),
                            ("History", "\(Int((monitor.cpuHistory.last ?? 0) * 100))%")
                        ],
                        history: [],
                        coreUsages: monitor.cpu.coreUsages
                    )

                    MemoryDashboardCard(
                        memory: monitor.memory,
                        color: ramColor
                    )

                    if let disk = rootDisk {
                        DashboardMetricCard(
                            icon: "internaldrive",
                            label: "Disk",
                            value: DiskInfo.formatted(disk.free),
                            subtitle: "free on \(disk.volumeName)",
                            badge: String(format: "%.0f%% used", disk.usedPercent * 100),
                            progress: disk.usedPercent,
                            color: diskColor(disk.usedPercent),
                            details: [
                                ("Used", DiskInfo.formatted(disk.used)),
                                ("Total", DiskInfo.formatted(disk.total))
                            ],
                            history: []
                        )
                    }

                    DashboardMetricCard(
                        icon: "network",
                        label: "Network",
                        value: NetworkInfo.formattedRate(monitor.network.downloadBytesPerSecond),
                        subtitle: "↓ \(NetworkInfo.formattedRate(monitor.network.downloadBytesPerSecond)) · ↑ \(NetworkInfo.formattedRate(monitor.network.uploadBytesPerSecond))",
                        badge: monitor.network.interfaceName,
                        progress: networkProgress,
                        color: .accentBlue,
                        details: [
                            ("IP \(countryFlag)", monitor.network.address),
                            ("State", monitor.network.isActive ? "Active" : "Idle")
                        ],
                        history: normalizedNetworkHistory.map(\.down),
                        historySecondary: normalizedNetworkHistory.map(\.up)
                    )

                    DashboardMetricCard(
                        icon: "display",
                        label: "GPU",
                        value: String(format: "%.0f%%", monitor.gpuUsage * 100),
                        subtitle: "\(gpuLoadLabel) · \(gpuCoresLabel)",
                        badge: temperatureBadge(gpuTemperature),
                        progress: monitor.gpuUsage,
                        color: .accentAmber,
                        details: [
                            ("Chip", HardwareInfo.chipName),
                            ("Display", HardwareInfo.displayInfo)
                        ],
                        history: monitor.gpuHistory
                    )

                    BatteryDashboardCard(battery: monitor.battery)
                }
                .padding(.horizontal, 24)

                // ── Top processes inline ─────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        SectionLabel(text: "Top Processes by Memory")
                            .foregroundStyle(Color.textSecondaryLight)
                        Spacer()
                        Text("\(monitor.processNodes.count) running")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                    // Table header
                    HStack {
                        Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                        Text("PID").frame(width: 56, alignment: .trailing)
                        Text("CPU").frame(width: 60, alignment: .trailing)
                        Text("MEM").frame(width: 80, alignment: .trailing)
                        Text("").frame(width: 80)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)

                    Rectangle().fill(Color.borderLight).frame(height: 1)

                    let maxMemory = monitor.processNodes.max(by: { $0.memoryBytes < $1.memoryBytes })?.memoryBytes ?? 1
                    ForEach(Array(monitor.processNodes.prefix(15).enumerated()), id: \.element.id) { idx, proc in
                        DashProcessRow(proc: proc, maxMem: maxMemory, onTap: { detailProcess = proc })
                        if idx < 14 {
                            Rectangle().fill(Color.borderLight.opacity(0.5)).frame(height: 1)
                                .padding(.leading, 24)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.surfaceLight)
        .processDetailOverlay(selectedProcess: $detailProcess)
        .onAppear {
            monitor.setConsumer(.dashboard, active: true)
        }
        .onDisappear {
            monitor.setConsumer(.dashboard, active: false)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.borderLight).frame(height: 1)
    }
    private var ramColor: Color {
        monitor.memory.usedPercent > 0.85 ? .accentRed
            : monitor.memory.usedPercent > 0.65 ? .accentAmber : .accentBlue
    }
    private var cpuColor: Color {
        monitor.cpu.totalUsage > 0.85 ? .accentRed
            : monitor.cpu.totalUsage > 0.65 ? .accentAmber : .accentBlue
    }
    private var dashboardColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    }
    private var rootDisk: DiskInfo? {
        monitor.disks.first(where: { $0.mountPoint == "/" }) ?? monitor.disks.first
    }
    private func diskColor(_ usedPercent: Double) -> Color {
        usedPercent > 0.9 ? .accentRed : usedPercent > 0.75 ? .accentAmber : .accentGreen
    }
    private var cpuLoadLabel: String {
        monitor.cpu.totalUsage > 0.65 ? "Busy" : monitor.cpu.totalUsage > 0.2 ? "Active" : "Idle"
    }
    private var cpuLoadValue: String {
        String(format: "%.2f", monitor.cpu.totalUsage * Double(max(1, monitor.cpu.processorCount)))
    }
    private var gpuTemperature: Double {
        monitor.thermal.gpuTemp > 0 ? monitor.thermal.gpuTemp : monitor.thermal.socTemp
    }
    private var gpuLoadLabel: String {
        monitor.gpuUsage > 0.7 ? "heavy" : monitor.gpuUsage > 0.3 ? "moderate" : "idle"
    }
    private var gpuCoresLabel: String {
        let cores = HardwareInfo.gpuCoreCount
        return cores > 0 ? "\(cores) GPU cores" : "Apple GPU"
    }
    private func temperatureBadge(_ value: Double) -> String {
        value > 0 ? String(format: "%.0f°C", value) : "Live"
    }
    private var networkProgress: Double {
        min(max(monitor.network.downloadBytesPerSecond, monitor.network.uploadBytesPerSecond) / 1_048_576, 1)
    }
    private var normalizedNetworkHistory: [(down: Double, up: Double)] {
        let maxDown = max(monitor.networkHistory.map(\.down).max() ?? 0, 1)
        let maxUp = max(monitor.networkHistory.map(\.up).max() ?? 0, 1)
        let maxValue = max(maxDown, maxUp)
        return monitor.networkHistory.map { (down: min($0.down / maxValue, 1), up: min($0.up / maxValue, 1)) }
    }
    private var countryFlag: String {
        let regionCode = Locale.current.region?.identifier ?? "US"
        let base = UnicodeScalar("🇦").value
        var scalars = String.UnicodeScalarView()
        for scalar in regionCode.uppercased().unicodeScalars.prefix(2) {
            guard let flagScalar = UnicodeScalar(base + scalar.value - UnicodeScalar("A").value) else { continue }
            scalars.append(flagScalar)
        }
        return scalars.isEmpty ? "🌐" : String(scalars)
    }
}

// MARK: - Metric Tile

struct DashboardMetricCard: View {
    let icon: String
    let label: String
    let value: String
    let subtitle: String
    let badge: String
    let progress: Double
    let color: Color
    let details: [(String, String)]
    let history: [Double]
    var historySecondary: [Double]? = nil
    var coreUsages: [Double]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 8) {
                Label {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.6)
                } icon: {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(color)

                Spacer(minLength: 8)

                Text(badge)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(value)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(details.prefix(2).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.0)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.textTertiaryLight)
                            Text(item.1)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.textSecondaryLight)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                .frame(width: 88, alignment: .leading)
            }

            if let cores = coreUsages, !cores.isEmpty {
                CoreBarChart(usages: cores)
                    .frame(height: 32)
                    .padding(.top, 2)
            } else if let sec = historySecondary, history.count > 1, sec.count > 1 {
                DualSparkline(topValues: sec, bottomValues: history, topColor: .accentGreen, bottomColor: .accentBlue)
                    .frame(height: 24)
                    .padding(.top, 4)
            } else if history.count > 1 {
                Sparkline(values: history, color: color.opacity(0.75), lineWidth: 1.6)
                    .frame(height: 24)
                    .padding(.top, 4)
            } else {
                MiniBar(value: max(0, min(1, progress)), color: color.opacity(0.85), height: 6)
                    .frame(height: 24)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(height: 166)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.shadowMedium, radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
}

// MARK: - Memory Dashboard Card

struct MemoryDashboardCard: View {
    let memory: MemoryInfo
    var color: Color = .accentBlue

    private var appBytes: UInt64 {
        max(0, memory.used - memory.wired - memory.compressed)
    }

    private var segments: [(label: String, bytes: UInt64, color: Color)] {
        [
            ("App", appBytes, .accentBlue),
            ("Wired", memory.wired, Color.textSecondaryLight),
            ("Compressed", memory.compressed, .accentAmber),
            ("Cached", memory.cached, Color.textTertiaryLight),
            ("Free", memory.free, .accentGreen)
        ]
    }

    private var usedPercent: Double {
        memory.total > 0 ? Double(memory.used) / Double(memory.total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 8) {
                Label {
                    Text("MEMORY")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.6)
                } icon: {
                    Image(systemName: "memorychip")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(color)

                Spacer(minLength: 8)

                Text("\(MemoryInfo.formatted(memory.free)) free")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%.0f%%", usedPercent * 100))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("\(MemoryInfo.formatted(memory.used)) / \(MemoryInfo.formatted(memory.total))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cached")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textTertiaryLight)
                        Text(MemoryInfo.formatted(memory.cached))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.textSecondaryLight)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Wired")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textTertiaryLight)
                        Text(MemoryInfo.formatted(memory.wired))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.textSecondaryLight)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(width: 88, alignment: .leading)
            }

            MemoryBreakdownBar(segments: segments, total: memory.total)
                .frame(height: 24)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(height: 166)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.shadowMedium, radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
}

struct MemoryBreakdownBar: View {
    let segments: [(label: String, bytes: UInt64, color: Color)]
    let total: UInt64

    @State private var hoveredIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let total = Double(max(1, total))
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                    let pct = Double(segment.bytes) / total
                    let width = max(0, geo.size.width * CGFloat(pct))
                    let isHovered = hoveredIndex == idx
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? segment.color.opacity(0.85) : segment.color)
                        .overlay(
                            Group {
                                if width > 30 {
                                    Text(segment.label)
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 2)
                                }
                            }
                        )
                        .frame(width: width)
                        .onHover { isHovered in
                            hoveredIndex = isHovered ? idx : nil
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if let hoveredIndex, segments.indices.contains(hoveredIndex) {
                    let segment = segments[hoveredIndex]
                    let pct = Double(segment.bytes) / total
                    let leading = segments.prefix(hoveredIndex).reduce(0.0) { partial, item in
                        partial + Double(item.bytes) / total
                    }
                    let x = min(
                        max(0, geo.size.width * CGFloat(leading + pct / 2) - 54),
                        max(0, geo.size.width - 108)
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(segment.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        Text("\(MemoryInfo.formatted(segment.bytes)) · \(String(format: "%.0f%%", pct * 100))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.borderLight, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)
                    .offset(x: x, y: -35)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

struct BatteryDashboardCard: View {
    let battery: BatteryInfo

    private var color: Color {
        battery.chargePercent <= 20 && !battery.isPluggedIn ? .accentRed : .accentGreen
    }

    private var status: String {
        if battery.isCharging { return "Charging" }
        if battery.isPluggedIn { return "Plugged in" }
        return timeRemainingText
    }

    private var timeRemainingText: String {
        guard battery.timeRemaining > 0 else { return "Calculating" }
        let hours = battery.timeRemaining / 60
        let minutes = battery.timeRemaining % 60
        if hours > 0 { return "\(hours)h \(minutes)m left" }
        return "\(minutes)m left"
    }

    private var macRing: BatteryDeviceInfo {
        if let internalDevice = battery.devices.first(where: {
            $0.name.lowercased().contains("mac") || $0.type.lowercased().contains("internal")
        }) {
            return internalDevice
        }
        return [BatteryDeviceInfo(id: "mac", name: "Mac", type: "Internal", chargePercent: battery.chargePercent, isCharging: battery.isCharging)]
            .first!
    }

    private var airPodsRings: [BatteryDeviceInfo] {
        let devices = battery.devices.filter {
            let name = $0.name.lowercased()
            return name.contains("airpod") || name.contains("head") || name.contains("case")
        }
        let left = devices.first { $0.name.lowercased().contains(" l") }
        let right = devices.first { $0.name.lowercased().contains(" r") }
        let caseDevice = devices.first { $0.name.lowercased().contains("case") }
        return [
            left ?? BatteryDeviceInfo(id: "airpods-left-none", name: "AirPods L", type: "Bluetooth", chargePercent: 0, isCharging: false),
            right ?? BatteryDeviceInfo(id: "airpods-right-none", name: "AirPods R", type: "Bluetooth", chargePercent: 0, isCharging: false),
            caseDevice ?? BatteryDeviceInfo(id: "airpods-case-none", name: "Case", type: "Bluetooth", chargePercent: 0, isCharging: false)
        ]
    }

    private var phonePlaceholder: BatteryDeviceInfo {
        BatteryDeviceInfo(id: "phone-none", name: "iPhone", type: "Phone", chargePercent: 0, isCharging: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Label {
                    Text("BATTERY")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.6)
                } icon: {
                    Image(systemName: battery.isPluggedIn ? "battery.100.bolt" : "battery.75")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(color)

                Spacer()

                Text(healthText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(battery.chargePercent)%")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                BatteryVerticalRings(mac: macRing, airPods: airPodsRings, phone: phonePlaceholder, color: color)
                    .frame(width: 110, alignment: .trailing)
            }

            HStack(spacing: 18) {
                compactDetail("Cycles", battery.cycleCount > 0 ? "\(battery.cycleCount)" : "N/A")
                compactDetail("Power", battery.wattage > 0 ? String(format: "%.1f W", battery.wattage) : "N/A")
                compactDetail("Temp", battery.temperature > 0 ? String(format: "%.0f°C", battery.temperature) : "N/A")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(height: 166)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.shadowMedium, radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }

    private var healthText: String {
        battery.healthPercent > 0 ? String(format: "%.0f%% Health", battery.healthPercent) : "Health"
    }

    private func compactDetail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textSecondaryLight)
                .lineLimit(1)
        }
    }

}

struct BatteryVerticalRings: View {
    let mac: BatteryDeviceInfo
    let airPods: [BatteryDeviceInfo]
    let phone: BatteryDeviceInfo
    let color: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                BatteryGlyphRing(device: mac, fallbackName: "Mac", marker: nil, color: color)
                BatteryGlyphRing(device: phone, fallbackName: "iPhone", marker: nil, color: color, isAvailableOverride: false)
                BatteryGlyphRing(device: airPods[safe: 2], fallbackName: "Case", marker: nil, color: color)
            }
            HStack(spacing: 8) {
                BatteryGlyphRing(device: airPods[safe: 0], fallbackName: "AirPods L", marker: "L", color: color)
                BatteryGlyphRing(device: airPods[safe: 1], fallbackName: "AirPods R", marker: "R", color: color)
            }
        }
    }
}

struct BatteryGlyphRing: View {
    let device: BatteryDeviceInfo?
    let fallbackName: String
    let marker: String?
    let color: Color
    var isAvailableOverride: Bool?

    private var resolvedDevice: BatteryDeviceInfo {
        device ?? BatteryDeviceInfo(id: fallbackName, name: fallbackName, type: fallbackName, chargePercent: 0, isCharging: false)
    }

    private var isAvailable: Bool {
        isAvailableOverride ?? !(resolvedDevice.id.hasSuffix("-none") || resolvedDevice.id == "phone-none")
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.borderLight.opacity(0.55), lineWidth: 3)
            Circle()
                .trim(from: 0, to: isAvailable ? Double(max(0, min(100, resolvedDevice.chargePercent))) / 100 : 0)
                .stroke(isAvailable ? color : Color.clear, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                if let marker {
                    Text(marker)
                        .font(.system(size: 6, weight: .bold, design: .rounded))
                        .offset(x: 4, y: 2)
                }
            }
            .foregroundStyle(isAvailable ? Color.textSecondaryLight : Color.textTertiaryLight)
        }
        .frame(width: 31, height: 31)
    }

    private var iconName: String {
        let lower = resolvedDevice.name.lowercased()
        if lower.contains("phone") || lower.contains("iphone") { return "iphone" }
        if lower.contains("case") { return "airpods.chargingcase" }
        if lower.contains("airpod") || lower.contains("head") { return "headphones" }
        return "laptopcomputer"
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct BatteryDeviceRing: View {
    let device: BatteryDeviceInfo
    let color: Color
    var showsPercent: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.borderLight, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: Double(max(0, min(100, device.chargePercent))) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
            }
            .frame(width: 36, height: 36)

            Text(shortName)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
                .lineLimit(1)
                .frame(width: showsPercent ? 50 : 42)
        }
    }

    private var iconName: String {
        let lower = device.name.lowercased()
        if lower.contains("mouse") { return "computermouse" }
        if lower.contains("keyboard") { return "keyboard" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if lower.contains("phone") || lower.contains("iphone") { return "iphone" }
        if lower.contains("case") { return "airpods.chargingcase" }
        if lower.contains("head") || lower.contains("airpod") { return "headphones" }
        return "laptopcomputer"
    }

    private var shortName: String {
        let trimmed = device.name
            .replacingOccurrences(of: "Magic ", with: "")
            .replacingOccurrences(of: "Battery", with: "")
            .replacingOccurrences(of: "MacBook", with: "Mac")
            .replacingOccurrences(of: "Dmitriy’s ", with: "")
            .replacingOccurrences(of: "Dmitriy's ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Device" : trimmed
        return showsPercent ? "\(name) \(device.chargePercent)%" : name
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let sub: String
    let progress: Double
    let history: [Double]
    let barColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: label)
                .padding(.bottom, 8)

            Text(value)
                .font(.mono(28, weight: .semibold))
                .foregroundStyle(.textPrimary)
                .padding(.bottom, 2)

            Text(sub)
                .font(.mono(10))
                .foregroundStyle(.textSecondary)
                .padding(.bottom, 10)

            MiniBar(value: progress, color: barColor, height: 2)
                .padding(.bottom, 8)

            if history.count > 1 {
                Sparkline(values: history, color: barColor.opacity(0.6), lineWidth: 1)
                    .frame(height: 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Metric Card Light (Glass Card Style)

struct MetricCardLight: View {
    let label: String
    let value: String
    let sub: String
    let progress: Double
    let barColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Label
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiaryLight)
            
            // Value
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(barColor)
            
            // Subtitle
            Text(sub)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondaryLight)
            
            Spacer()
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.borderLight)
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(20)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.shadowMedium, radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
}

// MARK: - Dashboard Process Row

struct DashProcessRow: View {
    let proc: ProcessNode
    let maxMem: UInt64
    var onTap: (() -> Void)? = nil

    @State private var hovered = false

    private var cpuColor: Color {
        proc.cpuUsage > 50 ? .accentRed : proc.cpuUsage > 10 ? .accentAmber : Color.textSecondaryLight
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                ProcessIconView(commandLine: proc.commandLine, size: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(proc.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                    if proc.isBackgroundAgent {
                        Text("background agent")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(proc.id)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textTertiaryLight)
                .frame(width: 56, alignment: .trailing)

            Text(String(format: "%.1f%%", proc.cpuUsage))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(cpuColor)
                .frame(width: 60, alignment: .trailing)

            Text(MemoryInfo.formatted(proc.memoryBytes))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color.textSecondaryLight)
                .frame(width: 80, alignment: .trailing)

            MiniBar(value: maxMem > 0 ? Double(proc.memoryBytes) / Double(maxMem) : 0,
                    color: .accentBlue, height: 2)
                .frame(width: 70)
                .padding(.leading, 10)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(hovered ? Color.borderLight.opacity(0.4) : Color.clear)
        .onHover { hovered = $0 }
        .onTapGesture { onTap?() }
    }
}
