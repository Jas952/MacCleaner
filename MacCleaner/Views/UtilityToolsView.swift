import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct UtilityToolsView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selection: UtilityToolID = .welcome
    @StateObject private var maintenance = MaintenanceService.shared
    @StateObject private var keyboard = KeyboardDiagnosticService()
    @StateObject private var speaker = SpeakerTestService()
    @StateObject private var storage = StorageHealthService()
    @StateObject private var disk = DiskIntegrityService()
    @StateObject private var advancedSSD = AdvancedSSDService()
    @StateObject private var thermal = ThermalPowerService()
    @StateObject private var network = NetworkDiagnosticService()

    private var visibleTools: [UtilityToolID] {
        [.welcome] + UtilityToolID.availableCases.filter(settings.isEnabled)
    }

    var body: some View {
        HStack(spacing: 0) {
            toolsSidebar
                .frame(width: 238)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.surfaceLight)
        .onChange(of: settings.enabledToolIDs) { _ in
            if !settings.isEnabled(selection) { selection = .welcome }
        }
        .onChange(of: selection) { stopInactiveDiagnostics(active: $0) }
        .onDisappear { stopInactiveDiagnostics(active: .welcome) }
    }

    private var toolsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOOLS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Color.textTertiaryLight)
                Text("Your utility belt")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ToolsSidebarRow(tool: .welcome, isSelected: selection == .welcome) {
                        selection = .welcome
                    }

                    ForEach(UtilityToolCategory.allCases) { category in
                        let tools = visibleTools.filter { $0 != .welcome && $0.category == category }
                        if !tools.isEmpty {
                            Text(category.rawValue.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.45)
                                .foregroundStyle(Color.textTertiaryLight)
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 2)

                            ForEach(tools) { tool in
                                ToolsSidebarRow(tool: tool, isSelected: selection == tool) {
                                    selection = tool
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }

            Rectangle().fill(Color.borderLight).frame(height: 1)
            AppSettingsLink {
                Label("Customize Tools", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
        .background(Color.surfaceCardLight)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .welcome:
            ToolsWelcomeView(toolCount: visibleTools.count - 1)
        case .shelf: ShelfToolView()
        case .colorPicker: ColorPickerToolView()
        case .fileReader: FileReaderToolView()
        case .mediaCompressor: ToolsWelcomeView(toolCount: visibleTools.count - 1)
        case .homebrew: HomebrewToolView()
        case .audioMixer, .chargeLimit: ToolsWelcomeView(toolCount: visibleTools.count - 1)
        case .physical:
            PhysicalMaintenanceToolView(service: maintenance, compact: true)
        case .keyboard:
            ToolPage(.keyboard) { KeyboardDiagnosticSection(service: keyboard); PointerInputTestPanel() }
        case .speaker:
            ToolPage(.speaker, compact: true) {
                SpeakerTestPanel(service: speaker)
                ToolPanel("Listening checklist", subtitle: "Use the same quiet listening position for every channel and sweep.") {
                    HStack(alignment: .top, spacing: 18) {
                        diagnosticHint("1", "Route", "Confirm macOS is using the speakers you intend to test.")
                        diagnosticHint("2", "Balance", "Compare left and right at the same system volume.")
                        diagnosticHint("3", "Quality", "Listen for crackle, buzz or a missing frequency range.")
                    }
                }
            }
        case .storage:
            ToolPage(.storage) {
                DeviceHealthPanel(storageService: storage, diskService: disk, advancedSSDService: advancedSSD, thermalService: thermal)
            }
        case .network:
            ToolPage(.network) { NetworkTestPanel(service: network) }
        }
    }

    private func diagnosticHint(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number).font(.caption.bold()).foregroundStyle(.white).frame(width: 24, height: 24).background(Color.accentBlue, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(Color.textSecondaryLight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stopInactiveDiagnostics(active: UtilityToolID) {
        if active != .keyboard { keyboard.stop() }
        if active != .speaker { speaker.stop() }
        if active != .storage {
            storage.cancel(); disk.cancel(); advancedSSD.cancel(); thermal.cancel()
        }
        if active != .network { network.cancel() }
    }
}

private struct ToolsSidebarRow: View {
    let tool: UtilityToolID
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: tool.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentBlue : Color.textSecondaryLight)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.textPrimaryLight : Color.textSecondaryLight)
                        .lineLimit(1)

                    if tool != .welcome {
                        Text(tool.subtitle)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Color.textTertiaryLight)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, tool == .welcome ? 8 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentBlue.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentBlue.opacity(0.16) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ToolsWelcomeView: View {
    let toolCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            ToolOrbitIllustration(animated: !reduceMotion)
                .frame(width: 390, height: 280)
            VStack(spacing: 8) {
                Text("Small tools. One calm workspace.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimaryLight)
                Text("Keep only what earns a place in your workflow. MacCleaner runs these utilities locally and surfaces quick actions only when you choose them.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondaryLight)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
            HStack(spacing: 12) {
                Label("\(toolCount) enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentGreen)
                AppSettingsLink {
                    Label("Choose Tools", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(AppPrimaryButtonStyle())
            }
            Spacer(minLength: 24)
        }
        .padding(32)
    }
}

private struct ToolOrbitIllustration: View {
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1 / 30 : 60)) { timeline in
            let phase = animated ? timeline.date.timeIntervalSinceReferenceDate * 0.18 : 0
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for radius in [68.0, 112.0] {
                        let rect = CGRect(x: center.x - radius, y: center.y - radius * 0.58, width: radius * 2, height: radius * 1.16)
                        context.stroke(Path(ellipseIn: rect), with: .color(Color.accentBlue.opacity(0.16)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.surfaceCardLight)
                        .frame(width: 110, height: 110)
                        .shadow(color: Color.accentBlue.opacity(0.22), radius: 24)
                        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.borderLight, lineWidth: 1))
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color.accentBlue.gradient)
                }
                ForEach(Array(["tray.and.arrow.down", "eyedropper", "keyboard", "mug", "speaker.wave.3", "network"].enumerated()), id: \.offset) { index, icon in
                    let angle = phase + Double(index) * (.pi * 2 / 6)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(index.isMultiple(of: 2) ? Color.accentBlue : Color.accentPurple)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.borderLight, lineWidth: 1))
                        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
                        .offset(x: cos(angle) * 142, y: sin(angle) * 82)
                }
            }
        }
    }
}

