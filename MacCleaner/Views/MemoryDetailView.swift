import SwiftUI

struct MemoryDetailView: View {
    @ObservedObject var monitor: SystemMonitor

    private var pressureLabel: String {
        let p = monitor.memory.usedPercent
        if p > 0.9 { return "Critical" }
        if p > 0.75 { return "High" }
        if p > 0.5  { return "Moderate" }
        return "Normal"
    }
    private var pressureColor: Color {
        let p = monitor.memory.usedPercent
        if p > 0.9 { return .accentRed }
        if p > 0.75 { return .accentAmber }
        if p > 0.5  { return .accentAmber }
        return .accentGreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text("RAM usage and pressure")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(pressureColor).frame(width: 6, height: 6)
                    Text(pressureLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(pressureColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(pressureColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(pressureColor.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Rectangle().fill(Color.borderLight).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Big stats row - in cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MemStatTile(label: "TOTAL", value: MemoryInfo.formatted(monitor.memory.total), color: Color.textSecondaryLight)
                        MemStatTile(label: "USED",  value: MemoryInfo.formatted(monitor.memory.used),  color: pressureColor)
                        MemStatTile(label: "FREE",  value: MemoryInfo.formatted(monitor.memory.free),  color: .accentGreen)
                        MemStatTile(label: "WIRED", value: MemoryInfo.formatted(monitor.memory.wired), color: Color.textSecondaryLight)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)

                    // Ring + breakdown
                    HStack(alignment: .center, spacing: 32) {
                        ZStack {
                            ThinRing(progress: monitor.memory.usedPercent, color: pressureColor, lineWidth: 12, size: 140)
                            VStack(spacing: 2) {
                                Text(String(format: "%.0f%%", monitor.memory.usedPercent * 100))
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.textPrimaryLight)
                                Text("in use")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textTertiaryLight)
                            }
                        }
                        .frame(width: 140, height: 140)

                        VStack(spacing: 0) {
                            MemBreakRow(label: "App Memory",
                                        bytes: max(0, monitor.memory.used - monitor.memory.wired - monitor.memory.compressed),
                                        total: monitor.memory.total, color: .accentBlue)
                            Rectangle().fill(Color.borderLight).frame(height: 1).padding(.leading, 8)
                            MemBreakRow(label: "Wired",      bytes: monitor.memory.wired,      total: monitor.memory.total, color: Color.textSecondaryLight)
                            Rectangle().fill(Color.borderLight).frame(height: 1).padding(.leading, 8)
                            MemBreakRow(label: "Compressed", bytes: monitor.memory.compressed, total: monitor.memory.total, color: .accentAmber)
                            Rectangle().fill(Color.borderLight).frame(height: 1).padding(.leading, 8)
                            MemBreakRow(label: "Cached",     bytes: monitor.memory.cached,     total: monitor.memory.total, color: Color.textTertiaryLight)
                            Rectangle().fill(Color.borderLight).frame(height: 1).padding(.leading, 8)
                            MemBreakRow(label: "Free",       bytes: monitor.memory.free,        total: monitor.memory.total, color: .accentGreen)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)

                    Rectangle().fill(Color.borderLight).frame(height: 1)

                    // Pressure bar section
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Memory Pressure")
                            .foregroundStyle(Color.textSecondaryLight)
                        MiniBar(value: monitor.memory.usedPercent, color: pressureColor, height: 4)
                        HStack {
                            Text("0").font(.system(size: 10)).foregroundStyle(Color.textTertiaryLight)
                            Spacer()
                            Text(String(format: "%.1f%%", monitor.memory.usedPercent * 100))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(pressureColor)
                            Spacer()
                            Text("100%").font(.system(size: 10)).foregroundStyle(Color.textTertiaryLight)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.surfaceLight)
    }
}

struct MemStatTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.textTertiaryLight)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

struct MemBreakRow: View {
    let label: String
    let bytes: UInt64
    let total: UInt64
    let color: Color

    private var pct: Double { total > 0 ? Double(bytes) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(color).frame(width: 2).clipShape(Capsule())
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondaryLight)
            Spacer()
            Text(MemoryInfo.formatted(bytes))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.textPrimaryLight)
            Text(String(format: "%.0f%%", pct * 100))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: 36)
        .padding(.horizontal, 4)
    }
}
