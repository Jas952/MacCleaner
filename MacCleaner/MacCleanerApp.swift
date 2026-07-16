import Darwin
import AppKit
import Combine
import CoreGraphics
import SwiftUI

@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sharedMonitor = SystemMonitor()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(monitor: sharedMonitor)
                .frame(
                    minWidth: 1300,
                    idealWidth: 1300,
                    maxWidth: 1300,
                    minHeight: 760,
                    idealHeight: 760,
                    maxHeight: 760,
                    alignment: .topLeading
                )
                .background {
                    StatusBarSceneBridge(monitor: sharedMonitor, appDelegate: appDelegate)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates()
                }
                .disabled(!UpdateService.shared.canCheckForUpdates)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit MacCleaner") {
                    let maintenance = MaintenanceService.shared
                    if maintenance.exitAllIfNeeded() ||
                        maintenance.consumeQuitSuppressionAfterMaintenanceShortcut() {
                        return
                    }
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView(monitor: sharedMonitor)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var utilityHotKeys: GlobalUtilityHotKeyController?

    @MainActor
    func configureStatusBar(
        monitor: SystemMonitor,
        openMain: @escaping () -> Void,
        openShelf: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        if let statusBarController {
            statusBarController.updateActions(openMain: openMain, openShelf: openShelf, openSettings: openSettings)
        } else {
            statusBarController = StatusBarController(
                monitor: monitor,
                openMain: openMain,
                openShelf: openShelf,
                openSettings: openSettings
            )
        }
        installUtilityRuntime()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.installUtilityRuntime()
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["MACCLEANER_MAINTENANCE_SELFTEST"] == "screenDimCmdQ" {
            Task { @MainActor in
                await MaintenanceRuntimeSelfTest.runScreenDimCmdQ()
            }
        }
        #endif
    }

    @MainActor
    private func installUtilityRuntime() {
        _ = ClipboardHistoryService.shared
        guard utilityHotKeys == nil else { return }
        utilityHotKeys = GlobalUtilityHotKeyController(
            openShelf: { ShelfPanelController.shared.show() },
            openClipboard: { ClipboardHistoryPanelController.shared.show() }
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Вместо закрытия прячем иконку из Dock
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let maintenance = MaintenanceService.shared
        if maintenance.exitAllIfNeeded() ||
            maintenance.consumeQuitSuppressionAfterMaintenanceShortcut() {
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        MaintenanceService.shared.exitAll()
    }
}

private struct StatusBarSceneBridge: View {
    @ObservedObject var monitor: SystemMonitor
    let appDelegate: AppDelegate

    @ViewBuilder
    var body: some View {
        if #available(macOS 14.0, *) {
            ModernStatusBarSceneBridge(monitor: monitor, appDelegate: appDelegate)
        } else {
            LegacyStatusBarSceneBridge(monitor: monitor, appDelegate: appDelegate)
        }
    }
}

@available(macOS 14.0, *)
private struct ModernStatusBarSceneBridge: View {
    @ObservedObject var monitor: SystemMonitor
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.configureStatusBar(
                    monitor: monitor,
                    openMain: {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    },
                    openShelf: {
                        ShelfPanelController.shared.show()
                    },
                    openSettings: {
                        openSettings()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            }
    }
}

private struct LegacyStatusBarSceneBridge: View {
    @ObservedObject var monitor: SystemMonitor
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.configureStatusBar(
                    monitor: monitor,
                    openMain: {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    },
                    openShelf: {
                        ShelfPanelController.shared.show()
                    },
                    openSettings: {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            }
    }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: SystemMonitor
    private let settings = SettingsManager.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var openMain: () -> Void
    private var openShelf: () -> Void
    private var openSettings: () -> Void

    init(
        monitor: SystemMonitor,
        openMain: @escaping () -> Void,
        openShelf: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.openMain = openMain
        self.openShelf = openShelf
        self.openSettings = openSettings
        super.init()
        configureStatusItem()
        configurePopover()
        observeUpdates()
        updateStatusItem()
    }

    deinit {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func updateActions(
        openMain: @escaping () -> Void,
        openShelf: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.openMain = openMain
        self.openShelf = openShelf
        self.openSettings = openSettings
        configurePopover()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = applicationStatusIcon()
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover(
                monitor: monitor,
                openMain: openMain,
                openShelf: openShelf,
                openSettings: openSettings
            )
            .frame(width: 420)
        )
    }

    func popoverWillShow(_ notification: Notification) {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func observeUpdates() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)

        monitor.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            configurePopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let title = NSMutableAttributedString()
        var accessibilityParts: [String] = []
        let gauges = settings.menuBarGaugeIDs.compactMap(MenuBarGauge.init(rawValue:))