struct ToolScroll<Content: View>: View {
    @ViewBuilder let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
            .foregroundStyle(Color.textPrimaryLight)
            .background(Color.surfaceLight)
    }
}

private struct ToolPage<Content: View>: View {
    let tool: UtilityToolID
    let compact: Bool
    @ViewBuilder let content: Content
    init(_ tool: UtilityToolID, compact: Bool = false, @ViewBuilder content: () -> Content) {
        self.tool = tool
        self.compact = compact
        self.content = content()
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 12 : 18) {
                    HStack(spacing: 10) {
                        Image(systemName: tool.icon).font(compact ? .headline : .title2).foregroundStyle(Color.accentBlue).frame(width: compact ? 36 : 42, height: compact ? 36 : 42).background(Color.accentBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: compact ? 10 : 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.title).font(.system(size: compact ? 18 : 20, weight: .semibold)).foregroundStyle(Color.textPrimaryLight)
                            Text(tool.subtitle).font(.system(size: 12)).foregroundStyle(Color.textSecondaryLight)
                        }
                    }
                    content
                }
                .padding(compact ? 18 : 26)
                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 1), alignment: .topLeading)
            }
        }
        .foregroundStyle(Color.textPrimaryLight)
        .background(Color.surfaceLight)
    }
}

private struct ToolStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondaryLight)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
    }
}

private struct ToolPanelHeaderAction {
    let title: String
    let systemImage: String
    let action: () -> Void
}

private struct ToolPanelHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ToolPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    let minHeight: CGFloat?
    let headerActions: [ToolPanelHeaderAction]
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        minHeight: CGFloat? = nil,
        headerActions: [ToolPanelHeaderAction] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.minHeight = minHeight
        self.headerActions = headerActions
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title).font(.headline)
                    ForEach(Array(headerActions.enumerated()), id: \.offset) { _, action in
                        SubtleToolIconButton(
                            title: action.title,
                            systemImage: action.systemImage,
                            compact: true,
                            action: action.action
                        )
                    }
                }
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Color.textSecondaryLight)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.borderLight, lineWidth: 1))
    }
}

