import AppKit
import SwiftUI

struct SimilarPhotoView: View {
    @ObservedObject var service: SimilarPhotoService
    @Binding var operationActive: Bool
    @State private var showCleanupConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.borderSubtle)

            if service.isScanning {
                scanningView
            } else if service.groups.isEmpty {
                emptyView
            } else {
                resultsView
            }
        }
        .background(Color.surfacePrimary)
        .onChange(of: service.isScanning) { _ in syncOperationState() }
        .onChange(of: service.isCleaning) { _ in syncOperationState() }
        .alert("Move visually similar photos to Trash?", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash") { service.moveSelectedToTrash() }
        } message: {
            Text("These are visual matches, not guaranteed byte-for-byte duplicates. \(service.selectedCount) selected photo\(service.selectedCount == 1 ? "" : "s") will be rechecked with Vision immediately before being moved to Trash. At least one photo remains in every group.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Exported photo folder")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text(displayPath(service.scanRoot))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 330, alignment: .leading)
            }

            Button("Choose…", action: chooseFolder)
                .buttonStyle(AppSecondaryButtonStyle())
                .disabled(service.isScanning || service.isCleaning)

            Spacer()

            AppSegmentedControl(
                selection: $service.mode,
                options: SimilarPhotoScanMode.allCases,
                accentColor: .accentGreen,
                title: \.rawValue
            )
            .frame(width: 180)
            .disabled(service.isScanning || service.isCleaning)

            if service.isScanning {
                Button("Cancel", action: service.cancelScan)
                    .buttonStyle(AppSecondaryButtonStyle())
            } else {
                Button(action: service.startScan) {
                    Label(service.status.phase == .finished ? "Rescan" : "Scan", systemImage: "photo.stack")
                }
                .buttonStyle(AppPrimaryButtonStyle(color: .pink))
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(service.isCleaning)
            }
        }
        .storageFeatureToolbar()
    }

    private var scanningView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(service.status.phase.rawValue)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: 18) {
                Label("\(service.status.discoveredPhotos.formatted()) found", systemImage: "photo.on.rectangle")
                Label("\(service.status.analyzedPhotos.formatted()) analyzed", systemImage: "viewfinder")
                Label("\(service.status.comparisons.formatted()) comparisons", systemImage: "arrow.left.arrow.right")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            Text(displayPath(URL(fileURLWithPath: service.status.currentPath)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 560)
            Text("On-device Vision · 512 px thumbnails · one utility-priority stream · no uploads")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        StorageFeatureEmptyState(
            icon: service.status.phase == .finished ? "checkmark.seal.fill" : "photo.stack.fill",
            color: .pink,
            title: service.status.phase == .finished ? "No conservative matches found" : "Find visually similar photos locally",
            subtitle: emptySubtitle,
            actionTitle: "Scan",
            actionIcon: "photo.stack",
            details: [
                "Read image dimensions without decoding originals",
                "Generate private 512 px Vision feature prints",
                "Keep every result unselected until you review it"
            ],
            footer: service.resultMessage,
            action: service.startScan
        )
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            summary
            if service.skippedCloudFiles > 0 || (service.resultMessage != nil && !service.scanWasLimited) {
                notice
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.groups) { group in
                        SimilarPhotoGroupCard(
                            group: group,
                            selectedPhotoIDs: service.selectedPhotoIDs,
                            scanRoot: service.scanRoot,
                            onToggle: { service.toggleSelection($0, in: group) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 92)
            }
            .overlay(alignment: .bottom) { cleanupBar }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            SimilarPhotoMetric(title: "GROUPS", value: service.groups.count.formatted(), detail: "conservative matches", color: .pink)
            SimilarPhotoMetric(title: "UP TO", value: formatBytes(service.potentialReclaimBytes), detail: "allocated variant bytes", color: .accentGreen)
            SimilarPhotoMetric(title: "ANALYZED", value: service.status.analyzedPhotos.formatted(), detail: "local feature prints", color: .accentBlue)
            SimilarPhotoMetric(title: "DURATION", value: formatDuration(service.lastScanDuration ?? 0), detail: service.mode.rawValue.lowercased() + " mode", color: .textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var notice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: service.scanWasLimited ? "gauge.with.dots.needle.67percent" : "info.circle")
                .foregroundStyle(service.scanWasLimited ? Color.accentAmber : Color.accentBlue)
            Text(noticeText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .padding(10)
        .background((service.scanWasLimited ? Color.accentAmber : Color.accentBlue).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var cleanupBar: some View {
        HStack(spacing: 12) {
            Button("Select lower-resolution variants", action: service.selectLowerResolutionVariants)
                .buttonStyle(AppSecondaryButtonStyle())
                .disabled(service.isCleaning)
            if !service.selectedPhotoIDs.isEmpty {
                Button("Clear", action: service.clearSelection)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(service.selectedCount) selected · up to \(formatBytes(service.selectedBytes))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Every file is rechecked; Trash only")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            if service.isCleaning { ProgressView().controlSize(.small) }
            Button("Move to Trash") { showCleanupConfirmation = true }
                .buttonStyle(AppPrimaryButtonStyle(color: .accentRed))
                .disabled(service.selectedPhotoIDs.isEmpty || service.isCleaning || !service.selectionKeepsOnePhotoPerGroup)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var emptySubtitle: String {
        if service.status.phase == .finished {
            return service.resultMessage ?? "The scan found no photos below its conservative visual-distance threshold."
        }
        return "\(service.mode.detail). Photos Library packages are never opened directly; choose a normal folder containing exported originals or copies."
    }

    private var noticeText: String {
        var parts: [String] = []
        if service.scanWasLimited { parts.append("The scan reached its photo, filesystem, comparison, or time budget; shown groups remain valid, but more may exist.") }
        if service.skippedCloudFiles > 0 { parts.append("\(service.skippedCloudFiles) cloud placeholder\(service.skippedCloudFiles == 1 ? " was" : "s were") skipped to avoid downloads.") }
        if let message = service.resultMessage { parts.append(message) }
        return parts.joined(separator: " ")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder containing exported photos"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = service.scanRoot
        if panel.runModal() == .OK, let url = panel.url { service.setScanRoot(url) }
    }

    private func syncOperationState() {
        operationActive = service.isScanning || service.isCleaning
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        value < 1 ? "< 1s" : "\(Int(value.rounded()))s"
    }
}

private struct SimilarPhotoMetric: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.textTertiary)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(color).monospacedDigit()
            Text(detail).font(.system(size: 9)).foregroundStyle(Color.textTertiary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderSubtle))
    }
}

private struct SimilarPhotoGroupCard: View {
    let group: SimilarPhotoGroup
    let selectedPhotoIDs: Set<String>
    let scanRoot: URL
    let onToggle: (SimilarPhotoItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(group.confidenceLabel, systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(group.maximumDistance <= SimilarPhotoService.verySimilarDistance ? Color.accentGreen : Color.pink)
                Text("\(group.photos.count) photos")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text("up to \(formatBytes(group.potentialReclaimBytes))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentGreen)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 10) {
                    ForEach(group.photos) { photo in
                        SimilarPhotoTile(
                            photo: photo,
                            isKeeper: photo.id == group.keeperID,
                            isSelected: selectedPhotoIDs.contains(photo.id),
                            relativePath: relativePath(photo.url),
                            onToggle: { onToggle(photo) }
                        )
                    }
                }
                .padding(.bottom, 5)
            }
        }
        .padding(13)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderSubtle))
    }

    private func relativePath(_ url: URL) -> String {
        let root = scanRoot.standardizedFileURL.path
        guard SafeDeletionService.isPath(url.path, inside: root) else { return url.path }
        let suffix = url.path.dropFirst(root.count)
        return suffix.isEmpty ? url.lastPathComponent : String(suffix.drop(while: { $0 == "/" }))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }
}

private struct SimilarPhotoTile: View {
    let photo: SimilarPhotoItem
    let isKeeper: Bool
    let isSelected: Bool
    let relativePath: String
    let onToggle: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.surfacePrimary)
                        .frame(width: 154, height: 112)
                        .overlay {
                            if let thumbnail {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 154, height: 112)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? Color.accentRed : Color.white)
                        .shadow(color: .black.opacity(0.45), radius: 2)
                        .padding(7)
                    if isKeeper {
                        Text("KEEP SUGGESTION")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.accentGreen)
                            .clipShape(Capsule())
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }
                }
                Text(photo.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(photo.resolution) · \(formatBytes(photo.allocatedBytes))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                Text(relativePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(8)
            .frame(width: 170, alignment: .leading)
            .background(isSelected ? Color.accentRed.opacity(0.08) : Color.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentRed.opacity(0.65) : Color.borderSubtle))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
        }
        .task(id: photo.id) {
            thumbnail = await DesktopThumbnailLoader.load(
                url: photo.url,
                maxPixelSize: 256,
                preferredSize: CGSize(width: 154, height: 112)
            )
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }
}
