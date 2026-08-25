import AppKit
import SwiftUI

struct UpdateWindowContent: View {
    @ObservedObject var updateService: UpdateService

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MacCleaner")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text("Version \(updateService.currentVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondaryLight)
                    Text("Secure updates powered by Sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
            }
            .padding(16)
            .background(Color.surfaceCardLight)
            .overlay(Rectangle().strokeBorder(Color.borderLight))

            Group {
                switch updateService.status {
                case .checking:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking for updates…")
                    }
                    .foregroundStyle(Color.textSecondaryLight)
                case .upToDate:
                    Label("MacCleaner is up to date", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentGreen)
                default:
                    Button { updateService.checkForUpdates() } label: {
                        Text("Check for Updates")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 18)
                            .frame(height: 32)
                            .background(Color.accentBlue)
                            .overlay(Rectangle().strokeBorder(Color.accentBlue.opacity(0.6)))
                    }
                        .buttonStyle(.plain)
                        .disabled(!updateService.canCheckForUpdates)
                        .opacity(updateService.canCheckForUpdates ? 1 : 0.50)
                }
            }
            .frame(minHeight: 32)

            Toggle("Automatically update", isOn: automaticUpdatesBinding)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundStyle(Color.textPrimaryLight)

            if updateService.status != .idle && updateService.status != .checking && updateService.status != .upToDate {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                    Text(statusText)
                }
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            Divider()
            Text("Update checks run quietly in the background. Manual results appear here without opening a separate Sparkle window.")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiaryLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updateService.automaticallyUpdates },
            set: { updateService.automaticallyUpdates = $0 }
        )
    }

    private var statusText: String { updateService.status.detailText }

    private var statusIcon: String {
        switch updateService.status {
        case .checking: return "arrow.triangle.2.circlepath"
        case .available: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle, .upToDate, .installed: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch updateService.status {
        case .available: return .blue
        case .failed: return .orange
        case .checking: return .secondary
        case .idle, .upToDate, .installed: return .green
        }
    }
}