private struct SubtleToolIconButton: View {
    let title: String
    let systemImage: String
    var compact = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 11 : 13, weight: .medium))
                .frame(width: compact ? 26 : 32, height: compact ? 22 : 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? Color.primary : Color.textSecondaryLight)
        .background(Color.primary.opacity(isHovered ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct MutedSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color.textSecondaryLight.opacity(0.46) : Color.primary.opacity(0.10))
                Circle()
                    .fill(Color.surfaceCardLight)
                    .shadow(color: Color.black.opacity(0.12), radius: 1, y: 0.5)
                    .padding(2)
            }
            .frame(width: 36, height: 20)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ShelfToolView: View {
    @ObservedObject private var store = ShelfStore.shared
    @ObservedObject private var preferences = ShelfWindowPreferences.shared
    @ObservedObject private var clipboard = ClipboardHistoryService.shared
    @State private var topCardHeight: CGFloat = 0
    var body: some View {
        ToolPage(.shelf) {
            HStack(alignment: .top, spacing: 12) {
                ToolPanel(
                    "Floating Shelf",
                    subtitle: "A small drop target that can stay above every workspace.",
                    minHeight: topCardHeight > 0 ? topCardHeight : nil,
                    headerActions: shelfHeaderActions
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Label(preferences.isPinned ? "Pinned above other windows" : "Use normal window level", systemImage: preferences.isPinned ? "pin.fill" : "pin.slash")
                            Spacer(minLength: 12)
                            Toggle("Pinned above other windows", isOn: $preferences.isPinned)
                                .labelsHidden()
                                .toggleStyle(MutedSwitchStyle())
                        }
                        Divider()
                        settingsShortcutRow("Open from anywhere", shortcut: "⌥S")
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ToolPanelHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )

                ToolPanel(
                    "Clipboard History",
                    subtitle: "Session-only history for text, images and files.",
                    minHeight: topCardHeight > 0 ? topCardHeight : nil,
                    headerActions: [
                        ToolPanelHeaderAction(
                            title: "Show Clipboard History",
                            systemImage: "clock.arrow.circlepath",
                            action: { ClipboardHistoryPanelController.shared.show() }
                        )
                    ]
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsShortcutRow("Show history", shortcut: "⌥C")
                        settingsShortcutRow("Reuse the first four items", shortcut: "⌘1–4")
                        Text("The shortcut follows the physical C key in English and Russian layouts.")
                            .font(.caption).foregroundStyle(Color.textSecondaryLight)
                        Text("\(clipboard.items.count) captured")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ToolPanelHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
            }
            .onPreferenceChange(ToolPanelHeightPreferenceKey.self) { measuredHeight in
                guard measuredHeight > 0, abs(measuredHeight - topCardHeight) > 0.5 else { return }
                topCardHeight = measuredHeight
            }

            ToolPanel("Shelf settings", subtitle: "Configure the floating shelf without turning this page into another drop target.") {
                VStack(alignment: .leading, spacing: 10) {
                    settingsShortcutRow("Open floating shelf", shortcut: "⌥S")
                    settingsShortcutRow("Paste into destination", shortcut: "⌘V")
                    Text("Drop files into the floating Shelf window. Files remain session-only and the original stays unchanged.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondaryLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var shelfHeaderActions: [ToolPanelHeaderAction] {
        var actions = [
            ToolPanelHeaderAction(
                title: "Open Shelf",
                systemImage: "tray.full",
                action: { ShelfPanelController.shared.show() }
            )
        ]
        if !store.items.isEmpty {
            actions.append(
                ToolPanelHeaderAction(
                    title: "Clear \(store.items.count) shelf items",
                    systemImage: "trash",
                    action: store.clear
                )
            )
        }
        return actions
    }

    private func settingsShortcutRow(_ title: String, shortcut: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.textSecondaryLight)
            Spacer()
            Text(shortcut).font(.system(.body, design: .monospaced).weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.surfaceLight, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct FloatingShelfView: View {
    @ObservedObject private var store = ShelfStore.shared
    @ObservedObject private var preferences = ShelfWindowPreferences.shared
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Drop Shelf", systemImage: "tray.and.arrow.down.fill").font(.headline)
                Spacer()
                Button { preferences.isPinned.toggle() } label: {
                    Image(systemName: preferences.isPinned ? "pin.fill" : "pin.slash")
                }
                .buttonStyle(.borderless)
                .help(preferences.isPinned ? "Pinned above other windows" : "Pin above other windows")
                if !store.items.isEmpty {
                    Button(action: store.clear) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Clear Shelf")
                        .accessibilityLabel("Clear Shelf")
                }
            }
            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 34)).foregroundStyle(Color.textSecondaryLight)
                    Text("Drop here").fontWeight(.medium).foregroundStyle(Color.textPrimaryLight)
                    Text("Files, links and text").font(.caption).foregroundStyle(Color.textSecondaryLight)
                    HStack(spacing: 6) {
                        shelfHint(icon: "arrow.down", text: "Drop in")
                        shelfHint(icon: "arrow.up", text: "Drag out")
                        shelfHint(icon: "checkmark.shield", text: "Safe copy")
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.items) { item in
                            HStack {
                                Image(systemName: item.storage == .sessionCopy ? "doc" : "doc.on.clipboard")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).foregroundStyle(Color.textPrimaryLight).lineLimit(1)
                                    Text(item.subtitle).font(.caption).foregroundStyle(Color.textSecondaryLight)
                                }
                                Spacer()
                                Button { store.copyForPaste(item) } label: {
                                    Image(systemName: "doc.on.clipboard")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(Color.accentBlue)
                                .help("Copy file for Cmd+V")
                                .accessibilityLabel("Copy file for paste")
                                Button { store.remove(item) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Color.textSecondaryLight)
                            }
                            .padding(10).background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.borderLight, lineWidth: 1))
                            .onDrag { store.dragProvider(for: item) }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 330, minHeight: 260)
        .foregroundStyle(Color.textPrimaryLight)
        .background(Color.surfaceLight)
        .background(ShelfWindowConfigurator(isPinned: preferences.isPinned))
        .onDrop(of: [UTType.fileURL.identifier, UTType.url.identifier, UTType.text.identifier, UTType.image.identifier], isTargeted: nil, perform: store.accept)
    }

    private func shelfHint(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.textSecondaryLight)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.surfaceCardLight.opacity(0.78), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.borderLight))
    }
}