        if gauges.isEmpty {
            button.image = applicationStatusIcon()
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }

        for (index, gauge) in gauges.enumerated() {
            let reading = reading(for: gauge)
            let format = settings.valueFormat(for: gauge)
            let displayStyle = settings.displayStyle(for: gauge)
            if index > 0 {
                title.append(NSAttributedString(
                    string: "   │   ",
                    attributes: [
                        .foregroundColor: NSColor.separatorColor,
                        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                        .baselineOffset: 1
                    ]
                ))
            }
            title.append(NSAttributedString(
                string: "\(gauge.shortTitle) ",
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .baselineOffset: 1
                ]
            ))

            switch displayStyle {
            case .battery:
                title.append(imageAttachment(
                    batteryIndicatorImage(progress: reading.progress, color: reading.color),
                    baselineOffset: -3
                ))
                if gauge == .temperature {
                    title.append(NSAttributedString(string: " "))
                    title.append(symbolAttachment(named: "thermometer.medium", accessibilityDescription: "Temperature"))
                }
                title.append(NSAttributedString(string: " "))
                appendFormatMarker(
                    gauge.formatMarker(for: format),
                    color: reading.color,
                    to: title
                )
            case .value:
                title.append(NSAttributedString(
                    string: reading.value,
                    attributes: [
                        .foregroundColor: reading.color,
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                        .baselineOffset: 1
                    ]
                ))
            }
            accessibilityParts.append("\(gauge.title) \(reading.value)")
        }

        button.attributedTitle = title
        button.setAccessibilityLabel(accessibilityParts.isEmpty ? "MacCleaner" : accessibilityParts.joined(separator: ", "))
        statusItem.length = max(26, button.intrinsicContentSize.width + 6)
    }

    private func reading(for gauge: MenuBarGauge) -> (value: String, progress: Double, color: NSColor) {
        let format = settings.valueFormat(for: gauge)
        switch gauge {
        case .cpu:
            let value = format == .cores ? "\(monitor.cpu.processorCount)C" : String(format: "%.0f%%", monitor.cpu.totalUsage * 100)
            return (value, monitor.cpu.totalUsage, loadColor(monitor.cpu.totalUsage))
        case .ram:
            let value = format == .percent
                ? String(format: "%.0f%%", monitor.memory.usedPercent * 100)
                : String(format: "%.1fG", Double(monitor.memory.used) / 1_073_741_824)
            return (value, monitor.memory.usedPercent, loadColor(monitor.memory.usedPercent))
        case .gpu:
            let temperature = monitor.thermal.gpuTemp
            let showsTemperature = format == .temperature
            let value = format == .temperature
                ? (temperature > 0 ? String(format: "%.0f°", temperature) : "—")
                : (monitor.gpuUsage > 0 ? String(format: "%.0f%%", monitor.gpuUsage * 100) : "—")
            let progress = showsTemperature ? temperatureProgress(temperature) : monitor.gpuUsage
            let color = showsTemperature
                ? temperatureColor(temperature)
                : (monitor.gpuUsage > 0 ? loadColor(monitor.gpuUsage) : .secondaryLabelColor)
            return (value, progress, color)
        case .temperature:
            let temperature = monitor.thermal.socTemp > 0 ? monitor.thermal.socTemp : monitor.thermal.cpuTemp
            let value = format == .fahrenheit
                ? (temperature > 0 ? String(format: "%.0fF", temperature * 9 / 5 + 32) : "—")
                : (temperature > 0 ? String(format: "%.0fC", temperature) : "—")
            return (value, temperatureProgress(temperature), temperatureColor(temperature))
        case .battery:
            let charge = monitor.battery.chargePercent
            let minutes = monitor.battery.timeRemaining
            let value = format == .time
                ? (minutes > 0 ? String(format: "%dh%02d", minutes / 60, minutes % 60) : "—")
                : (charge > 0 ? "\(charge)%" : "—")
            let progress = Double(charge) / 100
            return (value, progress, charge > 0 && charge < 20 ? .systemRed : .systemGreen)
        }
    }

    private func temperatureProgress(_ temperature: Double) -> Double {
        guard temperature > 0 else { return 0 }
        return min(max((temperature - 35) / 65, 0), 1)
    }

    private func temperatureColor(_ temperature: Double) -> NSColor {
        guard temperature > 0 else { return .secondaryLabelColor }
        if temperature > 85 { return .systemRed }
        if temperature > 70 { return .systemOrange }
        return .systemGreen
    }

    private func applicationStatusIcon() -> NSImage? {
        guard let image = NSApp.applicationIconImage?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        image.accessibilityDescription = "MacCleaner"
        return image
    }

    private func symbolAttachment(
        named name: String,
        accessibilityDescription: String
    ) -> NSAttributedString {
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(configuration)
        else { return NSAttributedString() }
        image.isTemplate = true
        return imageAttachment(image, baselineOffset: -1)
    }

    private func imageAttachment(_ image: NSImage, baselineOffset: CGFloat = 0) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(
            x: 0,
            y: baselineOffset,
            width: image.size.width,
            height: image.size.height
        )
        return NSAttributedString(attachment: attachment)
    }

    private func appendFormatMarker(
        _ marker: MenuBarGaugeFormatMarker,
        color: NSColor,
        to title: NSMutableAttributedString
    ) {
        switch marker {
        case .text(let value):
            title.append(NSAttributedString(
                string: value,
                attributes: [
                    .foregroundColor: color,
                    .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                    .baselineOffset: 1
                ]
            ))
        case .symbol(let name):
            title.append(symbolAttachment(
                named: name,
                accessibilityDescription: "Time remaining"
            ))
        }
    }

    private func batteryIndicatorImage(progress: Double, color: NSColor) -> NSImage {
        let clampedProgress = min(max(progress, 0), 1)
        let size = NSSize(width: 10, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let bodyRect = NSRect(x: 1.25, y: 0.5, width: 7.5, height: 13)
            let outline = NSBezierPath(roundedRect: bodyRect, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1
            NSColor.labelColor.withAlphaComponent(0.72).setStroke()
            outline.stroke()

            let terminal = NSBezierPath(roundedRect: NSRect(x: 3.25, y: 14, width: 3.5, height: 1.5), xRadius: 0.7, yRadius: 0.7)
            NSColor.labelColor.withAlphaComponent(0.72).setFill()
            terminal.fill()

            if clampedProgress > 0 {
                let fillHeight = max(1.5, 10 * clampedProgress)
                let fill = NSBezierPath(roundedRect: NSRect(x: 2.75, y: 2, width: 4.5, height: fillHeight), xRadius: 1, yRadius: 1)
                color.setFill()
                fill.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func loadColor(_ value: Double) -> NSColor {
        if value > 0.85 { return .systemRed }
        if value > 0.65 { return .systemOrange }
        return .systemGreen
    }
}

#if DEBUG
@MainActor
private enum MaintenanceRuntimeSelfTest {
    static func runScreenDimCmdQ() async {
        let cmdQKeyCode: UInt16 = 12
        let service = MaintenanceService.shared
        service.dimOpacity = .partial
        service.screenDimDuration = .one
        service.activateScreenDim()
        try? await Task.sleep(nanoseconds: 1_250_000_000)

        let started = service.isScreenDimmed && service.hasActiveMaintenanceMode
        let timerTicked = service.screenDimTimeRemaining < MaintenanceDuration.one.rawValue
        let keyWindow = NSApp.keyWindow
        let keyWindowClass = keyWindow.map { String(describing: type(of: $0)) } ?? "nil"
        let firstResponderClass = keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let posted = postCmdQ(keyCode: cmdQKeyCode)

        try? await Task.sleep(nanoseconds: 800_000_000)
        let stopped = !service.hasActiveMaintenanceMode && !service.isScreenDimmed
        let passed = started && timerTicked && posted && stopped
        let line = "MAINTENANCE_SELFTEST screenDimCmdQ started=\(started) timerTicked=\(timerTicked) keyWindow=\(keyWindowClass) firstResponder=\(firstResponderClass) hotKey={\(service.debugCmdQHotKeyState)} posted=\(posted) stopped=\(stopped) result=\(passed ? "PASS" : "FAIL")\n"
        NSLog("%@", line)
        if let data = line.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
        service.exitAll()
        Darwin._exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private static func postCmdQ(keyCode: UInt16) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
#endif

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings = SettingsManager.shared

    private var keyTemp: Double {
        monitor.thermal.socTemp > 0 ? monitor.thermal.socTemp : monitor.thermal.cpuTemp
    }

    private var currentRamStr: String {
        if settings.valueFormat(for: .ram) == .percent {
            return String(format: "%.0f%%", monitor.memory.usedPercent * 100)
        }

        return String(format: "%.1fG", Double(monitor.memory.used) / 1_073_741_824)
    }

    private var currentCPUValue: String {
        String(format: "%.0f%%", monitor.cpu.totalUsage * 100)
    }

    private var ramColor: Color {
        color(for: severity(forLoad: monitor.memory.usedPercent))
    }

    private var tempColor: Color {
        color(for: severity(forTemperature: keyTemp))
    }

    var body: some View {
        HStack(spacing: 7) {
            if settings.menuBarGaugeIDs.isEmpty {
                Image(systemName: "bolt.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            ForEach(Array(settings.menuBarGaugeIDs.enumerated()), id: \.element) { index, rawValue in
                if let gauge = MenuBarGauge(rawValue: rawValue) {
                    if index > 0 {
                        Divider()
                            .frame(height: 14)
                            .opacity(0.55)
                    }
                    gaugeView(gauge)
                }
            }
        }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .help(accessibilitySummary)
            .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func gaugeView(_ gauge: MenuBarGauge) -> some View {
        let data = gaugeData(gauge)
        HStack(alignment: .center, spacing: 2) {
            Text(gauge.shortTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            if settings.displayStyle(for: gauge) == .battery {
                MenuBarBatteryIndicator(progress: data.progress, color: data.color)
                if gauge == .temperature {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                MenuBarFormatMarker(marker: gauge.formatMarker(for: settings.valueFormat(for: gauge)))
            } else {
                Text(data.value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(data.color)
            }
        }
        .frame(height: 18, alignment: .center)
        .fixedSize()
        .help("\(gauge.title): \(data.value)")
    }

    private func gaugeData(_ gauge: MenuBarGauge) -> (value: String, progress: Double, color: Color, icon: String) {
        switch gauge {
        case .cpu:
            let value = settings.valueFormat(for: .cpu) == .cores ? "\(monitor.cpu.processorCount)C" : currentCPUValue
            return (value, monitor.cpu.totalUsage, color(for: severity(forLoad: monitor.cpu.totalUsage)), "cpu")
        case .ram:
            return (currentRamStr, monitor.memory.usedPercent, ramColor, "memorychip.fill")
        case .gpu:
            let showsTemperature = settings.valueFormat(for: .gpu) == .temperature
            let value = settings.valueFormat(for: .gpu) == .temperature
                ? (monitor.thermal.gpuTemp > 0 ? String(format: "%.0f°", monitor.thermal.gpuTemp) : "—")
                : (monitor.gpuUsage > 0 ? String(format: "%.0f%%", monitor.gpuUsage * 100) : "—")
            let progress = showsTemperature ? temperatureProgress(monitor.thermal.gpuTemp) : monitor.gpuUsage
            let gaugeColor = showsTemperature
                ? color(for: severity(forTemperature: monitor.thermal.gpuTemp))
                : color(for: severity(forLoad: monitor.gpuUsage))
            return (value, progress, gaugeColor, "rectangle.3.group")
        case .temperature:
            let value = settings.valueFormat(for: .temperature) == .fahrenheit
                ? (keyTemp > 0 ? String(format: "%.0fF", keyTemp * 9 / 5 + 32) : "—")
                : (keyTemp > 0 ? String(format: "%.0fC", keyTemp) : "—")
            return (value, temperatureProgress(keyTemp), tempColor, "thermometer.medium")
        case .battery:
            let value = Double(monitor.battery.chargePercent) / 100
            let display = settings.valueFormat(for: .battery) == .time ? batteryTime : "\(monitor.battery.chargePercent)%"
            return (display, value, value < 0.2 ? Color.accentRed : Color.accentGreen, "battery.75percent")
        }
    }

    private func temperatureProgress(_ temperature: Double) -> Double {
        guard temperature > 0 else { return 0 }
        return min(max((temperature - 35) / 65, 0), 1)
    }

    private var accessibilitySummary: String {
        let parts = settings.menuBarGaugeIDs.compactMap { rawValue -> String? in
            guard let gauge = MenuBarGauge(rawValue: rawValue) else { return nil }
            return "\(gauge.title) \(gaugeData(gauge).value)"
        }
        return parts.isEmpty ? "MacCleaner" : parts.joined(separator: ", ")
    }

    private func severity(forLoad value: Double) -> MenuBarMetricSeverity {
        if value > 0.85 { return .critical }
        if value > 0.65 { return .warning }
        return .normal
    }

    private func severity(forTemperature temperature: Double) -> MenuBarMetricSeverity {
        if temperature > 85 { return .critical }
        if temperature > 70 { return .warning }
        return .normal
    }

    private func color(for severity: MenuBarMetricSeverity) -> Color {
        switch severity {
        case .normal: return .accentGreen
        case .warning: return .accentAmber
        case .critical: return .accentRed
        }
    }

    private var batteryTime: String {
        let minutes = monitor.battery.timeRemaining
        guard minutes > 0 else { return "—" }
        return String(format: "%dh%02d", minutes / 60, minutes % 60)
    }

}

private enum MenuBarMetricSeverity: Int {
    case normal
    case warning
    case critical
}

struct MenuBarGaugeChip: View {
    let gauge: MenuBarGauge
    @ObservedObject var monitor: SystemMonitor
    let format: MenuBarGaugeValueFormat
    let displayStyle: MenuBarGaugeDisplayStyle

    private var keyTemperature: Double {
        monitor.thermal.socTemp > 0 ? monitor.thermal.socTemp : monitor.thermal.cpuTemp
    }

    private var reading: (value: String, progress: Double, color: Color) {
        switch gauge {
        case .cpu:
            let value = format == .cores ? "\(monitor.cpu.processorCount)C" : String(format: "%.0f%%", monitor.cpu.totalUsage * 100)
            return (value, monitor.cpu.totalUsage, loadColor(monitor.cpu.totalUsage))
        case .ram:
            let value = format == .percent
                ? String(format: "%.0f%%", monitor.memory.usedPercent * 100)
                : String(format: "%.1fG", Double(monitor.memory.used) / 1_073_741_824)
            return (value, monitor.memory.usedPercent, loadColor(monitor.memory.usedPercent))
        case .gpu:
            let value = format == .temperature
                ? (monitor.thermal.gpuTemp > 0 ? String(format: "%.0f°", monitor.thermal.gpuTemp) : "—")
                : (monitor.gpuUsage > 0 ? String(format: "%.0f%%", monitor.gpuUsage * 100) : "—")
            let progress = format == .temperature ? temperatureProgress(monitor.thermal.gpuTemp) : monitor.gpuUsage
            let color = format == .temperature ? temperatureColor(monitor.thermal.gpuTemp) : (monitor.gpuUsage > 0 ? loadColor(monitor.gpuUsage) : .secondary)
            return (value, progress, color)
        case .temperature:
            let color: Color = keyTemperature > 85 ? .accentRed : (keyTemperature > 70 ? .accentAmber : .accentGreen)
            let value = format == .fahrenheit
                ? (keyTemperature > 0 ? String(format: "%.0fF", keyTemperature * 9 / 5 + 32) : "—")
                : (keyTemperature > 0 ? String(format: "%.0fC", keyTemperature) : "—")
            return (value, temperatureProgress(keyTemperature), keyTemperature > 0 ? color : .secondary)
        case .battery:
            let charge = monitor.battery.chargePercent
            let minutes = monitor.battery.timeRemaining
            let value = format == .time
                ? (minutes > 0 ? String(format: "%dh%02d", minutes / 60, minutes % 60) : "—")
                : (charge > 0 ? "\(charge)%" : "—")
            return (value, Double(charge) / 100, charge > 0 && charge < 20 ? .accentRed : .accentGreen)
        }
    }

    var body: some View {
        let current = reading
        HStack(alignment: .center, spacing: 2) {
            Text(gauge.shortTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            if displayStyle == .battery {
                MenuBarBatteryIndicator(progress: current.progress, color: current.color)
                if gauge == .temperature {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9, weight: .semibold))
                }
                MenuBarFormatMarker(marker: gauge.formatMarker(for: format))
            } else {
                Text(current.value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(current.color)
            }
        }
        .frame(height: 18, alignment: .center)
        .fixedSize()
        .help("\(gauge.title): \(current.value)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gauge.title) \(current.value)")
    }

    private func loadColor(_ value: Double) -> Color {
        if value > 0.85 { return .accentRed }
        if value > 0.65 { return .accentAmber }
        return .accentGreen
    }

    private func temperatureProgress(_ temperature: Double) -> Double {
        guard temperature > 0 else { return 0 }
        return min(max((temperature - 35) / 65, 0), 1)
    }

    private func temperatureColor(_ temperature: Double) -> Color {
        guard temperature > 0 else { return .secondary }
        if temperature > 85 { return .accentRed }
        if temperature > 70 { return .accentAmber }
        return .accentGreen
    }
}

private struct MenuBarFormatMarker: View {
    let marker: MenuBarGaugeFormatMarker

    var body: some View {
        Group {
            switch marker {
            case .text(let value):
                Text(value)
            case .symbol(let name):
                Image(systemName: name)
            }
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .frame(minWidth: 7)
        .frame(height: 16, alignment: .center)
        .accessibilityHidden(true)
    }
}

private struct MenuBarBatteryIndicator: View {
    let progress: Double
    let color: Color

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        VStack(spacing: 1) {
            Capsule()
                .fill(.primary.opacity(0.72))
                .frame(width: 3.5, height: 1.5)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(.primary.opacity(0.72), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 4.5, height: max(clampedProgress > 0 ? 1.5 : 0, 10 * clampedProgress))
                    .padding(.bottom, 1.5)
            }
            .frame(width: 8, height: 13)
        }
        .frame(width: 10, height: 16)
    }
}

// MARK: - Menu Bar Popover

struct MenuBarPopover: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedTab: PopoverTab = .overview
    let openMain: () -> Void
    let openShelf: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            tabContent
                .frame(height: 378, alignment: .top)
        }
        .padding(12)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.16), value: selectedTab)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .details:
            detailsTab
        case .tools:
            toolsTab
        }
    }

    private var toolsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Tools").font(.headline)
                ForEach(UtilityToolID.configurableCases.filter { settings.isEnabled($0) && settings.isInMenuBar($0) }) { tool in
                    Button { runQuickTool(tool) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tool.icon).foregroundStyle(Color.accentBlue).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) { Text(tool.title).fontWeight(.medium); Text(tool.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                if settings.clipboardHistoryInMenuBar {
                    Button { ClipboardHistoryPanelController.shared.show() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.on.clipboard").foregroundStyle(Color.accentBlue).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Clipboard History").fontWeight(.medium)
                                Text("Reuse recent text, images and files · ⌥C").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                if settings.menuBarToolIDs.isEmpty && !settings.clipboardHistoryInMenuBar {
                    VStack(spacing: 8) {
                        Image(systemName: "menubar.rectangle").font(.title).foregroundStyle(.secondary)
                        Text("No Quick Tools").font(.headline)
                        Text("Choose tools in Settings.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).frame(height: 220)
                }
                Spacer(minLength: 4)
                HStack {
                    Button("Open MacCleaner") {
                        openMain()
                    }
                    Spacer()
                    Button("Settings…", action: openSettings)
                }
            }
        }
    }

    private func runQuickTool(_ tool: UtilityToolID) {
        switch tool {
        case .shelf: openShelf()
        case .colorPicker: ColorPickerService.shared.sample()
        default: openMain()
        }
    }

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 9) {
            PopoverHealthCard(
                score: healthScore,
                title: healthTitle,
                subtitle: healthSubtitle,
                color: healthColor
            )

            HStack(spacing: 8) {
                PopoverMetricTile(
                    icon: "cpu",
                    label: "CPU Load",
                    value: String(format: "%.0f%%", monitor.cpu.totalUsage * 100),
                    subtitle: "\(monitor.cpu.processorCount) cores",
                    color: loadColor(monitor.cpu.totalUsage),
                    progress: monitor.cpu.totalUsage,
                    history: monitor.cpuHistory
                )

                PopoverMetricTile(
                    icon: "memorychip",
                    label: "Memory",
                    value: String(format: "%.0f%%", monitor.memory.usedPercent * 100),
                    subtitle: "\(MemoryInfo.formatted(monitor.memory.used)) used",
                    color: loadColor(monitor.memory.usedPercent),
                    progress: monitor.memory.usedPercent,
                    history: monitor.ramHistory
                )
            }

            PopoverBatteryStatusCard(battery: monitor.battery)
        }
    }

    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if let disk = rootDisk {
                    PopoverInfoCard(
                        icon: "internaldrive",
                        label: "Storage",
                        value: DiskInfo.formatted(disk.free),
                        detail: "free on \(disk.volumeName)",
                        color: loadColor(disk.usedPercent),
                        progress: disk.usedPercent
                    )
                    .frame(width: 166)
                    .frame(maxHeight: .infinity)
                }

                PopoverNetworkView(monitor: monitor)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 120)

            PopoverTemperatureView(monitor: monitor)
                .frame(height: 86)

            PopoverTopProcessesView(monitor: monitor)
                .frame(height: 154)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentBlue.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MacCleaner Monitor")
                    .font(.system(size: 13, weight: .semibold))
.foregroundStyle(Color.primary)
                Text("Live device telemetry")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.72))
            }

            Spacer(minLength: 12)

            Picker("Section", selection: $selectedTab) {
                ForEach(PopoverTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 188)

            Spacer(minLength: 12)

            Text(healthTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(healthColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(healthColor.opacity(0.10)))
        }
        .padding(.bottom, 2)
    }

    private var rootDisk: DiskInfo? {
        monitor.disks.first(where: { $0.mountPoint == "/" }) ?? monitor.disks.first
    }

    private var keyTemp: Double {
        monitor.thermal.socTemp > 0 ? monitor.thermal.socTemp : monitor.thermal.cpuTemp
    }

    private var healthScore: Double {
        var score = 100.0
        score -= monitor.cpu.totalUsage * 18
        score -= monitor.memory.usedPercent * 22
        if keyTemp > 0 { score -= max(0, keyTemp - 55) * 0.72 }
        if let disk = rootDisk { score -= max(0, disk.usedPercent - 0.72) * 42 }
        if monitor.battery.healthPercent > 0 { score -= max(0, 90 - monitor.battery.healthPercent) * 0.45 }
        return max(0, min(100, score))
    }

    private var healthTitle: String {
        if healthScore > 78 { return "Healthy" }
        if healthScore > 58 { return "Watch" }
        return "Stressed"
    }

    private var healthSubtitle: String {
        if keyTemp > 78 { return "Thermals are the primary pressure point right now." }
        if monitor.memory.usedPercent > 0.82 { return "Memory pressure is elevated; keep an eye on active apps." }
        if monitor.cpu.totalUsage > 0.72 { return "CPU activity is high, but the device is still responsive." }
        return "System load, memory, and thermal signals look balanced."
    }

    private var healthColor: Color {
        if healthScore > 78 { return .accentGreen }
        if healthScore > 58 { return .accentAmber }
        return .accentRed
    }

    private func loadColor(_ value: Double) -> Color {
        if value > 0.85 { return .accentRed }
        if value > 0.66 { return .accentAmber }
        return .accentGreen
    }
}

