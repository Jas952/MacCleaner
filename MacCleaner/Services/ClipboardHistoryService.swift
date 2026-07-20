import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct PasteboardPayload: Equatable {
    struct Representation: Equatable {
        let typeIdentifier: String
        let data: Data
    }

    struct Entry: Equatable {
        let representations: [Representation]
    }

    let entries: [Entry]

    @MainActor
    init(pasteboard: NSPasteboard) {
        entries = (pasteboard.pasteboardItems ?? []).compactMap { item in
            let representations = item.types.compactMap { type -> Representation? in
                guard let data = item.data(forType: type) else { return nil }
                return Representation(typeIdentifier: type.rawValue, data: data)
            }
            return representations.isEmpty ? nil : Entry(representations: representations)
        }
    }

    init(entries: [Entry]) {
        self.entries = entries
    }

    var signature: Int {
        var hasher = Hasher()
        for entry in entries {
            for representation in entry.representations {
                hasher.combine(representation.typeIdentifier)
                hasher.combine(representation.data)
            }
        }
        return hasher.finalize()
    }

    @MainActor
    @discardableResult
    func write(to pasteboard: NSPasteboard) -> Bool {
        let items = entries.compactMap { entry -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            var wroteRepresentation = false
            for representation in entry.representations {
                let type = NSPasteboard.PasteboardType(representation.typeIdentifier)
                wroteRepresentation = item.setData(representation.data, forType: type) || wroteRepresentation
            }
            return wroteRepresentation ? item : nil
        }
        guard !items.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }

    @MainActor
    func makeItemProviders() -> [NSItemProvider] {
        entries.map { entry in
            let provider = NSItemProvider()
            for representation in entry.representations {
                let data = representation.data
                provider.registerDataRepresentation(
                    forTypeIdentifier: representation.typeIdentifier,
                    visibility: .all
                ) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            return provider
        }
    }
}

@MainActor
final class ShelfWindowPreferences: ObservableObject {
    static let shared = ShelfWindowPreferences()

    @Published var isPinned: Bool {
        didSet { UserDefaults.standard.set(isPinned, forKey: "floatingShelfPinned") }
    }

    private init() {
        if UserDefaults.standard.object(forKey: "floatingShelfPinned") == nil {
            isPinned = true
        } else {
            isPinned = UserDefaults.standard.bool(forKey: "floatingShelfPinned")
        }
    }
}

@MainActor
final class ClipboardHistoryService: ObservableObject {
    private static let maximumItemCount = 12

    enum Kind: String {
        case text = "Text"
        case image = "Image"
        case files = "Files"

        var icon: String {
            switch self {
            case .text: return "text.alignleft"
            case .image: return "photo"
            case .files: return "doc.on.doc"
            }
        }
    }

    struct Item: Identifiable {
        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String
        let text: String?
        let image: NSImage?
        let fileURLs: [URL]
        let payload: PasteboardPayload
        let createdAt = Date()

        var signature: String {
            "\(kind.rawValue):\(payload.signature)"
        }
    }

    static let shared = ClipboardHistoryService()

    @Published private(set) var items: [Item] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureIfChanged() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        captureCurrentPasteboard()
    }

    func captureIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        captureCurrentPasteboard()
    }

    func captureCurrentPasteboard() {
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        let payload = PasteboardPayload(pasteboard: pasteboard)
        guard !payload.entries.isEmpty else { return }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let title = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
            insert(Item(kind: .files, title: title, detail: urls.map(\.lastPathComponent).joined(separator: ", "), text: nil, image: nil, fileURLs: urls, payload: payload))
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            let size = "\(Int(image.size.width)) × \(Int(image.size.height))"
            insert(Item(kind: .image, title: "Image", detail: size, text: nil, image: image, fileURLs: [], payload: payload))
            return
        }

        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            insert(Item(kind: .text, title: String(oneLine.prefix(80)), detail: "\(text.count) characters", text: text, image: nil, fileURLs: [], payload: payload))
        }
    }

    func restore(_ item: Item) {
        let pasteboard = NSPasteboard.general
        if !item.payload.write(to: pasteboard) {
            pasteboard.clearContents()
            switch item.kind {
            case .text:
                if let text = item.text { pasteboard.setString(text, forType: .string) }
            case .image:
                if let image = item.image { pasteboard.writeObjects([image]) }
            case .files:
                pasteboard.writeObjects(item.fileURLs as [NSURL])
            }
        }
        lastChangeCount = pasteboard.changeCount
    }

    /// Restores an item and sends Cmd-V to the application that was active
    /// before Clipboard History opened. This makes Enter a complete
    /// copy-and-paste action rather than requiring a second manual paste.
    func restoreAndPaste(_ item: Item, into application: NSRunningApplication?) {
        restore(item)
        application?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard CGPreflightPostEventAccess() else {
                _ = CGRequestPostEventAccess()
                return
            }
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    func clear() { items.removeAll() }

    private func insert(_ item: Item) {
        items.removeAll { $0.signature == item.signature }
        items.insert(item, at: 0)
        if items.count > Self.maximumItemCount {
            items.removeLast(items.count - Self.maximumItemCount)
        }
    }
}

