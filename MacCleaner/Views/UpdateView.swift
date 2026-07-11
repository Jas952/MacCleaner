import AppKit
import SwiftUI

struct UpdatePopoverView: View {
    @ObservedObject var updateService: UpdateService

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            VStack(spacing: 3) {
                Text("MacCleaner")
                    .font(.system(size: 17, weight: .semibold))
                Text("Version \(updateService.currentVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Button("Check for Updates") {
                updateService.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!updateService.canCheckForUpdates)

            Toggle("Automatically check for and install updates", isOn: automaticUpdatesBinding)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Label(statusText, systemImage: statusIcon)
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 330)
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