private enum PopoverTab: String, CaseIterable, Identifiable {
    case overview
    case details
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .details: return "Details"
        case .tools: return "Tools"
        }
    }
}

struct PopoverHealthCard: View {
    let score: Double
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.14), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.04, min(score / 100.0, 1)))
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int(score))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
.foregroundStyle(Color.primary)
                    Text("score")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.72))
                }
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
.foregroundStyle(Color.primary)
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.75)
                )
        )
    }
}

struct PopoverMetricTile: View {
    let icon: String
    let label: String
    let value: String
    let subtitle: String
    let color: Color
    let progress: Double
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
.foregroundStyle(Color.primary)
                Spacer()
            }

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary.opacity(0.72))
                .lineLimit(1)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geometry.size.width * max(0, min(progress, 1))))
                }
            }
            .frame(height: 5)

            MiniSparkline(values: history, color: color)
                .frame(height: 34)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.75)
                )
        )
    }
}

struct PopoverInfoCard: View {
    let icon: String
    let label: String
    let value: String
    let detail: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
                Spacer()
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary.opacity(0.72))
                .lineLimit(1)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geometry.size.width * max(0, min(progress, 1))))
                }
            }
            .frame(height: 5)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.75)
                )
        )
    }
}

struct PopoverBatteryStatusCard: View {
    let battery: BatteryInfo

