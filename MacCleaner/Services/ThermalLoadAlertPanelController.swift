import AppKit
import SwiftUI

@MainActor
final class ThermalLoadAlertPanelController {
    static let shared = ThermalLoadAlertPanelController()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(_ alert: ThermalLoadAlert) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let effectView = NSVisualEffectView()
        // Match Clipboard History: `.popover` avoids the bright rectangular
        // HUD backing that becomes visible over white windows.
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        let hostingView = NSHostingView(rootView: ThermalLoadAlertPanelView(alert: alert) { [weak self] in
            self?.openDestination(alert.destination)
        } onDismiss: { [weak self] in
            self?.hide()
        })
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
        panel.contentView = effectView

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let origin = CGPoint(
                x: visible.maxX - panel.frame.width - 22,
                y: visible.maxY - panel.frame.height - 22
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 244),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func openDestination(_ destination: String) {
        hide()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .macCleanerOpenDestination,
            object: nil,
            userInfo: ["destination": destination]
        )
    }
}

private struct ThermalLoadAlertPanelView: View {
    let alert: ThermalLoadAlert
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                    Image(systemName: "flame.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text("High thermal load")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("MacCleaner detected sustained pressure")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss warning")
            }

            HStack(spacing: 8) {
                metric(title: "CPU LOAD", value: String(format: "%.0f%%", alert.cpuUsage))
                metric(title: alert.temperatureLabel, value: String(format: "%.0f°C", alert.temperature))
                metric(title: "TOP", value: "\(alert.topProcesses.count) processes")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("MAIN CONTRIBUTORS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(Color.white.opacity(0.62))
                ForEach(Array(alert.topProcesses.enumerated()), id: \.offset) { index, process in
                    HStack(spacing: 7) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.58))
                            .frame(width: 14)
                        Text(process)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }

            Button(action: onOpen) {
                HStack {
                    Image(systemName: "cpu.fill")
                    Text("Open Processes")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.27, green: 0.12, blue: 0.03))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.60, green: 0.12, blue: 0.045).opacity(0.84), Color(red: 0.85, green: 0.35, blue: 0.06).opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20))
        )
        .shadow(color: Color.black.opacity(0.30), radius: 22, y: 10)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.62))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }
}
