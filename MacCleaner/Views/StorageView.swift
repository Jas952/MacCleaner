import SwiftUI

// MARK: - StorageView

struct StorageView: View {
    @Binding var selectedTool: InternalStorageTool?
    @ObservedObject var uninstallerService: UninstallerService
    @ObservedObject var analyzerService: StorageAnalyzerService
    @ObservedObject var storageWorkspace: StorageWorkspaceService
    @Binding var operationActive: Bool
    @Binding var analysisOperationActive: Bool
    @StateObject private var cleanupStatsStore = CleanupStatsStore.shared
    @State private var showingCleanupReport = false
    private let homeMaxWidth: CGFloat = 1180

    private var isWorking: Bool {
        operationActive || analysisOperationActive || storageWorkspace.isWorking
            || uninstallerService.isScanning || analyzerService.isScanning || analyzerService.isScanningJunk
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if selectedTool != nil {
                    Button(action: returnToHome) {
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

                if selectedTool == nil {
                    Button(action: { showingCleanupReport = true }) {
                        HStack(spacing: 7) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Cleanup Report")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Color.accentBlue.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentBlue.opacity(0.20))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)
                }
                Spacer()

                if let currentTool = selectedTool {
                    Menu {
                        Section("Core cleanup") {
                            ForEach(InternalStorageTool.coreTools, id: \.self) { tool in
                                Button(action: { selectedTool = tool }) {
                                    Label(tool.rawValue, systemImage: tool.icon)
                                }
                            }
                        }
                        Section("Specialized analysis") {
                            ForEach(InternalStorageTool.smartTools, id: \.self) { tool in
                                Button(action: { selectedTool = tool }) {
                                    Label(tool.rawValue, systemImage: tool.icon)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: currentTool.icon)
                                .foregroundStyle(currentTool.color)
                            Text("Switch tool")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Color.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(isWorking)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 76)
            .background(Color.surfaceSecondary)

            Divider().background(Color.borderSubtle)

            // Content
            Group {
                if let tool = selectedTool {
                    switch tool {
                        case .advisor:
                            CleanupAdvisorView(service: storageWorkspace.cleanupAdvisor, operationActive: $analysisOperationActive)
                        case .duplicates:
                            DuplicateFinderView(service: storageWorkspace.duplicateFinder, operationActive: $analysisOperationActive)
                        case .similarPhotos:
                            SimilarPhotoView(service: storageWorkspace.similarPhotos, operationActive: $analysisOperationActive)
                        case .cloud:
                            CloudReclaimView(service: storageWorkspace.cloudReclaim, operationActive: $analysisOperationActive)
                        case .uninstaller:
                            UninstallerView(service: uninstallerService, operationActive: $operationActive)
                        case .analyzer:
                            DiskAnalyzerView(service: analyzerService, operationActive: $operationActive)
                        case .largeFiles:
                            LargeFilesView(service: analyzerService, operationActive: $operationActive)
                        case .junkFiles:
                            JunkFilesView(service: analyzerService, operationActive: $operationActive)
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
	    .sheet(isPresented: $showingCleanupReport) {
            StorageCleanupReportSheet(
                store: cleanupStatsStore,
                dismiss: { showingCleanupReport = false }
            )
        }
	    }

    private var storageHome: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 22) {
                StorageHomeSectionHeader(
                    title: "Core cleanup",
                    subtitle: "The fastest paths to meaningful disk space"
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(InternalStorageTool.coreTools, id: \.self) { tool in
                        Button(action: { selectedTool = tool }) {
                            StorageToolCard(tool: tool)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().background(Color.borderSubtle)

                StorageHomeSectionHeader(
                    title: "Specialized analysis",
                    subtitle: "Use when you need a more specific reclaim strategy"
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(InternalStorageTool.smartTools, id: \.self) { tool in
                        Button(action: { selectedTool = tool }) {
                            StorageToolCard(tool: tool)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: homeMaxWidth, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func returnToHome() {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTool = nil
            }
        }
    }
}

private struct StorageCleanupReportSheet: View {
    @ObservedObject var store: CleanupStatsStore
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentBlue.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cleanup Intelligence")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Reclaimed space, recurring paths, and rebuildable cache history")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Button("Close", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .frame(height: 68)
            .background(Color.surfaceSecondary)

            Divider().background(Color.borderSubtle)

            ScrollView(.vertical, showsIndicators: true) {
                StorageCleanupStatsPanel(store: store)
                    .padding(22)
            }
            .background(Color.surfacePrimary)
        }
        .frame(minWidth: 820, idealWidth: 940, minHeight: 540, idealHeight: 620)
    }
}

private struct StorageHomeSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
        }
    }
}

struct StorageFeatureEmptyState: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let actionTitle: String
    let actionIcon: String
    var details: [String] = []
    var footer: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)
            ZStack {
                Circle().fill(color.opacity(0.07)).frame(width: 124, height: 124)
                Circle().fill(color.opacity(0.12)).frame(width: 100, height: 100)
                Image(systemName: icon)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 580)

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(details.enumerated()), id: \.offset) { index, detail in
                        Label(detail, systemImage: "\(index + 1).circle.fill")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            }

            Button(action: action) {
                Label(actionTitle, systemImage: actionIcon)
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(color)

            if let footer {
                Text(footer)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StorageFeatureToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(Color.surfaceSecondary)
    }
}

extension View {
    func storageFeatureToolbar() -> some View {
        modifier(StorageFeatureToolbarModifier())
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
                        subtitle: "Trash or cloud-local",
                        color: .accentBlue,
                        info: "Tracks non-rebuildable cleanup. Trashed items reclaim disk space after Trash is emptied; Cloud Reclaim removes only local iCloud downloads while preserving cloud originals."
                    )
                    CleanupMetricTile(
                        title: "Rebuildable Cache",
                        value: formatBytes(store.rebuildableBytes),
                        subtitle: "will come back",
                        color: .accentPurple,
                        info: "Examples: Xcode DerivedData, build indexes, module caches, V8 data, GPU/code caches. They are safe to remove, but tools recreate them during normal work, so they are tracked separately and not mixed into stable reclaim."
                    )
                    CleanupMetricTile(
                        title: "30-day Reclaim",
                        value: formatBytes(store.cleanedLast30DaysBytes),
                        subtitle: "deduped paths",
                        color: .accentGreen,
                        info: "Counts the latest stable cleanup size for each path in the last 30 days, excluding rebuildable cache so repeated Xcode/browser rebuilds do not inflate the report."
                    )
                    CleanupMetricTile(
                        title: "Tracked Targets",
                        value: "\(store.trackedTargetCount)",
                        subtitle: "\(store.rebuildableCleanCount) rebuildable runs",
                        color: .textSecondary,
                        info: "Number of unique cleanup targets being tracked. Rebuildable runs are shown as behavior signals, not summed as permanent disk savings."
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
        let totals = store.categoryTotals
        let maximumBytes = max(totals.first?.bytes ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text("Stable paths only; rebuildable cache is separate")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)

            VStack(spacing: 9) {
                ForEach(Array(totals.prefix(5)), id: \.category) { item in
                    CleanupCategoryRow(
                        name: item.category.shortName,
                        bytes: item.bytes,
                        count: item.count,
                        color: item.category.color,
                        maxBytes: maximumBytes
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
