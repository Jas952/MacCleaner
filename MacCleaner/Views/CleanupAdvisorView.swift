import AppKit
import SwiftUI

struct CleanupAdvisorView: View {
    @ObservedObject var service: CleanupAdvisorService
    @Binding var operationActive: Bool
    @State private var showReviewConfirmation = false

    private var selectedRecommendations: [CleanupRecommendation] {
        service.recommendations.filter { service.selectedIDs.contains($0.id) }
    }

    private var hasReviewSelection: Bool {
        selectedRecommendations.contains { $0.risk == .review }
    }

    var body: some View {
        VStack(spacing: 0) {
            advisorToolbar
            Divider().background(Color.borderSubtle)

            if service.isScanning {
                scanningState
            } else if service.recommendations.isEmpty {
                emptyState
            } else {
                recommendationsList
            }
        }
        .background(Color.surfacePrimary)
        .onChange(of: service.isScanning) { _ in syncOperationState() }
        .onChange(of: service.isCleaning) { _ in syncOperationState() }
        .alert("Review-sensitive items selected", isPresented: $showReviewConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash") { service.moveSelectedToTrash() }
        } message: {
            Text("The selection includes personal archives, installers, or device backups. Confirm that you reviewed these paths. Items remain recoverable in Trash until you empty it.")
        }
    }

    private var advisorToolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Evidence-based reclaim")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Ranks real allocated bytes by impact, age, safety, and rebuild cost")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            if let lastScanAt = service.lastScanAt, !service.isScanning {
                Text("Scanned \(lastScanAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            if service.isScanning {
                Button("Cancel") { service.cancelScan() }
                    .buttonStyle(.bordered)
            } else {
                Button(action: service.scan) {
                    Label(service.lastScanAt == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(service.isCleaning)
            }
        }
        .storageFeatureToolbar()
    }

    private var scanningState: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Measuring reclaim opportunities")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text("The scan is local, read-only, time-bounded, and can be cancelled at any time.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        StorageFeatureEmptyState(
            icon: service.lastScanAt == nil ? "sparkle.magnifyingglass" : "checkmark.shield.fill",
            color: .accentGreen,
            title: service.lastScanAt == nil ? "Find the best cleanup opportunities" : "No meaningful opportunities found",
            subtitle: service.lastScanAt == nil
                ? "Scan developer caches, old installers, app archives, and local device backups."
                : "The scan found no supported target larger than 10 MB.",
            actionTitle: service.lastScanAt == nil ? "Start local scan" : "Scan again",
            actionIcon: "sparkle.magnifyingglass",
            action: service.scan
        )
    }

    private var recommendationsList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AdvisorMetric(
                    title: "Found",
                    value: formatBytes(service.totalBytes, limited: service.recommendations.contains(where: \.estimateIsLimited)),
                    detail: "\(service.recommendations.count) ranked opportunities",
                    color: .accentBlue
                )
                AdvisorMetric(
                    title: "Selected",
                    value: formatBytes(service.selectedBytes, limited: selectedRecommendations.contains(where: \.estimateIsLimited)),
                    detail: "moves to Trash only",
                    color: .accentGreen
                )
                AdvisorMetric(
                    title: "Safety",
                    value: "Undoable",
                    detail: "no permanent-delete fallback",
                    color: .accentPurple
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            if let message = service.resultMessage {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.accentBlue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(service.recommendations) { recommendation in
                        CleanupRecommendationRow(
                            recommendation: recommendation,
                            isSelected: service.selectedIDs.contains(recommendation.id),
                            toggle: { service.toggleSelection(recommendation) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 86)
            }
            .overlay(alignment: .bottom) {
                cleanupBar
            }
        }
    }

    private var cleanupBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(Color.accentGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected: \(formatBytes(service.selectedBytes, limited: selectedRecommendations.contains(where: \.estimateIsLimited)))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Disk space is reclaimed after you empty Trash in Finder")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
            if service.isCleaning { ProgressView().controlSize(.small) }
            Button("Move selected to Trash") {
                if hasReviewSelection {
                    showReviewConfirmation = true
                } else {
                    service.moveSelectedToTrash()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.selectedIDs.isEmpty || service.isCleaning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func syncOperationState() {
        operationActive = service.isScanning || service.isCleaning
    }

    private func formatBytes(_ bytes: UInt64, limited: Bool) -> String {
        let value = DiskCleaner.formattedSize(Int64(min(bytes, UInt64(Int64.max))))
        return limited ? "≥ \(value)" : value
    }
}

private struct AdvisorMetric: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 10))
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

private struct CleanupRecommendationRow: View {
    let recommendation: CleanupRecommendation
    let isSelected: Bool
    let toggle: () -> Void
    @State private var isExpanded = false

    private var riskColor: Color {
        recommendation.risk == .low ? .accentGreen : .accentAmber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: toggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Deselect \(recommendation.title)" : "Select \(recommendation.title)")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(recommendation.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text(recommendation.risk.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(riskColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(riskColor.opacity(0.12))
                            .clipShape(Capsule())
                        Text(recommendation.rebuildCost.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    Text(recommendation.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(sizeText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .monospacedDigit()
                    Text("Priority \(recommendation.priorityScore)/100")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(priorityColor)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                AdvisorExplanation(label: "WHY", text: recommendation.why)
                AdvisorExplanation(label: "SOLUTION", text: recommendation.solution)
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recommendation.paths.prefix(20), id: \.path) { url in
                        HStack(spacing: 7) {
                            Image(systemName: "doc")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                            Text(displayPath(url))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentBlue)
                        }
                    }
                    if recommendation.paths.count > 20 {
                        Text("+ \(recommendation.paths.count - 20) more paths")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.top, 7)
            } label: {
                Text("\(recommendation.paths.count) cleanup path\(recommendation.paths.count == 1 ? "" : "s") · \(recommendation.itemCount) measured files")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .tint(Color.textSecondary)
        }
        .padding(15)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentBlue.opacity(0.45) : Color.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
        )
    }

    private var sizeText: String {
        let value = DiskCleaner.formattedSize(Int64(min(recommendation.bytes, UInt64(Int64.max))))
        return recommendation.estimateIsLimited ? "≥ \(value)" : value
    }

    private var priorityColor: Color {
        if recommendation.priorityScore >= 70 { return .accentGreen }
        if recommendation.priorityScore >= 45 { return .accentBlue }
        return .textTertiary
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

private struct AdvisorExplanation: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
