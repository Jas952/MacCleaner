import SwiftUI

// MARK: - Cleaner Tool enum

enum CleanerTool: CaseIterable, Identifiable {
    case ram, disk, refresh, dns, shredder

    var id: Self { self }

    var title: String {
        switch self {
        case .ram:       return "RAM"
        case .disk:      return "Disk Junk"
        case .refresh:   return "Refresh"
        case .dns:       return "DNS Cache"
        case .shredder:  return "Safe Delete"
        }
    }

    var subtitle: String {
        switch self {
        case .ram:       return "Close memory-heavy apps"
        case .disk:      return "Remove caches & logs"
        case .refresh:   return "System maintenance"
        case .dns:       return "Flush DNS records"
        case .shredder:  return "Move files to Trash"
        }
    }

    var icon: String {
        switch self {
        case .ram:       return "cpu"
        case .disk:      return "cylinder.split.1x2"
        case .refresh:   return "arrow.triangle.2.circlepath"
        case .dns:       return "globe.americas"
        case .shredder:  return "scissors.badge.ellipsis"
        }
    }

    var tileIcon: String {
        switch self {
        case .ram:       return "memorychip.fill"
        case .disk:      return "internaldrive.fill"
        case .refresh:   return "gearshape.arrow.triangle.2.circlepath"
        case .dns:       return "network"
        case .shredder:  return "doc.zipper"
        }
    }

    var accentColor: Color {
        switch self {
        case .ram:       return .accentBlue
        case .disk:      return .accentGreen
        case .refresh:   return Color(red: 0.85, green: 0.65, blue: 0.3)
        case .dns:       return .accentBlue
        case .shredder:  return Color(red: 0.95, green: 0.45, blue: 0.4)
        }
    }

    var hints: [String] {
        switch self {
        case .ram:       return ["Performance issues", "App launch lag", "Memory pressure"]
        case .disk:      return ["Browser caches", "Dev tool leftovers", "AI tool caches"]
        case .refresh:   return ["QuickLook rebuild", "Font cache", "Launch Services"]
        case .dns:       return ["Site loading issues", "Internet connectivity", "DNS lookup errors"]
        case .shredder:  return ["Reversible removal", "macOS Trash", "No false overwrite claims"]
        }
    }
}

// MARK: - Scan phase for animation

enum ScanPhase: String, CaseIterable {
    case ready        = "Ready to scan"
    case browsers     = "Browser caches…"
    case devTools     = "Developer tools…"
    case aiTools      = "AI tool caches…"
    case appCaches    = "App caches…"
    case systemCaches = "System caches…"
    case logs         = "Logs & reports…"
    case savedState   = "Saved state…"
    case trash        = "Trash…"
    case done         = "Done"
}

enum SimpleToolFlow { case idle, running, done }

enum OptimizationLogStatus: String {
    case pending, running, success, failure
}

enum OptimizationPhase {
    case ready, scanning, review, cleaning, success
}

struct OptimizationLog: Identifiable {
    let id = UUID()
    let message: String
    var status: OptimizationLogStatus
    let timestamp = Date()
}

enum RAMCleaningFlow {
    case idle, analyzing, results, cleaning, done

    var isActive: Bool {
        switch self {
        case .analyzing, .cleaning:
            return true
        case .idle, .results, .done:
            return false
        }
    }
}

final class CleanerViewState: ObservableObject {
    @Published var scanItems: [CleanableItem] = []
    @Published var diskScanWasLimited = false
    @Published var diskScannedEntryCount = 0
    @Published var diskScanMode: DiskCleanScanMode = .efficient
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var hasScan = false
    @Published var scanPhase: ScanPhase = .ready
    @Published var scanProgress: Double = 0
    @Published var resultFreed: Int64? = nil
    @Published var resultErrors: Int = 0
    @Published var showResult = false

    @Published var ramAnalysis: RAMAnalysisResult? = nil
    @Published var ramSources: [RAMSource] = []
    @Published var ramAnalyzeProgress: Double = 0
    @Published var ramFreedBytes: UInt64 = 0
    @Published var ramPurgeSuccess = true
    @Published var ramClosedApps = 0
    @Published var ramRefusedApps = 0
    @Published var ramAnalyzePhase = "Checking memory pressure…"

    @Published var dnsFlow: SimpleToolFlow = .idle
    @Published var dnsSuccess = false
    @Published var dnsMessage = ""

    @Published var shredderFiles: [URL] = []
    @Published var isShredding = false
    @Published var shredderDone = false
    @Published var shredderCount = 0

    @Published var refreshTasks: [RefreshTask] = []
    @Published var refreshRunning = false
    @Published var refreshDone = false
    @Published var refreshCurrent = 0
    @Published var refreshTotal = 0

    @Published var expandedCategories: Set<String> = []

    @Published var optimizationLogs: [OptimizationLog] = []
    @Published var optimizationRunning = false
    @Published var optimizationPhase: OptimizationPhase = .ready

    @Published var optimizationFoundRAM: UInt64 = 0
    @Published var optimizationFreedRAM: UInt64 = 0
    @Published var optimizationFoundDisk: Int64 = 0
    @Published var optimizationFreedDisk: Int64 = 0
    @Published var optimizationRefreshTaskCount: Int = 0
    @Published var optimizationRefreshDoneCount: Int = 0
    @Published var optimizationDNSSuccess: Bool = false
    @Published var optimizationRAMSources: [RAMSource] = []

    @Published var optimizationSelectedRoots: Set<DiskScanRoot> = Set(DiskScanRoot.allCases)
    @Published var optimizationScannedRoots: Set<DiskScanRoot> = []

    func resetForNavigation() {
        guard !isScanning, !isCleaning, !optimizationRunning, !refreshRunning, !isShredding else { return }
        // Keep the session scan cache. Returning to Optimize should not walk
        // the same roots again unless the user explicitly clears the cache.
        hasScan = false; scanPhase = .ready; scanProgress = 0
        resultFreed = nil; resultErrors = 0; showResult = false
        ramAnalysis = nil; ramSources = []; ramAnalyzeProgress = 0; ramFreedBytes = 0
        dnsFlow = .idle; dnsSuccess = false; dnsMessage = ""
        shredderFiles = []; shredderDone = false; shredderCount = 0
        refreshTasks = []; refreshDone = false; refreshCurrent = 0; refreshTotal = 0
        expandedCategories = []; optimizationLogs = []; optimizationPhase = .ready
        optimizationFoundRAM = 0; optimizationFreedRAM = 0
        optimizationFoundDisk = 0; optimizationFreedDisk = 0
        optimizationRefreshTaskCount = 0; optimizationRefreshDoneCount = 0
        optimizationDNSSuccess = false; optimizationRAMSources = []
    }

    func clearOptimizationScanCache() {
        optimizationScannedRoots = []
        scanItems = []
        diskScanWasLimited = false
        diskScannedEntryCount = 0
    }
}

