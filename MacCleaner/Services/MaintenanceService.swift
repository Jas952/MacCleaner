import AppKit
import Carbon
import Combine
import SwiftUI

private let maintenanceSystemDefinedEventRawValue: Int64 = 14
private let maintenanceCmdQKeyCode: Int64 = 12
private let maintenanceCmdQHotKeySignature = OSType(0x4D435151) // MCQQ
private let maintenanceCmdQHotKeyID = UInt32(1)

// MARK: - Timer duration options

enum MaintenanceDuration: Int, CaseIterable, Identifiable {
    case one    = 60
    case five   = 300
    case fifteen = 900
    case thirty  = 1800
    case manual  = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .one:     return "1 min"
        case .five:    return "5 min"
        case .fifteen: return "15 min"
        case .thirty:  return "30 min"
        case .manual:  return "Manual"
        }
    }

    var menuLabel: String { label }
}

// MARK: - Dim opacity

enum DimOpacity: Double, CaseIterable, Identifiable {
    case full    = 1.0
    case partial = 0.9
    case manual  = -1.0   // sentinel: user adjusts slider

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .full:    return "100%"
        case .partial: return "90%"
        case .manual:  return "Manual"
        }
    }

    var menuLabel: String { label }

    var effectiveOpacity: Double {
        switch self {
        case .full:    return 1.0
        case .partial: return 0.9
        case .manual:  return 1.0
        }
    }
}

// MARK: - MaintenanceService

@MainActor
final class MaintenanceService: ObservableObject {

    static let shared = MaintenanceService()

    // Screen dim state
    @Published var isScreenDimmed = false
    @Published var dimOpacity: DimOpacity = .full
    @Published var screenDimCountdown = 3       // countdown before activation
    @Published var screenDimCountdownActive = false
    @Published var screenDimTimeRemaining: Int = 0
    @Published var screenDimDuration: MaintenanceDuration = .five

    // Keyboard lock state
    @Published var isKeyboardLocked = false
    @Published var keyboardLockTimeRemaining: Int = 0
    @Published var keyboardLockDuration: MaintenanceDuration = .five

    // Both state
    @Published var isBothActive = false
    @Published var bothCountdown = 3
    @Published var bothCountdownActive = false
    @Published var bothTimeRemaining: Int = 0
    @Published var bothDuration: MaintenanceDuration = .five

    // ── private ───────────────────────────────────────────────────
    private var dimWindow: NSWindow?
    private var retiredDimWindows: [NSWindow] = []
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var shortcutEventTap: CFMachPort?
    private var shortcutEventTapRunLoopSource: CFRunLoopSource?
    private var cmdQHotKeyRef: EventHotKeyRef?
    private var cmdQHotKeyHandlerRef: EventHandlerRef?
    private var cmdQHotKeyRegisterStatus: OSStatus?
    private var dimTimer: Timer?
    private var keyboardTimer: Timer?
    private var bothTimer: Timer?
    private var countdownTimer: Timer?
    private var bothCDTimer: Timer?
    private var cmdQGlobalMonitor: Any?
    private var cmdQLocalMonitor: Any?
    private var quitSuppressionUntil: Date?

    private init() {}

    // MARK: Screen dim

