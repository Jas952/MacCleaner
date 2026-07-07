import SwiftUI

struct DiskDetailView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disk")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text("Macintosh HD · APFS Storage")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Rectangle().fill(Color.borderLight).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(monitor.disks.filter { $0.mountPoint == "/" }) { disk in
                        DiskVolumeCard(disk: disk)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .background(Color.surfaceLight)
    }
}

// MARK: - DiskVolumeCard

struct DiskVolumeCard: View {
    let disk: DiskInfo

    private var accent: Color {
        disk.usedPercent > 0.9 ? .accentRed
            : disk.usedPercent > 0.75 ? .accentAmber
            : Color(red: 0.3, green: 0.75, blue: 0.55)
    }
    private var pressureLabel: String {
        disk.usedPercent > 0.9 ? "Critical"
            : disk.usedPercent > 0.8 ? "High"
            : disk.usedPercent > 0.6 ? "Moderate" : "Healthy"
    }

    private let spaceCategories: [(name: String, icon: String, ratio: Double, color: Color)] = [
        ("System & Apps",  "internaldrive",   0.25, Color(red: 0.55, green: 0.45, blue: 0.9)),
        ("User Documents", "doc.text.fill",   0.30, Color(red: 0.25, green: 0.65, blue: 1.0)),
        ("Photos & Video", "photo.fill",      0.20, Color(red: 0.3,  green: 0.75, blue: 0.55)),
        ("Caches & Logs",  "archivebox.fill", 0.12, Color(red: 0.95, green: 0.65, blue: 0.25)),
        ("Other",          "ellipsis.circle", 0.13, Color.gray),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Volume title
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accent.opacity(0.1)).frame(width: 36, height: 36)
                    Image(systemName: disk.mountPoint == "/" ? "internaldrive.fill" : "externaldrive.fill")
                        .font(.system(size: 15)).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.volumeName)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.textPrimaryLight)
                    Text(disk.mountPoint == "/" ? "Boot Volume · APFS" : disk.mountPoint)
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f%%", disk.usedPercent * 100))
                        .font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(accent)
                    Text("used").font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                }
            }

            // Stable capacity bar — NO .animation modifier to avoid constant flicker
            DiskCapacityBar(usedFraction: disk.usedPercent, color: accent)

            // Stat strip
            HStack(spacing: 0) {
                DiskStatCell(label: "USED",  value: DiskInfo.formatted(disk.used),  color: accent)
                Rectangle().fill(Color.borderLight).frame(width: 1, height: 30)
                DiskStatCell(label: "FREE",  value: DiskInfo.formatted(disk.free),
                             color: Color.accentGreen)
                Rectangle().fill(Color.borderLight).frame(width: 1, height: 30)
                DiskStatCell(label: "TOTAL", value: DiskInfo.formatted(disk.total), color: Color.textSecondaryLight)
            }
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight))

            // Storage pressure badge
            HStack(spacing: 8) {
                Image(systemName: disk.usedPercent > 0.8
                      ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 12)).foregroundStyle(accent)
                Text("Storage Pressure: \(pressureLabel)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.textPrimaryLight)
                Spacer()
                Text(DiskInfo.formatted(disk.free) + " available")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(accent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accent.opacity(0.2)))

            // Estimated space breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("ESTIMATED SPACE BREAKDOWN")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                let usedGB = Double(disk.used) / 1_073_741_824
                ForEach(spaceCategories, id: \.name) { cat in
                    let estGB = usedGB * cat.ratio
                    HStack(spacing: 8) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 10)).foregroundStyle(cat.color).frame(width: 14)
                        Text(cat.name)
                            .font(.system(size: 11)).foregroundStyle(Color.textPrimaryLight)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.borderLight).frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cat.color.opacity(0.8))
                                    .frame(width: max(4, g.size.width * CGFloat(cat.ratio)), height: 4)
                            }
                        }
                        .frame(width: 80, height: 4)
                        Text(String(format: "~%.1f GB", estGB))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }
            .padding(10)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight))

            // Key metrics
            VStack(alignment: .leading, spacing: 6) {
                Text("KEY METRICS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                let totalGB = Double(disk.total) / 1_073_741_824
                let freeGB  = Double(disk.free)  / 1_073_741_824
                let usedGB2 = Double(disk.used)  / 1_073_741_824
                let rows: [(String, String, String)] = [
                    ("internaldrive.fill",    "Total Capacity",
                     String(format: "%.0f GB", totalGB)),
                    ("checkmark.circle.fill", "Available Space",
                     String(format: "%.1f GB", freeGB)),
                    ("minus.circle.fill",     "Used Space",
                     String(format: "%.1f GB (%.0f%%)", usedGB2, disk.usedPercent * 100)),
                    ("bolt.fill",             "Filesystem",
                     disk.mountPoint == "/" ? "APFS (SSD)" : "External Volume"),
                ]
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row.0)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentGreen)
                            .frame(width: 14)
                        Text(row.1)
                            .font(.system(size: 11)).foregroundStyle(Color.textSecondaryLight)
                        Spacer()
                        Text(row.2)
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Color.textPrimaryLight)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.surfaceLight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight))
        }
        .padding(16)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight))
    }
}

// MARK: - DiskCapacityBar (no animation to prevent per-tick flicker)

struct DiskCapacityBar: View {
    let usedFraction: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.borderLight)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(4, g.size.width * CGFloat(usedFraction)), height: 10)
                }
            }
            .frame(height: 10)
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text("Used").font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.borderLight).frame(width: 6, height: 6)
                    Text("Free").font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                }
            }
        }
    }
}

// MARK: - DiskStatCell

struct DiskStatCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}