struct CleanerView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var state: CleanerViewState
    @Binding var activeTool: CleanerTool?
    @Binding var ramFlow: RAMCleaningFlow
    @Binding var operationActive: Bool
    let onOpenStartup: () -> Void

    // Disk cleaner state
    @State private var runningPulse = false
    @State private var cachedNetworkInterface = "Detecting…"
    @State private var cachedDNSResolver = "Detecting…"
    @State private var showOptimizationCleanupConfirmation = false
    @State private var isOptimizationScopeExpanded = false
    @State private var showRAMCloseConfirmation = false

    private var totalSelected: Int64 { state.scanItems.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes } }
    private var selectedCount: Int   { state.scanItems.filter(\.isSelected).count }
    private var foundCategories: [CleanCategory] {
        CleanCategory.allCases.filter { cat in !state.scanItems.filter { $0.category == cat }.isEmpty }
    }
    private var maxCategorySize: Int64 {
        foundCategories.map { cat in state.scanItems.filter { $0.category == cat }.reduce(0) { $0 + $1.sizeBytes } }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ─────────────────────────────────────────────
            HStack {
                if let tool = activeTool {
                    Button(action: returnToToolGrid) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.textSecondaryLight)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.surfaceCardLight)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)

                    Spacer()

                    HStack(spacing: 7) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(tool.accentColor)
                        Text(tool.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        if ramFlow.isActive || operationActive {
                            CleaningActivityIndicator(color: tool.accentColor, size: 12)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .transition(.opacity)

                    Spacer()
                    // Balance spacer
                    Color.clear.frame(width: 68, height: 1)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Optimize")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.textPrimaryLight)
                            if ramFlow.isActive || operationActive || state.optimizationRunning {
                                CleaningActivityIndicator(color: .accentBlue, size: 14)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        Text("One-click system tune-up")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                    .transition(.opacity)
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Rectangle().fill(Color.borderLight).frame(height: 1)

            optimizationView
                .transition(.opacity)
        }
        .background(Color.surfaceLight)
        .alert("Confirm cleanup", isPresented: $showOptimizationCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clean", role: .destructive) {
                runCleanup()
            }
        } message: {
            Text("MacCleaner will flush DNS cache, refresh system state, and clean \(selectedCount) selected disk items totaling \(DiskCleaner.formattedSize(totalSelected)). Applications remain open; RAM suggestions always require separate manual review.")
        }
        .alert("Quit selected applications?", isPresented: $showRAMCloseConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Request Quit") { performRAMClean() }
        } message: {
            let selected = state.ramSources.filter(\.isSelected)
            let bytes = selected.reduce(0) { $0 &+ $1.bytes }
            Text("MacCleaner will request a normal Quit from \(selected.count) application\(selected.count == 1 ? "" : "s") using up to \(MemoryInfo.formatted(bytes)). Apps may ask you to save work. MacCleaner will never force-terminate them.")
        }
    }
    // MARK: - Tool Picker Grid

    private let statusStripH: CGFloat = 48
    private let gridPad: CGFloat = 16
    private let gridGap: CGFloat = 10

    private var toolGrid: some View {
        GeometryReader { geo in
            let p = gridPad
            let g = gridGap
            let stripH = statusStripH
            let availH = geo.size.height - p * 2 - g * 2 - stripH
            let row1H = availH * 0.52
            let row2H = availH - row1H

            VStack(spacing: g) {
                HStack(spacing: g) {
                    toolTile(.ram,     height: row1H)
                    toolTile(.disk,    height: row1H)
                    toolTile(.refresh, height: row1H)
                }
                HStack(spacing: g) {
                    toolTile(.dns,       height: row2H)
                    toolTile(.shredder,  height: row2H)
                    toolTile(.dns,       height: row2H)
                }
                systemStatusStrip
                    .frame(height: stripH)
            }
            .padding(p)
        }
    }

    // MARK: - Optimization Mode

    private var optimizationView: some View {
        ZStack {
            optimizationCompactView
                .opacity(state.optimizationPhase == .review ? 0 : 1)
                .scaleEffect(state.optimizationPhase == .review ? 0.985 : 1)
                .allowsHitTesting(state.optimizationPhase != .review)

            optimizationReviewView
                .opacity(state.optimizationPhase == .review ? 1 : 0)
                .scaleEffect(state.optimizationPhase == .review ? 1 : 1.01)
                .allowsHitTesting(state.optimizationPhase == .review)
        }
        .animation(.easeInOut(duration: 0.28), value: state.optimizationPhase)
    }

    private var optimizationCompactView: some View {
        GeometryReader { geo in
            ZStack {
                // Circle centered within the detail pane
                VStack(spacing: 20) {
                    mainActionCircle
                        .frame(width: 236, height: 236)
                }
                .position(x: geo.size.width / 2 - 10, y: geo.size.height * 0.39)

                // Bottom panel aligned with the circle
                VStack {
                    Spacer()
                    bottomContentArea
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var optimizationReviewView: some View {
        VStack(spacing: 0) {
            optimizationReviewHeader
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 14)

            optimizationCleanupList
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to clean")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text("Selected items will be moved to Trash and remain recoverable there.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
                Button(action: leaveOptimizationReview) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(state.optimizationRunning)

                Button(action: leaveOptimizationReview) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                        Text("Done")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(Color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(state.optimizationRunning)

                Button {
                    showOptimizationCleanupConfirmation = true
                } label: {
                    Label(
                        selectedCount > 0 ? "Clean \(DiskCleaner.formattedSize(totalSelected))" : "Select items",
                        systemImage: "trash"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(selectedCount > 0 ? Color.accentBlue : Color.textTertiaryLight.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0 || state.optimizationRunning)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.surfaceCardLight.opacity(0.86))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.borderLight).frame(height: 1)
            }
        }
    }

    private func leaveOptimizationReview() {
        guard !state.optimizationRunning else { return }
        state.resetForNavigation()
        isOptimizationScopeExpanded = false
    }

    private var optimizationReviewHeader: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(width: 32, height: 32)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cleanup report")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        Text("Review each item before it is moved to Trash.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                }
                Spacer()
                Text("READY TO REVIEW")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.textSecondaryLight)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.surfaceSecondary)
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                optimizationReviewMetric(
                    title: "Disk junk",
                    value: DiskCleaner.formattedSize(state.optimizationFoundDisk),
                    detail: "found",
                    color: .textSecondaryLight
                )
                optimizationReviewMetric(
                    title: "Items",
                    value: "\(state.scanItems.count)",
                    detail: "in report",
                    color: .textSecondaryLight
                )
                optimizationReviewMetric(
                    title: "Selected",
                    value: DiskCleaner.formattedSize(totalSelected),
                    detail: "to Trash",
                    color: .textSecondaryLight
                )
            }
        }
        .padding(14)
        .background(Color.surfaceCardLight.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight))
    }

    private func optimizationReviewMetric(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiaryLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.surfaceSecondary.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var bottomContentArea: some View {
        Group {
            switch state.optimizationPhase {
            case .scanning:
                optimizationLogList
                    .frame(width: 600, height: 120)
                    .transition(.opacity)
            case .review:
                EmptyView()
            case .cleaning, .success:
                optimizationSummaryPanel
                    .transition(.opacity)
            case .ready:
                optimizationReadyPanel
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: state.optimizationPhase)
    }

    private var optimizationReadyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                optimizationReadyItem(
                    icon: "internaldrive",
                    color: .accentBlue,
                    title: "Disk cleanup",
                    detail: "Caches, logs, browser data and safe user-space leftovers"
                )
                optimizationReadyItem(
                    icon: "memorychip",
                    color: .accentPurple,
                    title: "Memory review",
                    detail: "Memory pressure and applications you can choose to close"
                )
                optimizationReadyItem(
                    icon: "gearshape.2",
                    color: .accentGreen,
                    title: "System & DNS",
                    detail: "Maintenance tasks, stale DNS records and system state"
                )
            }

            optimizationScopeDisclosure
            if isOptimizationScopeExpanded {
                optimizationRootPicker
                    .transition(.opacity)
            }

            optimizationStartupLink
        }
        .frame(width: 700)
        .padding(10)
        .background(Color.surfaceCardLight)
        .overlay(Rectangle().strokeBorder(Color.borderLight))
    }

    private var optimizationScopeDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.24)) {
                isOptimizationScopeExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.borderLight)
                    .frame(height: 1)
                Image(systemName: isOptimizationScopeExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiaryLight.opacity(0.72))
                    .frame(width: 24, height: 16)
                    .background(Color.surfaceSecondary.opacity(0.5))
                    .clipShape(Capsule())
                Rectangle()
                    .fill(Color.borderLight)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOptimizationScopeExpanded ? "Hide scan scope" : "Show scan scope")
        .accessibilityLabel("Scan scope")
        .accessibilityValue(isOptimizationScopeExpanded ? "Expanded" : "Collapsed")
    }

    private var optimizationStartupLink: some View {
        Button(action: onOpenStartup) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                    .frame(width: 22, height: 22)
                    .background(Color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Startup")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.textSecondaryLight)
                    Text("Review login items and background helpers separately")
                        .font(.system(size: 7.5))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(Color.surfaceSecondary.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Startup Optimizer")
        .accessibilityLabel("Startup Optimizer")
        .accessibilityHint("Review login items and background helpers")
    }

    private var optimizationRootPicker: some View {
        // Keep related areas in a stable reading order: browser/AI/system data
        // on the left, developer/application data on the right.
        let leftRoots: [DiskScanRoot] = [.browser, .ai, .logs, .trash]
        let rightRoots: [DiskScanRoot] = [.developer, .applications, .savedState]

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 20) {
                optimizationRootColumn(leftRoots)
                optimizationRootColumn(rightRoots)
            }

            if !state.optimizationScannedRoots.isEmpty {
                Button("Rescan selected roots") {
                    let roots = state.optimizationSelectedRoots
                    state.optimizationScannedRoots.subtract(roots)
                    state.scanItems.removeAll { roots.contains($0.category.scanRoot) }
                    state.diskScanWasLimited = false
                    state.diskScannedEntryCount = 0
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.accentBlue)
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
    }

    private func optimizationRootColumn(_ roots: [DiskScanRoot]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(roots) { root in
                optimizationRootRow(root)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optimizationRootRow(_ root: DiskScanRoot) -> some View {
        let selected = state.optimizationSelectedRoots.contains(root)

        return Button {
            guard !state.optimizationRunning else { return }
            if selected { state.optimizationSelectedRoots.remove(root) }
            else { state.optimizationSelectedRoots.insert(root) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentGreen : Color.textTertiaryLight)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(root.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(root.detail)
                        .font(.system(size: 7.5))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.optimizationRunning)
        .accessibilityLabel(root.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func optimizationReadyItem(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.textPrimaryLight)
                Text(detail).font(.system(size: 9)).foregroundStyle(Color.textTertiaryLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var mainActionCircle: some View {
        let isBusy = state.optimizationPhase == .scanning || state.optimizationPhase == .cleaning

        return Group {
            if isBusy {
                OptimizationActionCore(
                    phase: state.optimizationPhase,
                    color: circleColorForPhase,
                    progress: optimizationCoreProgress,
                    icon: optimizationCoreIcon,
                    title: optimizationCoreTitle,
                    subtitle: optimizationCoreSubtitle,
                    pulsing: runningPulse
                )
            } else {
                Button {
                    handleOptimizationCoreTap()
                } label: {
                    OptimizationActionCore(
                        phase: state.optimizationPhase,
                        color: circleColorForPhase,
                        progress: optimizationCoreProgress,
                        icon: optimizationCoreIcon,
                        title: optimizationCoreTitle,
                        subtitle: optimizationCoreSubtitle,
                        pulsing: runningPulse
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Circle())
        .onAppear {
            runningPulse = true
        }
    }

    private var circleColorForPhase: Color {
        switch state.optimizationPhase {
        case .ready:     return .accentBlue
        case .scanning:  return .accentAmber
        case .review:    return .accentAmber
        case .cleaning:  return .accentAmber
        case .success:   return .accentGreen
        }
    }

    private var optimizationSummaryPanel: some View {
        VStack(spacing: 12) {
            Text(state.optimizationPhase == .review ? "Cleanup report" : "Results")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondaryLight)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 14) {
                optimizationReportCell(
                    icon: "internaldrive",
                    color: .accentBlue,
                    label: "Disk",
                    value: state.optimizationPhase == .review
                        ? DiskCleaner.formattedSize(state.optimizationFoundDisk)
                        : DiskCleaner.formattedSize(state.optimizationFreedDisk),
                    sublabel: sublabelForDisk
                )
                optimizationReportCell(
                    icon: "memorychip",
                    color: .accentPurple,
                    label: "RAM",
                    value: state.optimizationPhase == .review
                        ? MemoryInfo.formatted(state.optimizationFoundRAM)
                        : MemoryInfo.formatted(state.optimizationFreedRAM),
                    sublabel: sublabelForRAM
                )
                optimizationReportCell(
                    icon: "gearshape.2",
                    color: .accentGreen,
                    label: "System",
                    value: state.optimizationPhase == .review
                        ? "\(state.optimizationRefreshTaskCount)"
                        : "\(state.optimizationRefreshDoneCount)",
                    sublabel: sublabelForSystem
                )
                optimizationReportCell(
                    icon: "globe",
                    color: .accentAmber,
                    label: "DNS",
                    value: state.optimizationPhase == .review
                        ? "Ready"
                        : (state.optimizationDNSSuccess ? "Cleared" : "Skipped"),
                    sublabel: sublabelForDNS
                )
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surfaceCardLight.opacity(0.8))
        )
        .frame(width: 420)
    }

    private var optimizationCleanupList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Items to move to Trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Spacer()
                Text("\(selectedCount) selected · \(DiskCleaner.formattedSize(totalSelected))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textSecondaryLight)
            }
            .padding(.bottom, 7)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(foundCategories, id: \.self) { category in
                        let categoryItems = state.scanItems
                            .filter { $0.category == category }
                            .sorted { lhs, rhs in
                                if lhs.sizeBytes != rhs.sizeBytes { return lhs.sizeBytes > rhs.sizeBytes }
                                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                            }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(category.color)
                                    .frame(width: 22, height: 22)
                                    .background(category.color.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(category.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.textPrimaryLight)
                                Spacer()
                                Text(DiskCleaner.formattedSize(categoryItems.reduce(0) { $0 + $1.sizeBytes }))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.textTertiaryLight)
                            }

                            ForEach(categoryItems) { item in
                                optimizationCleanupRow(item)
                            }
                        }
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.borderLight.opacity(0.65)).frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if state.diskScanWasLimited {
                Text("This result is partial because the scan budget was reached. Select another root or scan the remaining scope later.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentAmber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
            }
        }
        .padding(10)
        .background(Color.surfaceLight.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.borderLight))
    }

    private func optimizationCleanupRow(_ item: CleanableItem) -> some View {
        let selected = item.isSelected

        return Button {
            guard let index = state.scanItems.firstIndex(where: { $0.id == item.id }) else { return }
            state.scanItems[index].isSelected.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentGreen : Color.textTertiaryLight)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textPrimaryLight)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(DiskCleaner.formattedSize(item.sizeBytes))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                    Text(item.path)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityValue(selected ? "Selected, \(DiskCleaner.formattedSize(item.sizeBytes))" : "Not selected, \(DiskCleaner.formattedSize(item.sizeBytes))")
    }

    private var sublabelForDisk: String {
        switch state.optimizationPhase {
        case .review:   return "to clean"
        case .cleaning: return "cleaning"
        case .success:  return "cleaned"
        default:        return ""
        }
    }

    private var sublabelForRAM: String {
        switch state.optimizationPhase {
        case .review:   return "manual review"
        case .cleaning: return "apps unchanged"
        case .success:  return "manual only"
        default:        return ""
        }
    }

    private var sublabelForSystem: String {
        switch state.optimizationPhase {
        case .review:   return "queued"
        case .cleaning: return "running"
        case .success:  return "done"
        default:        return ""
        }
    }

    private var sublabelForDNS: String {
        switch state.optimizationPhase {
        case .review:   return "cache"
        case .cleaning: return "clearing"
        case .success:  return state.optimizationDNSSuccess ? "" : "failed"
        default:        return ""
        }
    }

    private func optimizationReportCell(icon: String, color: Color, label: String, value: String, sublabel: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimaryLight)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(sublabel.isEmpty ? " " : sublabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color.opacity(sublabel.isEmpty ? 0 : 0.8))
                .frame(height: 11)
        }
        .frame(width: 80)
        .frame(minHeight: 62, alignment: .top)
    }

    private var optimizationLogList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Optimization Log")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                Spacer()
                Text("\(state.optimizationLogs.count) steps")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.optimizationLogs) { log in
                                optimizationLogRow(log)
                                    .id(log.id)
                            }
                            if state.optimizationLogs.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "hand.tap")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.accentBlue)
                                    Text("Tap Scan to begin system optimization")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.textSecondaryLight)
                                }
                                .padding(.vertical, 20)
                            }
                        }
                    }
                    .onChange(of: state.optimizationLogs.count) { _ in
                        if let first = state.optimizationLogs.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }

            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceCardLight.opacity(0.7))
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0.0),
                    .init(color: .white, location: 0.82),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func optimizationLogRow(_ log: OptimizationLog) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForStatus(log.status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colorForStatus(log.status))
                .frame(width: 16)
            Text(log.message)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondaryLight)
                .lineLimit(1)
            Spacer()
            Text(timeString(log.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.textTertiaryLight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func iconForStatus(_ status: OptimizationLogStatus) -> String {
        switch status {
        case .pending:  return "circle"
        case .running:  return "arrow.triangle.2.circlepath"
        case .success:  return "checkmark.circle.fill"
        case .failure:  return "exclamationmark.triangle.fill"
        }
    }

    private func colorForStatus(_ status: OptimizationLogStatus) -> Color {
        switch status {
        case .pending:  return Color.textTertiaryLight
        case .running:  return .accentBlue
        case .success:  return .accentGreen
        case .failure:  return .accentRed
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    @discardableResult
    private func addOptimizationLog(_ message: String, status: OptimizationLogStatus, animated: Bool = true) -> UUID {
        let log = OptimizationLog(message: message, status: status)
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                state.optimizationLogs.insert(log, at: 0)
            }
        } else {
            state.optimizationLogs.insert(log, at: 0)
        }
        return log.id
    }

    private func updateOptimizationLog(id: UUID, status: OptimizationLogStatus, animated: Bool = true) {
        if let idx = state.optimizationLogs.firstIndex(where: { $0.id == id }) {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.optimizationLogs[idx].status = status
                }
            } else {
                state.optimizationLogs[idx].status = status
            }
        }
    }

    private func bulkUpdateRunningLogsToSuccess(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let target = Set(ids)
        var logs = state.optimizationLogs
        for idx in logs.indices where target.contains(logs[idx].id) {
            logs[idx].status = .success
        }
        state.optimizationLogs = logs
    }

    private func updateAllRemainingRunningLogsToSuccess() {
        var logs = state.optimizationLogs
        for idx in logs.indices where logs[idx].status == .running {
            logs[idx].status = .success
        }
        state.optimizationLogs = logs
    }

    private func resetOptimizationResults() {
        state.optimizationFoundRAM = 0
        state.optimizationFreedRAM = 0
        state.optimizationFoundDisk = 0
        state.optimizationFreedDisk = 0
        state.optimizationRefreshTaskCount = 0
        state.optimizationRefreshDoneCount = 0
        state.optimizationDNSSuccess = false
        state.optimizationRAMSources = []
        state.scanItems = []
        state.diskScanWasLimited = false
        state.diskScannedEntryCount = 0
    }

    private func runOptimization() {
        guard state.optimizationPhase == .ready else { return }

        state.optimizationLogs.removeAll()
        resetOptimizationResults()
        state.optimizationPhase = .scanning
        state.optimizationRunning = true
        operationActive = true

        addOptimizationLog("Starting system scan", status: .running)

        let group = DispatchGroup()

        // 1. RAM scan
        group.enter()
        var ramLogIDs: [UUID] = []
        ramLogIDs.append(addOptimizationLog("Scanning memory", status: .running))
        RAMCleaner.analyze(memory: monitor.memory, processes: monitor.processNodes) { logMessage in
            DispatchQueue.main.async {
                let id = self.addOptimizationLog(logMessage, status: .running, animated: false)
                ramLogIDs.append(id)
            }
        } completion: { result in
            DispatchQueue.main.async {
                self.bulkUpdateRunningLogsToSuccess(ids: ramLogIDs)
                self.state.optimizationFoundRAM = result.totalFreeable
                self.state.optimizationRAMSources = []
                if result.totalFreeable == 0 {
                    self.addOptimizationLog("Memory is already optimized", status: .success)
                } else {
                    self.addOptimizationLog("RAM Advisor found up to \(MemoryInfo.formatted(result.totalFreeable)); app review remains manual", status: .success)
                }
                group.leave()
            }
        }

        // 2. DNS — ready to clear
        group.enter()
        addOptimizationLog("DNS cache ready to clear", status: .success)
        group.leave()

        // 3. System refresh — discover tasks
        group.enter()
        state.refreshTasks = SystemRefreshService.allTasks()
        let selected = state.refreshTasks.enumerated().filter { $0.element.isSelected }
        state.optimizationRefreshTaskCount = selected.count
        if selected.isEmpty {
            addOptimizationLog("No maintenance tasks selected", status: .failure)
        } else {
            addOptimizationLog("Found \(selected.count) maintenance tasks", status: .success)
            for (_, task) in selected {
                addOptimizationLog("Will run: \(task.title)", status: .success)
            }
        }
        group.leave()

        // 4. Disk scan
        group.enter()
        var diskLogIDs: [UUID] = []
        let selectedRoots = state.optimizationSelectedRoots
        state.scanItems = state.scanItems.filter { selectedRoots.contains($0.category.scanRoot) }
        let rootsToScan = selectedRoots.subtracting(state.optimizationScannedRoots)
        if rootsToScan.isEmpty {
            addOptimizationLog("Reusing the previous disk result; no scanned roots were visited again", status: .success)
            state.optimizationFoundDisk = state.scanItems.reduce(0) { $0 + $1.sizeBytes }
            group.leave()
        } else {
            diskLogIDs.append(addOptimizationLog("Scanning selected disk roots", status: .running))
            DiskCleaner.scan(roots: rootsToScan) { logMessage in
                DispatchQueue.main.async {
                    let id = self.addOptimizationLog(logMessage, status: .running, animated: false)
                    diskLogIDs.append(id)
                }
            } completion: { result in
                DispatchQueue.main.async {
                    self.bulkUpdateRunningLogsToSuccess(ids: diskLogIDs)
                    self.state.scanItems.append(contentsOf: result.items)
                    self.state.optimizationScannedRoots.formUnion(rootsToScan)
                    self.state.diskScanWasLimited = self.state.diskScanWasLimited || result.wasLimited
                    self.state.diskScannedEntryCount += result.scannedEntryCount
                    self.state.optimizationFoundDisk = self.state.scanItems.reduce(0) { $0 + $1.sizeBytes }
                    if result.wasLimited {
                        self.addOptimizationLog(
                            "Low-load scan stopped after \(result.scannedEntryCount) entries; shown results are partial",
                            status: .success
                        )
                    }
                    if self.state.scanItems.isEmpty {
                        self.addOptimizationLog("No disk junk found", status: .success)
                    } else {
                        self.addOptimizationLog("Found \(DiskCleaner.formattedSize(self.state.optimizationFoundDisk)) of disk junk", status: .success)
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.updateAllRemainingRunningLogsToSuccess()
            self.addOptimizationLog("Scan complete — ready to clean", status: .success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.state.optimizationPhase = .review
            }
            self.state.optimizationRunning = false
            self.operationActive = false
        }
    }

    private func runCleanup() {
        guard state.optimizationPhase == .review else { return }

        state.optimizationPhase = .cleaning
        state.optimizationRunning = true
        operationActive = true

        addOptimizationLog("Starting cleanup", status: .running)

        let group = DispatchGroup()

        // 1. RAM purge
        group.enter()
        if state.optimizationRAMSources.isEmpty {
            addOptimizationLog(
                state.optimizationFoundRAM > 0
                    ? "RAM suggestions preserved for manual review"
                    : "Memory pressure needs no action",
                status: .success
            )
            group.leave()
        } else {
            addOptimizationLog("Closing selected memory-heavy apps", status: .running)
            RAMCleaner.closeSelectedApplications(items: state.optimizationRAMSources) { result in
                DispatchQueue.main.async {
                    if result.closedAny {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.state.optimizationFreedRAM = result.estimatedReleasedBytes
                        }
                        self.addOptimizationLog("Closed \(result.closedCount) app\(result.closedCount == 1 ? "" : "s"); up to \(MemoryInfo.formatted(result.estimatedReleasedBytes)) released", status: .success)
                    } else if result.requestedCount == 0 {
                        self.addOptimizationLog("No user apps selected", status: .success)
                    } else {
                        self.addOptimizationLog("Apps remained open; no force termination was used", status: .failure)
                    }
                    group.leave()
                }
            }
        }

        // 2. DNS flush
        group.enter()
        addOptimizationLog("Flushing DNS cache", status: .running)
        DNSCleaner.flush { success, message in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.state.optimizationDNSSuccess = success
                }
                if success {
                    self.addOptimizationLog("DNS cache cleared", status: .success)
                } else {
                    self.addOptimizationLog("DNS: \(message)", status: .failure)
                }
                group.leave()
            }
        }

        // 3. System refresh execute
        group.enter()
        runRefreshForOptimization {
            group.leave()
        }

        // 4. Disk clean
        group.enter()
        let items = state.scanItems.filter(\.isSelected)
        if items.isEmpty {
            addOptimizationLog("No disk junk to clean", status: .success)
            group.leave()
        } else {
            let selectedDiskBytes = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
            addOptimizationLog("Cleaning \(DiskCleaner.formattedSize(selectedDiskBytes)) of disk junk", status: .running)
            DiskCleaner.clean(items: items) { freed, errors in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.state.optimizationFreedDisk = freed
                    }
                    self.state.scanItems.removeAll { item in
                        items.contains(where: { $0.id == item.id })
                    }
                    self.state.optimizationFoundDisk = self.state.scanItems.reduce(0) { $0 + $1.sizeBytes }
                    if freed > 0 {
                        self.addOptimizationLog("Moved \(DiskCleaner.formattedSize(freed)) to Trash", status: .success)
                    } else {
                        self.addOptimizationLog("Disk already clean", status: .success)
                    }
                    if !errors.isEmpty {
                        self.addOptimizationLog("\(errors.count) disk items skipped", status: .failure)
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.updateAllRemainingRunningLogsToSuccess()
            self.addOptimizationLog("Cleanup complete", status: .success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.state.optimizationPhase = .success
            }
            self.state.optimizationRunning = false
            self.operationActive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.monitor.refresh(forceProcesses: true) }
        }
    }

    private func runRefreshForOptimization(completion: @escaping () -> Void) {
        state.refreshTasks = SystemRefreshService.allTasks()
        let selected = state.refreshTasks.enumerated().filter { $0.element.isSelected }
        guard !selected.isEmpty else {
            addOptimizationLog("No maintenance tasks selected", status: .failure)
            completion()
            return
        }
        operationActive = true
        state.refreshRunning = true
        state.refreshDone = false
        state.refreshTotal = selected.count
        state.refreshCurrent = 0

        let headerLogID = addOptimizationLog("Running system maintenance", status: .running)
        var successCount = 0

        func runNext(_ remaining: [(Int, RefreshTask)]) {
            guard let (idx, task) = remaining.first else {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        state.refreshRunning = false
                        state.refreshDone = true
                        state.optimizationRefreshDoneCount = successCount
                    }
                    self.updateOptimizationLog(id: headerLogID, status: .success)
                    completion()
                }
                return
            }
            let taskLogID = addOptimizationLog("Running \(task.title)", status: .running)
            DispatchQueue.main.async {
                withAnimation { state.refreshTasks[idx].state = .running }
            }
            SystemRefreshService.execute(task: task) { ok in
                withAnimation {
                    state.refreshTasks[idx].state = ok ? .done : .failed
                    state.refreshCurrent += 1
                }
                if ok { successCount += 1 }
                DispatchQueue.main.async {
                    self.updateOptimizationLog(id: taskLogID, status: ok ? .success : .failure)
                }
                runNext(Array(remaining.dropFirst()))
            }
        }
        runNext(selected.map { ($0.offset, $0.element) })
    }

    private func toolTile(_ tool: CleanerTool, height: CGFloat) -> some View {
        Button {
            if tool == .refresh && state.refreshTasks.isEmpty {
                state.refreshTasks = SystemRefreshService.allTasks()
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                activeTool = tool
            }
        } label: {
            ToolTileContent(tool: tool)
        }
        .buttonStyle(ToolTileButtonStyle(accentColor: tool.accentColor))
        .frame(maxWidth: .infinity).frame(height: height, alignment: .top)
    }
    
    private struct ToolTileContent: View {
        let tool: CleanerTool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tool.accentColor.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: tool.tileIcon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(tool.accentColor)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiaryLight)
                        .padding(.top, 4)
                }
                .padding(.bottom, 10)

                Text(tool.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(tool.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiaryLight)
                    .padding(.top, 2)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(tool.hints.prefix(2), id: \.self) { hint in
                        Text(hint)
                            .font(.system(size: 8))
                            .foregroundStyle(tool.accentColor.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(tool.accentColor.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }
    
    struct ToolTileButtonStyle: ButtonStyle {
        let accentColor: Color
        @State private var isHovered = false
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.surfaceCardLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isHovered ? accentColor.opacity(0.4) : Color.borderLight, lineWidth: isHovered ? 1.5 : 1)
                        )
                        .shadow(color: isHovered ? accentColor.opacity(0.15) : Color.shadowLight, radius: isHovered ? 8 : 4, x: 0, y: isHovered ? 2 : 1)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.01 : 1.0))
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHovered)
                .animation(.spring(response: 0.1, dampingFraction: 0.6), value: configuration.isPressed)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        isHovered = hovering
                    }
                }
        }
    }

    // System status strip at bottom of picker
    private var systemStatusStrip: some View {
        HStack(spacing: 0) {
            statusCell(
                label: "RAM",
                value: String(format: "%.0f%%", monitor.memory.usedPercent * 100),
                color: monitor.memory.usedPercent > 0.8 ? Color.accentRed : Color.accentGreen
            )
            Rectangle().fill(Color.borderLight).frame(width: 1)
            statusCell(
                label: "Free RAM",
                value: MemoryInfo.formatted(monitor.memory.free),
                color: Color.textSecondaryLight
            )
            Rectangle().fill(Color.borderLight).frame(width: 1)
            if let disk = monitor.disks.first(where: { $0.mountPoint == "/" }) {
                statusCell(
                    label: "Disk Free",
                    value: DiskInfo.formatted(disk.free),
                    color: disk.usedPercent > 0.9 ? Color.accentRed : Color.accentGreen
                )
                Rectangle().fill(Color.borderLight).frame(width: 1)
                statusCell(
                    label: "Disk Used",
                    value: String(format: "%.0f%%", disk.usedPercent * 100),
                    color: Color.textSecondaryLight
                )
            }
        }
        .frame(height: 48)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight))
    }
    private func statusCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 8)).foregroundStyle(Color.textTertiaryLight)
        }.frame(maxWidth: .infinity)
    }

    // MARK: - Tool Panel Dispatcher

    @ViewBuilder
    private func toolPanel(for tool: CleanerTool) -> some View {
        switch tool {
        case .ram:       ramPanel
        case .disk:      diskPanel
        case .refresh:   refreshPanel
        case .dns:       dnsPanel
        case .shredder:  shredderPanel
        }
    }

    // MARK: - Unified Split Panel Shell

    private func toolShell<Info: View, Right: View, Left: View>(
        description: String,
        infoTitle: String,
        @ViewBuilder info: @escaping () -> Info,
        @ViewBuilder right: @escaping () -> Right,
        @ViewBuilder left: @escaping () -> Left
    ) -> some View {
        GeometryReader { geo in
            let pad: CGFloat = 16
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondaryLight)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    ToolInfoButton(title: infoTitle, content: info)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)

                Divider().opacity(0.4)

                HStack(spacing: 0) {
                    left()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(16)
                        .contentTransition(.opacity)
                    Divider().opacity(0.4)
                    right()
                        .frame(width: 236, alignment: .top)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                        .contentTransition(.opacity)
                }
            }
            .frame(width: geo.size.width - pad * 2, height: geo.size.height - pad * 2)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight))
            .padding(pad)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: geo.size)
        }
    }

    private func statusBlock(label: String, value: String, valueColor: Color, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.system(size: 21, weight: .bold)).foregroundStyle(valueColor)
            Text(sub)
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, disabled: Bool = false, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { action() } }) {
            HStack(spacing: 7) {
                if busy { 
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                        .frame(width: 14, height: 14)
                }
                else { 
                    Image(systemName: icon)
                        .font(.system(size: 13))
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(disabled ? Color.textTertiaryLight : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(disabled ? Color.surfaceCardLight : color)
                    .shadow(color: disabled ? .clear : color.opacity(0.35), radius: disabled ? 0 : 5, x: 0, y: disabled ? 0 : 2)
            )
        }
        .buttonStyle(ActionButtonStyle())
        .disabled(disabled || busy)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { action() } }) {
            Text(title)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.textSecondaryLight)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.surfaceCardLight)
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.borderLight))
                )
        }
        .buttonStyle(ActionButtonStyle())
    }
    
    struct ActionButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .opacity(configuration.isPressed ? 0.9 : 1.0)
                .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }

    private func toolProgressBar(_ progress: Double, color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.borderLight.opacity(0.6))
                    .frame(height: 5)
                
                // Progress fill with glow
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [color.opacity(0.7), color]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: g.size.width * CGFloat(max(0, min(1, progress))), height: 5)
                    .shadow(color: color.opacity(0.5), radius: 3, x: 0, y: 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.1), value: progress)
                
                // Leading edge highlight
                if progress > 0.05 {
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 4, height: 4)
                        .offset(x: g.size.width * CGFloat(max(0, min(1, progress))) - 2)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.1), value: progress)
                }
            }
        }
        .frame(height: 5)
    }

    private func stepRow(_ text: String, state: Int, detail: String) -> some View {
        StepRowContent(text: text, state: state, detail: detail)
    }
    
    struct StepRowContent: View {
        let text: String
        let state: Int
        let detail: String
        @State private var pulseOffset: CGFloat = 0
        
        var body: some View {
            HStack(spacing: 8) {
                Group {
                    if state == 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentGreen)
                            .transition(.scale.combined(with: .opacity))
                    } else if state == 1 {
                        RunningDots()
                    } else {
                        Circle()
                            .stroke(Color.textSecondaryLight.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                    }
                }
                .frame(width: 14)
                
                Text(text)
                    .font(.system(size: 12, weight: state == 1 ? .medium : .regular))
                    .foregroundStyle(state == 2 ? Color.textTertiaryLight : Color.textPrimaryLight)
                
                Spacer()
                
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(state == 0 ? Color.accentGreen : (state == 1 ? Color.accentBlue : Color.textTertiaryLight))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: state)
        }
    }
    
    struct RunningDots: View {
        @State private var phase = 0
        @State private var timer: Timer?
        
        var body: some View {
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.accentBlue)
                        .frame(width: 3, height: 3)
                        .offset(y: phase == i ? -2 : 2)
                        .animation(.easeInOut(duration: 0.35), value: phase)
                }
            }
            .frame(width: 14)
            .onAppear {
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                    phase = (phase + 1) % 3
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
        }
    }

    // Generic gauge for tools without a measurable percentage
    @ViewBuilder
    private func simpleGauge(flow: SimpleToolFlow, color: Color, icon: String, success: Bool, doneLabel: String, idleLabel: String) -> some View {
        VStack(spacing: 0) {
            // Top: Gauge Ring
            VStack(spacing: 6) {
                switch flow {
                case .idle:
                    GaugeRing(progress: 0, color: color) {
                        Image(systemName: icon).font(.system(size: 34)).foregroundStyle(color)
                    }
                    .frame(width: 148, height: 148)
                    Text(idleLabel).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight).padding(.top, 24)
                case .running:
                    GaugeRing(progress: 0, color: color, spinning: true, cleaning: true) {
                        Image(systemName: icon).font(.system(size: 30)).foregroundStyle(color)
                    }
                    .frame(width: 148, height: 148)
                    Text("Working…").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight).padding(.top, 24)
                case .done:
                    GaugeRing(progress: 1, color: success ? color : Color.accentRed) {
                        Image(systemName: success ? "checkmark" : "xmark")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(success ? color : Color.accentRed)
                    }
                    .frame(width: 148, height: 148)
                    Text(doneLabel).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight).padding(.top, 24)
                }
            }

            Spacer()

            // Bottom: Status area (placeholder for tool-specific info)
            VStack(spacing: 6) {
                Circle().fill(flow == .done ? (success ? Color.accentGreen : Color.accentRed) : color).frame(width: 6, height: 6)
                Text(flow == .idle ? "Ready" : flow == .running ? "Processing" : (success ? "Complete" : "Failed"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Color.textSecondaryLight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - RAM Panel

    private var ramPanel: some View {
        let usedPct = monitor.memory.usedPercent
        let freeable = state.ramSources.filter { $0.isSelected }.reduce(0) { $0 + $1.bytes }
        return toolShell(
            description: "Explains memory pressure and lets you close selected user apps. macOS continues to manage inactive and compressed memory.",
            infoTitle: "Memory Breakdown",
            info: { ramLiveAnalytics },
            right: { ramGauge(usedPct: usedPct, freeable: freeable) },
            left: { ramLeft(freeable: freeable) }
        )
    }

    @ViewBuilder
    private func ramGauge(usedPct: Double, freeable: UInt64) -> some View {
        VStack(spacing: 0) {
            // Top: Gauge Ring
            VStack(spacing: 6) {
                switch ramFlow {
                case .analyzing:
                    GaugeRing(progress: 0, color: .accentBlue, spinning: true) {
                        Image(systemName: "waveform.path.ecg").font(.system(size: 28)).foregroundStyle(Color.accentBlue)
                    }
                    .frame(width: 148, height: 148)
                    Text("Analyzing…").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight).padding(.top, 24)
                case .cleaning:
                    GaugeRing(progress: 0, color: .accentBlue, spinning: true, cleaning: true) {
                        Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(Color.accentBlue)
                    }
                    .frame(width: 148, height: 148)
                    Text("Closing apps…").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight).padding(.top, 24)
                case .done:
                    GaugeRing(progress: 1, color: state.ramPurgeSuccess ? .accentGreen : .accentRed) {
                        Image(systemName: state.ramPurgeSuccess ? "checkmark" : "xmark")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(state.ramPurgeSuccess ? Color.accentGreen : Color.accentRed)
                    }
                    .frame(width: 148, height: 148)
                    Text(state.ramPurgeSuccess ? (state.ramFreedBytes > 1024 * 1024 ? "Up to \(MemoryInfo.formatted(state.ramFreedBytes))" : "Completed") : "Not closed")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(state.ramPurgeSuccess ? Color.textTertiaryLight : Color.accentRed)
                        .padding(.top, 24)
                case .results:
                    GaugeRing(progress: Double(freeable) / Double(max(monitor.memory.total, 1)), color: .accentBlue) {
                        VStack(spacing: 2) {
                            Text(MemoryInfo.formatted(freeable)).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.textPrimaryLight).monospacedDigit()
                            Text("to free").font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                        }
                    }
                    .frame(width: 148, height: 148)
                    Text("Pressure: \(ramPressureLabel)").font(.system(size: 9, design: .monospaced)).foregroundStyle(ramPressureColor).padding(.top, 24)
                case .idle:
                    GaugeRing(progress: usedPct, color: ramPressureColor) {
                        VStack(spacing: 2) {
                            Text("\(Int(usedPct * 100))%").font(.system(size: 28, weight: .bold)).foregroundStyle(Color.textPrimaryLight).monospacedDigit()
                            Text("used").font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                        }
                    }
                    .frame(width: 148, height: 148)
                    Text(MemoryInfo.formatted(monitor.memory.free) + " free").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight).padding(.top, 24)
                }
            }

            Spacer()

            // Bottom: Compact status card
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(ramPressureColor).frame(width: 6, height: 6)
                    Text(ramPressureLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.textSecondaryLight)
                }
                Text("\(MemoryInfo.formatted(monitor.memory.total)) total")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func ramLeft(freeable: UInt64) -> some View {
        switch ramFlow {
        case .idle:
            VStack(alignment: .leading, spacing: 0) {
                statusBlock(label: "Memory Pressure", value: ramPressureLabel, valueColor: ramPressureColor,
                            sub: "\(Int(monitor.memory.usedPercent * 100))% of \(MemoryInfo.formatted(monitor.memory.total))")
                VStack(alignment: .leading, spacing: 9) {
                    ramHint("Inactive cache", icon: "memorychip")
                    ramHint("Compressed pages", icon: "rectangle.compress.vertical")
                    ramHint("Top consumers", icon: "chart.bar")
                }
                .padding(.top, 14)
                Spacer()
                actionButton("Analyze Memory", icon: "waveform.path.ecg", color: .accentBlue) { startRAMAnalysis() }
            }
        case .analyzing:
            VStack(alignment: .leading, spacing: 14) {
                statusBlock(label: "Status", value: "Analyzing", valueColor: Color.textPrimaryLight, sub: state.ramAnalyzePhase)
                toolProgressBar(state.ramAnalyzeProgress, color: Color.accentBlue)
                Spacer()
            }
        case .results:
            VStack(spacing: 10) {
                HStack {
                    Text("\(state.ramSources.count) sources found")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.textPrimaryLight)
                    Spacer()
                    Button { withAnimation { ramFlow = .idle; state.ramAnalysis = nil } } label: {
                        Text("Reset").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.surfaceCardLight).clipShape(RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain)
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) { ForEach(state.ramSources) { s in ramSourceRow(for: s.id) } }
                }
                actionButton(freeable > 0 ? "Review & Quit · \(MemoryInfo.formatted(freeable))" : "Select apps",
                             icon: "rectangle.portrait.and.arrow.right", color: Color.accentBlue, disabled: freeable == 0) {
                    showRAMCloseConfirmation = true
                }
            }
        case .cleaning:
            VStack(alignment: .leading, spacing: 12) {
                statusBlock(label: "Status", value: "Closing selected apps", valueColor: Color.textPrimaryLight, sub: "Requesting a normal application termination")
                Spacer()
            }
        case .done:
            VStack(alignment: .leading, spacing: 14) {
                if state.ramPurgeSuccess {
                    statusBlock(label: "Complete", value: "\(state.ramClosedApps) App\(state.ramClosedApps == 1 ? "" : "s") Closed", valueColor: Color.accentGreen,
                                sub: "Up to \(MemoryInfo.formatted(state.ramFreedBytes)) released" + (state.ramRefusedApps > 0 ? " · \(state.ramRefusedApps) remained open" : ""))
                    Text("macOS reclaims inactive and compressed pages automatically as pressure changes.")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight).fixedSize(horizontal: false, vertical: true)
                } else {
                    statusBlock(label: "Not Closed", value: "Apps Remained Open", valueColor: Color.accentAmber,
                                sub: "The app declined Quit, showed a save prompt, or changed state")
                    Text("MacCleaner never force-terminates apps or purges system memory.")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 8) {
                    secondaryButton("Done") { activeTool = nil; ramFlow = .idle; state.ramAnalysis = nil }
                    actionButton("Try Again", icon: "arrow.clockwise", color: Color.accentBlue) {
                        showRAMCloseConfirmation = true
                    }
                }
            }
        }
    }

    private func ramHint(_ label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(Color.accentBlue.opacity(0.6))
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
        }
    }

    @ViewBuilder
    private func ramSourceRow(for id: UUID) -> some View {
        if let idx = state.ramSources.firstIndex(where: { $0.id == id }) {
            let source = state.ramSources[idx]
            HStack(spacing: 10) {
                // Checkbox
                if source.safety != .locked {
                    Button {
                        state.ramSources[idx].isSelected.toggle()
                    } label: {
                        Image(systemName: source.isSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(source.isSelected ? Color.accentBlue : Color.textTertiaryLight)
                            .font(.system(size: 14))
                    }.buttonStyle(.plain)
                } else {
                    Image(systemName: "square")
                        .foregroundStyle(.clear)
                        .font(.system(size: 14))
                }

                // Safety indicator
                Circle()
                    .fill(safetyColor(source.safety))
                    .frame(width: 7, height: 7)

                // Icon
                Image(systemName: ramSourceIcon(source.kind))
                    .font(.system(size: 11))
                    .foregroundStyle(.textTertiary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(source.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                    Text(source.detail)
                        .font(.mono(8))
                        .foregroundStyle(.textTertiary)
                        .lineLimit(1)
                }
                Spacer()

                // Safety badge
                Text(safetyLabel(source.safety))
                    .font(.mono(8, weight: .semibold))
                    .foregroundStyle(safetyColor(source.safety))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(safetyColor(source.safety).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(MemoryInfo.formatted(source.bytes))
                    .font(.mono(10, weight: .semibold))
                    .foregroundStyle(.textSecondary)
                    .frame(width: 58, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
    // MARK: - Disk Panel

    private var diskPanel: some View {
        let disk = monitor.disks.first(where: { $0.mountPoint == "/" })
        return toolShell(
            description: "Scans safe user-space locations for caches, logs, dev-tool leftovers and trash. System files are never touched.",
            infoTitle: "SSD Space Breakdown",
            info: { diskLiveAnalytics },
            right: { diskGauge(disk: disk) },
            left: { diskLeft(disk: disk) }
        )
    }

    @ViewBuilder
    private func diskGauge(disk: DiskInfo?) -> some View {
        let usedPct = disk?.usedPercent ?? 0
        let diskColor: Color = usedPct > 0.85 ? .accentRed : usedPct > 0.7 ? .accentAmber : Color(red: 0.3, green: 0.75, blue: 0.55)
        VStack(spacing: 0) {
            // Top: Gauge Ring
            VStack(spacing: 6) {
                if state.showResult, let freed = state.resultFreed {
                    GaugeRing(progress: 1, color: .accentGreen) {
                        Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.accentGreen)
                    }
                    .frame(width: 148, height: 148)
                    Text("\(DiskCleaner.formattedSize(freed)) moved").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 24)
                } else if state.isCleaning {
                    GaugeRing(progress: 0, color: CleanerTool.disk.accentColor, spinning: true, cleaning: true) {
                        Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(CleanerTool.disk.accentColor)
                    }
                    .frame(width: 148, height: 148)
                    Text("Cleaning…").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 24)
                } else if state.isScanning {
                    GaugeRing(progress: state.scanProgress, color: CleanerTool.disk.accentColor, spinning: true) {
                        Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(CleanerTool.disk.accentColor)
                    }
                    .frame(width: 148, height: 148)
                    Text(state.scanPhase.rawValue).font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 24)
                } else if state.hasScan {
                    let total = state.scanItems.reduce(0) { $0 + $1.sizeBytes }
                    GaugeRing(progress: total > 0 ? Double(totalSelected) / Double(total) : 0, color: CleanerTool.disk.accentColor) {
                        VStack(spacing: 2) {
                            Text(DiskCleaner.formattedSize(totalSelected)).font(.system(size: 16, weight: .bold)).foregroundStyle(.textPrimary).monospacedDigit()
                            Text("selected").font(.mono(8)).foregroundStyle(.textTertiary)
                        }
                    }
                    .frame(width: 148, height: 148)
                    Text("\(DiskCleaner.formattedSize(total)) found").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 24)
                } else {
                    GaugeRing(progress: usedPct, color: diskColor) {
                        VStack(spacing: 2) {
                            Text("\(Int(usedPct * 100))%").font(.system(size: 28, weight: .bold)).foregroundStyle(.textPrimary).monospacedDigit()
                            Text("used").font(.mono(8)).foregroundStyle(.textTertiary)
                        }
                    }
                    .frame(width: 148, height: 148)
                    Text((disk.map { DiskInfo.formatted($0.free) } ?? "—") + " free").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 24)
                }
            }

            Spacer()

            // Bottom: Compact status card
            if let d = disk {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(diskColor).frame(width: 6, height: 6)
                        Text(usedPct > 0.85 ? "Critically Full" : usedPct > 0.7 ? "Getting Full" : "Healthy")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.textSecondary)
                    }
                    Text("\(DiskInfo.formatted(d.total)) total")
                        .font(.mono(9)).foregroundStyle(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.surfaceCardLight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func diskLeft(disk: DiskInfo?) -> some View {
        if state.showResult, let freed = state.resultFreed {
            VStack(alignment: .leading, spacing: 14) {
                statusBlock(label: "Complete", value: "\(DiskCleaner.formattedSize(freed)) moved", valueColor: .accentGreen, sub: "Items are recoverable from Trash")
                if state.resultErrors > 0 {
                    Text("\(state.resultErrors) item(s) skipped — needs Full Disk Access in Settings")
                        .font(.mono(9)).foregroundStyle(.accentAmber).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 8) {
                    secondaryButton("Done") { activeTool = nil; state.showResult = false; state.hasScan = false }
                    actionButton("Scan Again", icon: "arrow.clockwise", color: CleanerTool.disk.accentColor) { startScan() }
                }
            }
        } else if state.isScanning {
            VStack(alignment: .leading, spacing: 14) {
                statusBlock(label: "Status", value: "Scanning", valueColor: .textPrimary, sub: state.scanPhase.rawValue)
                toolProgressBar(state.scanProgress, color: CleanerTool.disk.accentColor)
                Text("Scanning only safe user-space locations").font(.mono(9)).foregroundStyle(.textTertiary)
                Spacer()
            }
        } else if state.hasScan {
            VStack(spacing: 8) {
                HStack {
                    Text("\(foundCategories.count) categories · \(state.scanItems.count) items")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        Button {
                            let allSel = state.scanItems.allSatisfy(\.isSelected)
                            for i in state.scanItems.indices { state.scanItems[i].isSelected = !allSel }
                        } label: {
                            Text(state.scanItems.allSatisfy(\.isSelected) ? "Deselect All" : "Select All")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.surfaceCardLight).clipShape(RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain)
                        Button { withAnimation { startScan() } } label: {
                            Text("Rescan").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.surfaceCardLight).clipShape(RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain)
                    }
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(foundCategories, id: \.self) { cat in
                            diskCategorySection(cat)
                        }
                    }
                }
                actionButton(selectedCount > 0 ? "Clean \(DiskCleaner.formattedSize(totalSelected))" : "Select items",
                             icon: "sparkles", color: .accentRed, disabled: selectedCount == 0, busy: state.isCleaning) { startClean() }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                statusBlock(label: "Disk Usage", value: disk.map { "\(Int($0.usedPercent * 100))% used" } ?? "—",
                            valueColor: .textPrimary,
                            sub: disk.map { "\(DiskInfo.formatted($0.used)) of \(DiskInfo.formatted($0.total))" } ?? "")
                VStack(alignment: .leading, spacing: 9) {
                    scanHint("Browser caches", icon: "globe")
                    scanHint("Dev & AI tool caches", icon: "hammer")
                    scanHint("App caches & logs", icon: "archivebox")
                }
                .padding(.top, 14)
                Spacer()
                actionButton("Scan for Junk", icon: "magnifyingglass", color: CleanerTool.disk.accentColor) { startScan() }
            }
        }
    }

    private func scanHint(_ label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(Color.accentBlue.opacity(0.6))
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
        }
    }

    @ViewBuilder
    private func diskCategorySection(_ cat: CleanCategory) -> some View {
        let catItems = state.scanItems.filter { $0.category == cat }
        let catSize  = catItems.reduce(0) { $0 + $1.sizeBytes }
        let selectedInCat = catItems.filter(\.isSelected).count
        let allSel   = selectedInCat == catItems.count
        let someSel  = selectedInCat > 0
        let expanded = state.expandedCategories.contains(cat.rawValue)

        VStack(spacing: 0) {
            // Category header
            HStack(spacing: 8) {
                // Checkbox for category
                Button {
                    let newVal = !allSel
                    for item in catItems {
                        if let idx = state.scanItems.firstIndex(where: { $0.id == item.id }) {
                            state.scanItems[idx].isSelected = newVal
                        }
                    }
                } label: {
                    Image(systemName: allSel ? "checkmark.square.fill" : (someSel ? "minus.square.fill" : "square"))
                        .font(.system(size: 14))
                        .foregroundStyle(someSel ? cat.color : Color.textTertiaryLight.opacity(0.4))
                }.buttonStyle(.plain)

                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(cat.color.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: cat.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(cat.color)
                }

                Text(cat.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimaryLight)

                Spacer()

                Text("\(catItems.count)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)

                Text(DiskCleaner.formattedSize(catSize))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(someSel ? Color.accentAmber : Color.textTertiaryLight)
                    .frame(width: 58, alignment: .trailing)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expanded { state.expandedCategories.remove(cat.rawValue) }
                        else { state.expandedCategories.insert(cat.rawValue) }
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .frame(width: 16, height: 16)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(someSel ? cat.color.opacity(0.05) : Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : 7))

            // Expanded item list
            if expanded {
                VStack(spacing: 0) {
                    ForEach(catItems) { item in
                        diskItemRow(item: item, cat: cat)
                    }
                }
            }
        }
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight.opacity(0.5)))
    }

    @ViewBuilder
    private func diskItemRow(item: CleanableItem, cat: CleanCategory) -> some View {
        let idx = state.scanItems.firstIndex(where: { $0.id == item.id })
        HStack(spacing: 8) {
            if let idx = idx {
                Button {
                    state.scanItems[idx].isSelected.toggle()
                } label: {
                    Image(systemName: state.scanItems[idx].isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(state.scanItems[idx].isSelected ? cat.color : Color.textTertiaryLight.opacity(0.4))
                }.buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondaryLight)
                    .lineLimit(1)
                Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(1)
            }
            Spacer()
            Text(DiskCleaner.formattedSize(item.sizeBytes))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondaryLight)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color.surfaceCardLight)
    }

    // MARK: - Refresh Panel (System Maintenance)

    private var refreshPanel: some View {
        let col = CleanerTool.refresh.accentColor
        return toolShell(
            description: "Runs system maintenance tasks: rebuilds caches, cleans broken agents, prunes databases. Fixes sluggish behaviour and stale system state.",
            infoTitle: "Maintenance Details",
            info: { refreshLiveAnalytics },
            right: { refreshGauge(col: col) },
            left: { refreshLeft(col: col) }
        )
    }

    @ViewBuilder
    private func refreshGauge(col: Color) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                if state.refreshDone {
                    let doneTasks = state.refreshTasks.filter { $0.state == .done }.count
                    let failedTasks = state.refreshTasks.filter { $0.state == .failed }.count
                    let allOk = failedTasks == 0
                    GaugeRing(progress: 1, color: allOk ? .accentGreen : .accentAmber) {
                        VStack(spacing: 2) {
                            Image(systemName: allOk ? "checkmark" : "exclamationmark.triangle")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(allOk ? Color.accentGreen : Color.accentAmber)
                        }
                    }
                    .frame(width: 148, height: 148)
                    Text("\(doneTasks)/\(state.refreshTasks.count) completed")
                        .font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 24)
                } else if state.refreshRunning {
                    let progress = state.refreshTotal > 0 ? Double(state.refreshCurrent) / Double(state.refreshTotal) : 0
                    GaugeRing(progress: progress, color: col, spinning: true, cleaning: true) {
                        VStack(spacing: 2) {
                            Text("\(state.refreshCurrent)").font(.system(size: 24, weight: .bold)).foregroundStyle(.textPrimary).monospacedDigit()
                            Text("of \(state.refreshTotal)").font(.mono(8)).foregroundStyle(.textTertiary)
                        }
                    }
                    .frame(width: 148, height: 148)
                    Text("Running…").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 24)
                } else {
                    let selectedCount = state.refreshTasks.filter(\.isSelected).count
                    GaugeRing(progress: selectedCount > 0 ? Double(selectedCount) / Double(max(state.refreshTasks.count, 1)) : 0, color: col) {
                        VStack(spacing: 2) {
                            Text("\(selectedCount)").font(.system(size: 28, weight: .bold)).foregroundStyle(.textPrimary).monospacedDigit()
                            Text("tasks").font(.mono(8)).foregroundStyle(.textTertiary)
                        }
                    }
                    .frame(width: 148, height: 148)
                    Text("\(state.refreshTasks.count) available").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 24)
                }
            }

            Spacer()

            VStack(spacing: 6) {
                Circle().fill(state.refreshDone ? Color.accentGreen : (state.refreshRunning ? col : Color.textTertiaryLight)).frame(width: 6, height: 6)
                Text(state.refreshDone ? "Complete" : (state.refreshRunning ? "Processing" : "Ready"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func refreshLeft(col: Color) -> some View {
        if state.refreshDone {
            let executed = state.refreshTasks.filter { $0.state == .done || $0.state == .failed }
            let doneTasks = executed.filter { $0.state == .done }.count
            let failedTasks = executed.filter { $0.state == .failed }.count
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: failedTasks == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(failedTasks == 0 ? Color.accentGreen : Color.accentAmber)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(doneTasks) of \(executed.count) completed")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.textPrimary)
                        if failedTasks > 0 {
                            Text("\(failedTasks) skipped — may need permissions")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.accentAmber)
                        } else {
                            Text("All tasks completed successfully")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(failedTasks == 0 ? Color.accentGreen.opacity(0.06) : Color.accentAmber.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder((failedTasks == 0 ? Color.accentGreen : Color.accentAmber).opacity(0.2)))

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(executed) { task in
                            HStack(spacing: 8) {
                                Image(systemName: task.state == .done ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(task.state == .done ? Color.accentGreen : Color.accentRed)
                                Text(task.title)
                                    .font(.system(size: 11)).foregroundStyle(Color.textSecondaryLight)
                                    .lineLimit(1)
                                Spacer()
                                Text(task.state == .done ? "OK" : "Skip")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(task.state == .done ? Color.accentGreen.opacity(0.7) : Color.accentRed.opacity(0.7))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.surfaceCardLight)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                HStack(spacing: 8) {
                    secondaryButton("Done") {
                        activeTool = nil
                        state.refreshDone = false
                        state.refreshTasks = SystemRefreshService.allTasks()
                    }
                    actionButton("Run Again", icon: "arrow.clockwise", color: col) { startRefresh() }
                }
            }
        } else if state.refreshRunning {
            VStack(alignment: .leading, spacing: 10) {
                statusBlock(label: "Status", value: "Refreshing", valueColor: .textPrimary,
                            sub: "\(state.refreshCurrent) of \(state.refreshTotal) tasks")
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(state.refreshTasks) { task in
                            HStack(spacing: 8) {
                                Group {
                                    switch task.state {
                                    case .done:
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentGreen)
                                    case .failed:
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.accentRed)
                                    case .running:
                                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                                    case .pending:
                                        Circle().stroke(Color.textTertiaryLight.opacity(0.3), lineWidth: 1.5).frame(width: 12, height: 12)
                                    }
                                }
                                .font(.system(size: 12))
                                .frame(width: 14)

                                Text(task.title)
                                    .font(.system(size: 11, weight: task.state == .running ? .medium : .regular))
                                    .foregroundStyle(task.state == .pending ? Color.textTertiaryLight : Color.textSecondaryLight)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.surfaceCardLight)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                HStack {
                    Text("Maintenance Tasks")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.textPrimary)
                    Spacer()
                    Button {
                        let allSel = state.refreshTasks.allSatisfy(\.isSelected)
                        for i in state.refreshTasks.indices { state.refreshTasks[i].isSelected = !allSel }
                    } label: {
                        Text(state.refreshTasks.allSatisfy(\.isSelected) ? "Deselect All" : "Select All")
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.textTertiaryLight)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.surfaceCardLight).clipShape(RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain)
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(state.refreshTasks.indices, id: \.self) { i in
                            HStack(spacing: 8) {
                                Button {
                                    state.refreshTasks[i].isSelected.toggle()
                                } label: {
                                    Image(systemName: state.refreshTasks[i].isSelected ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 13))
                                        .foregroundStyle(state.refreshTasks[i].isSelected ? col : Color.textTertiaryLight.opacity(0.4))
                                }.buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(state.refreshTasks[i].title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(state.refreshTasks[i].isSelected ? Color.textPrimaryLight : Color.textSecondaryLight)
                                        .lineLimit(1)
                                    Text(state.refreshTasks[i].detail)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(Color.textTertiaryLight)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(state.refreshTasks[i].isSelected ? col.opacity(0.04) : Color.surfaceCardLight)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                let selectedCount = state.refreshTasks.filter(\.isSelected).count
                actionButton(selectedCount > 0 ? "Run \(selectedCount) Tasks" : "Select tasks",
                             icon: "arrow.triangle.2.circlepath", color: col,
                             disabled: selectedCount == 0, busy: state.refreshRunning) { startRefresh() }
            }
        }
    }

    private var refreshLiveAnalytics: some View {
        VStack(spacing: 0) {
            analyticsHeader("Maintenance Tasks")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach([
                        ("QuickLook Cache",        "eye",                     "Preview thumbnail cache"),
                        ("Font Cache",             "textformat",              "System font rendering cache"),
                        ("Launch Services DB",     "app.badge",               "App file type associations"),
                        ("Launch Agents",          "gearshape.2",             "Background service plists"),
                        ("Notification Center",    "bell.badge",              "Notification database WAL"),
                        ("Quarantine History",     "shield.checkered",        "Downloaded file quarantine log"),
                        ("Spotlight Rules",        "magnifyingglass",         "Spotlight exclusion entries"),
                        (".DS_Store Prevention",   "folder.badge.gearshape",  "Prevent on network/USB drives"),
                    ], id: \.0) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.1).font(.system(size: 11))
                                .foregroundStyle(CleanerTool.refresh.accentColor).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.0).font(.system(size: 11, weight: .medium)).foregroundStyle(.textPrimary)
                                Text(item.2).font(.mono(9)).foregroundStyle(.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
    }

    // MARK: - DNS Panel

    private var dnsPanel: some View {
        toolShell(
            description: "Removes cached DNS records stored by macOS. Fixes connectivity issues caused by stale or wrong DNS entries.",
            infoTitle: "What DNS cache contains",
            info: { dnsLiveAnalytics },
            right: { simpleGauge(flow: state.dnsFlow, color: CleanerTool.dns.accentColor, icon: "network", success: state.dnsSuccess, doneLabel: state.dnsSuccess ? "Cache cleared" : "Failed", idleLabel: "Cache active") },
            left: { dnsLeft }
        )
    }

    @ViewBuilder
    private var dnsLeft: some View {
        let col = CleanerTool.dns.accentColor
        switch state.dnsFlow {
        case .idle:
            VStack(alignment: .leading, spacing: 0) {
                statusBlock(label: "DNS Cache", value: "Active", valueColor: .textPrimary, sub: "Managed by mDNSResponder")
                VStack(alignment: .leading, spacing: 8) {
                    networkInfoRow(icon: "wifi", label: "Interface", value: cachedNetworkInterface).onAppear(perform: loadNetworkInfo)
                    networkInfoRow(icon: "dot.radiowaves.left.and.right", label: "Resolver", value: cachedDNSResolver)
                }
                .padding(.top, 14)
                Spacer()
                actionButton("Flush DNS Cache", icon: "arrow.triangle.2.circlepath", color: col) {
                    operationActive = true
                    state.dnsFlow = .running
                    DNSCleaner.flush { s, m in withAnimation { state.dnsSuccess = s; state.dnsMessage = m; state.dnsFlow = .done; operationActive = false } }
                }
            }
        case .running:
            VStack(alignment: .leading, spacing: 14) {
                statusBlock(label: "Status", value: "Flushing", valueColor: .textPrimary, sub: "Restarting DNS resolver")
                VStack(spacing: 11) {
                    stepRow("Stopping mDNSResponder", state: 1, detail: "working…")
                    stepRow("Clearing cache entries", state: 1, detail: "")
                    stepRow("Restarting resolver", state: 2, detail: "pending")
                }
                Spacer()
            }
        case .done:
            VStack(alignment: .leading, spacing: 14) {
                statusBlock(label: state.dnsSuccess ? "Complete" : "Failed", value: state.dnsSuccess ? "Cache Cleared" : "Error",
                            valueColor: state.dnsSuccess ? .accentGreen : .accentRed,
                            sub: state.dnsSuccess ? "All DNS records flushed" : state.dnsMessage)
                VStack(spacing: 11) {
                    stepRow("mDNSResponder service", state: state.dnsSuccess ? 0 : 2, detail: state.dnsSuccess ? "restarted" : "error")
                    stepRow("DNS cache entries", state: state.dnsSuccess ? 0 : 2, detail: state.dnsSuccess ? "cleared" : "failed")
                }
                Spacer()
                HStack(spacing: 8) {
                    secondaryButton("Done") { activeTool = nil; state.dnsFlow = .idle }
                    if state.dnsSuccess {
                        actionButton("Flush Again", icon: "arrow.clockwise", color: col) {
                            operationActive = true
                            state.dnsFlow = .running
                            DNSCleaner.flush { s, m in withAnimation { state.dnsSuccess = s; state.dnsMessage = m; state.dnsFlow = .done; operationActive = false } }
                        }
                    }
                }
            }
        }
    }
    // MARK: - Safe Delete Panel

    private var shredderPanel: some View {
        let col = CleanerTool.shredder.accentColor
        return toolShell(
            description: "Moves selected files to the macOS Trash so accidental removal can be undone.",
            infoTitle: "Safe Deletion Info",
            info: { shredderLiveAnalytics },
            right: { shredderGauge(col: col) },
            left: { shredderLeft(col: col) }
        )
    }

    @ViewBuilder
    private func shredderGauge(col: Color) -> some View {
        VStack(spacing: 0) {
            // Top: Gauge Ring
            VStack(spacing: 10) {
                if state.shredderDone {
                    GaugeRing(progress: 1, color: .accentGreen) {
                        Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.accentGreen)
                    }
                    Text("\(state.shredderCount) moved").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 14)
                } else if state.isShredding {
                    GaugeRing(progress: 0, color: col, spinning: true, cleaning: true) {
                        Image(systemName: "flame.fill").font(.system(size: 28)).foregroundStyle(col)
                    }
                    Text("Moving to Trash…").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 14)
                } else {
                    GaugeRing(progress: state.shredderFiles.isEmpty ? 0 : 1, color: col) {
                        VStack(spacing: 2) {
                            Text("\(state.shredderFiles.count)").font(.system(size: 30, weight: .bold)).foregroundStyle(.textPrimary).monospacedDigit()
                            Text("file(s)").font(.mono(8)).foregroundStyle(.textTertiary)
                        }
                    }
                    Text(state.shredderFiles.isEmpty ? "No files selected" : "Ready to move").font(.mono(9)).foregroundStyle(.textTertiary).padding(.top, 14)
                }
            }

            Spacer()

            // Bottom: Compact status
            VStack(spacing: 6) {
                Circle().fill(state.shredderDone ? Color.accentGreen : col).frame(width: 6, height: 6)
                Text(state.shredderDone ? "Moved to Trash" : state.isShredding ? "Processing" : "Waiting")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.surfaceSecondary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func shredderLeft(col: Color) -> some View {
        if state.shredderDone {
            VStack(alignment: .leading, spacing: 14) {
                statusBlock(label: "Complete", value: "\(state.shredderCount) Moved", valueColor: .accentGreen, sub: "Items remain recoverable from Trash")
                VStack(spacing: 11) {
                    stepRow("Move to Trash", state: 0, detail: "completed")
                    stepRow("Original location", state: 0, detail: "cleared")
                    stepRow("Recovery", state: 0, detail: "available")
                }
                Spacer()
                HStack(spacing: 8) {
                    secondaryButton("Done") { activeTool = nil; state.shredderDone = false; state.shredderFiles = [] }
                    actionButton("Move More", icon: "plus", color: col) { state.shredderDone = false; state.shredderFiles = [] }
                }
            }
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(state.shredderFiles.isEmpty ? "Select files to move" : "\(state.shredderFiles.count) file(s) queued")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.textPrimary)
                    Spacer()
                }
                if state.shredderFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        scanHint("Sensitive documents", icon: "lock.doc")
                        scanHint("Private data", icon: "person.badge.minus")
                        scanHint("Stubborn files", icon: "hammer")
                    }
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(state.shredderFiles, id: \.self) { url in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.fill").font(.system(size: 11)).foregroundStyle(.accentAmber)
                                    Text(url.lastPathComponent).font(.system(size: 11)).foregroundStyle(.textPrimary).lineLimit(1)
                                    Spacer()
                                    Button { state.shredderFiles.removeAll { $0 == url } } label: {
                                        Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.textTertiary)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.surfaceSecondary).clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK { state.shredderFiles.append(contentsOf: panel.urls) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 11))
                            Text(state.shredderFiles.isEmpty ? "Select Files" : "Add").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.surfaceSecondary).clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.borderSubtle))
                    }.buttonStyle(.plain)
                    if !state.shredderFiles.isEmpty {
                        actionButton("Move \(state.shredderFiles.count) to Trash", icon: "trash", color: col, busy: state.isShredding) {
                            operationActive = true
                            state.isShredding = true
                            let urls = state.shredderFiles
                            DispatchQueue.global(qos: .utility).async {
                                var moved: [URL] = []
                                for url in urls {
                                    if (try? SafeDeletionService.moveToTrash(url)) != nil {
                                        moved.append(url)
                                    }
                                }
                                DispatchQueue.main.async {
                                    operationActive = false
                                    state.isShredding = false
                                    state.shredderCount = moved.count
                                    state.shredderFiles.removeAll { moved.contains($0) }
                                    withAnimation { state.shredderDone = true }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // MARK: - Live Analytics per tool

    private var ramLiveAnalytics: some View {
        VStack(spacing: 8) {
            analyticsHeader("Memory Breakdown")
                .padding(.bottom, 2)
            let mem = monitor.memory
            let total = Double(max(mem.total, 1))
            analyticsBar(label: "Wired",      value: Double(mem.wired) / total,      bytes: mem.wired,      color: Color(red: 0.9, green: 0.35, blue: 0.35))
            analyticsBar(label: "Active",     value: Double(mem.used - min(mem.used, mem.wired + mem.compressed)) / total, bytes: mem.used - min(mem.used, mem.wired + mem.compressed), color: .accent)
            analyticsBar(label: "Compressed", value: Double(mem.compressed) / total,  bytes: mem.compressed, color: Color(red: 0.9, green: 0.65, blue: 0.2))
            analyticsBar(label: "Inactive",   value: Double(mem.cached) / total,      bytes: mem.cached,     color: Color(red: 0.3, green: 0.75, blue: 0.55))
            analyticsBar(label: "Free",       value: Double(mem.free) / total,        bytes: mem.free,       color: .textTertiary)

            Divider().opacity(0.3).padding(.vertical, 2)

            Text("Top Consumers")
                .font(.mono(9, weight: .semibold)).foregroundStyle(.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(monitor.topProcesses.prefix(3)) { proc in
                analyticsProcessRow(name: proc.name, value: proc.memoryBytes,
                    total: mem.total, color: .accent, isMemory: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
    private var diskLiveAnalytics: some View {
        VStack(spacing: 0) {
            analyticsHeader("SSD Space Breakdown")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if let disk = monitor.disks.first(where: { $0.mountPoint == "/" }) {
                        let usedFrac  = CGFloat(disk.usedPercent)
                        let freeFrac  = CGFloat(1.0 - disk.usedPercent)
                        let diskColor = disk.usedPercent > 0.85 ? Color.accentRed
                                      : disk.usedPercent > 0.7  ? Color.accentAmber
                                      : Color(red: 0.3, green: 0.75, blue: 0.55)

                        // ── Segmented capacity bar ──────────────────
                        VStack(spacing: 5) {
                            HStack {
                                Text(disk.volumeName)
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.textPrimary)
                                Spacer()
                                Text(String(format: "%.1f%%  used", disk.usedPercent * 100))
                                    .font(.mono(10)).foregroundStyle(diskColor)
                            }
                            GeometryReader { g in
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(diskColor)
                                        .frame(width: max(4, g.size.width * usedFrac), height: 10)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.borderSubtle.opacity(0.5))
                                        .frame(width: max(4, g.size.width * freeFrac), height: 10)
                                }
                            }.frame(height: 10)
                            HStack {
                                HStack(spacing: 4) {
                                    Circle().fill(diskColor).frame(width: 6, height: 6)
                                    Text(DiskInfo.formatted(disk.used) + " used")
                                        .font(.mono(8)).foregroundStyle(.textTertiary)
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    Circle().fill(Color.borderSubtle.opacity(0.8)).frame(width: 6, height: 6)
                                    Text(DiskInfo.formatted(disk.free) + " free of " + DiskInfo.formatted(disk.total))
                                        .font(.mono(8)).foregroundStyle(.textTertiary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // ── Space pressure indicator ─────────────────
                        let pressureLabel: String = disk.usedPercent > 0.9 ? "Critical"
                            : disk.usedPercent > 0.8 ? "High" : disk.usedPercent > 0.6 ? "Moderate" : "Healthy"
                        let pressureIcon  = disk.usedPercent > 0.8 ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                        let pressureColor = disk.usedPercent > 0.8 ? Color.accentRed
                            : disk.usedPercent > 0.6 ? Color.accentAmber : Color(red: 0.3, green: 0.75, blue: 0.55)
                        HStack(spacing: 10) {
                            Image(systemName: pressureIcon)
                                .font(.system(size: 13)).foregroundStyle(pressureColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Storage Pressure: \(pressureLabel)")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.textPrimary)
                                Text(disk.usedPercent > 0.8
                                     ? "Run Disk Junk scan to reclaim space"
                                     : "Storage is in good shape")
                                    .font(.mono(8)).foregroundStyle(.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(pressureColor.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(pressureColor.opacity(0.2)))

                        Divider().opacity(0.3).padding(.vertical, 2)

                        // ── Estimated space categories ───────────────
                        Text("Estimated Space Categories")
                            .font(.mono(9, weight: .semibold)).foregroundStyle(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        let categories: [(String, String, Double, Color)] = [
                            ("System & Apps",   "internaldrive",      0.25,  Color(red: 0.55, green: 0.45, blue: 0.9)),
                            ("User Documents",  "doc.text.fill",      0.30,  Color(red: 0.25, green: 0.65, blue: 1.0)),
                            ("Photos & Video",  "photo.fill",         0.20,  Color(red: 0.3,  green: 0.75, blue: 0.55)),
                            ("Caches & Logs",   "archivebox.fill",    0.12,  Color.accentAmber),
                            ("Other",           "ellipsis.circle",    0.13,  Color.textTertiary),
                        ]
                        let usedGB = Double(disk.used) / 1_073_741_824
                        ForEach(categories, id: \.0) { cat in
                            let estimatedGB = usedGB * cat.2
                            HStack(spacing: 8) {
                                Image(systemName: cat.1)
                                    .font(.system(size: 10)).foregroundStyle(cat.3)
                                    .frame(width: 14)
                                Text(cat.0)
                                    .font(.system(size: 11)).foregroundStyle(.textPrimary)
                                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color.borderSubtle).frame(height: 4)
                                        RoundedRectangle(cornerRadius: 2).fill(cat.3.opacity(0.75))
                                            .frame(width: max(4, g.size.width * CGFloat(cat.2)), height: 4)
                                    }
                                }.frame(width: 70, height: 4)
                                Text(String(format: "%.1f GB", estimatedGB))
                                    .font(.mono(9)).foregroundStyle(.textTertiary)
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }

                        Divider().opacity(0.3).padding(.vertical, 2)

                        // ── Key disk metrics ─────────────────────────
                        Text("Key Metrics")
                            .font(.mono(9, weight: .semibold)).foregroundStyle(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        let freeGB  = Double(disk.free)  / 1_073_741_824
                        let totalGB = Double(disk.total) / 1_073_741_824
                        let metrics: [(String, String, String)] = [
                            ("internaldrive.fill",   "Total capacity",   String(format: "%.0f GB", totalGB)),
                            ("checkmark.circle.fill","Available",        String(format: "%.1f GB", freeGB)),
                            ("externaldrive.fill",   "Used",             String(format: "%.1f GB (%.0f%%)", usedGB, disk.usedPercent * 100)),
                            ("bolt.fill",            "Volume",           disk.mountPoint == "/" ? "System (APFS)" : "External"),
                        ]
                        ForEach(metrics, id: \.0) { m in
                            HStack(spacing: 8) {
                                Image(systemName: m.0)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(red: 0.3, green: 0.75, blue: 0.55))
                                    .frame(width: 14)
                                Text(m.1).font(.system(size: 11)).foregroundStyle(.textSecondary)
                                Spacer()
                                Text(m.2).font(.mono(9, weight: .medium)).foregroundStyle(.textPrimary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.surfaceSecondary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        Text("No disk data available")
                            .font(.mono(10)).foregroundStyle(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
    }
    private var dnsLiveAnalytics: some View {
        VStack(spacing: 0) {
            analyticsHeader("Network Status")
            VStack(spacing: 8) {
                networkInfoRow(icon: "wifi", label: "Interface", value: cachedNetworkInterface)
                    .onAppear(perform: loadNetworkInfo)
                networkInfoRow(icon: "dot.radiowaves.left.and.right", label: "DNS Resolver", value: cachedDNSResolver)
                networkInfoRow(icon: "clock", label: "Cache Age", value: "Managed by mDNSResponder")
                networkInfoRow(icon: "lock.shield", label: "DNS over HTTPS", value: "System Default")

                Divider().opacity(0.3).padding(.vertical, 2)

                Text("What DNS cache contains")
                    .font(.mono(9, weight: .semibold)).foregroundStyle(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach([
                        ("Safari & WebKit",     "globe",         "Recent site lookups"),
                        ("Mail & Calendar",     "envelope",      "Server hostname cache"),
                        ("App Store & iCloud",  "icloud",        "Apple service endpoints"),
                        ("Background services", "gearshape.2",   "Daemon resolver cache"),
                    ], id: \.0) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.1).font(.system(size: 11))
                                .foregroundStyle(CleanerTool.dns.accentColor).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.0).font(.system(size: 11, weight: .medium)).foregroundStyle(.textPrimary)
                                Text(item.2).font(.mono(9)).foregroundStyle(.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
    private var shredderLiveAnalytics: some View {
        VStack(spacing: 0) {
            analyticsHeader("Safe Deletion Info")
            VStack(spacing: 8) {
                ForEach([
                    ("1. Select files",    "1.circle",          "Choose files you no longer need"),
                    ("2. Move to Trash",   "2.circle",          "macOS relocates each selected item"),
                    ("3. Review",          "3.circle",          "Restore an item if removal was accidental"),
                    ("4. Empty later",     "4.circle",          "Use Finder when permanent deletion is intended"),
                ], id: \.0) { step in
                    HStack(spacing: 10) {
                        Image(systemName: step.1).font(.system(size: 14))
                            .foregroundStyle(CleanerTool.shredder.accentColor).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(.textPrimary)
                            Text(step.2).font(.mono(9)).foregroundStyle(.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }

                    Divider().opacity(0.3).padding(.vertical, 2)

                    Text("MacCleaner does not claim secure overwrite on APFS or SSD storage. FileVault is the appropriate protection for data at rest.")
                        .font(.mono(9)).foregroundStyle(.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
    }

    private var optimizationCoreProgress: Double {
        switch state.optimizationPhase {
        case .ready:
            return 0.08
        case .scanning:
            guard !state.optimizationLogs.isEmpty else { return 0.18 }
            let finished = state.optimizationLogs.filter { $0.status == .success || $0.status == .failure }.count
            let estimated = Double(finished) / Double(max(state.optimizationLogs.count + 2, 4))
            return min(0.92, max(0.18, estimated))
        case .review:
            return 1
        case .cleaning:
            return 0.78
        case .success:
            return 1
        }
    }

    private var optimizationCoreIcon: String {
        switch state.optimizationPhase {
        case .ready: return "sparkles"
        case .scanning: return "magnifyingglass"
        case .review: return "checkmark.seal"
        case .cleaning: return "wand.and.stars"
        case .success: return "checkmark"
        }
    }

    private var optimizationCoreTitle: String {
        switch state.optimizationPhase {
        case .ready: return "Scan"
        case .scanning: return "Scanning"
        case .review: return "Clean"
        case .cleaning: return "Cleaning"
        case .success: return "Done"
        }
    }

    private var optimizationCoreSubtitle: String {
        switch state.optimizationPhase {
        case .ready:
            return "Smart system check"
        case .scanning:
            return state.optimizationLogs.last(where: { $0.status == .running })?.message ?? "Analyzing safe areas"
        case .review:
            return "Confirm cleanup"
        case .cleaning:
            return state.optimizationLogs.last(where: { $0.status == .running })?.message ?? "Applying cleanup"
        case .success:
            return "Optimization complete"
        }
    }

    private func handleOptimizationCoreTap() {
        switch state.optimizationPhase {
        case .ready:
            runOptimization()
        case .review:
            showOptimizationCleanupConfirmation = true
        case .success:
            withAnimation(.easeInOut(duration: 0.2)) {
                state.optimizationPhase = .ready
                state.optimizationLogs.removeAll()
            }
        case .scanning, .cleaning:
            break
        }
    }
    private func analyticsHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.mono(8, weight: .semibold))
                .foregroundStyle(.textTertiary)
            Rectangle().fill(Color.borderSubtle).frame(height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 2)
    }

    private func analyticsBar(label: String, value: Double, bytes: UInt64, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11)).foregroundStyle(.textSecondary)
                .frame(width: 76, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.borderSubtle).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(4, g.size.width * CGFloat(max(0, min(1, value)))), height: 6)
                }
            }.frame(height: 6)
            Text(MemoryInfo.formatted(bytes))
                .font(.mono(9)).foregroundStyle(.textTertiary)
                .frame(width: 62, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func analyticsProcessRow(name: String, value: UInt64, total: UInt64, color: Color, isMemory: Bool, labelOverride: String? = nil) -> some View {
        let ratio = total > 0 ? Double(value) / Double(total) : 0
        let label = labelOverride ?? (isMemory ? MemoryInfo.formatted(value) : String(format: "%.1f%%", ratio * 100))
        return HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 11)).foregroundStyle(.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.borderSubtle).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.7))
                        .frame(width: max(2, g.size.width * CGFloat(max(0, min(1, ratio)))), height: 4)
                }
            }.frame(width: 72, height: 4)
            Text(label)
                .font(.mono(9)).foregroundStyle(.textTertiary)
                .frame(width: 58, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func networkInfoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 11))
                .foregroundStyle(CleanerTool.dns.accentColor).frame(width: 16)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.textSecondary)
            Spacer()
            Text(value).font(.mono(9)).foregroundStyle(.textTertiary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func loadNetworkInfo() {
        guard cachedNetworkInterface == "Detecting\u{2026}" else { return }
        let ifaceFn = networkInterface
        let dnsFn   = dnsResolver
        Task {
            async let iface = Task.detached(priority: .utility) { ifaceFn() }.value
            async let dns   = Task.detached(priority: .utility) { dnsFn()   }.value
            let (resolvedIface, resolvedDns) = await (iface, dns)
            cachedNetworkInterface = resolvedIface
            cachedDNSResolver      = resolvedDns
        }
    }

    private func networkInterface() -> String {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/route")
        task.arguments = ["get", "default"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            let out = try runShortProcess(task, pipe: pipe, timeout: 3)
            for line in out.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface:") {
                    return trimmed.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
            return "en0"
        } catch {
            return "en0"
        }
    }

    private func dnsResolver() -> String {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/scutil")
        task.arguments = ["--dns"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            let out = try runShortProcess(task, pipe: pipe, timeout: 3)
            // scutil --dns output: "  nameserver[0] : 192.168.1.1"
            for line in out.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("nameserver[0]") {
                    if let colonIdx = trimmed.firstIndex(of: ":") {
                        let ip = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        if !ip.isEmpty { return ip }
                    }
                }
            }
            return "System DNS"
        } catch {
            return "System DNS"
        }
    }

    private func runShortProcess(_ task: Process, pipe: Pipe, timeout: TimeInterval) throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in semaphore.signal() }
        try task.run()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            return ""
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Actions

    private func startRAMAnalysis() {
        withAnimation(.easeInOut(duration: 0.2)) {
            operationActive = true
            ramFlow = .analyzing
            state.ramAnalyzeProgress = 0
        }
        let phases: [(String, Double)] = [
            ("Checking memory pressure…", 0.2),
            ("Reading inactive page cache…", 0.45),
            ("Scanning top consumers…", 0.70),
            ("Evaluating compressed pages…", 0.88),
            ("Finalizing report…", 1.0),
        ]
        for (i, (phase, prog)) in phases.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.18) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.ramAnalyzePhase = phase
                    state.ramAnalyzeProgress = prog
                }
            }
        }
        RAMCleaner.analyze(memory: monitor.memory, processes: monitor.processNodes) { result in
            withAnimation(.easeInOut(duration: 0.3)) {
                state.ramAnalysis = result
                state.ramSources = result.sources
                ramFlow = .results
                operationActive = false
            }
        }
    }

    private func performRAMClean() {
        guard !state.ramSources.filter({ $0.isSelected }).isEmpty else { return }
        withAnimation {
            operationActive = true
            ramFlow = .cleaning
            state.ramFreedBytes = 0
            state.ramPurgeSuccess = true
            state.ramClosedApps = 0
            state.ramRefusedApps = 0
        }

        RAMCleaner.closeSelectedApplications(items: state.ramSources) { result in
            state.ramPurgeSuccess = result.closedAny
            state.ramFreedBytes = result.estimatedReleasedBytes
            state.ramClosedApps = result.closedCount
            state.ramRefusedApps = result.refusedCount
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                ramFlow = .done
                operationActive = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { monitor.refresh(forceProcesses: true) }
        }
    }

    private func returnToToolGrid() {
        DispatchQueue.main.async {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                activeTool = nil
            }
        }
    }

    private func startScan(mode: DiskCleanScanMode = .efficient) {
        withAnimation(.easeInOut(duration: 0.2)) {
            operationActive = true
            state.isScanning = true
            state.hasScan = false
            state.showResult = false
            state.scanProgress = 0
            state.scanPhase = .browsers
            state.diskScanWasLimited = false
            state.diskScannedEntryCount = 0
            state.diskScanMode = mode
        }

        // Animate through phases
        let phases: [(ScanPhase, Double)] = [
            (.browsers,     0.10),
            (.devTools,     0.24),
            (.aiTools,      0.36),
            (.appCaches,    0.50),
            (.systemCaches, 0.62),
            (.logs,         0.74),
            (.savedState,   0.84),
            (.trash,        0.94),
            (.done,         1.0),
        ]
        for (i, (phase, prog)) in phases.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.22) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.scanPhase = phase
                    state.scanProgress = prog
                }
            }
        }

        DiskCleaner.scan(mode: mode) { result in
            withAnimation(.easeInOut(duration: 0.3)) {
                state.scanItems = result.items
                state.diskScanWasLimited = result.wasLimited
                state.diskScannedEntryCount = result.scannedEntryCount
                state.isScanning = false
                operationActive = false
                state.hasScan = true
                state.scanProgress = 1.0
            }
        }
    }

    private func startClean() {
        operationActive = true
        state.isCleaning = true
        let toClean = state.scanItems.filter(\.isSelected)
        DiskCleaner.clean(items: toClean) { freed, errors in
            state.isCleaning = false
            operationActive = false
            state.resultFreed = freed
            state.resultErrors = errors.count
            state.scanItems.removeAll { $0.isSelected }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                state.showResult = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { monitor.refresh(forceProcesses: true) }
        }
    }

    private func startRefresh() {
        let selected = state.refreshTasks.enumerated().filter { $0.element.isSelected }
        guard !selected.isEmpty else { return }
        operationActive = true
        state.refreshRunning = true
        state.refreshDone = false
        state.refreshTotal = selected.count
        state.refreshCurrent = 0

        func runNext(_ remaining: [(Int, RefreshTask)]) {
            guard let (idx, task) = remaining.first else {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        state.refreshRunning = false
                        state.refreshDone = true
                        operationActive = false
                    }
                }
                return
            }
            DispatchQueue.main.async {
                withAnimation { state.refreshTasks[idx].state = .running }
            }
            SystemRefreshService.execute(task: task) { ok in
                withAnimation {
                    state.refreshTasks[idx].state = ok ? .done : .failed
                    state.refreshCurrent += 1
                }
                runNext(Array(remaining.dropFirst()))
            }
        }
        runNext(selected.map { ($0.offset, $0.element) })
    }

    // MARK: - Helpers

    private var ramSubtitle: String {
        "\(Int(monitor.memory.usedPercent * 100))% used · \(MemoryInfo.formatted(monitor.memory.total)) total"
    }

    private var ramPressureLabel: String {
        let p = monitor.memory.usedPercent
        if p > 0.9 { return "Critical" } else if p > 0.75 { return "High" } else if p > 0.6 { return "Moderate" } else { return "Normal" }
    }

    private var ramPressureColor: Color {
        let p = monitor.memory.usedPercent
        if p > 0.75 { return .accentRed } else if p > 0.6 { return .accentAmber } else { return .accentGreen }
    }

    private func safetyColor(_ s: RAMSafety) -> Color {
        switch s { case .safe: return .accentGreen; case .review: return .accentAmber; case .locked: return .textTertiary }
    }

    private func safetyLabel(_ s: RAMSafety) -> String {
        switch s { case .safe: return "Safe"; case .review: return "Review"; case .locked: return "Locked" }
    }

    private func ramSourceIcon(_ k: RAMSourceKind) -> String {
        switch k {
        case .inactiveCache: return "memorychip"
        case .compressed:    return "rectangle.compress.vertical"
        case .topProcess:    return "app.fill"
        case .wired:         return "lock.fill"
        }
    }

    private var diskSubtitle: String {
        if let disk = monitor.disks.first(where: { $0.mountPoint == "/" }) {
            return "\(DiskInfo.formatted(disk.free)) free · \(DiskInfo.formatted(disk.total)) total"
        }
        return "Disk usage"
    }
}

// MARK: - Optimization Action Core

private struct OptimizationActionCore: View {
    let phase: OptimizationPhase
    let color: Color
    let progress: Double
    let icon: String
    let title: String
    let subtitle: String
    let pulsing: Bool

    private var clampedProgress: CGFloat {
        CGFloat(max(0.0, min(1.0, progress)))
    }

    private var isBusy: Bool {
        phase == .scanning || phase == .cleaning
    }

    private var statusText: String {
        switch phase {
        case .ready: return "READY"
        case .scanning: return "ANALYZING"
        case .review: return "REVIEW"
        case .cleaning: return "APPLYING"
        case .success: return "COMPLETE"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.085))
                .frame(width: 226, height: 226)
                .scaleEffect(pulsing && phase == .ready ? 1.035 : 1.0)
                .opacity(pulsing && phase == .ready ? 0.55 : 0.34)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: pulsing)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.surfaceCardLight.opacity(0.98),
                            color.opacity(0.105),
                            Color.surfaceCardLight.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: color.opacity(0.22), radius: 20, x: 0, y: 12)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                .overlay(Circle().strokeBorder(color.opacity(0.16), lineWidth: 1))

            Circle()
                .stroke(Color.black.opacity(0.055), lineWidth: 8)
                .padding(14)

            Circle()
                .trim(from: 0, to: max(0.05, clampedProgress))
                .stroke(
                    LinearGradient(
                        colors: [
                            color.opacity(0.25),
                            color,
                            phase == .success ? Color.accentGreen : color.opacity(0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(14)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: clampedProgress)

            Circle()
                .stroke(color.opacity(0.10), lineWidth: 1)
                .padding(42)

            if isBusy {
                RotatingOptimizationSweep(color: color)
                    .padding(22)
            }

            VStack(spacing: 9) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                        .tracking(0.8)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.035))
                        .overlay(Capsule().strokeBorder(Color.borderLight, lineWidth: 1))
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(color.opacity(0.11))
                        .frame(width: 54, height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(color.opacity(0.15), lineWidth: 1))
                    Image(systemName: icon)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(color)
                        .scaleEffect(pulsing && isBusy ? 1.04 : 1.0)
                        .opacity(pulsing && isBusy ? 0.82 : 1.0)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                }

                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimaryLight)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 142)
            }
        }
    }
}