    func startScreenDimCountdown() {
        installCmdQMonitor()
        screenDimCountdown = 3
        screenDimCountdownActive = true
        countdownTimer?.invalidate()
        countdownTimer = Self.scheduledCommonTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.screenDimCountdown > 1 {
                    self.screenDimCountdown -= 1
                } else {
                    t.invalidate()
                    self.screenDimCountdownActive = false
                    self.activateScreenDim()
                }
            }
        }
    }

    func activateScreenDim() {
        guard !isScreenDimmed else { return }
        installCmdQMonitor()
        showDimOverlay(opacity: dimOpacity.effectiveOpacity)
        isScreenDimmed = true
        screenDimTimeRemaining = screenDimDuration.rawValue
        dimTimer?.invalidate()
        guard screenDimDuration != .manual else { return }
        dimTimer = Self.scheduledCommonTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self, self.isScreenDimmed else { t.invalidate(); return }
                if self.screenDimTimeRemaining > 0 {
                    self.screenDimTimeRemaining -= 1
                } else {
                    t.invalidate()
                    self.deactivateScreenDim()
                }
            }
        }
    }

    func deactivateScreenDim() {
        dimTimer?.invalidate()
        dimTimer = nil
        countdownTimer?.invalidate()
        screenDimCountdownActive = false
        hideDimOverlay()
        isScreenDimmed = false
        screenDimTimeRemaining = 0
        removeCmdQMonitorIfIdle()
    }

    // MARK: Keyboard lock

    func activateKeyboardLock() {
        guard !isKeyboardLocked else { return }
        installEventTap()
        installCmdQMonitor()
        isKeyboardLocked = true
        keyboardLockTimeRemaining = keyboardLockDuration.rawValue
        keyboardTimer?.invalidate()
        guard keyboardLockDuration != .manual else { return }
        keyboardTimer = Self.scheduledCommonTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self, self.isKeyboardLocked else { t.invalidate(); return }
                if self.keyboardLockTimeRemaining > 0 {
                    self.keyboardLockTimeRemaining -= 1
                } else {
                    t.invalidate()
                    self.deactivateKeyboardLock()
                }
            }
        }
    }

    func deactivateKeyboardLock() {
        keyboardTimer?.invalidate()
        keyboardTimer = nil
        removeEventTap()
        isKeyboardLocked = false
        keyboardLockTimeRemaining = 0
        removeCmdQMonitorIfIdle()
    }

    // MARK: Both

    func startBothCountdown() {
        installCmdQMonitor()
        bothCountdown = 3
        bothCountdownActive = true
        bothCDTimer?.invalidate()
        bothCDTimer = Self.scheduledCommonTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.bothCountdown > 1 {
                    self.bothCountdown -= 1
                } else {
                    t.invalidate()
                    self.bothCountdownActive = false
                    self.activateBoth()
                }
            }
        }
    }

    func activateBoth() {
        guard !isBothActive else { return }
        installCmdQMonitor()
        showDimOverlay(opacity: dimOpacity.effectiveOpacity)
        installEventTap()
        isBothActive = true
        bothTimeRemaining = bothDuration.rawValue
        bothTimer?.invalidate()
        guard bothDuration != .manual else { return }
        bothTimer = Self.scheduledCommonTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self, self.isBothActive else { t.invalidate(); return }
                if self.bothTimeRemaining > 0 {
                    self.bothTimeRemaining -= 1
                } else {
                    t.invalidate()
                    self.deactivateBoth()
                }
            }
        }
    }

    func deactivateBoth() {
        bothTimer?.invalidate()
        bothTimer = nil
        bothCDTimer?.invalidate()
        bothCountdownActive = false
        hideDimOverlay()
        removeEventTap()
        isBothActive = false
        bothTimeRemaining = 0
        removeCmdQMonitorIfIdle()
    }

    // MARK: - Overlay window

    /// Returns the built-in MacBook display. Falls back to main, then first screen.
    private var builtInScreen: NSScreen {
        // Built-in screen has no localizedName containing "display" in its
        // deviceDescription — the reliable key is NSDeviceDescriptionKey("NSScreenNumber").
        // Simpler heuristic: built-in screen is always listed first in NSScreen.screens
        // when it exists, OR we can detect it via QuartzCore displayID.
        // Most reliable cross-OS way: look for "Built-in" in localizedName.
        if let builtin = NSScreen.screens.first(where: {
            $0.localizedName.localizedCaseInsensitiveContains("built-in") ||
            $0.localizedName.localizedCaseInsensitiveContains("retina") ||
            $0.localizedName.localizedCaseInsensitiveContains("liquid")
        }) { return builtin }
        // Fallback: first screen in the list is usually the built-in on MacBooks
        return NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func showDimOverlay(opacity: Double) {
        hideDimOverlay()
        let screen = builtInScreen
        let win = MaintenanceDimWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.level = .screenSaver
        win.backgroundColor = NSColor.black.withAlphaComponent(opacity)
        win.isOpaque = false
        win.animationBehavior = .none
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let label = NSTextField(labelWithString: "=)")
        label.font = NSFont.systemFont(ofSize: 28, weight: .light)
        label.textColor = NSColor.white.withAlphaComponent(0.7)
        label.isBezeled = false
        label.isEditable = false
        label.backgroundColor = .clear
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: screen.frame.width / 2 - label.frame.width / 2,
            y: screen.frame.height / 2 - label.frame.height / 2
        )

        let view = MaintenanceDimOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onExitShortcut = { [weak self] in
            _ = self?.exitAllIfNeeded()
        }
        view.addSubview(label)
        win.contentView = view
        dimWindow = win
        focusDimOverlay(window: win, responder: view)
    }

    private func focusDimOverlay(window: NSWindow, responder: NSResponder) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(responder)

        for delay in [0.05, 0.20, 0.60] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window, weak responder] in
                guard let self,
                      let window,
                      let responder,
                      self.dimWindow === window
                else { return }
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(responder)
            }
        }
    }

    private func hideDimOverlay() {
        guard let window = dimWindow else { return }
        dimWindow = nil
        window.animationBehavior = .none
        window.orderOut(nil)
        window.contentView = nil

        retiredDimWindows.append(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak window] in
            guard let self, let window else { return }
            self.retiredDimWindows.removeAll { $0 === window }
        }
    }

    private final class MaintenanceDimWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private final class MaintenanceDimOverlayView: NSView {
        var onExitShortcut: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if Self.isExitShortcut(event) {
                onExitShortcut?()
                return
            }
            super.keyDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard Self.isExitShortcut(event) else {
                return super.performKeyEquivalent(with: event)
            }
            onExitShortcut?()
            return true
        }

        override func cancelOperation(_ sender: Any?) {
            onExitShortcut?()
        }

        override func mouseDown(with event: NSEvent) {
            onExitShortcut?()
        }

        override func rightMouseDown(with event: NSEvent) {
            onExitShortcut?()
        }

        override func otherMouseDown(with event: NSEvent) {
            onExitShortcut?()
        }

        private static func isExitShortcut(_ event: NSEvent) -> Bool {
            if event.keyCode == 53 { return true }
            return event.modifierFlags.contains(.command) && Int64(event.keyCode) == maintenanceCmdQKeyCode
        }
    }

    // MARK: - CGEventTap (keyboard intercept)
    // Blocks keyboard, modifier and media-key events. Cmd+Q (keyCode 12)
    // exits maintenance mode instead of reaching the front app as Quit.

    private func installEventTap() {
        guard eventTap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << maintenanceSystemDefinedEventRawValue)

        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            if type == .keyDown || type == .keyUp || type == .flagsChanged || type.rawValue == maintenanceSystemDefinedEventRawValue {
                let flags = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let isCmd = flags.contains(.maskCommand)
                if isCmd && keyCode == 12 {
                    if type == .keyDown {
                        DispatchQueue.main.async {
                            Task { @MainActor in
                                _ = MaintenanceService.shared.exitAllIfNeeded()
                            }
                        }
                    }
                    return nil
                }
            }
            // Block everything else
            return nil
        }

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        )

        if let tap {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            eventTap = tap
            eventTapRunLoopSource = src
        }
    }

    private func removeEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            eventTapRunLoopSource = nil
        }
        eventTap = nil
    }

    // MARK: - Cmd+Q event tap
    // NSEvent global monitors cannot cancel the original key event. This tap
    // suppresses Cmd+Q before AppKit/Xcode can turn it into a Quit command.

    private func installShortcutEventTap() {
        guard shortcutEventTap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            guard type == .keyDown || type == .keyUp else {
                return Unmanaged.passUnretained(event)
            }

            let flags = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard flags.contains(.maskCommand), keyCode == maintenanceCmdQKeyCode else {
                return Unmanaged.passUnretained(event)
            }

            if type == .keyDown {
                DispatchQueue.main.async {
                    Task { @MainActor in
                        _ = MaintenanceService.shared.exitAllIfNeeded()
                    }
                }
            }
            return nil
        }

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        )

        guard let tap else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        shortcutEventTap = tap
        shortcutEventTapRunLoopSource = src
    }

    private func removeShortcutEventTap() {
        guard let tap = shortcutEventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = shortcutEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            shortcutEventTapRunLoopSource = nil
        }
        shortcutEventTap = nil
    }

    // MARK: - Carbon hotkey fallback
    // RegisterEventHotKey does not require Accessibility permission and works
    // even when the blackout overlay is not the key window.

    private func installCmdQHotKey() {
        guard cmdQHotKeyRef == nil else { return }

        if cmdQHotKeyHandlerRef == nil {
            var eventSpec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let userData = Unmanaged.passUnretained(self).toOpaque()
            var handlerRef: EventHandlerRef?
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let event, let userData else { return noErr }

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
                    guard status == noErr,
                          hotKeyID.signature == maintenanceCmdQHotKeySignature,
                          hotKeyID.id == maintenanceCmdQHotKeyID
                    else { return noErr }

                    let service = Unmanaged<MaintenanceService>.fromOpaque(userData).takeUnretainedValue()
                    Task { @MainActor in
                        _ = service.exitAllIfNeeded()
                    }
                    return noErr
                },
                1,
                &eventSpec,
                userData,
                &handlerRef
            )
            if status == noErr {
                cmdQHotKeyHandlerRef = handlerRef
            }
        }

        let hotKeyID = EventHotKeyID(
            signature: maintenanceCmdQHotKeySignature,
            id: maintenanceCmdQHotKeyID
        )
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        cmdQHotKeyRegisterStatus = status
        if status == noErr {
            cmdQHotKeyRef = hotKeyRef
        }
    }

    private func removeCmdQHotKey() {
        if let hotKeyRef = cmdQHotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            cmdQHotKeyRef = nil
        }
        cmdQHotKeyRegisterStatus = nil
        if let handlerRef = cmdQHotKeyHandlerRef {
            RemoveEventHandler(handlerRef)
            cmdQHotKeyHandlerRef = nil
        }
    }

    // MARK: - Cmd+Q monitors
    // Ensures Cmd+Q exits maintenance instead of quitting MacCleaner.

    private func installCmdQMonitor() {
        installCmdQHotKey()
        installShortcutEventTap()
        guard cmdQGlobalMonitor == nil, cmdQLocalMonitor == nil else { return }
        cmdQGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isCmdQ(event) else { return }
            DispatchQueue.main.async { _ = self?.exitAllIfNeeded() }
        }
        cmdQLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isCmdQ(event) else { return event }
            if self?.exitAllIfNeeded() == true {
                return nil
            }
            return event
        }
    }

    private func removeCmdQMonitor() {
        if let monitor = cmdQGlobalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = cmdQLocalMonitor { NSEvent.removeMonitor(monitor) }
        cmdQGlobalMonitor = nil
        cmdQLocalMonitor = nil
        removeShortcutEventTap()
        removeCmdQHotKey()
    }

    private func removeCmdQMonitorIfIdle() {
        guard !isScreenDimmed,
              !screenDimCountdownActive,
              !isKeyboardLocked,
              !isBothActive,
              !bothCountdownActive
        else { return }
        removeCmdQMonitor()
    }

    private static func isCmdQ(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && Int64(event.keyCode) == maintenanceCmdQKeyCode
    }

    // MARK: - Exit all

    var hasActiveMaintenanceMode: Bool {
        isScreenDimmed ||
        screenDimCountdownActive ||
        isKeyboardLocked ||
        isBothActive ||
        bothCountdownActive
    }

    #if DEBUG
    var debugCmdQHotKeyState: String {
        let status = cmdQHotKeyRegisterStatus.map(String.init) ?? "nil"
        return "registered=\(cmdQHotKeyRef != nil) status=\(status)"
    }
    #endif

    @discardableResult
    func exitAllIfNeeded() -> Bool {
        guard hasActiveMaintenanceMode else { return false }
        suppressQuitAfterMaintenanceShortcut()
        exitAll()
        return true
    }

    func consumeQuitSuppressionAfterMaintenanceShortcut() -> Bool {
        guard let quitSuppressionUntil else { return false }
        if Date() <= quitSuppressionUntil {
            self.quitSuppressionUntil = nil
            return true
        }
        self.quitSuppressionUntil = nil
        return false
    }

    func exitAll() {
        deactivateScreenDim()
        deactivateKeyboardLock()
        deactivateBoth()
    }

    private func suppressQuitAfterMaintenanceShortcut() {
        quitSuppressionUntil = Date().addingTimeInterval(2)
    }

    // MARK: - Helpers

    private static func scheduledCommonTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        block: @escaping @Sendable (Timer) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
