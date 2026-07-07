import SwiftUI

// MARK: - StorageView

struct StorageView: View {
    @Binding var selectedTool: InternalStorageTool?
    @ObservedObject var uninstallerService: UninstallerService
    @ObservedObject var analyzerService: StorageAnalyzerService
    @Binding var operationActive: Bool
    @StateObject private var cleanupStatsStore = CleanupStatsStore.shared
    private let homeMaxWidth: CGFloat = 1180

    private var isWorking: Bool {
        operationActive || uninstallerService.isScanning || analyzerService.isScanning || analyzerService.isScanningJunk
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if selectedTool != nil {
                    Button(action: {
                        selectedTool = nil
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.surfacePrimary)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(selectedTool?.rawValue ?? "SSD & Storage")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        if isWorking {
                            CleaningActivityIndicator(color: selectedTool?.color ?? .accentBlue, size: 13)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Text(selectedTool?.description ?? "Analyze, visualize, and clean your files")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()

                // Tab Bar — icon only to fit
                if let currentTool = selectedTool {
                    HStack(spacing: 2) {
                        ForEach(InternalStorageTool.allCases, id: \.self) { tool in
                            Button(action: { selectedTool = tool }) {
                                VStack(spacing: 3) {
                                    Image(systemName: tool.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 18, height: 14)
                                    Text(tool.shortName)
                                        .font(.system(size: 10, weight: .medium))
                                        .fixedSize()
                                }
                                .frame(width: 62, height: 40)
                                .background(currentTool == tool ? tool.color.opacity(0.18) : Color.clear)
                                .foregroundStyle(currentTool == tool ? tool.color : Color.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
            .background(Color.surfaceSecondary)

            Divider().background(Color.borderSubtle)

            // Content
            ZStack {
	                if let tool = selectedTool {
	                    Group {
                        switch tool {
                        case .uninstaller:
                            UninstallerView(service: uninstallerService, operationActive: $operationActive)
                        case .analyzer:
                            DiskAnalyzerView(service: analyzerService, operationActive: $operationActive)
                        case .largeFiles:
                            LargeFilesView(service: analyzerService, operationActive: $operationActive)
                        case .junkFiles:
                            JunkFilesView(service: analyzerService, operationActive: $operationActive)
	                        }
	                    }
	                } else {
	                    storageHome
	                }
	            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surfacePrimary)
	        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
	    }

    private var storageHome: some View {
        VStack(spacing: 0) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ],
                spacing: 14
            ) {
                ForEach(InternalStorageTool.allCases, id: \.self) { tool in
                    Button(action: {
                        selectedTool = tool
                    }) {
                        StorageToolCard(tool: tool)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: homeMaxWidth)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 22)

            ScrollView(.vertical, showsIndicators: true) {
                StorageCleanupStatsPanel(store: cleanupStatsStore)
                    .frame(maxWidth: homeMaxWidth, alignment: .top)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Storage Cleanup Stats

struct StorageCleanupStatsPanel: View {
    @ObservedObject var store: CleanupStatsStore

    private var hasHistory: Bool {
        store.isLoaded && !store.entries.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cleanup Intelligence")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(panelSubtitle)
		                        .font(.system(size: 12))
		                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                if hasHistory, let latest = store.events.last?.cleanedAt {
                    Text(latest, style: .relative)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                }
            }

            if store.isLoaded {
                HStack(spacing: 10) {
                    CleanupMetricTile(
                        title: "Stable Reclaim",
                        value: formatBytes(store.totalBytes),
                        subtitle: "not auto-restored",
                        color: .accentBlue,
                        info: "This excludes caches that developer tools or browsers usually recreate. It is the cleaner estimate of space that should remain freed."
                    )
                    CleanupMetricTile(
                        title: "Rebuildable Cache",
                        value: formatBytes(store.rebuildableBytes),
                        subtitle: "will come back",
                        color: .accentPurple,
                        info: "Examples: Xcode DerivedData, build indexes, module caches, V8 data, GPU/code caches. They are safe to remove, but tools recreate them during normal work, so they are tracked separately and not mixed into stable reclaim."
                    )
                    CleanupMetricTile(
                        title: "30-day Stable",
                        value: formatBytes(store.cleanedLast30DaysBytes),
                        subtitle: "deduped paths",
                        color: .accentGreen,
                        info: "Counts the latest cleaned size for each path in the last 30 days, excluding rebuildable cache so repeated Xcode/browser rebuilds do not inflate the report."
                    )
                    CleanupMetricTile(
                        title: "Tracked Targets",
                        value: "\(store.trackedTargetCount)",
                        subtitle: "\(store.rebuildableCleanCount) rebuildable runs",
                        color: .textSecondary,
                        info: "Number of unique cleanup targets being tracked. Rebuildable runs are shown as behavior signals, not summed as permanent savings."
                    )
                }
            } else {
                CleanupMetricsLoadingRow()
            }

            if !store.isLoaded {
                CleanupStatsLoadingState()
            } else if hasHistory {
		                HStack(alignment: .top, spacing: 14) {
		                    CleanupCategoryBreakdown(store: store)
                        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
                    CleanupRecurringList(entries: store.topRecurringEntries)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
	            } else {
	                CleanupStatsEmptyState()
	            }
        }
        .padding(.top, 4)
	        .frame(maxWidth: .infinity, alignment: .topLeading)
	    }

    private var panelSubtitle: String {
        if !store.isLoaded { return "Loading cleanup history and recurring cache patterns" }
        return hasHistory ? "Latest reclaimable footprint, recurring cache patterns, and cleanup history" : "No cleanup history yet"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }
}

private struct CleanupMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let info: String
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Button(action: { showingInfo.toggle() }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingInfo, arrowEdge: .top) {
                    Text(info)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(width: 260, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceSecondary.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct CleanupMetricsLoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    CleanupLoadingBar(width: 82, height: 10)
                    CleanupLoadingBar(width: 54, height: 18)
                    CleanupLoadingBar(width: 96, height: 10)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceSecondary.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct CleanupStatsLoadingState: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CleanupLoadingCard(titleWidth: 70, lineCount: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            CleanupLoadingCard(titleWidth: 110, lineCount: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 250)
    }
}

private struct CleanupLoadingCard: View {
    let titleWidth: CGFloat
    let lineCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CleanupLoadingBar(width: titleWidth, height: 12)
            CleanupLoadingBar(width: 180, height: 9)

            VStack(spacing: 11) {
                ForEach(0..<lineCount, id: \.self) { index in
                    HStack(spacing: 10) {
                        CleanupLoadingBar(width: index.isMultiple(of: 2) ? 88 : 120, height: 12)
                        Spacer()
                        CleanupLoadingBar(width: 64, height: 12)
                    }
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceSecondary.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Loading cleanup statistics")
    }
}

private struct CleanupLoadingBar: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color.textTertiary.opacity(0.16))
            .frame(width: width, height: height)
            .redacted(reason: .placeholder)
    }
}

private struct CleanupCategoryBreakdown: View {
    @ObservedObject var store: CleanupStatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text("Stable paths only; rebuildable cache is separate")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)

            VStack(spacing: 9) {
                ForEach(Array(store.categoryTotals.prefix(5)), id: \.category) { item in
                    CleanupCategoryRow(
                        name: item.category.shortName,
                        bytes: item.bytes,
                        count: item.count,
                        color: item.category.color,
                        maxBytes: max(store.categoryTotals.first?.bytes ?? 1, 1)
                    )
                }
            }
        }
	        .padding(14)
	        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	        .background(Color.surfaceSecondary.opacity(0.62))
	        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct CleanupCategoryRow: View {
    let name: String
    let bytes: UInt64
    let count: Int
    let color: Color
    let maxBytes: UInt64

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(formatBytes(bytes)) · \(count)x")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textTertiary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.045))
                    Capsule()
                        .fill(color.opacity(0.72))
                        .frame(width: geo.size.width * max(0.05, CGFloat(bytes) / CGFloat(maxBytes)))
                }
            }
            .frame(height: 5)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }
}

private struct CleanupRecurringList: View {
    let entries: [CleanupStatsEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recurring Paths")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: 5) {
                Text("Rebuildable paths are expected to return")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                InfoPopoverButton(text: "A recurring rebuildable path means a tool recreated the cache after cleanup. This is normal for Xcode, browsers, V8, module caches, and indexes. The size is shown as current footprint, not accumulated permanent savings.")
            }

            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(entry.category.color.opacity(0.18))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("\(entry.cleanCount)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(entry.category.color)
                                    .monospacedDigit()
                            )

	                        VStack(alignment: .leading, spacing: 2) {
	                            HStack(spacing: 6) {
	                                Text(entry.displayName)
	                                    .font(.system(size: 12, weight: .semibold))
	                                    .foregroundStyle(Color.textPrimary)
	                                    .lineLimit(1)
	                                if entry.isRebuildable {
	                                    Text("Rebuilds")
	                                        .font(.system(size: 9, weight: .bold))
	                                        .foregroundStyle(Color.accentPurple)
	                                        .padding(.horizontal, 5)
	                                        .padding(.vertical, 1)
	                                        .background(Color.accentPurple.opacity(0.12))
	                                        .clipShape(Capsule())
	                                }
	                            }
	                            Text(entry.isRebuildable ? "\(entry.category.rawValue) · recreated by tools" : entry.category.rawValue)
	                                .font(.system(size: 10))
	                                .foregroundStyle(Color.textTertiary)
	                                .lineLimit(1)
	                        }

                        Spacer()

                        Text(formatBytes(entry.lastBytes))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
	        .padding(14)
	        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	        .background(Color.surfaceSecondary.opacity(0.62))
	        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }
}

private struct InfoPopoverButton: View {
    let text: String
    @State private var showingInfo = false

    var body: some View {
        Button(action: { showingInfo.toggle() }) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingInfo, arrowEdge: .top) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(width: 280, alignment: .leading)
        }
    }
}

private struct CleanupStatsEmptyState: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentBlue.opacity(0.10))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Run a cleanup to start tracking recurring files")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Cache, logs, app leftovers, trash, downloads, and repeated system cleanup paths will be counted here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceSecondary.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