private struct ShelfWindowConfigurator: NSViewRepresentable {
    let isPinned: Bool

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = isPinned ? .floating : .normal
            window.collectionBehavior = isPinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        }
    }
}

private struct FileReaderToolView: View {
    @State private var selectedURL: URL?
    @State private var previewText = ""
    @State private var previewImage: NSImage?
    @State private var previewPDF: PDFDocument?
    @State private var errorMessage: String?

    var body: some View {
        ToolPage(.fileReader) {
            ToolPanel("Read a local file", subtitle: "Choose any file. PDFs and images get a native preview; text and unknown formats remain local and readable as text or hex.") {
                HStack(spacing: 10) {
                    Button("Choose File", action: chooseFile)
                        .buttonStyle(AppPrimaryButtonStyle())
                    if let selectedURL {
                        Label(selectedURL.path, systemImage: "doc.text.magnifyingglass")
                            .font(.mono(10))
                            .foregroundStyle(Color.textSecondaryLight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.accentRed)
                }

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 520)
                        .background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 10))
                } else if let previewPDF {
                    ScrollView {
                        Text(previewPDF.string ?? "This PDF contains no extractable text.")
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(minHeight: 260, maxHeight: 520)
                    .background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 10))
                } else if !previewText.isEmpty {
                    ScrollView {
                        Text(previewText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(14)
                    }
                    .frame(minHeight: 260, maxHeight: 520)
                    .background(Color.surfaceCardLight, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc").font(.system(size: 34)).foregroundStyle(Color.textTertiaryLight)
                        Text("No file selected").font(.headline)
                        Text("The reader never uploads or modifies the selected file.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.item]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            load(url)
        }
    }

    private func load(_ url: URL) {
        selectedURL = url
        previewText = ""
        previewImage = nil
        previewPDF = nil
        errorMessage = nil

        if let image = NSImage(contentsOf: url) {
            previewImage = image
            return
        }
        if let pdf = PDFDocument(url: url) {
            previewPDF = pdf
            return
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            if let text = String(data: data, encoding: .utf8) {
                previewText = text.isEmpty ? "(empty file)" : text
            } else {
                previewText = data.prefix(4096).map { String(format: "%02x", $0) }.joined(separator: " ")
                if data.count > 4096 { previewText += "\n…\n\(data.count - 4096) more bytes" }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ColorPickerToolView: View {
    @ObservedObject private var service = ColorPickerService.shared
    var body: some View {
        ToolPage(.colorPicker) {
            HStack(spacing: 18) {
                ToolPanel("Selected color", subtitle: "Sampled from the screen and converted to sRGB.", minHeight: 350) {
                    VStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(service.color.map(Color.init) ?? Color.secondary.opacity(0.10))
                            .frame(height: 220)
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.borderLight, lineWidth: 1))
                            .overlay {
                                if service.color == nil {
                                    Label("No color sampled", systemImage: "eyedropper")
                                        .foregroundStyle(Color.textSecondaryLight)
                                }
                            }
                        HStack {
                            Button("Pick Color", action: service.sample).buttonStyle(AppPrimaryButtonStyle())
                            Button("Copy HEX", action: service.copyHex).disabled(service.color == nil)
                        }
                    }
                }

                ToolPanel("Color values", subtitle: "Ready for design tools, CSS and native UI work.", minHeight: 350) {
                    VStack(spacing: 0) {
                        colorValueRow("HEX", service.hex, icon: "number", copyValue: service.hex)
                        Divider()
                        colorValueRow("RGB", service.rgbDescription.replacingOccurrences(of: "RGB ", with: ""), icon: "circle.grid.cross")
                        Divider()
                        colorValueRow("HSB", service.hsbDescription.replacingOccurrences(of: "HSB ", with: ""), icon: "dial.high")
                        Divider()
                        colorValueRow("Color space", "sRGB", icon: "square.3.layers.3d")
                    }
                }
            }

            ToolPanel("Recent samples", subtitle: "The eight latest colors are kept only for the current MacCleaner session.") {
                if service.history.isEmpty {
                    Text("Pick a color to start a temporary local history.")
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .center)
                } else {
                    HStack(spacing: 10) {
                        ForEach(service.history) { sample in
                            Button { service.copy(sample.hex) } label: {
                                VStack(spacing: 7) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(sample.color))
                                        .frame(width: 62, height: 46)
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight, lineWidth: 1))
                                    Text(sample.hex)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Copy \(sample.hex)")
                        }
                    }
                }
            }

            Label("Wide-gamut source colors can differ slightly after conversion to sRGB.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Color.textSecondaryLight)
        }
    }

    private func colorValueRow(_ label: String, _ value: String, icon: String, copyValue: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.accentBlue).frame(width: 20)
            Text(label).foregroundStyle(Color.textSecondaryLight)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced)).fontWeight(.semibold)
            if let copyValue {
                SubtleToolIconButton(title: "Copy \(label)", systemImage: "doc.on.doc", compact: true) {
                    service.copy(copyValue)
                }
            }
        }
        .padding(.vertical, 14)
    }
}