    private var chargeProgress: Double {
        Double(max(0, min(battery.chargePercent, 100))) / 100.0
    }

    private var batteryColor: Color {
        if battery.chargePercent <= 20 && !battery.isPluggedIn { return .accentRed }
        if battery.chargePercent <= 45 && !battery.isPluggedIn { return .accentAmber }
        return .accentGreen
    }

    private var statusText: String {
        if battery.isCharging { return "Charging" }
        if battery.isPluggedIn { return "Plugged in" }
        if battery.timeRemaining > 0 {
            let h = battery.timeRemaining / 60
            let m = battery.timeRemaining % 60
            return "\(h)h \(m)m left"
        }
        return "On battery"
    }

    private var healthText: String {
        battery.healthPercent > 0 ? "\(Int(battery.healthPercent))% \(battery.healthLabel)" : "Health N/A"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(batteryColor.opacity(0.14), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.04, chargeProgress))
                    .stroke(
                        batteryColor,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: battery.isPluggedIn ? "bolt.fill" : "battery.75")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(batteryColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                        Text(statusText)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary.opacity(0.72))
                    }

                    Spacer()

                    Text(battery.chargePercent > 0 ? "\(battery.chargePercent)%" : "N/A")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(nsColor: .separatorColor))
                        Capsule()
                            .fill(batteryColor)
                            .frame(width: max(4, geometry.size.width * chargeProgress))
                    }
                }
                .frame(height: 5)

                HStack(spacing: 6) {
                    batteryChip("Health", healthText, batteryColor)
                    batteryChip("Cycles", battery.cycleCount > 0 ? "\(battery.cycleCount)" : "N/A", Color.accentBlue)
                    batteryChip("Power", battery.wattage > 0 ? String(format: "%.1f W", battery.wattage) : "N/A", Color.accentAmber)
                    batteryChip("Temp", battery.temperature > 0 ? String(format: "%.0f°C", battery.temperature) : "N/A", Color.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private func batteryChip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.72))
            Text(value)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.58))
        )
    }
}

