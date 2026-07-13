import AppKit
import SwiftUI

struct DuplicateFinderView: View {
    @ObservedObject var service: DuplicateFinderService
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
        .alert("Move verified duplicates to Trash?", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash") { service.moveSelectedToTrash() }
        } message: {
            Text("\(service.selectedCount) selected file\(service.selectedCount == 1 ? "" : "s") will be moved to Trash. At least one exact copy remains in each group, and nothing is permanently deleted.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Scan location")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text(displayPath(service.scanRoot))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 340, alignment: .leading)
            }

            Button("Choose…", action: chooseFolder)
                .buttonStyle(AppSecondaryButtonStyle())
                .disabled(service.isScanning || service.isCleaning)

            Spacer()

            AppSegmentedControl(
                selection: $service.mode,
                options: DuplicateScanMode.allCases,
                accentColor: .accentGreen,
                title: \.rawValue
            )
            .frame(width: 180)
            .disabled(service.isScanning || service.isCleaning)

            if service.isScanning {
                Button("Cancel", action: service.cancelScan)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentRed)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.accentRed.opacity(0.08))
                    .overlay(Rectangle().strokeBorder(Color.accentRed.opacity(0.28)))
            } else {
                Button(action: service.startScan) {
                    Label(service.status.phase == .finished ? "Rescan" : "Scan", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(Color.accentPurple)
                .overlay(Rectangle().strokeBorder(Color.accentPurple.opacity(0.55)))
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(service.isCleaning)
            }
        }
        .storageFeatureToolbar()
    }

    private var scanningView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(service.status.phase.rawValue)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: 18) {
                Label("\(service.status.scannedFiles.formatted()) files indexed", systemImage: "doc.text.magnifyingglass")
                Label("\(service.status.hashedFiles.formatted()) fingerprints", systemImage: "number")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            Text(displayPath(URL(fileURLWithPath: service.status.currentPath)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 560)
            Text("Single-stream utility-priority I/O · cloud placeholders and hard links are skipped")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        StorageFeatureEmptyState(
            icon: service.status.phase == .finished ? "checkmark.seal.fill" : "doc.on.doc.fill",
            color: .accentPurple,
            title: service.status.phase == .finished ? "No exact duplicates verified" : "Find byte-for-byte duplicate files",
            subtitle: emptySubtitle,
            actionTitle: "Scan",
            actionIcon: "doc.on.doc",
            details: [
                "Group by logical size",
                "Compare first and last 64 KB",
                "Prove matches with full SHA-256"
            ],
            footer: service.resultMessage,
            action: service.startScan
        )
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            summary

            if service.skippedCloudFiles > 0 || (service.resultMessage != nil && !service.scanWasLimited) {
                resultNotice
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.groups) { group in
                        DuplicateGroupCard(
                            group: group,
                            selectedFileIDs: service.selectedFileIDs,
                            scanRoot: service.scanRoot,
                            onToggle: { service.toggleSelection($0, in: group) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 90)
            }
            .overlay(alignment: .bottom) { cleanupBar }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            DuplicateMetric(
                title: "EXACT GROUPS",
                value: service.groups.count.formatted(),
                detail: "full SHA-256 matches",
                color: .accentPurple
            )
            DuplicateMetric(
                title: "POTENTIAL",
                value: formatBytes(service.potentialReclaimBytes),
                detail: "allocated copy bytes",
                color: .accentGreen
            )
            DuplicateMetric(
                title: "VERIFIED",
                value: service.status.hashedFiles.formatted(),
                detail: "fingerprint operations",
                color: .accentBlue
            )
            DuplicateMetric(
                title: "DURATION",
                value: formatDuration(service.lastScanDuration ?? 0),
                detail: service.mode.rawValue.lowercased() + " mode",
                color: .textSecondary
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var resultNotice: some View {
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
            Button("Select suggested copies", action: service.selectSuggestedCopies)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Color.accentBlue.opacity(0.10))
                .overlay(Rectangle().strokeBorder(Color.accentBlue.opacity(0.28)))
                .disabled(service.isCleaning)
            if !service.selectedFileIDs.isEmpty {
                Button("Clear", action: service.clearSelection)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("\(service.selectedCount) selected · \(formatBytes(service.selectedBytes))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("At least one exact copy remains per group")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            if service.isCleaning { ProgressView().controlSize(.small) }
            Button("Delete") { showCleanupConfirmation = true }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(Color.accentRed)
                .overlay(Rectangle().strokeBorder(Color.accentRed.opacity(0.65)))
                .disabled(service.selectedFileIDs.isEmpty || service.isCleaning || !service.selectionKeepsOneFilePerGroup)
                .opacity(service.selectedFileIDs.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.surfacePrimary)
        .overlay(alignment: .top) { Divider() }
    }

    private var emptySubtitle: String {
        if service.status.phase == .finished {
            return service.resultMessage ?? "The scan found no files with identical full content."
        }
        return "\(service.mode.detail). The default Home scan excludes Library, generated dependencies, packages, hidden files, and undownloaded cloud content."
    }

    private var noticeText: String {
        var parts: [String] = []
        if service.scanWasLimited { parts.append("The scan reached its entry, time, or I/O budget; shown matches are exact, but more may exist.") }
        if service.skippedCloudFiles > 0 { parts.append("\(service.skippedCloudFiles) cloud placeholder\(service.skippedCloudFiles == 1 ? " was" : "s were") skipped to avoid downloads.") }
        if let message = service.resultMessage { parts.append(message) }
        return parts.joined(separator: " ")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to scan for exact duplicates"
        panel.prompt = "Scan Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = service.scanRoot
        if panel.runModal() == .OK, let url = panel.url {
            service.setScanRoot(url)
        }
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 { return "< 1s" }
        if duration < 60 { return "\(Int(duration.rounded()))s" }
        return "\(Int(duration) / 60)m \(Int(duration) % 60)s"
    }
}

private struct DuplicateMetric: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderSubtle))
    }
}

