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
    private let homeMaxWidth: CGFloat = 1180
    private let quickTools: [InternalStorageTool] = [
        .junkFiles,
        .uninstaller,
        .largeFiles,
        .analyzer,
        .specialized
    ]

    private var isWorking: Bool {
        operationActive || analysisOperationActive || storageWorkspace.isWorking
            || uninstallerService.isScanning || analyzerService.isScanning || analyzerService.isScanningJunk
    }

    var body: some View {
        ZStack {
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

                Spacer()

                if selectedTool != nil {
                    StorageQuickSwitcher(
                        selection: quickToolSelection,
                        tools: quickTools
                    )
                    .disabled(isWorking)
                    .help(isWorking ? "Finish the current operation before switching tools" : "Switch storage tool")
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
                        case .specialized:
                            ComprehensiveStorageAnalysisView(
                                advisor: storageWorkspace.cleanupAdvisor,
                                duplicates: storageWorkspace.duplicateFinder,
                                photos: storageWorkspace.similarPhotos,
                                cloud: storageWorkspace.cloudReclaim,
                                operationActive: $analysisOperationActive
                            )
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

    }
    }

    private var storageHome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(InternalStorageTool.coreTools, id: \.self) { tool in
                        Button(action: { selectedTool = tool }) {
                            StorageToolCard(tool: tool, height: 108)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Button(action: { selectedTool = .specialized }) {
                    StorageToolCard(tool: .specialized, height: 230)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .frame(width: 300)
            }
            .frame(maxWidth: homeMaxWidth, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Divider().background(Color.borderSubtle).padding(.top, 20)

            StorageCleanupStatsPanel(store: cleanupStatsStore)
                .frame(maxWidth: homeMaxWidth, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
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

    private var quickToolSelection: Binding<InternalStorageTool> {
        Binding(
            get: { selectedTool ?? .junkFiles },
            set: { selectedTool = $0 }
        )
    }
}

private struct StorageQuickSwitcher: View {
    @Binding var selection: InternalStorageTool
    let tools: [InternalStorageTool]
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tools, id: \.self) { tool in
                let isSelected = selection == tool

                Button {
                    selection = tool
                } label: {
                    Text(tool.shortName)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(isSelected ? Color.surfaceCardLight : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.borderLight, lineWidth: 1)
                            }
                        }
                        .shadow(
                            color: isSelected ? Color.black.opacity(0.12) : Color.clear,
                            radius: 2,
                            y: 1
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.rawValue)
            }
        }
        .padding(3)
        .frame(width: 410, height: 34)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.borderLight.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        .opacity(isEnabled ? 1 : 0.52)
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
                    .buttonStyle(AppPrimaryButtonStyle())
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
                .lineLimit(2)
                .frame(maxWidth: 620, minHeight: 28)

            actionButton

            descriptionBlock
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionButton: some View {
        Button(action: action) {
            Label(actionTitle, systemImage: actionIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 190, height: 38)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var descriptionBlock: some View {
        VStack(spacing: 9) {
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 580, minHeight: 36, alignment: .top)

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(details.enumerated()), id: \.offset) { index, detail in
                        Label(detail, systemImage: "\(index + 1).circle.fill")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            }

            if let footer {
                Text(footer)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 620, minHeight: 100, alignment: .top)
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

// MARK: - Comprehensive Specialized Analysis

private enum ComprehensiveAnalysisPhase: Equatable {
    case idle, advisor, duplicates, photos, cloud, finished

    var isRunning: Bool {
        switch self {
        case .advisor, .duplicates, .photos, .cloud: return true
        case .idle, .finished: return false
        }
    }

    var title: String {
        switch self {
        case .idle: return "Ready for a complete analysis"
        case .advisor: return "Analyzing cleanup opportunities"
        case .duplicates: return "Verifying exact duplicates"
        case .photos: return "Comparing similar photos"
        case .cloud: return "Inspecting local iCloud copies"
        case .finished: return "Complete analysis finished"
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0
        case .advisor: return 0.12
        case .duplicates: return 0.38
        case .photos: return 0.64
        case .cloud: return 0.88
        case .finished: return 1
        }
    }
}

struct ComprehensiveStorageAnalysisView: View {
    @ObservedObject var advisor: CleanupAdvisorService
    @ObservedObject var duplicates: DuplicateFinderService
    @ObservedObject var photos: SimilarPhotoService
    @ObservedObject var cloud: CloudReclaimService
    @Binding var operationActive: Bool
    @State private var phase: ComprehensiveAnalysisPhase = .idle

    private var totalReclaimBytes: UInt64 {
        advisor.totalBytes &+ duplicates.potentialReclaimBytes &+ photos.potentialReclaimBytes &+ cloud.totalEligibleBytes
    }

    private var isCleanupRunning: Bool {
        advisor.isCleaning || duplicates.isCleaning || photos.isCleaning || cloud.isEvicting
    }

    private var selectedReclaimBytes: UInt64 {
        let duplicateBytes = duplicates.groups
            .flatMap(\.files)
            .filter { duplicates.selectedFileIDs.contains($0.id) }
            .reduce(UInt64(0)) { $0 &+ $1.allocatedBytes }
        let photoBytes = photos.groups
            .flatMap(\.photos)
            .filter { photos.selectedPhotoIDs.contains($0.id) }
            .reduce(UInt64(0)) { $0 &+ $1.allocatedBytes }
        let cloudBytes = cloud.items
            .filter { cloud.selectedIDs.contains($0.id) }
            .reduce(UInt64(0)) { $0 &+ $1.allocatedBytes }
        return advisor.selectedBytes &+ duplicateBytes &+ photoBytes &+ cloudBytes
    }

    private var selectedItemCount: Int {
        advisor.selectedIDs.count
            + duplicates.selectedFileIDs.count
            + photos.selectedPhotoIDs.count
            + cloud.selectedIDs.count
    }

    var body: some View {
        Group {
            if phase == .finished {
                cleanupResults
                .transition(.opacity)
            } else {
                GeometryReader { geo in
                    ZStack {
                        // Static top section
                        VStack(spacing: 16) {
                            scanPanel
                        }
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.42)

                        // Bottom panel (readiness or progress)
                        VStack {
                            Spacer()
                            if phase == .idle {
                                readinessPanel
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else {
                                progressPanel
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .transition(.opacity)
            }
        }
        .background(Color.white)
        .onAppear { operationActive = phase.isRunning }
        .onChange(of: phase) { operationActive = $0.isRunning || isCleanupRunning }
        .onChange(of: isCleanupRunning) { operationActive = phase.isRunning || $0 }
        .onChange(of: advisor.isScanning) { scanning in
            if phase == .advisor, !scanning { beginDuplicates() }
        }
        .onChange(of: duplicates.isScanning) { scanning in
            if phase == .duplicates, !scanning { beginPhotos() }
        }
        .onChange(of: photos.isScanning) { scanning in
            if phase == .photos, !scanning { beginCloudOrFinish() }
        }
        .onChange(of: cloud.isScanning) { scanning in
            if phase == .cloud, !scanning { 
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    phase = .finished 
                }
            }
        }
    }

    private var cleanupResults: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cleanup Results")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Review every selected item before cleaning")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 72)
            .background(Color.surfaceSecondary)

            Divider().background(Color.borderSubtle)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 14) {
                    advisorCleanupSection
                    duplicateCleanupSection
                    photoCleanupSection
                    cloudCleanupSection
                }
                .frame(maxWidth: 980)
                .padding(20)
                .frame(maxWidth: .infinity)
            }

            Divider().background(Color.borderSubtle)

            HStack(spacing: 12) {
                if selectedItemCount == 0 {
                    Text("Select items to clean")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Text(formatBytes(selectedReclaimBytes))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("across \(selectedItemCount) selected item\(selectedItemCount == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                Button(action: start) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11))
                        Text("Scan Again").font(.system(size: 12))
                    }
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(isCleanupRunning)

                Button(action: clearSelection) {
                    Text("Clear")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                    .buttonStyle(.plain)
                    .disabled(selectedItemCount == 0 || isCleanupRunning)

                Button(action: selectSafeItems) {
                    Text("Select Safe")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                    .buttonStyle(.plain)
                    .disabled(isCleanupRunning)

                Button(action: cleanSelectedItems) {
                    HStack(spacing: 7) {
                        if isCleanupRunning {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text(isCleanupRunning ? "Cleaning…" : "Clean Selected")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedItemCount == 0 ? Color.textTertiary : Color.white)
                    .frame(width: 160, height: 34)
                    .background(selectedItemCount == 0 ? Color.surfaceSecondary : Color.accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(selectedItemCount == 0 || isCleanupRunning)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.surfaceSecondary.opacity(0.55))
        }
        .background(Color.surfaceLight)
    }

    private var advisorCleanupSection: some View {
        CompleteCleanupSection(
            title: "Cleanup Advisor",
            subtitle: "Caches, installers, archives, and developer leftovers",
            icon: "sparkle.magnifyingglass",
            color: .accentGreen,
            emptyText: "No supported cleanup opportunities found.",
            isEmpty: advisor.recommendations.isEmpty
        ) {
            ForEach(advisor.recommendations) { item in
                CompleteCleanupRow(
                    isSelected: advisor.selectedIDs.contains(item.id),
                    title: item.title,
                    subtitle: "\(item.detail) · \(item.itemCount) items",
                    value: formatBytes(item.bytes),
                    safety: item.isSelectedByDefault ? "Safe" : "Review",
                    safetyColor: item.isSelectedByDefault ? .accentGreen : .accentAmber,
                    action: { advisor.toggleSelection(item) }
                )
            }
        }
    }

    private var duplicateCleanupSection: some View {
        let removable = duplicates.groups.flatMap { group in
            group.files.filter { $0.id != group.keeperID }.map { (group, $0) }
        }
        return CompleteCleanupSection(
            title: "Exact Duplicates",
            subtitle: "Byte-for-byte verified copies; one copy always remains",
            icon: "doc.on.doc.fill",
            color: .accentPurple,
            emptyText: "No exact duplicate copies found.",
            isEmpty: removable.isEmpty
        ) {
            ForEach(removable, id: \.1.id) { group, item in
                CompleteCleanupRow(
                    isSelected: duplicates.selectedFileIDs.contains(item.id),
                    title: item.displayName,
                    subtitle: item.url.path,
                    value: formatBytes(item.allocatedBytes),
                    safety: "Verified",
                    safetyColor: .accentGreen,
                    action: { duplicates.toggleSelection(item, in: group) }
                )
            }
        }
    }

    private var photoCleanupSection: some View {
        let variants = photos.groups.flatMap { group in
            group.photos.filter { $0.id != group.keeperID }.map { (group, $0) }
        }
        return CompleteCleanupSection(
            title: "Similar Photos",
            subtitle: "Visual matches require manual review and are never selected automatically",
            icon: "photo.stack.fill",
            color: .pink,
            emptyText: "No conservative visual matches found.",
            isEmpty: variants.isEmpty
        ) {
            ForEach(variants, id: \.1.id) { group, item in
                CompleteCleanupRow(
                    isSelected: photos.selectedPhotoIDs.contains(item.id),
                    title: item.displayName,
                    subtitle: "\(item.url.path) · \(item.resolution)",
                    value: formatBytes(item.allocatedBytes),
                    safety: "Review",
                    safetyColor: .accentAmber,
                    action: { photos.toggleSelection(item, in: group) }
                )
            }
        }
    }

    private var cloudCleanupSection: some View {
        CompleteCleanupSection(
            title: "Cloud Reclaim",
            subtitle: "Remove local copies while preserving originals in iCloud",
            icon: "icloud.and.arrow.down.fill",
            color: .accentBlue,
            emptyText: cloud.isAvailable ? "No reclaimable local iCloud copies found." : "iCloud Drive is not available.",
            isEmpty: cloud.items.isEmpty
        ) {
            ForEach(cloud.items) { item in
                CompleteCleanupRow(
                    isSelected: cloud.selectedIDs.contains(item.id),
                    title: item.displayName,
                    subtitle: "\(item.url.path) · inactive \(item.inactiveDays) days",
                    value: formatBytes(item.allocatedBytes),
                    safety: item.inactiveDays >= 90 ? "Safe" : "Review",
                    safetyColor: item.inactiveDays >= 90 ? .accentGreen : .accentAmber,
                    action: { cloud.toggle(item) }
                )
            }
        }
    }

    private func selectSafeItems() {
        advisor.selectedIDs = Set(advisor.recommendations.filter(\.isSelectedByDefault).map(\.id))
        duplicates.selectSuggestedCopies()
        photos.clearSelection()
        cloud.selectInactive(days: 90)
    }

    private func clearSelection() {
        advisor.selectedIDs = []
        duplicates.clearSelection()
        photos.clearSelection()
        cloud.clearSelection()
    }

    private func cleanSelectedItems() {
        if !advisor.selectedIDs.isEmpty { advisor.moveSelectedToTrash() }
        if !duplicates.selectedFileIDs.isEmpty { duplicates.moveSelectedToTrash() }
        if !photos.selectedPhotoIDs.isEmpty { photos.moveSelectedToTrash() }
        if !cloud.selectedIDs.isEmpty { cloud.removeSelectedLocalCopies() }
    }

    private var scanPanel: some View {
        StorageScanHero(
            icon: "scope",
            color: .accentBlue,
            title: phase.title,
            subtitle: "One sequential scan covers cleanup opportunities, exact duplicates, similar photos, and reclaimable local iCloud copies.",
            isRunning: phase.isRunning,
            buttonTitle: "Scan",
            subtitleWidth: 500,
            action: phase.isRunning ? cancel : start
        )
    }

    private var readinessPanel: some View {
        VStack(spacing: 16) {
            Text("WHAT WILL BE ANALYZED")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondaryLight)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(alignment: .top, spacing: 20) {
                analysisScopeRowCompact("Cleanup Advisor", "Developer caches, installers, archives", "sparkle.magnifyingglass", .accentGreen)
                analysisScopeRowCompact("Exact Duplicates", "Byte-for-byte full verification", "doc.on.doc.fill", .accentPurple)
                analysisScopeRowCompact("Similar Photos", "Private on-device visual check", "photo.stack.fill", .pink)
                analysisScopeRowCompact("Cloud Reclaim", "Safe local-copy candidates", "icloud.and.arrow.down.fill", .accentBlue)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surfaceCardLight)
                .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
        )
        .frame(maxWidth: 800)
    }

    private func analysisScopeRowCompact(_ title: String, _ desc: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(height: 24)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textSecondaryLight)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var currentPhasePath: String {
        switch phase {
        case .advisor: return "Analyzing recommendations..."
        case .duplicates:
            return duplicates.status.currentPath.isEmpty ? "Indexing..." : duplicates.status.currentPath
        case .photos:
            return photos.status.currentPath.isEmpty ? "Scanning library..." : photos.status.currentPath
        case .cloud: return cloud.scanProgress.currentPath.isEmpty ? "Checking cloud files..." : cloud.scanProgress.currentPath
        default: return "Preparing..."
        }
    }

    private var progressPanel: some View {
        VStack(spacing: 12) {
            Text("ANALYSIS IN PROGRESS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondaryLight)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: phase.progress)
                    .tint(Color.accentBlue)
                
                HStack {
                    Text(phase.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textPrimaryLight)
                    Spacer()
                    Text("\(Int(phase.progress * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.textSecondaryLight)
                }

                Text(currentPhasePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surfaceCardLight)
                .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
        )
        .frame(maxWidth: 500)
    }

    private var summary: some View {
        AnalysisReportSection(title: "Executive summary", icon: "chart.bar.xaxis", color: .accentBlue) {
            HStack(spacing: 12) {
                reportMetric("Potential reclaim", formatBytes(totalReclaimBytes), .accentBlue)
                reportMetric("Advisor findings", "\(advisor.recommendations.count)", .accentGreen)
                reportMetric("Duplicate groups", "\(duplicates.groups.count)", .accentPurple)
                reportMetric("Photo groups", "\(photos.groups.count)", .pink)
                reportMetric("Cloud files", "\(cloud.items.count)", .cyan)
            }
        }
    }

    private var advisorResults: some View {
        AnalysisReportSection(title: "Cleanup Advisor", icon: "sparkle.magnifyingglass", color: .accentGreen) {
            if advisor.recommendations.isEmpty {
                emptyCategory("No supported cleanup opportunities found.")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(advisor.recommendations) { item in
                        DetailedAnalysisRow(
                            title: item.title,
                            subtitle: item.detail,
                            value: formatBytes(item.bytes),
                            details: [item.category.rawValue, item.risk.label, item.rebuildCost.label, "\(item.itemCount) items", item.why, item.solution],
                            color: .accentGreen
                        )
                    }
                }
            }
        }
    }

    private var duplicateResults: some View {
        AnalysisReportSection(title: "Exact Duplicates", icon: "doc.on.doc.fill", color: .accentPurple) {
            if duplicates.groups.isEmpty {
                emptyCategory("No byte-for-byte duplicate groups verified.")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(duplicates.groups) { group in
                        DetailedAnalysisRow(
                            title: "Duplicate group · \(group.files.count) files",
                            subtitle: group.files.map(\.displayName).joined(separator: ", "),
                            value: formatBytes(group.potentialReclaimBytes),
                            details: group.files.map { "\($0.id == group.keeperID ? "Keep" : "Copy"): \($0.url.path) · \(formatBytes($0.allocatedBytes))" },
                            color: .accentPurple
                        )
                    }
                }
            }
        }
    }

    private var photoResults: some View {
        AnalysisReportSection(title: "Similar Photos", icon: "photo.stack.fill", color: .pink) {
            if photos.groups.isEmpty {
                emptyCategory("No conservative visual matches found.")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(photos.groups) { group in
                        DetailedAnalysisRow(
                            title: "Photo group · \(group.confidenceLabel) · \(group.photos.count) files",
                            subtitle: group.photos.map(\.displayName).joined(separator: ", "),
                            value: formatBytes(group.potentialReclaimBytes),
                            details: group.photos.map { "\($0.id == group.keeperID ? "Best copy" : "Variant"): \($0.url.path) · \($0.resolution) · \(formatBytes($0.allocatedBytes))" },
                            color: .pink
                        )
                    }
                }
            }
        }
    }

    private var cloudResults: some View {
        AnalysisReportSection(title: "Cloud Reclaim", icon: "icloud.and.arrow.down.fill", color: .accentBlue) {
            if !cloud.isAvailable {
                emptyCategory("iCloud Drive is not available at the standard local location.")
            } else if cloud.items.isEmpty {
                emptyCategory("No safely reclaimable local iCloud copies found.")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(cloud.items) { item in
                        DetailedAnalysisRow(
                            title: item.displayName,
                            subtitle: item.url.path,
                            value: formatBytes(item.allocatedBytes),
                            details: ["Logical size: \(formatBytes(item.logicalBytes))", "Inactive for \(item.inactiveDays) days", "Cloud original remains available"],
                            color: .accentBlue
                        )
                    }
                }
            }
        }
    }

    private func start() {
        guard !phase.isRunning else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            advisor.resetForNavigation()
            duplicates.resetForNavigation()
            photos.resetForNavigation()
            cloud.resetForNavigation()
            phase = .advisor
        }
        advisor.scan()
    }

    private func beginDuplicates() {
        guard phase == .advisor else { return }
        phase = .duplicates
        duplicates.startScan()
    }

    private func beginPhotos() {
        guard phase == .duplicates else { return }
        phase = .photos
        photos.startScan()
    }

    private func beginCloudOrFinish() {
        guard phase == .photos else { return }
        if cloud.isAvailable {
            phase = .cloud
            cloud.scan()
        } else {
            phase = .finished
        }
    }

    private func cancel() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            phase = .idle
        }
        advisor.cancelScan()
        duplicates.cancelScan()
        photos.cancelScan()
        cloud.cancelScan()
    }

    private func analysisScopeRow(_ title: String, _ subtitle: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func reportMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.textSecondary)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private func emptyCategory(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }
}

private struct CompleteCleanupSection<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let emptyText: String
    let isEmpty: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }

            if isEmpty {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    content
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.035), radius: 8, y: 2)
    }
}