private struct MediaCompressorToolView: View {
    @StateObject private var service = MediaCompressorService()
    @State private var quality = 0.72
    @State private var removeMetadata = true
    var body: some View {
        ToolPage(.mediaCompressor) {
            if !service.results.isEmpty {
                HStack(spacing: 12) {
                    ToolStatCard(title: "Processed", value: "\(service.results.count)", icon: "photo.stack", color: .accentBlue)
                    ToolStatCard(title: "Smaller files", value: "\(savedCount)", icon: "arrow.down.circle", color: .accentGreen)
                    ToolStatCard(title: "Space saved", value: ByteCountFormatter.string(fromByteCount: totalSaved, countStyle: .file), icon: "externaldrive.badge.checkmark", color: .accentPurple)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                ToolPanel("Compression settings", subtitle: "Quality applies to JPEG and HEIC. PNG and GIF remain lossless.") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Lossy quality")
                            Slider(value: $quality, in: 0.2...0.95)
                            Text("\(Int(quality * 100))%")
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                        Toggle("Remove metadata when possible", isOn: $removeMetadata)
                        Button(service.isWorking ? "Compressing…" : "Choose Images…") {
                            service.quality = quality
                            service.removeMetadata = removeMetadata
                            service.chooseAndCompress()
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(service.isWorking)
                    }
                }

                ToolPanel("Safe output policy", subtitle: "MacCleaner only creates a file when it is actually smaller.") {
                    VStack(alignment: .leading, spacing: 12) {
                        policyRow("Original is never overwritten", icon: "lock.shield.fill", color: .accentGreen)
                        policyRow("Larger candidates are discarded", icon: "arrow.up.circle.fill", color: .accentAmber)
                        policyRow("Outputs use a unique -compressed name", icon: "doc.badge.plus", color: .accentBlue)
                        policyRow("Animated GIF frames are retained", icon: "film.stack", color: .accentPurple)
                    }
                }
            }

            ToolPanel("Results", subtitle: "Each row states whether a smaller file was created or the original was kept.") {
                if service.results.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.arrow.down").font(.system(size: 34)).foregroundStyle(Color.textTertiaryLight)
                        Text("Choose one or more JPEG, PNG, HEIC or GIF images.")
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    VStack(spacing: 8) {
                        ForEach(service.results) { result in
                            HStack(spacing: 12) {
                                Image(systemName: result.output == nil ? "equal.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundStyle(result.output == nil ? Color.accentAmber : Color.accentGreen)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.source.lastPathComponent).fontWeight(.medium).lineLimit(1)
                                    Text(result.output?.lastPathComponent ?? "Original kept — candidate was not smaller")
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondaryLight)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("\(ByteCountFormatter.string(fromByteCount: result.originalBytes, countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: result.candidateBytes, countStyle: .file))")
                                        .font(.system(.caption, design: .monospaced))
                                    Text(result.output == nil ? "No larger copy saved" : "Saved \(Int(result.savingsPercent * 100))%")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(result.output == nil ? Color.accentAmber : Color.accentGreen)
                                }
                            }
                            .padding(12)
                            .background(Color.surfaceLight, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            if let error = service.errorMessage { Text(error).font(.caption).foregroundStyle(Color.accentRed) }
        }
    }

    private var savedCount: Int { service.results.filter { $0.output != nil }.count }
    private var totalSaved: Int64 { service.results.reduce(0) { $0 + $1.savedBytes } }

    private func policyRow(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title).font(.callout)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
    }
}

private struct HomebrewToolView: View {
    @StateObject private var service = HomebrewService()
    @State private var confirmingUpgrade = false
    @State private var confirmingCleanup = false
    var body: some View {
        ToolPage(.homebrew) {
            ToolPanel("Homebrew status", subtitle: "MacCleaner uses the existing user-owned brew executable and never installs it silently.", minHeight: 154) {
                if let executable = service.executable {
                    Label(executable.path, systemImage: "checkmark.seal.fill").foregroundStyle(Color.accentGreen)
                    Text("Audit lists formulae and casks with newer versions. Select only packages you want to upgrade; Cleanup Dry Run previews old downloads before any removal.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondaryLight)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Audit Outdated", action: service.audit)
                            .buttonStyle(AppPrimaryButtonStyle())
                            .help("Find installed formulae and casks with newer versions")
                        Button("Cleanup Dry Run", action: service.cleanupDryRun)
                            .buttonStyle(AppSecondaryButtonStyle())
                            .help("Preview removable Homebrew downloads and old versions")
                        Button("Run Cleanup") { confirmingCleanup = true }
                            .buttonStyle(AppSecondaryButtonStyle())
                            .disabled(service.isWorking)
                            .help("Remove only what Homebrew reports as safe cleanup")
                    }
                    .disabled(service.isWorking)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "mug.fill").font(.system(size: 28)).foregroundStyle(Color.textTertiaryLight)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Homebrew was not found").font(.headline)
                            Text("Standard Apple silicon and Intel locations were checked. Install Homebrew independently, then return here to audit packages.")
                                .foregroundStyle(Color.textSecondaryLight)
                        }
                    }
                }
            }

