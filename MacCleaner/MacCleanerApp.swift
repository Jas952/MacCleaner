import Darwin
import AppKit
import Combine
import CoreGraphics
import SwiftUI

@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sharedMonitor = SystemMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains(where: {
                    $0.hasPrefix("--debug-process-history-") || $0.hasPrefix("--debug-thermal-")
                }) {
                    MenuBarPopover(
                        monitor: sharedMonitor,
                        openMain: {},
                        openShelf: {},
                        openSettings: {},
                        openAbout: {},
                        quit: {}
                    )
                    .frame(width: 456, height: 646)
                } else {
                    mainContent
                }
                #else
                mainContent
                #endif
            }
            .background {
                StatusBarSceneBridge(monitor: sharedMonitor, appDelegate: appDelegate)
            }
                .onChange(of: scenePhase) { phase in
                    sharedMonitor.setBackgroundSuspended(phase != .active)
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

    private var mainContent: some View {
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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: {
                $0.hasPrefix("--debug-thermal-") || $0.hasPrefix("--debug-process-history-")
            }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                    self?.statusBarController?.showPopoverForDebug()
                }
            }
            #endif
        }
        installUtilityRuntime()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLogStore.shared.append(
            category: "lifecycle",
            message: "MacCleaner launched",
            metadata: ["os": ProcessInfo.processInfo.operatingSystemVersionString]
        )
        Task { @MainActor [weak self] in
            self?.installUtilityRuntime()
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["MACCLEANER_TEST_THERMAL_ALERT"] == "1" ||
            ProcessInfo.processInfo.arguments.contains("--test-thermal-alert") {
            Task { @MainActor in
                ThermalLoadAlertService.shared.triggerTestAlert()
            }
        }
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
        FanControlXPCClient.shared.setAllAutomatic { _, _ in }
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

private final class StatusBarPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let monitor: SystemMonitor
    private let settings = SettingsManager.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var labelHost: StatusBarPassthroughHostingView<MenuBarLabel>?
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
        button.title = ""
        let host = StatusBarPassthroughHostingView(rootView: MenuBarLabel(monitor: monitor))
        host.isHidden = true
        button.addSubview(host)
        labelHost = host
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 430, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover(
                monitor: monitor,
                openMain: openMain,
                openShelf: openShelf,
                openSettings: openSettings,
                openAbout: {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(nil)
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
            .frame(width: 430, height: 620)
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
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    #if DEBUG
    func showPopoverForDebug() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    #endif

    private func updateStatusItem() {
        guard let button = statusItem.button, let labelHost else { return }
        let gauges = settings.menuBarGaugeIDs.compactMap(MenuBarGauge.init(rawValue:))
        let accessibilityParts = gauges.map { gauge in
            "\(gauge.title) \(reading(for: gauge).value)"
        }

        if gauges.isEmpty {
            labelHost.isHidden = true
            button.image = applicationStatusIcon()
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString()
            statusItem.length = 26
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = NSAttributedString()
            labelHost.rootView = MenuBarLabel(monitor: monitor)
            labelHost.isHidden = false
            let fittingSize = labelHost.fittingSize
            statusItem.length = max(30, fittingSize.width + 8)
            labelHost.frame = NSRect(
                x: 4,
                y: max(0, (button.bounds.height - fittingSize.height) / 2),
                width: fittingSize.width,
                height: min(button.bounds.height, fittingSize.height)
            )
        }

        button.setAccessibilityLabel(accessibilityParts.isEmpty ? "MacCleaner" : accessibilityParts.joined(separator: ", "))
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

private final class MenuBarRefreshDriver: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var cancellable: AnyCancellable?

    init(monitor: SystemMonitor) {
        cancellable = monitor.objectWillChange
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
}

struct MenuBarLabel: View {
    let monitor: SystemMonitor
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var refreshDriver: MenuBarRefreshDriver

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        _refreshDriver = StateObject(wrappedValue: MenuBarRefreshDriver(monitor: monitor))
    }

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

    private var gaugeColumns: [[MenuBarGauge]] {
        let gauges = settings.menuBarGaugeIDs.compactMap(MenuBarGauge.init(rawValue:))
        return stride(from: 0, to: gauges.count, by: 2).map { start in
            Array(gauges[start..<min(start + 2, gauges.count)])
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if settings.menuBarGaugeIDs.isEmpty {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 17, height: 17)
            }
            ForEach(Array(gaugeColumns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: -1) {
                    ForEach(column) { gauge in
                        gaugeView(gauge)
                    }
                }
                .frame(height: 20, alignment: .center)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .help(accessibilitySummary)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func gaugeView(_ gauge: MenuBarGauge) -> some View {
        let data = gaugeData(gauge)
        HStack(alignment: .center, spacing: 1.5) {
            Text(gauge.shortTitle)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            if settings.displayStyle(for: gauge) == .battery {
                MenuBarBatteryIndicator(progress: data.progress, color: data.color)
                    .scaleEffect(0.62)
                    .frame(width: 7, height: 9)
                if gauge == .temperature {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                MenuBarFormatMarker(marker: gauge.formatMarker(for: settings.valueFormat(for: gauge)))
                    .scaleEffect(0.78)
                    .frame(width: 6, height: 9)
            } else {
                Text(data.value)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(data.color)
            }
        }
        .frame(height: 10, alignment: .center)
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
    let monitor: SystemMonitor
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var refreshDriver: MenuBarRefreshDriver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: MenuBarPopoverTab = .system
    @State private var isEditing = false
    @State private var dragSession: MenuBarCardDragSession?
    @State private var dragOrder: [MenuBarDashboardModule]?
    @State private var cardFrames: [MenuBarDashboardModule: CGRect] = [:]

    let openMain: () -> Void
    let openShelf: () -> Void
    let openSettings: () -> Void
    let openAbout: () -> Void
    let quit: () -> Void

    init(
        monitor: SystemMonitor,
        openMain: @escaping () -> Void,
        openShelf: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openAbout: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.openMain = openMain
        self.openShelf = openShelf
        self.openSettings = openSettings
        self.openAbout = openAbout
        self.quit = quit
        _refreshDriver = StateObject(wrappedValue: MenuBarRefreshDriver(monitor: monitor))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: {
            $0.hasPrefix("--debug-thermal-") || $0.hasPrefix("--debug-process-history-")
        }) {
            _selectedTab = State(initialValue: .graphs)
        }
        #endif
    }

    private var visibleModules: [MenuBarDashboardModule] {
        settings.menuBarDashboardModuleIDs.compactMap(MenuBarDashboardModule.init(rawValue:))
    }

    private var hiddenModules: [MenuBarDashboardModule] {
        MenuBarDashboardModule.allCases.filter { !settings.menuBarDashboardModuleIDs.contains($0.rawValue) }
    }

    private var displayedModules: [MenuBarDashboardModule] {
        dragOrder ?? visibleModules
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)

            Group {
                switch selectedTab {
                case .system:
                    systemTab
                case .graphs:
                    MenuBarGraphsView(monitor: monitor)
                case .tools:
                    toolsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
        }
        .background(.regularMaterial)
        .onChange(of: isEditing) { editing in
            if !editing { finishCardDrag() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: openMain) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .menuBarHoverChrome()
            .help("Open MacCleaner")
            .accessibilityLabel("Open MacCleaner")

            HStack(spacing: 4) {
                ForEach(MenuBarPopoverTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedTab = tab
                            if tab != .system { isEditing = false }
                        }
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? Color.accentBlue : Color.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .menuBarHoverChrome(isSelected: selectedTab == tab)
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                }
            }

            Spacer(minLength: 6)

            if selectedTab == .system {
                Button {
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isEditing ? Color.accentBlue : Color.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .menuBarHoverChrome(isSelected: isEditing)
                .help(isEditing ? "Finish editing dashboard cards" : "Reorder or remove dashboard cards")
            }
        }
    }

    private var systemTab: some View {
        ZStack {
            MenuBarSystemBackdrop()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(Array(displayedModules.enumerated()), id: \.element.id) { index, module in
                        MenuBarDashboardCard(
                            module: module,
                            index: index,
                            isEditing: isEditing,
                            isDragging: dragSession?.module == module,
                            reduceMotion: reduceMotion,
                            dragChanged: { value in
                                updateCardDrag(module: module, value: value)
                            },
                            dragEnded: finishCardDrag,
                            remove: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    settings.removeMenuBarDashboardModule(module)
                                }
                            },
                            content: {
                                dashboardCard(for: module)
                            }
                        )
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: MenuBarCardFramePreferenceKey.self,
                                    value: [module: geometry.frame(in: .named("menuBarCards"))]
                                )
                            }
                        }
                    }

                    if visibleModules.isEmpty && !isEditing {
                        VStack(spacing: 8) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("No system cards")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Choose Edit to restore a card.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }

                    if isEditing {
                        restoreMenu
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(12)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.022),
                        .init(color: .black, location: 0.978),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            if let dragSession {
                dashboardCard(for: dragSession.module)
                    .frame(width: dragSession.frame.width, height: dragSession.frame.height)
                    .scaleEffect(1.018)
                    .shadow(color: .black.opacity(0.20), radius: 22, y: 12)
                    .position(
                        x: dragSession.frame.midX,
                        y: dragSession.pointerY - dragSession.grabOffsetY + dragSession.frame.height / 2
                    )
                    .allowsHitTesting(false)
                    .transition(.identity)
                    .zIndex(10)
            }
        }
        .coordinateSpace(name: "menuBarCards")
        .onPreferenceChange(MenuBarCardFramePreferenceKey.self) { cardFrames = $0 }
    }

    private var restoreMenu: some View {
        Menu {
            if hiddenModules.isEmpty {
                Text("All cards are visible")
            } else {
                ForEach(hiddenModules) { module in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            settings.restoreMenuBarDashboardModule(module)
                        }
                    } label: {
                        Label(module.title, systemImage: module.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: hiddenModules.isEmpty ? "checkmark.circle" : "plus.circle")
                Text(hiddenModules.isEmpty ? "All cards are visible" : "Add a removed card")
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.secondary.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .menuStyle(.borderlessButton)
        .disabled(hiddenModules.isEmpty)
        .help("Restore a hidden dashboard card")
    }

    private var toolsTab: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
                ForEach(UtilityToolID.configurableCases.filter { settings.isEnabled($0) && settings.isInMenuBar($0) }) { tool in
                    quickToolButton(tool)
                }

                if settings.clipboardHistoryInMenuBar {
                    Button { ClipboardHistoryPanelController.shared.show() } label: {
                        quickToolLabel(
                            icon: "doc.on.clipboard",
                            title: "Clipboard History",
                            subtitle: "Recent text, images and files · ⌥C"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if settings.menuBarToolIDs.isEmpty && !settings.clipboardHistoryInMenuBar {
                    VStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No quick tools")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Choose them in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(12)
        }
    }

    private func quickToolButton(_ tool: UtilityToolID) -> some View {
        Button { runQuickTool(tool) } label: {
            quickToolLabel(icon: tool.icon, title: tool.title, subtitle: tool.subtitle)
        }
        .buttonStyle(.plain)
    }

    private func quickToolLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 26, height: 26)
                .background(Color.accentBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.68), in: RoundedRectangle(cornerRadius: 11))
        .contentShape(RoundedRectangle(cornerRadius: 11))
    }

    private var footer: some View {
        HStack {
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .menuBarHoverChrome()
            .foregroundStyle(.secondary)
            .help("Settings")
            .accessibilityLabel("Open Settings")

            Spacer()

            Button {
                MenuBarOverflowMenuController.shared.show(
                    openMain: openMain,
                    openAbout: openAbout,
                    quit: quit
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .menuBarHoverChrome()
            .foregroundStyle(.secondary)
            .help("More")
            .accessibilityLabel("More MacCleaner actions")
        }
    }

    private func runQuickTool(_ tool: UtilityToolID) {
        switch tool {
        case .shelf: openShelf()
        case .colorPicker: ColorPickerService.shared.sample()
        default: openMain()
        }
    }

    private func updateCardDrag(module: MenuBarDashboardModule, value: DragGesture.Value) {
        guard isEditing else { return }

        if dragSession == nil {
            guard let frame = cardFrames[module] else { return }
            dragOrder = visibleModules
            dragSession = MenuBarCardDragSession(
                module: module,
                frame: frame,
                grabOffsetY: min(max(value.startLocation.y - frame.minY, 0), frame.height),
                pointerY: value.location.y
            )
        } else {
            dragSession?.pointerY = value.location.y
        }

        guard let dragSession, let currentOrder = dragOrder else { return }
        var remaining = currentOrder.filter { $0 != module }
        let insertionIndex = remaining.firstIndex { candidate in
            guard let frame = cardFrames[candidate] else { return false }
            return dragSession.pointerY < frame.midY
        } ?? remaining.endIndex
        remaining.insert(module, at: insertionIndex)

        guard remaining != currentOrder else { return }
        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.84, blendDuration: 0.08)) {
            dragOrder = remaining
        }
    }

    private func finishCardDrag() {
        guard var session = dragSession else {
            dragOrder = nil
            return
        }
        guard !session.isSettling else { return }

        if let dragOrder {
            settings.setMenuBarDashboardModuleOrder(dragOrder)
        }

        session.isSettling = true
        let sessionID = session.id
        let targetFrame = cardFrames[session.module] ?? session.frame
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.90, blendDuration: 0.08)) {
            session.pointerY = targetFrame.minY + session.grabOffsetY
            dragSession = session
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard dragSession?.id == sessionID else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragSession = nil
                dragOrder = nil
            }
        }
    }

    @ViewBuilder
    private func dashboardCard(for module: MenuBarDashboardModule) -> some View {
        switch module {
        case .cpu:
            DashboardMetricCard(
                icon: "cpu",
                label: "CPU",
                value: String(format: "%.1f%%", monitor.cpu.totalUsage * 100),
                subtitle: "Load \(cpuLoadValue) / \(monitor.cpu.processorCount) cores · \(cpuLoadLabel.lowercased())",
                badge: temperatureBadge(monitor.thermal.cpuTemp),
                progress: monitor.cpu.totalUsage,
                color: cpuColor,
                details: [
                    ("Load", cpuLoadValue),
                    ("History", "\(Int((monitor.cpuHistory.last ?? 0) * 100))%")
                ],
                history: [],
                coreUsages: monitor.cpu.coreUsages
            )
        case .memory:
            MemoryDashboardCard(memory: monitor.memory, color: ramColor)
        case .disk:
            if let disk = rootDisk {
                DashboardMetricCard(
                    icon: "internaldrive",
                    label: "Disk",
                    value: DiskInfo.formatted(disk.free),
                    subtitle: "free on \(disk.volumeName)",
                    badge: String(format: "%.0f%% used", disk.usedPercent * 100),
                    progress: disk.usedPercent,
                    color: diskColor(disk.usedPercent),
                    details: [
                        ("Used", DiskInfo.formatted(disk.used)),
                        ("Total", DiskInfo.formatted(disk.total))
                    ],
                    history: []
                )
            } else {
                DashboardMetricCard(
                    icon: "internaldrive",
                    label: "Disk",
                    value: "—",
                    subtitle: "No current reading",
                    badge: "Unavailable",
                    progress: 0,
                    color: .accentRed,
                    details: [],
                    history: []
                )
            }
        case .network:
            let history = normalizedNetworkHistory
            DashboardMetricCard(
                icon: "network",
                label: "Network",
                value: NetworkInfo.formattedRate(monitor.network.downloadBytesPerSecond),
                subtitle: "↓ \(NetworkInfo.formattedRate(monitor.network.downloadBytesPerSecond)) · ↑ \(NetworkInfo.formattedRate(monitor.network.uploadBytesPerSecond))",
                badge: monitor.network.interfaceName,
                progress: min(max(monitor.network.downloadBytesPerSecond, monitor.network.uploadBytesPerSecond) / 1_048_576, 1),
                color: .accentBlue,
                details: [
                    ("IP \(countryFlag)", monitor.network.address),
                    ("State", monitor.network.isActive ? "Active" : "Idle")
                ],
                history: history.map(\.down),
                historySecondary: history.map(\.up)
            )
        case .graphics:
            DashboardMetricCard(
                icon: "display",
                label: "GPU",
                value: String(format: "%.0f%%", monitor.gpuUsage * 100),
                subtitle: "\(gpuLoadLabel) · \(gpuCoresLabel)",
                badge: temperatureBadge(gpuTemperature),
                progress: monitor.gpuUsage,
                color: .accentAmber,
                details: [
                    ("Chip", HardwareInfo.chipName),
                    ("Display", HardwareInfo.displayInfo)
                ],
                history: monitor.gpuHistory
            )
        case .battery:
            BatteryDashboardCard(battery: monitor.battery)
        }
    }

    private var rootDisk: DiskInfo? {
        monitor.disks.first(where: { $0.mountPoint == "/" }) ?? monitor.disks.first
    }

    private var normalizedNetworkHistory: [(down: Double, up: Double)] {
        let maximum = max(
            monitor.networkHistory.map(\.down).max() ?? 0,
            monitor.networkHistory.map(\.up).max() ?? 0,
            1
        )
        return monitor.networkHistory.map { (min($0.down / maximum, 1), min($0.up / maximum, 1)) }
    }

    private var ramColor: Color {
        monitor.memory.usedPercent > 0.85 ? .accentRed
            : monitor.memory.usedPercent > 0.65 ? .accentAmber : .accentBlue
    }

    private var cpuColor: Color {
        monitor.cpu.totalUsage > 0.85 ? .accentRed
            : monitor.cpu.totalUsage > 0.65 ? .accentAmber : .accentBlue
    }

    private var cpuLoadLabel: String {
        monitor.cpu.totalUsage > 0.65 ? "Busy" : monitor.cpu.totalUsage > 0.2 ? "Active" : "Idle"
    }

    private var cpuLoadValue: String {
        String(format: "%.2f", monitor.cpu.totalUsage * Double(max(1, monitor.cpu.processorCount)))
    }

    private var gpuTemperature: Double {
        monitor.thermal.gpuTemp > 0 ? monitor.thermal.gpuTemp : monitor.thermal.socTemp
    }

    private var gpuLoadLabel: String {
        monitor.gpuUsage > 0.7 ? "heavy" : monitor.gpuUsage > 0.3 ? "moderate" : "idle"
    }

    private var gpuCoresLabel: String {
        let cores = HardwareInfo.gpuCoreCount
        return cores > 0 ? "\(cores) GPU cores" : "Apple GPU"
    }

    private func temperatureBadge(_ value: Double) -> String {
        value > 0 ? String(format: "%.0f°C", value) : "Live"
    }

    private func diskColor(_ value: Double) -> Color {
        if value > 0.90 { return .accentRed }
        if value > 0.75 { return .accentAmber }
        return .accentGreen
    }

    private var countryFlag: String {
        let regionCode = Locale.current.region?.identifier ?? "US"
        let base = UnicodeScalar("🇦").value
        var scalars = String.UnicodeScalarView()
        for scalar in regionCode.uppercased().unicodeScalars.prefix(2) {
            guard let flagScalar = UnicodeScalar(base + scalar.value - UnicodeScalar("A").value) else { continue }
            scalars.append(flagScalar)
        }
        return scalars.isEmpty ? "🌐" : String(scalars)
    }
}

