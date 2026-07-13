import AppKit
import SwiftUI

struct StartupOptimizerView: View {
    @ObservedObject var service: StartupOptimizerService
    @State private var searchText = ""
    @State private var showDisableConfirmation = false

    private var displayedItems: [StartupAgentItem] {
        guard !searchText.isEmpty else { return service.items }
        return service.items.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.label.localizedCaseInsensitiveContains(searchText)
                || ($0.executablePath?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.5)

            if service.isScanning && service.items.isEmpty {
                scanningView
            } else if service.items.isEmpty {
                emptyView
            } else {
                resultsView
            }
        }
        .background(Color.surfaceLight)
        .onAppear {
            if service.items.isEmpty && !service.isScanning { service.startScan() }
        }
        .alert("Disable selected startup items?", isPresented: $showDisableConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Disable") { service.disableSelected() }
        } message: {
            Text("MacCleaner will move \(service.selectedCount) user LaunchAgent plist\(service.selectedCount == 1 ? "" : "s") into its private disabled-items folder and ask launchd to stop the related services. Sync, updates, notifications, or helper features may stop. Every item can be restored.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("User LaunchAgents")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                Text("No root access · reversible changes only")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiaryLight)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiaryLight)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .frame(width: 150)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.borderLight))

            Button(action: openLoginItemsSettings) {
                Label("GUI Login Items", systemImage: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color.accentBlue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentBlue.opacity(0.26)))
            }
            .buttonStyle(.plain)
            .help("Open macOS Login Items & Extensions settings for app-managed login items")

            Button(action: service.startScan) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentBlue.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .disabled(service.isScanning || service.isMutating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.surfaceCardLight.opacity(0.55))
    }

    private var scanningView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Measuring startup agents")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)
            Text("Reading up to 500 small plist files and matching their executables to the current process list")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiaryLight)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 46))
                .foregroundStyle(Color.accentGreen)
            Text("No user LaunchAgents found")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)
            Text("App-managed GUI login items are controlled by macOS. Use the button below to review them in System Settings.")
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondaryLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("Open Login Items", action: openLoginItemsSettings)
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Color.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentBlue.opacity(0.55)))
            if let message = service.resultMessage {
                Text(message).font(.system(size: 10)).foregroundStyle(Color.textSecondaryLight)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            metrics

            if let message = service.resultMessage {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Color.accentBlue)
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                    Spacer()
                }
                .padding(9)
                .background(Color.accentBlue.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(displayedItems) { item in
                        StartupAgentRow(
                            item: item,
                            isSelected: service.selectedItemIDs.contains(item.id),
                            isBusy: service.isMutating,
                            onToggle: { service.toggleSelection(item) },
                            onRestore: { service.restore(item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 76)
            }
            .overlay(alignment: .bottom) { actionBar }
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            StartupMetric(
                title: "USER AGENTS",
                value: service.enabledItems.count.formatted(),
                detail: "plist startup services",
                color: .accentBlue
            )
            StartupMetric(
                title: "RUNNING NOW",
                value: service.runningCount.formatted(),
                detail: "matched executables",
                color: .accentPurple
            )
            StartupMetric(
                title: "MEASURED RAM",
                value: MemoryInfo.formatted(service.measuredMemoryBytes),
                detail: "not a theoretical estimate",
                color: .accentAmber
            )
            StartupMetric(
                title: "HIGH IMPACT",
                value: service.highImpactCount.formatted(),
                detail: "score ≥ 60 / 100",
                color: service.highImpactCount > 0 ? .accentRed : .accentGreen
            )
            StartupMetric(
                title: "DISABLED",
                value: service.disabledItems.count.formatted(),
                detail: "available to restore",
                color: .accentGreen
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if !service.selectedItemIDs.isEmpty {
                Button("Clear", action: service.clearSelection)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondaryLight)
            }
            Text("Nothing is selected automatically")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiaryLight)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(service.selectedCount) selected · \(MemoryInfo.formatted(service.selectedMeasuredMemoryBytes)) measured now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text("Exited-process RSS is reported only after the matched PID disappears")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            if service.isMutating { ProgressView().controlSize(.small) }
            Button("Disable Selected") { showDisableConfirmation = true }
                .buttonStyle(.plain)
                .foregroundStyle(service.selectedItemIDs.isEmpty ? Color.textTertiaryLight : Color.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(service.selectedItemIDs.isEmpty ? Color.surfaceCardLight : Color.accentPurple)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(service.selectedItemIDs.isEmpty ? Color.borderLight : Color.accentPurple.opacity(0.55)))
                .disabled(service.selectedItemIDs.isEmpty || service.isMutating || service.isScanning)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.surfaceCardLight)
        .overlay(alignment: .top) { Divider() }
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

private struct StartupMetric: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 8))
                .foregroundStyle(Color.textTertiaryLight)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.borderLight))
    }
}

private struct StartupAgentRow: View {
    let item: StartupAgentItem
    let isSelected: Bool
    let isBusy: Bool
    let onToggle: () -> Void
    let onRestore: () -> Void

    private var impactColor: Color {
        switch item.impact {
        case .high: return .accentRed
        case .medium: return .accentAmber
        case .low: return .accentGreen
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            if item.location == .enabled {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiaryLight)
                }
                .buttonStyle(.plain)
                .disabled(!item.canDisable || isBusy)
                .help(item.canDisable ? "Select for reversible disable" : "Protected item")
            } else {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.accentGreen)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(impactColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: item.keepAlive ? "arrow.triangle.2.circlepath" : "bolt.horizontal.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(impactColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(item.location.rawValue)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(item.location == .enabled ? Color.accentBlue : Color.accentGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((item.location == .enabled ? Color.accentBlue : Color.accentGreen).opacity(0.08))
                        .clipShape(Capsule())
                    if item.isProtected {
                        Label("Protected", systemImage: "lock.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                }
                Text(item.label.isEmpty ? item.url.lastPathComponent : item.label)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(1)
                Text(item.recommendation)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.textSecondaryLight)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.scheduleSummary)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
                if item.isRunning {
                    Text("\(MemoryInfo.formatted(item.currentMemoryBytes)) · \(item.currentCPUPercent, specifier: "%.1f")% CPU")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.accentPurple)
                } else {
                    Text("not matched running")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.textTertiaryLight)
                }
            }
            .frame(width: 150, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.impactScore)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(impactColor)
                    .monospacedDigit()
                Text(item.impact.rawValue)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(impactColor)
            }
            .frame(width: 72, alignment: .trailing)

            if item.canRestore {
                Button("Restore", action: onRestore)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentGreen)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.accentGreen.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentGreen.opacity(0.28)))
                    .disabled(isBusy)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentBlue.opacity(0.06) : Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentBlue.opacity(0.45) : Color.borderLight))
        .contextMenu {
            Button("Show plist in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            if let path = item.executablePath, FileManager.default.fileExists(atPath: NSString(string: path).expandingTildeInPath) {
                Button("Show executable in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)])
                }
            }
        }
    }
}