            if service.executable != nil {
                if !service.packages.isEmpty {
                    ToolPanel("Outdated packages", subtitle: "Only checked packages are passed to an explicit upgrade command.") {
                        VStack(spacing: 0) {
                            ForEach(service.packages) { package in
                                Toggle(isOn: Binding(get: { service.selectedNames.contains(package.id) }, set: { _ in service.toggle(package) })) {
                                    HStack { Text(package.name).fontWeight(.medium); Text(package.kind).font(.caption).foregroundStyle(Color.textSecondaryLight); Spacer(); Text(package.currentVersion).font(.caption.monospaced()).foregroundStyle(Color.textSecondaryLight) }
                                }.toggleStyle(.checkbox).padding(.vertical, 5)
                                Divider()
                            }
                        }.padding(5)
                        Button("Upgrade Selected (\(service.selectedNames.count))") { confirmingUpgrade = true }
                            .buttonStyle(AppPrimaryButtonStyle()).disabled(service.selectedNames.isEmpty || service.isWorking)
                    }
                }
                ToolPanel("Command output", subtitle: "Audit, dry-run and confirmed maintenance output stays visible for review.", minHeight: 250) {
                    ScrollView {
                        Text(service.output.isEmpty ? "Run an audit or cleanup dry run to see the exact Homebrew output here." : service.output)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(service.output.isEmpty ? Color.textSecondaryLight : Color.textPrimaryLight)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 180)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            ToolPanel("Maintenance policy") {
                HStack(alignment: .top, spacing: 18) {
                    policyNote("checkmark.square.fill", "Selected only", "Upgrades never include unchecked top-level packages.")
                    policyNote("doc.text.magnifyingglass", "Dry run first", "Cleanup can be inspected before anything changes.")
                    policyNote("hand.raised.fill", "No background work", "Every package change requires a visible action and confirmation.")
                }
            }
        }
        .confirmationDialog("Upgrade selected Homebrew packages?", isPresented: $confirmingUpgrade) {
            Button("Upgrade Selected") { service.upgradeSelected() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Homebrew may update dependencies of the selected packages. Output and exit status remain visible here.") }
        .confirmationDialog("Run Homebrew cleanup?", isPresented: $confirmingCleanup) {
            Button("Run Cleanup") { service.cleanup() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Review Cleanup Dry Run first. This removes old Homebrew downloads and package versions.") }
    }

    private func policyNote(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 26, height: 26, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(Color.textSecondaryLight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AudioMixerToolView: View {
    @StateObject private var service = AudioCapabilityReportService()

    var body: some View {
        ToolPage(.audioMixer) {
            HStack(spacing: 12) {
                ToolStatCard(
                    title: "Process tap API",
                    value: service.processTapAPISupported ? "Available" : "Unavailable",
                    icon: "waveform",
                    color: service.processTapAPISupported ? .accentGreen : .accentAmber
                )
                ToolStatCard(
                    title: "Output devices",
                    value: service.isLoading ? "…" : "\(service.devices.count)",
                    icon: "hifispeaker.2",
                    color: .accentBlue
                )
                ToolStatCard(
                    title: "Virtual routes",
                    value: service.isLoading ? "…" : "\(service.virtualOutputCount)",
                    icon: "point.3.connected.trianglepath.dotted",
                    color: .accentPurple
                )
            }

            ToolPanel("Compatibility verdict", subtitle: "This is a real route report, not a non-functional volume mixer.") {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentBlue)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(service.processTapAPISupported ? "This macOS version supports Core Audio process taps." : "This macOS version does not support Core Audio process taps.")
                            .font(.headline)
                        Text("Per-app gain and mute remain unavailable in MacCleaner because a safe tap graph, permission lifecycle and output-route restoration have not been implemented. The tool reports the current routes without changing them.")
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                    Spacer()
                    Button(service.isLoading ? "Reading…" : "Refresh Report", action: service.refresh)
                        .disabled(service.isLoading)
                    Button("Sound Settings") { openSystemSettings("com.apple.Sound-Settings.extension") }
                }
            }

            ToolPanel("Current output route") {
                if let output = service.defaultOutput {
                    HStack(spacing: 14) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentGreen)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(output.name).font(.title3.weight(.semibold))
                            Text("\(output.manufacturer) · \(output.outputChannels) channels · \(output.sampleRate / 1000) kHz · \(output.transport)")
                                .foregroundStyle(Color.textSecondaryLight)
                        }
                    }
                    .padding(.vertical, 8)
                } else if service.isLoading {
                    ProgressView("Reading Core Audio routes…")
                        .frame(maxWidth: .infinity, minHeight: 70)
                } else {
                    Text("No default output route was reported.")
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(maxWidth: .infinity, minHeight: 70)
                }
            }

            ToolPanel("Detected output devices") {
                VStack(spacing: 0) {
                    ForEach(service.devices) { device in
                        HStack(spacing: 10) {
                            Image(systemName: device.isDefaultOutput ? "checkmark.circle.fill" : "speaker")
                                .foregroundStyle(device.isDefaultOutput ? Color.accentGreen : Color.textTertiaryLight)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).fontWeight(device.isDefaultOutput ? .semibold : .regular)
                                Text("\(device.manufacturer) · \(device.transport)")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondaryLight)
                            }
                            Spacer()
                            Text("\(device.outputChannels) ch · \(device.sampleRate / 1000) kHz")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.textSecondaryLight)
                        }
                        .padding(.vertical, 9)
                        if device.id != service.devices.last?.id { Divider() }
                    }
                }
            }