private enum MenuBarPopoverTab: String, CaseIterable, Identifiable {
    case system
    case graphs
    case tools

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .graphs: return "Graphs"
        case .tools: return "Tools"
        }
    }
    var icon: String {
        switch self {
        case .system: return "rectangle.stack"
        case .graphs: return "chart.xyaxis.line"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

private struct MenuBarCardDragSession {
    let id = UUID()
    let module: MenuBarDashboardModule
    let frame: CGRect
    let grabOffsetY: CGFloat
    var pointerY: CGFloat
    var isSettling = false
}

private struct MenuBarCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [MenuBarDashboardModule: CGRect] = [:]

    static func reduce(
        value: inout [MenuBarDashboardModule: CGRect],
        nextValue: () -> [MenuBarDashboardModule: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct MenuBarDashboardCard<Content: View>: View {
    let module: MenuBarDashboardModule
    let index: Int
    let isEditing: Bool
    let isDragging: Bool
    let reduceMotion: Bool
    let dragChanged: (DragGesture.Value) -> Void
    let dragEnded: () -> Void
    let remove: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.animation(minimumInterval: isEditing && !reduceMotion ? 1.0 / 30.0 : 1.0)) { timeline in
            card(
                rotation: isEditing && !reduceMotion && !isDragging
                    ? wiggleAngle(at: timeline.date)
                    : .zero
            )
        }
    }

    @ViewBuilder
    private func card(rotation: Angle) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if isEditing {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.red.opacity(0.88))
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: -6)
                    .help("Remove \(module.title) card")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .trailing) {
                if isEditing {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(width: 28, height: 42)
                        .background(.thinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.07), radius: 7, y: 3)
                        .contentShape(Capsule())
                        .offset(x: 5)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("menuBarCards"))
                                .onChanged(dragChanged)
                                .onEnded { _ in dragEnded() }
                        )
                        .help("Hold and drag to reorder")
                        .accessibilityLabel("Reorder \(module.title) card")
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .rotationEffect(rotation)
            .opacity(isDragging ? 0 : 1)
            .animation(.easeInOut(duration: 0.16), value: isEditing)
    }

    private func wiggleAngle(at date: Date) -> Angle {
        let cycle = date.timeIntervalSinceReferenceDate * 2 * Double.pi / 0.72
        let phase = cycle + Double(index) * Double.pi * 0.58
        return .degrees(sin(phase) * 0.26)
    }
}

