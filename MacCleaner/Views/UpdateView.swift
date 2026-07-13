import AppKit
import SwiftUI

struct UpdateWindowContent: View {
    @ObservedObject var updateService: UpdateService

    // This bundled Markdown file is also passed verbatim to GitHub Releases by
    // release.yml. Keeping one source prevents the in-app notes from drifting.
    private let releaseNotes = BundledReleaseNotes.current

    var body: some View {
        VStack(spacing: 16) {
            applicationCard
            releaseNotesCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var applicationCard: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 66)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text("MacCleaner")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)

                Text("Version \(updateService.currentVersion)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)

                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 10) {
                Button(action: updateService.checkForUpdates) {
                    HStack(spacing: 7) {
                        if updateService.status == .checking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(updateService.status == .checking ? "Checking…" : "Check for Updates")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 176, height: 34)
                    .background(Color.accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!updateService.canCheckForUpdates || updateService.status == .checking)
                .opacity(updateService.canCheckForUpdates ? 1 : 0.50)

                Toggle("Automatically check", isOn: automaticUpdatesBinding)
                    .toggleStyle(GreenCheckboxToggleStyle())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textPrimaryLight)
            }
        }
        .padding(18)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.borderLight, lineWidth: 1)
        )
    }

    private var releaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Release Notes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text("What’s new in version \(updateService.currentVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
                Link(destination: URL(string: "https://github.com/Jas952/MacCleaner/releases")!) {
                    Image("icon_github")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .opacity(0.72)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open GitHub Releases")
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(releaseNotes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(Color.accentBlue.opacity(0.75))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textSecondaryLight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(maxHeight: .infinity)
            .clipped()
        }
        .padding(16)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.borderLight, lineWidth: 1)
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updateService.automaticallyUpdates },
            set: { updateService.automaticallyUpdates = $0 }
        )
    }

    private var statusText: String {
        switch updateService.status {
        case .idle: return "Ready to check for updates"
        default: return updateService.status.detailText
        }
    }

    private var statusIcon: String {
        switch updateService.status {
        case .checking: return "arrow.triangle.2.circlepath"
        case .available: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "checkmark.shield.fill"
        case .upToDate, .installed: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch updateService.status {
        case .available: return Color.accentBlue
        case .failed: return Color.accentAmber
        case .checking: return Color.textSecondaryLight
        case .idle, .upToDate, .installed: return Color.accentGreen
        }
    }
}

private enum BundledReleaseNotes {
    static let current: [String] = {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return ["Release notes are unavailable."]
        }

        return markdown
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard line.hasPrefix("- ") else { return nil }
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
    }()
}

private struct GreenCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(configuration.isOn ? Color.accentGreen : Color.surfaceSecondary)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            configuration.isOn ? Color.accentGreen : Color.borderLight,
                            lineWidth: 1
                        )
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 19, height: 19)

                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