            if let error = service.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.accentRed)
            }
        }
        .onAppear { if service.devices.isEmpty { service.refresh() } }
    }
}

private struct ChargeLimitToolView: View {
    @ObservedObject var monitor: SystemMonitor

    private var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private var supportsSystemChargeLimit: Bool {
        isAppleSilicon && ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        )
    }

    private var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
    }

    var body: some View {
        ToolPage(.chargeLimit) {
            HStack(spacing: 12) {
                ToolStatCard(title: "Current charge", value: monitor.battery.chargePercent > 0 ? "\(monitor.battery.chargePercent)%" : "N/A", icon: "battery.75percent", color: .accentGreen)
                ToolStatCard(title: "Battery health", value: monitor.battery.healthPercent > 0 ? "\(Int(monitor.battery.healthPercent))%" : "N/A", icon: "heart.text.square", color: .accentBlue)
                ToolStatCard(title: "System control", value: supportsSystemChargeLimit ? "Available" : "Unavailable", icon: "gearshape.2", color: supportsSystemChargeLimit ? .accentGreen : .accentAmber)
            }

            ToolPanel("Capability report", subtitle: "MacCleaner checks the platform before offering any charge-limit action.") {
                VStack(spacing: 0) {
                    capabilityRow("Apple silicon", value: isAppleSilicon ? "Yes" : "No", passed: isAppleSilicon)
                    Divider()
                    capabilityRow("macOS 26.4 or newer", value: osVersion, passed: ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)))
                    Divider()
                    capabilityRow("Public third-party control API", value: "Not available", passed: false)
                }
            }

            ToolPanel(supportsSystemChargeLimit ? "Managed safely by macOS" : "Charge Limit is not available on this system") {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: supportsSystemChargeLimit ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(supportsSystemChargeLimit ? Color.accentGreen : Color.accentAmber)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(supportsSystemChargeLimit
                             ? "Use Battery Settings to choose the supported 80–100% limit."
                             : "This Mac or macOS version does not expose Apple's supported charge-limit setting.")
                            .font(.headline)
                        Text("MacCleaner never writes private SMC keys. Battery Settings remains available for Optimized Battery Charging and other system-managed options.")
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                    Spacer()
                    Button("Open Battery Settings") { openSystemSettings("com.apple.Battery-Settings.extension") }
                        .buttonStyle(AppPrimaryButtonStyle())
                }
            }
        }
    }

    private func capabilityRow(_ title: String, value: String, passed: Bool) -> some View {
        HStack {
            Image(systemName: passed ? "checkmark.circle.fill" : "minus.circle.fill")
                .foregroundStyle(passed ? Color.accentGreen : Color.accentAmber)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Color.textSecondaryLight)
        }
        .padding(.vertical, 12)
    }
}