private struct DuplicateGroupCard: View {
    let group: DuplicateFileGroup
    let selectedFileIDs: Set<String>
    let scanRoot: URL
    let onToggle: (DuplicateFileItem) -> Void
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.accentGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.files.first?.displayName ?? "Exact duplicates")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(group.files.count) byte-for-byte copies · \(formatBytes(group.logicalBytes)) each")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Text("Up to \(formatBytes(group.potentialReclaimBytes))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentGreen)
                    .monospacedDigit()
                Button(action: { expanded.toggle() }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if expanded {
                Divider().background(Color.borderSubtle)
                VStack(spacing: 7) {
                    ForEach(group.files) { item in
                        DuplicateFileRow(
                            item: item,
                            isKeeper: item.id == group.keeperID,
                            isSelected: selectedFileIDs.contains(item.id),
                            scanRoot: scanRoot,
                            onToggle: { onToggle(item) }
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderSubtle))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }
}

private struct DuplicateFileRow: View {
    let item: DuplicateFileItem
    let isKeeper: Bool
    let isSelected: Bool
    let scanRoot: URL
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Keep \(item.displayName)" : "Select \(item.displayName) for Trash")

            Image(systemName: "doc.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if isKeeper {
                        Text("Suggested keeper")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.accentGreen)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentGreen.opacity(0.11))
                            .clipShape(Capsule())
                    }
                }
                Text(relativePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
            Text(item.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.accentBlue)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentBlue.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var relativePath: String {
        let root = scanRoot.standardizedFileURL.path
        let path = item.url.standardizedFileURL.path
        if SafeDeletionService.isPath(path, inside: root) {
            let suffix = path.dropFirst(root.count)
            return suffix.isEmpty ? item.displayName : "." + suffix
        }
        return path
    }
}