struct PopoverNetworkView: View {
    @ObservedObject var monitor: SystemMonitor

    private var networkColor: Color {
        monitor.network.isActive ? .accentBlue : .textTertiaryLight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Network", systemImage: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                Spacer()
                Text(monitor.network.interfaceName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(networkColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(networkColor.opacity(0.10)))
            }

            HStack(spacing: 8) {
                networkRate(icon: "arrow.down", title: "Down", value: NetworkInfo.formattedRate(monitor.network.downloadBytesPerSecond))
                networkRate(icon: "arrow.up", title: "Up", value: NetworkInfo.formattedRate(monitor.network.uploadBytesPerSecond))
            }

        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.75)
                )
        )
    }

    private func networkRate(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(networkColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.72))
                Text(value)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.58))
        )
    }
}

struct MiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let maxV = values.max() ?? 1.0
            let minV = values.min() ?? 0.0
            let range = max(maxV - minV, 0.1)
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
                let y = size.height * (1 - CGFloat((v - minV) / range))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            
            // Fill with gradient underneath
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            let gradient = Gradient(colors: [color.opacity(0.35), color.opacity(0.0)])
            ctx.fill(fillPath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            
            // Stroke the main line
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct PopoverTopProcessesView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Top Activity", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                Spacer()
                Text("CPU & RAM")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.72))
            }

            if monitor.topProcesses.isEmpty {
                Text("Collecting foreground process activity")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(monitor.topProcesses.prefix(3)) { proc in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(processColor(proc.cpuUsage))
                                .frame(width: 6, height: 6)

                            Text(proc.name)
                                .font(.system(size: 11, weight: .medium))
.foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Text(String(format: "%.1f%%", proc.cpuUsage))
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(processColor(proc.cpuUsage))
                                .frame(width: 45, alignment: .trailing)

                            Text(MemoryInfo.formatted(proc.memoryBytes))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(Color.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.58))
                        )
                    }
                }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.75)
                )
        )
    }

    private func processColor(_ cpu: Double) -> Color {
        if cpu > 55 { return .accentRed }
        if cpu > 18 { return .accentAmber }
        return .accentBlue
    }
}