private struct RotatingOptimizationSweep: View {
    let color: Color
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.04, to: 0.16)
            .stroke(
                LinearGradient(
                    colors: [color.opacity(0.02), color.opacity(0.85), color.opacity(0.16)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 1.05).repeatForever(autoreverses: false), value: rotating)
            .onAppear {
                rotating = true
            }
    }
}

// MARK: - Gauge Ring (shared visual for all tools)

struct GaugeRing<Center: View>: View {
    var progress: Double
    var color: Color
    var spinning: Bool = false
    var cleaning: Bool = false
    var size: CGFloat = 164
    var lineWidth: CGFloat = 11
    var glow: Bool = true
    @ViewBuilder var center: () -> Center
    @State private var rotate = false
    @State private var pulse = false
    @State private var cleaningPulse = false
    @State private var isVisible = false

    var body: some View {
        ZStack {
            // Glow effect
            if glow && (spinning || progress > 0) {
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: size * 1.15, height: size * 1.15)
                    .scaleEffect(isVisible && pulse ? 1.05 : 1.0)
                    .opacity(isVisible && pulse ? 0.6 : 0.3)
                    .animation(isVisible ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: pulse)
            }
            
            // Enhanced cleaning pulse effect
            if cleaning {
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: lineWidth * 0.5)
                    .frame(width: size * 1.1, height: size * 1.1)
                    .scaleEffect(isVisible && cleaningPulse ? 1.15 : 1.0)
                    .opacity(isVisible && cleaningPulse ? 0.0 : 0.6)
                    .animation(isVisible ? .easeOut(duration: 0.6).repeatForever(autoreverses: false) : .default, value: cleaningPulse)
                
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: size * 1.2, height: size * 1.2)
                    .scaleEffect(isVisible && cleaningPulse ? 1.1 : 0.95)
                    .opacity(isVisible && cleaningPulse ? 0.3 : 0.5)
                    .animation(isVisible ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .default, value: cleaningPulse)
            }
            
            // Track
            Circle()
                .stroke(Color.borderSubtle.opacity(0.4), lineWidth: lineWidth)
            
            if spinning {
                // Animated spinning arc with gradient
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.4), color, color.opacity(0.9)]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(isVisible && rotate ? 360 : 0))
                    .animation(isVisible ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: rotate)
                    
                // Counter-rotating smaller arc for visual interest
                Circle()
                    .trim(from: 0, to: 0.12)
                    .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round))
                    .rotationEffect(.degrees(isVisible && rotate ? -360 : 0))
                    .animation(isVisible ? .linear(duration: 1.3).repeatForever(autoreverses: false) : .default, value: rotate)
                    
            } else {
                // Progress arc with spring animation
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.0001, min(1, progress))))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.5), color, color.opacity(0.85)]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.55, dampingFraction: 0.65, blendDuration: 0.1), value: progress)
                    
                // Shine effect on progress
                if progress > 0 {
                    Circle()
                        .trim(from: CGFloat(max(0, progress - 0.08)), to: CGFloat(min(1, progress + 0.02)))
                        .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.55, dampingFraction: 0.65), value: progress)
                }
            }
            
            // Center content with subtle scale animation
            center()
                .scaleEffect(isVisible && spinning ? 1.02 : 1.0)
                .animation(isVisible ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: spinning)
        }
        .frame(width: size, height: size)
        .offset(x: -8)
        .onAppear {
            isVisible = true
            pulse = true
            cleaningPulse = true
            rotate = true
        }
        .onDisappear {
            isVisible = false
        }
    }
}

// MARK: - Info popover button (hover-to-reveal details)

struct ToolInfoButton<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var isHovered = false
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator

    var body: some View {
        Button {
            modalCoordinator.present(title: title, subtitle: "Tool details") { content() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .rotationEffect(.degrees(isHovered ? 15 : 0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHovered)
                Text("Details").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isHovered ? Color.textSecondary : Color.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.surfaceSecondary.opacity(isHovered ? 0.9 : 0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isHovered ? Color.accent.opacity(0.3) : Color.borderSubtle, lineWidth: isHovered ? 1.5 : 1)
                    )
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in 
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Checkbox style

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundStyle(configuration.isOn ? Color.accent : Color.textTertiary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
