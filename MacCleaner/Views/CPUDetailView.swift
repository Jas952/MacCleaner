import SwiftUI

struct CPUDetailView: View {
    @ObservedObject var monitor: SystemMonitor

    private var cpuColor: Color {
        monitor.cpu.totalUsage > 0.85 ? .accentRed : monitor.cpu.totalUsage > 0.65 ? .accentAmber : .accentBlue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text("Processor load per core")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Rectangle().fill(Color.borderLight).frame(height: 1)

            VStack(spacing: 0) {
                // Total + sparkline
                HStack(alignment: .center, spacing: 32) {
                    ZStack {
                        ThinRing(progress: monitor.cpu.totalUsage, color: cpuColor, lineWidth: 10, size: 120)
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f%%", monitor.cpu.totalUsage * 100))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.textPrimaryLight)
                            Text("\(monitor.cpu.processorCount) cores")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textTertiaryLight)
                        }
                    }
                    .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Load History · 60 samples")
                            .foregroundStyle(Color.textSecondaryLight)
                        Sparkline(values: monitor.cpuHistory, color: cpuColor, lineWidth: 1.5)
                            .frame(maxWidth: .infinity, minHeight: 70)
                        MiniBar(value: monitor.cpu.totalUsage, color: cpuColor, height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)

                Rectangle().fill(Color.borderLight).frame(height: 1)

                // Per-core grid
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "CPU Cores")
                        .foregroundStyle(Color.textSecondaryLight)
                        .padding(.horizontal, 24)
                    let columns = [GridItem(.adaptive(minimum: 100, maximum: 160))]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(monitor.cpu.coreUsages.enumerated()), id: \.offset) { idx, usage in
                            CoreTile(coreIndex: idx, usage: usage)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color.surfaceLight)
    }
}

struct CoreTile: View {
    let coreIndex: Int
    let usage: Double
    private var color: Color { usage > 0.8 ? .accentRed : usage > 0.5 ? .accentAmber : .accentBlue }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ThinRing(progress: usage, color: color, lineWidth: 4, size: 52)
                Text(String(format: "%.0f%%", usage * 100))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textSecondaryLight)
            }
            .padding(.top, 4)
            Text("C\(coreIndex)")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiaryLight)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.borderLight))
    }
}