// MARK: - Popover Aesthetics

struct PopoverFansView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cooling", systemImage: "fanblades")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                Spacer()
                Text("\(monitor.fans.count) fans")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.72))
            }
            
            HStack(spacing: 8) {
                ForEach(monitor.fans) { fan in
                    VStack(spacing: 7) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(rpmColor(fan))
                                .frame(width: 6, height: 6)
                            
                            Text(fan.label)
                                .font(.system(size: 11, weight: .medium))
.foregroundStyle(Color.primary)
                        }
                        
                        if fan.actualRPM > 0 {
                            Text("\(fan.actualRPM)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(rpmColor(fan))
                            Text("RPM")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary)
                        } else {
                            Text("Auto")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.secondary)
                            Text("MODE")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.secondary)
                        }
                        
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 60, height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(rpmColor(fan))
                                .frame(width: max(3, 60 * fan.percentOfMax), height: 3)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.58))
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
        )
    }
    
    private func rpmColor(_ fan: FanInfo) -> Color {
        let p = fan.percentOfMax
        if p > 0.85 { return .accentRed }
        if p > 0.6  { return .accentAmber }
        return .accentGreen
    }
}

struct PopoverTemperatureView: View {
    @ObservedObject var monitor: SystemMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let cpuHist = monitor.thermalHistory.map { $0.cpu }
            let socHist = monitor.thermalHistory.map { $0.soc }
            let battHist = monitor.thermalHistory.map { $0.battery }
            
            HStack(spacing: 12) {
                tempColumn(label: "CPU", temp: monitor.thermal.cpuTemp, history: cpuHist, color: .accentRed)
                tempColumn(label: "SoC", temp: monitor.thermal.socTemp, history: socHist, color: .accentBlue)
                tempColumn(label: "BATT", temp: monitor.thermal.batteryTemp, history: battHist, color: .accentAmber)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 0.75)
                )
        )
    }
    
    @ViewBuilder
    private func tempColumn(label: String, temp: Double, history: [Double], color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.secondary)
                Spacer()
                Text(temp > 0 ? String(format: "%.0f°", temp) : "N/A")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(temp > 0 ? color : Color.secondary.opacity(0.65))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .windowBackgroundColor).opacity(0.58))
                let validHistory = history.filter { $0 > 0 }
                if validHistory.count > 1 {
                    MiniSparkline(values: validHistory, color: color)
                        .padding(3)
                } else {
                    Text("No data")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }
            .frame(height: 28)
        }
        .frame(maxWidth: .infinity)
    }
}