@MainActor
private enum UtilityPanelPresenter {
    static func show(_ panel: NSPanel) {
        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
            for window in NSApp.windows where window !== panel {
                window.orderOut(nil)
            }
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }
}

@MainActor
final class ShelfPanelController {
    static let shared = ShelfPanelController()

    private var panel: NSPanel?

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.level = ShelfWindowPreferences.shared.isPinned ? .floating : .normal

        if !panel.isVisible, let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(
                x: visible.maxX - panel.frame.width - 24,
                y: visible.maxY - panel.frame.height - 54
            ))
        }
        UtilityPanelPresenter.show(panel)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Drop Shelf"
        panel.level = ShelfWindowPreferences.shared.isPinned ? .floating : .normal
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 330, height: 260)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: FloatingShelfView())
        return panel
    }
}

@MainActor
final class ClipboardHistoryPanelController {
    static let shared = ClipboardHistoryPanelController()

    private var panel: ClipboardHistoryPanel?
    private var targetApplication: NSRunningApplication?
    private let selectionModel = ClipboardHistorySelectionModel()
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func show() {
        targetApplication = NSWorkspace.shared.frontmostApplication
        ClipboardHistoryService.shared.captureCurrentPasteboard()
        selectionModel.reset(to: ClipboardHistoryService.shared.items)
        let panel = panel ?? makePanel()
        self.panel = panel

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let origin = CGPoint(x: visible.midX - panel.frame.width / 2, y: visible.maxY - panel.frame.height - 86)
            panel.setFrameOrigin(origin)
        }
        UtilityPanelPresenter.show(panel)
        installOutsideClickMonitors()
    }

    func hide() {
        panel?.orderOut(nil)
        removeOutsideClickMonitors()
    }

    private func makePanel() -> ClipboardHistoryPanel {
        let panel = ClipboardHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.shortcutHandler = { [weak self] index in
            let items = ClipboardHistoryService.shared.items
            guard items.indices.contains(index) else { return }
            ClipboardHistoryService.shared.restoreAndPaste(items[index], into: self?.targetApplication)
            self?.hide()
        }
        panel.navigationHandler = { [weak self] command in
            guard let self else { return }
            let service = ClipboardHistoryService.shared
            switch command {
            case .moveUp:
                self.selectionModel.move(by: -1, through: service.items)
            case .moveDown:
                self.selectionModel.move(by: 1, through: service.items)
            case .activate:
                guard let item = self.selectionModel.selectedItem(in: service.items) else { return }
                service.restoreAndPaste(item, into: self.targetApplication)
                self.hide()
            }
        }
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true

        let hostingView = NSHostingView(
            rootView: ClipboardHistoryView(selectionModel: selectionModel) { [weak self] item in
                ClipboardHistoryService.shared.restore(item)
                self?.hide()
            }
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        panel.contentView = effectView
        return panel
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.hideIfOutside()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hideIfOutside() }
        }
    }

    private func hideIfOutside() {
        guard let panel, panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        hide()
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }
}

private enum ClipboardHistoryKeyboardCommand {
    case moveUp
    case moveDown
    case activate
}