private struct CapabilityCard: View {
    let title: String; let icon: String; let detail: String
    var body: some View { GroupBox { HStack(alignment: .top, spacing: 14) { Image(systemName: icon).font(.title).foregroundStyle(Color.accentBlue); VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline).foregroundStyle(Color.textPrimaryLight); Text(detail).foregroundStyle(Color.textSecondaryLight) } }.padding(10) } }
}

private func openSystemSettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
}

struct AppSettingsLink<Label: View>: View {
    private let label: Label

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { label }
        } else {
            Button(action: openLegacySettings) { label }
        }
    }

    private func openLegacySettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PhysicalMaintenanceToolView: View {
    @ObservedObject var service: MaintenanceService
    let compact: Bool
    init(service: MaintenanceService, compact: Bool = false) {
        self.service = service
        self.compact = compact
    }
    var body: some View {
        ToolPage(.physical, compact: compact) {
            CapabilityCard(title: "Cleaning mode", icon: "sparkles", detail: "Use the established Screen Blackout, Keyboard Lock and combined maintenance controls below. Cmd-Q remains protected while a maintenance session is active.")
            ScreenDimCard(svc: service, cardHeight: 160)
            KeyboardLockCard(svc: service, cardHeight: 160)
            BothCard(svc: service, cardHeight: 180)
        }
    }
}