private struct MenuBarSystemBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.34),
                    Color.accentBlue.opacity(0.055),
                    Color.clear,
                    Color.accentGreen.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.accentBlue.opacity(0.11), Color.clear],
                center: UnitPoint(x: 0.12, y: 0.08),
                startRadius: 0,
                endRadius: 245
            )
            RadialGradient(
                colors: [Color.accentGreen.opacity(0.09), Color.clear],
                center: UnitPoint(x: 0.92, y: 0.78),
                startRadius: 0,
                endRadius: 300
            )
        }
        .allowsHitTesting(false)
    }
}

@MainActor
private final class MenuBarOverflowMenuController: NSObject {
    static let shared = MenuBarOverflowMenuController()

    private var openMain: (() -> Void)?
    private var openAbout: (() -> Void)?
    private var quit: (() -> Void)?

    func show(
        openMain: @escaping () -> Void,
        openAbout: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.openMain = openMain
        self.openAbout = openAbout
        self.quit = quit

        let menu = NSMenu()
        menu.addItem(item(title: "Open MacCleaner", action: #selector(openMainAction)))
        menu.addItem(item(title: "About MacCleaner", action: #selector(openAboutAction)))
        menu.addItem(.separator())
        menu.addItem(item(title: "Quit MacCleaner", action: #selector(quitAction)))

        if let event = NSApp.currentEvent, let view = event.window?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openMainAction() { openMain?() }
    @objc private func openAboutAction() { openAbout?() }
    @objc private func quitAction() { quit?() }
}

private struct MenuBarHoverChrome: ViewModifier {
    let isSelected: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.72 : 0),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentBlue.opacity(isHovered ? 0.28 : 0) : Color.primary.opacity(isHovered ? 0.10 : 0),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(isHovered ? 0.055 : 0), radius: 5, y: 2)
            .animation(.easeOut(duration: 0.13), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private extension View {
    func menuBarHoverChrome(isSelected: Bool = false) -> some View {
        modifier(MenuBarHoverChrome(isSelected: isSelected))
    }
}