private final class ClipboardHistoryPanel: NSPanel {
    var shortcutHandler: ((Int) -> Void)?
    var navigationHandler: ((ClipboardHistoryKeyboardCommand) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           let character = event.charactersIgnoringModifiers?.first,
           let number = Int(String(character)),
           (1...4).contains(number) {
            shortcutHandler?(number - 1)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            ClipboardHistoryPanelController.shared.hide()
            return
        }
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            navigationHandler?(.moveUp)
            return
        case kVK_DownArrow:
            navigationHandler?(.moveDown)
            return
        case kVK_Return, kVK_ANSI_KeypadEnter:
            navigationHandler?(.activate)
            return
        default:
            break
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class GlobalUtilityHotKeyController {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var openShelf: () -> Void
    private var openClipboard: () -> Void

    init(openShelf: @escaping () -> Void, openClipboard: @escaping () -> Void) {
        self.openShelf = openShelf
        self.openClipboard = openClipboard
        install()
    }

    func update(openShelf: @escaping () -> Void, openClipboard: @escaping () -> Void) {
        self.openShelf = openShelf
        self.openClipboard = openClipboard
    }

    private func install() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<GlobalUtilityHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                Task { @MainActor in
                    if hotKeyID.id == 1 { owner.openShelf() }
                    if hotKeyID.id == 2 { owner.openClipboard() }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        register(id: 1, keyCode: UInt32(kVK_ANSI_S))
        register(id: 2, keyCode: UInt32(kVK_ANSI_C))
    }

    private func register(id: UInt32, keyCode: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D_43_4C_4E), id: id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &reference)
        if status == noErr {
            hotKeyRefs.append(reference)
        } else {
            NSLog("MacCleaner utility hotkey %u registration failed: %d", id, status)
        }
    }

    deinit {
        hotKeyRefs.compactMap { $0 }.forEach { _ = UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

@MainActor
private final class ClipboardHistorySelectionModel: ObservableObject {
    @Published var selectedID: ClipboardHistoryService.Item.ID?

    func reset(to items: [ClipboardHistoryService.Item]) {
        selectedID = items.first?.id
    }

    func move(by offset: Int, through items: [ClipboardHistoryService.Item]) {
        guard !items.isEmpty else {
            selectedID = nil
            return
        }
        let currentIndex = selectedID.flatMap { selectedID in
            items.firstIndex { $0.id == selectedID }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        selectedID = items[nextIndex].id
    }

    func selectedItem(in items: [ClipboardHistoryService.Item]) -> ClipboardHistoryService.Item? {
        items.first { $0.id == selectedID } ?? items.first
    }
}

private struct ClipboardHistoryView: View {
    @ObservedObject private var service = ClipboardHistoryService.shared
    @ObservedObject var selectionModel: ClipboardHistorySelectionModel
    let onSelect: (ClipboardHistoryService.Item) -> Void

    private var selectedItem: ClipboardHistoryService.Item? {
        selectionModel.selectedItem(in: service.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "doc.on.clipboard.fill").foregroundStyle(Color.accentBlue)
                Text("Clipboard History").font(.headline)
                Spacer()
                Text("⌥C").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider()

            if service.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clipboard").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text("Clipboard history is empty").fontWeight(.medium)
                    Text("Copy text, an image or files in any app.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 3) {
                                ForEach(Array(service.items.enumerated()), id: \.element.id) { index, item in
                                    Button { selectionModel.selectedID = item.id } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: item.kind.icon).foregroundStyle(Color.accentBlue).frame(width: 18)
                                            Text(item.title).lineLimit(1).foregroundStyle(.primary)
                                            Spacer(minLength: 4)
                                            if index < 4 { Text("⌘\(index + 1)").font(.caption.monospaced()).foregroundStyle(.tertiary) }
                                        }
                                        .padding(.horizontal, 9)
                                        .frame(height: 42)
                                        .background(selectionModel.selectedID == item.id ? Color.accentBlue.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                    }
                                    .id(item.id)
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture(count: 2).onEnded { onSelect(item) })
                                }
                            }
                            .padding(8)
                        }
                        .onChange(of: selectionModel.selectedID) { selectedID in
                            guard let selectedID else { return }
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo(selectedID, anchor: .center)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Clear History", role: .destructive) { service.clear() }
                    }
                    .frame(width: 230)
                    .background(Color.primary.opacity(0.035))

                    Divider()
                    preview
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(Color.primary)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }

    @ViewBuilder
    private var preview: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 0) {
                switch item.kind {
                case .text:
                    ScrollView { Text(item.text ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading) }
                        .padding(12)
                case .image:
                    if let image = item.image {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .files:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(item.fileURLs, id: \.self) { url in
                                Label(url.lastPathComponent, systemImage: "doc").lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                }
            }
        }
    }
}
