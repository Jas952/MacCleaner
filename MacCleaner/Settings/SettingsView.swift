import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject var monitor: SystemMonitor
    @State private var selectedTab = SettingsTab.general
    @State private var draggedMenuBarGauge: MenuBarGauge?
    @State private var isBrowserMonitorInstallGuidePresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            tools
                .tabItem { Label("Tools", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.tools)
            menuBar
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(SettingsTab.menuBar)
        }
        .padding(18)
        .frame(width: 760, height: 580)
        .foregroundStyle(Color.textPrimaryLight)
        .background(Color.surfaceLight)
        // The application currently uses a light-only semantic palette. Keeping
        // the Settings scene light prevents native Form/GroupBox materials from
        // switching to dark while their labels retain the app's light colors.
        .preferredColorScheme(.light)
    }

    private var general: some View {
        Form {
            Section("Appearance") {
                Text("Tool availability and menu bar layout are stored locally on this Mac.")
                    .foregroundStyle(Color.textSecondaryLight)
            }
            Section("Privacy") {
                Label("Capture and media tools process content locally.", systemImage: "lock.shield")
                Label("Optional permissions are requested only when a tool is used.", systemImage: "hand.raised")
            }
            Section {
                HStack(alignment: .center, spacing: 16) {
                    Image("browser_monitor")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 64)
                        .accessibilityLabel("Browser Monitor icon")

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Browser Monitor")
                            .font(.headline)
                        Text("Local Chrome tab insights, tracker protection and reversible controls for busy pages.")
                            .font(.callout)
                            .foregroundStyle(Color.textSecondaryLight)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Link(destination: BrowserMonitorLink.download) {
                                Label("Download", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Link(destination: BrowserMonitorLink.repository) {
                                Image("icon_github")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.link)
                            .help("Open the project page")
                            .accessibilityLabel("Open the Browser Monitor project page")

                            Button {
                                isBrowserMonitorInstallGuidePresented.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("How to install Browser Monitor")
                            .accessibilityLabel("Browser Monitor installation instructions")
                            .popover(isPresented: $isBrowserMonitorInstallGuidePresented, arrowEdge: .bottom) {
                                BrowserMonitorInstallGuide()
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            } header: {
                Text("More tools from this developer")
            } footer: {
                Text("A companion utility from the same developer, available separately from MacCleaner.")
            }
        }
        .formStyle(.grouped)
    }

    private var tools: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsHeader(
                    title: "Choose your tools",
                    subtitle: "Each switch controls one thing: whether the tool appears in the Tools sidebar. Menu bar shortcuts are configured in the Menu Bar tab."
                )
                ForEach(UtilityToolCategory.allCases) { category in
                    GroupBox(category.rawValue) {
                        VStack(spacing: 0) {
                            ForEach(UtilityToolID.configurableCases.filter { $0.category == category }) { tool in
                                HStack(spacing: 12) {
                                    Image(systemName: tool.icon)
                                        .frame(width: 22)
                                        .foregroundStyle(Color.accentBlue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 7) {
                                            Text(tool.title).fontWeight(.medium)
                                            if tool.isBeta {
                                                Text("BETA")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .tracking(0.6)
                                                    .foregroundStyle(Color.accentPurple)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(Color.accentPurple.opacity(0.10), in: Capsule())
                                            }
                                        }
                                        Text(tool.subtitle).font(.caption).foregroundStyle(Color.textSecondaryLight)
                                    }
                                    Spacer()
                                    if tool.isBeta {
                                        Text("In development")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(Color.textTertiaryLight)
                                            .frame(width: 112, alignment: .trailing)
                                    } else {
                                        Toggle("Show in Tools", isOn: Binding(
                                            get: { settings.isEnabled(tool) },
                                            set: { settings.setEnabled($0, for: tool) }
                                        ))
                                        .toggleStyle(.switch)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 8)
                                if tool != UtilityToolID.configurableCases.filter({ $0.category == category }).last { Divider() }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(4)
        }
    }

    private var menuBar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsHeader(
                    title: "Menu bar",
                    subtitle: "Choose which modules appear, then set each module's indicator style and value format. Order below matches the macOS menu bar."
                )

                GroupBox("Live preview") {
                    HStack {
                        ForEach(Array(settings.menuBarGaugeIDs.enumerated()), id: \.element) { index, rawValue in
                            if let gauge = MenuBarGauge(rawValue: rawValue) {
                                if index > 0 {
                                    Divider()
                                        .frame(height: 14)
                                        .opacity(0.55)
                                }
                                MenuBarGaugeChip(
                                    gauge: gauge,
                                    monitor: monitor,
                                    format: settings.valueFormat(for: gauge),
                                    displayStyle: settings.displayStyle(for: gauge)
                                )
                            }
                        }
                        if settings.menuBarGaugeIDs.isEmpty {
                            Image(nsImage: NSApplication.shared.applicationIconImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .help("MacCleaner icon")
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 10))
                }

                GroupBox("Status modules · drag to reorder") {
                    VStack(spacing: 8) {
                        ForEach(orderedMenuBarGauges) { gauge in
                            menuBarGaugeRow(gauge)
                        }
                    }
                    .padding(4)
                    .animation(.easeInOut(duration: 0.16), value: settings.menuBarGaugeIDs)
                }

                GroupBox("Quick tools inside the MacCleaner menu") {
                    VStack(spacing: 0) {
                        ForEach(UtilityToolID.configurableCases.filter(\.supportsMenuBar)) { tool in
                            MenuBarQuickToolRow(
                                title: tool.title,
                                subtitle: "Show in the Tools tab of the menu bar popover",
                                icon: tool.icon,
                                isEnabled: Binding(
                                    get: { settings.isInMenuBar(tool) },
                                    set: { settings.setInMenuBar($0, for: tool) }
                                )
                            )
                            if tool != UtilityToolID.configurableCases.filter(\.supportsMenuBar).last { Divider() }
                        }
                        Divider()
                        MenuBarQuickToolRow(
                            title: "Clipboard History",
                            subtitle: "Show the session history beside the other quick tools",
                            icon: "doc.on.clipboard",
                            isEnabled: $settings.clipboardHistoryInMenuBar
                        )
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(4)
        }
    }

    private var orderedMenuBarGauges: [MenuBarGauge] {
        let enabled = settings.menuBarGaugeIDs.compactMap(MenuBarGauge.init(rawValue:))
        let enabledIDs = Set(enabled.map(\.rawValue))
        return enabled + MenuBarGauge.allCases.filter { !enabledIDs.contains($0.rawValue) }
    }

    @ViewBuilder
    private func menuBarGaugeRow(_ gauge: MenuBarGauge) -> some View {
        let isEnabled = settings.isGaugeEnabled(gauge)
        let row = HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.textSecondaryLight : Color.textTertiaryLight.opacity(0.45))
                .frame(width: 18, height: 24)
                .help(isEnabled ? "Drag this tile to reorder" : "Enable this module to reorder it")

            Label(gauge.title, systemImage: gauge.icon)
                .frame(width: 142, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { settings.isGaugeEnabled(gauge) },
                set: { settings.setGaugeEnabled($0, gauge: gauge) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(width: 42)

            Group {
                if isEnabled {
                    MenuBarGaugeChip(
                        gauge: gauge,
                        monitor: monitor,
                        format: settings.valueFormat(for: gauge),
                        displayStyle: settings.displayStyle(for: gauge)
                    )
                } else {
                    Text("Hidden")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiaryLight)
                }
            }
            .frame(width: 126, alignment: .leading)

            Picker("Indicator style", selection: Binding(
                get: { settings.displayStyle(for: gauge) },
                set: { settings.setDisplayStyle($0, for: gauge) }
            )) {
                ForEach(MenuBarGaugeDisplayStyle.allCases) { style in
                    Image(systemName: style.icon)
                        .accessibilityLabel(style.title)
                        .tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 72)
            .help("Indicator style: \(settings.displayStyle(for: gauge).title)")

            Picker("Format", selection: Binding(
                get: { settings.valueFormat(for: gauge) },
                set: { settings.setValueFormat($0, for: gauge) }
            )) {
                ForEach(gauge.valueFormats) { format in
                    Image(systemName: gauge.formatIcon(for: format))
                        .accessibilityLabel(format.accessibilityTitle)
                        .tag(format)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 72)
            .help("Value format: \(settings.valueFormat(for: gauge).accessibilityTitle)")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.black.opacity(isEnabled ? 0.09 : 0.05), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onDrop(
            of: [UTType.text],
            delegate: MenuBarGaugeDropDelegate(
                target: gauge,
                draggedGauge: $draggedMenuBarGauge,
                settings: settings
            )
        )

        if isEnabled {
            row.onDrag {
                draggedMenuBarGauge = gauge
                return NSItemProvider(object: gauge.rawValue as NSString)
            }
        } else {
            row.opacity(0.72)
        }
    }

}

private enum SettingsTab: Hashable {
    case general
    case tools
    case menuBar
}

private enum BrowserMonitorLink {
    static let repository = URL(string: "https://github.com/Jas952/BrowserMonitor")!
    static let download = URL(string: "https://github.com/Jas952/BrowserMonitor/releases/download/v1.0.0/browser-monitor-1.0.0.zip")!
}

private struct BrowserMonitorInstallGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Install in Chrome")
                .font(.headline)

            VStack(alignment: .leading, spacing: 7) {
                installStep(1, "Extract the downloaded ZIP to a permanent folder.")
                installStep(2, "Open chrome://extensions and enable Developer mode.")
                installStep(3, "Choose Load unpacked and select the folder containing manifest.json.")
                installStep(4, "Pin Browser Monitor to the Chrome toolbar.")
            }

            Text("Keep the extracted folder after installation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
    }

    private func installStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MenuBarGaugeDropDelegate: DropDelegate {
    let target: MenuBarGauge
    @Binding var draggedGauge: MenuBarGauge?
    let settings: SettingsManager

    func dropEntered(info: DropInfo) {
        guard
            let draggedGauge,
            draggedGauge != target,
            settings.isGaugeEnabled(target)
        else { return }

        settings.moveGauge(draggedGauge.rawValue, to: target.rawValue)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedGauge = nil
        return true
    }
}

private struct MenuBarQuickToolRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondaryLight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.callout).foregroundStyle(Color.textSecondaryLight)
        }
    }
}
