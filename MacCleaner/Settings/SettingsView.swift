import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject var monitor: SystemMonitor
    @State private var draggedMenuBarGauge: MenuBarGauge?

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            tools
                .tabItem { Label("Tools", systemImage: "square.grid.2x2") }
            menuBar
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
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