private struct CompleteCleanupRow: View {
    let isSelected: Bool
    let title: String
    let subtitle: String
    let value: String
    let safety: String
    let safetyColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Text(safety)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(safetyColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(safetyColor.opacity(0.10))
                    .clipShape(Capsule())

                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 82, alignment: .trailing)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider().background(Color.borderSubtle)
    }
}

private struct AnalysisReportSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.textPrimary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

private struct DetailedAnalysisRow: View {
    let title: String
    let subtitle: String
    let value: String
    let details: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.textPrimary)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text(value).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(color)
            }
            ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(13)
        .background(Color.white)
    }
}

// MARK: - Storage Cleanup Stats

struct StorageCleanupStatsPanel: View {
    @ObservedObject var store: CleanupStatsStore

    private var hasHistory: Bool {
        store.isLoaded && !store.entries.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
		                HStack(alignment: .top, spacing: 12) {
		                    CleanupCategoryBreakdown(store: store)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(height: 180)
                    CleanupRecurringList(entries: store.topRecurringEntries)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(height: 180)
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
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Button {
                    modalCoordinator.present(title: title, subtitle: subtitle) {
                        Text(info).font(.system(size: 12)).foregroundStyle(Color.textSecondary)
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.035), radius: 5, y: 2)
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

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 9) {
                    ForEach(totals, id: \.category) { item in
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
            HStack(spacing: 5) {
                Text("Recurring Paths")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                InfoPopoverButton(text: "A recurring rebuildable path means a tool recreated the cache after cleanup. This is normal for Xcode, browsers, V8, module caches, and indexes. The size is shown as current footprint, not accumulated permanent savings.")
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 8) {
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
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator

    var body: some View {
        Button {
            modalCoordinator.present(title: "Information") {
                Text(text).font(.system(size: 12)).foregroundStyle(Color.textSecondary)
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .buttonStyle(.plain)
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
