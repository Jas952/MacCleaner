import AppKit
import SwiftUI

struct CloudReclaimView: View {
    @ObservedObject var service: CloudReclaimService
    @Binding var operationActive: Bool
    @State private var sortOrder: CloudReclaimSortOrder = .size
    @State private var searchText = ""
    @State private var showEvictionConfirmation = false

    private var displayedItems: [CloudReclaimItem] {
        let filtered = searchText.isEmpty
            ? service.items
            : service.items.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
                    || $0.url.path.localizedCaseInsensitiveContains(searchText)
            }
        switch sortOrder {
        case .size:
            return filtered.sorted { $0.allocatedBytes > $1.allocatedBytes }
        case .inactive:
            return filtered.sorted { $0.lastUsedAt < $1.lastUsedAt }
        case .name:
            return filtered.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.borderSubtle)

            if service.isScanning {
                scanningView
            } else if service.items.isEmpty {
                emptyView
            } else {
                resultsView
            }
        }
        .background(Color.surfacePrimary)
        .onChange(of: service.isScanning) { _ in syncOperationState() }
        .onChange(of: service.isEvicting) { _ in syncOperationState() }
        .alert("Remove local iCloud downloads?", isPresented: $showEvictionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Free Local Space") { service.removeSelectedLocalCopies() }
        } message: {
            Text("The selected files remain in iCloud, but they will need an internet connection to open again. Files whose upload or conflict state cannot be revalidated will be protected.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("iCloud Drive")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Metadata-only scan · file contents are never opened")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()

            if !service.items.isEmpty {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(CloudReclaimSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 215)
            }

            if service.isScanning {
                Button("Cancel", action: service.cancelScan)
                    .buttonStyle(.bordered)
            } else {
                Button(action: { service.scan() }) {
                    Label(service.lastScanDuration == nil ? "Scan" : "Rescan", systemImage: "icloud.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!service.isAvailable || service.isEvicting)
            }
        }
        .storageFeatureToolbar()
    }

    private var scanningView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Inspecting local iCloud metadata")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: 18) {
                Label("\(service.scanProgress.scannedFiles.formatted()) files checked", systemImage: "doc.text.magnifyingglass")
                Label("\(service.scanProgress.eligibleFiles.formatted()) local copies", systemImage: "internaldrive")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            Text(relativePath(URL(fileURLWithPath: service.scanProgress.currentPath)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 580)
            Text("No content download, hashing, or network request is performed")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        Group {
            if service.isAvailable {
                StorageFeatureEmptyState(
                    icon: "icloud.fill",
                    color: .accentBlue,
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                    actionTitle: "Scan local iCloud copies",
                    actionIcon: "icloud.and.arrow.down",
                    footer: service.resultMessage,
                    action: { service.scan() }
                )
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "icloud.slash.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                    Text(emptyTitle).font(.system(size: 21, weight: .bold))
                    Text(emptySubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            summary
            safetyNotice

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textTertiary)
                TextField("Filter by file name or path", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderSubtle))
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(displayedItems) { item in
                        CloudReclaimRow(
                            item: item,
                            isSelected: service.selectedIDs.contains(item.id),
                            rootURL: service.rootURL,
                            onToggle: { service.toggle(item) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 88)
            }
            .overlay(alignment: .bottom) { actionBar }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            CloudMetric(
                title: "LOCAL COPIES",
                value: service.items.count.formatted(),
                detail: "uploaded and current",
                color: .accentBlue
            )
            CloudMetric(
                title: "POTENTIAL",
                value: formatBytes(service.totalEligibleBytes),
                detail: "allocated local bytes",
                color: .accentGreen
            )
            CloudMetric(
                title: "INACTIVE 90D",
                value: service.inactiveNinetyDayCount.formatted(),
                detail: "suggested for review",
                color: .accentAmber
            )
            CloudMetric(
                title: "SCAN",
                value: formatDuration(service.lastScanDuration ?? 0),
                detail: service.scanWasLimited ? "limit reached" : "metadata only",
                color: .textSecondary
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(Color.accentGreen)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cloud originals stay intact")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(noticeText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if service.scanWasLimited, service.scanMode == .efficient, !service.isScanning {
                Button("Run Thorough Scan") { service.scan(mode: .thorough) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(11)
        .background(Color.accentGreen.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Select inactive 90+ days") { service.selectInactive() }
                .buttonStyle(.bordered)
                .disabled(service.isEvicting)
            if !service.selectedIDs.isEmpty {
                Button("Clear", action: service.clearSelection)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(service.selectedIDs.count) selected · up to \(formatBytes(service.selectedBytes))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Selected files will require internet to open again")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            if service.isEvicting { ProgressView().controlSize(.small) }
            Button("Free Local Space") { showEvictionConfirmation = true }
                .buttonStyle(.borderedProminent)
                .disabled(service.selectedIDs.isEmpty || service.isEvicting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var emptyTitle: String {
        if !service.isAvailable { return "iCloud Drive is not available" }
        if service.lastScanDuration != nil { return "No safely evictable local copies" }
        return "Free disk space without deleting cloud files"
    }

    private var emptySubtitle: String {
        if !service.isAvailable {
            return "Enable iCloud Drive in System Settings or sign in to iCloud, then return to this screen."
        }
        if service.lastScanDuration != nil {
            return "No local iCloud file larger than 1 MB passed every upload, download-state, and conflict safety check."
        }
        return "Find files already uploaded to iCloud that still consume local disk space. Removing a local download does not remove the cloud original."
    }

    private var noticeText: String {
        var details = ["Only current, fully uploaded files without conflicts are eligible. State is checked again immediately before eviction."]
        if service.skippedUnverified > 0 {
            details.append("\(service.skippedUnverified) iCloud item\(service.skippedUnverified == 1 ? " was" : "s were") excluded because safety could not be proven.")
        }
        if service.scanWasLimited {
            details.append(service.scanMode == .efficient
                ? "The efficient scan hit its 8-second or 200,000-file limit; shown items remain valid."
                : "The thorough scan hit its 60-second or 1,000,000-file limit; shown items remain valid.")
        }
        if let message = service.resultMessage { details.append(message) }
        return details.joined(separator: " ")
    }

    private func syncOperationState() {
        operationActive = service.isScanning || service.isEvicting
    }

    private func relativePath(_ url: URL) -> String {
        let root = service.rootURL.path
        guard SafeDeletionService.isPath(url.path, inside: root) else { return url.path }
        let suffix = url.path.dropFirst(root.count)
        return suffix.isEmpty ? "iCloud Drive" : "iCloud Drive" + suffix
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        value < 1 ? "< 1s" : "\(Int(value.rounded()))s"
    }
}

private enum CloudReclaimSortOrder: String, CaseIterable {
    case size = "Largest"
    case inactive = "Oldest Use"
    case name = "Name"
}

private struct CloudMetric: View {
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

private struct CloudReclaimRow: View {
    let item: CloudReclaimItem
    let isSelected: Bool
    let rootURL: URL
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Keep \(item.displayName) downloaded" : "Select \(item.displayName) to remove its local download")

            Image(systemName: "icloud.and.arrow.down.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(relativePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
            Text(item.inactiveDays == 0 ? "Used recently" : "\(item.inactiveDays)d inactive")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(item.inactiveDays >= 90 ? Color.accentAmber : Color.textTertiary)
                .frame(width: 84, alignment: .trailing)
            Text(formatBytes(item.allocatedBytes))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
                .frame(width: 75, alignment: .trailing)
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentBlue.opacity(0.06) : Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(isSelected ? Color.accentBlue.opacity(0.35) : Color.borderSubtle))
    }

    private var relativePath: String {
        let root = rootURL.standardizedFileURL.path
        let path = item.url.standardizedFileURL.path
        guard SafeDeletionService.isPath(path, inside: root) else { return path }
        let suffix = path.dropFirst(root.count)
        return suffix.isEmpty ? item.displayName : "." + suffix
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
    }
}
