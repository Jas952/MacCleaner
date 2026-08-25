import Foundation
import Combine
import SwiftUI

enum MenuBarDashboardModule: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case disk
    case network
    case graphics
    case battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .graphics: return "Graphics"
        case .battery: return "Battery"
        }
    }

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .graphics: return "display"
        case .battery: return "battery.75percent"
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published private(set) var enabledToolIDs: Set<String> {
        didSet { defaults.set(Array(enabledToolIDs), forKey: Keys.enabledTools) }
    }
    @Published private(set) var menuBarToolIDs: Set<String> {
        didSet { defaults.set(Array(menuBarToolIDs), forKey: Keys.menuBarTools) }
    }
    @Published private(set) var menuBarGaugeIDs: [String] {
        didSet { defaults.set(menuBarGaugeIDs, forKey: Keys.menuBarGauges) }
    }
    @Published private(set) var menuBarGaugeFormats: [String: String] {
        didSet { defaults.set(menuBarGaugeFormats, forKey: Keys.menuBarGaugeFormats) }
    }
    @Published private(set) var menuBarGaugeDisplayStyles: [String: String] {
        didSet { defaults.set(menuBarGaugeDisplayStyles, forKey: Keys.menuBarGaugeDisplayStyles) }
    }
    @Published private(set) var menuBarDashboardModuleIDs: [String] {
        didSet { defaults.set(menuBarDashboardModuleIDs, forKey: Keys.menuBarDashboardModules) }
    }
    @Published var clipboardHistoryInMenuBar: Bool {
        didSet { defaults.set(clipboardHistoryInMenuBar, forKey: Keys.clipboardHistoryInMenuBar) }
    }
    private let defaults: UserDefaults

    private enum Keys {
        static let enabledTools = "enabledUtilityTools"
        static let menuBarTools = "menuBarUtilityTools"
        static let menuBarGauges = "menuBarGaugeOrder"
        static let menuBarGaugeFormats = "menuBarGaugeFormats"
        static let menuBarGaugeDisplayStyles = "menuBarGaugeDisplayStyles"
        static let legacyMenuBarGaugeDisplayStyle = "menuBarGaugeDisplayStyle"
        static let menuBarDashboardModules = "menuBarDashboardModules"
        static let clipboardHistoryInMenuBar = "clipboardHistoryInMenuBar"
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let defaultTools = UtilityToolID.availableCases.filter(\.enabledByDefault).map(\.rawValue)
        let validToolIDs = Set(UtilityToolID.availableCases.map(\.rawValue))
        enabledToolIDs = Set(defaults.stringArray(forKey: Keys.enabledTools) ?? defaultTools)
            .intersection(validToolIDs)
        menuBarToolIDs = Set(defaults.stringArray(forKey: Keys.menuBarTools) ?? [
            UtilityToolID.shelf.rawValue,
            UtilityToolID.colorPicker.rawValue
        ]).intersection(Set(UtilityToolID.configurableCases.filter(\.supportsMenuBar).map(\.rawValue)))
        let validGaugeIDs = Set(MenuBarGauge.allCases.map(\.rawValue))
        let storedGauges = defaults.stringArray(forKey: Keys.menuBarGauges) ?? [
            MenuBarGauge.cpu.rawValue,
            MenuBarGauge.ram.rawValue
        ]
        menuBarGaugeIDs = storedGauges.filter(validGaugeIDs.contains)
        let storedFormats = defaults.dictionary(forKey: Keys.menuBarGaugeFormats) as? [String: String] ?? [:]
        menuBarGaugeFormats = Dictionary(uniqueKeysWithValues: MenuBarGauge.allCases.map { gauge in
            let validFormats = Set(gauge.valueFormats.map(\.rawValue))
            let stored = storedFormats[gauge.rawValue]
            return (gauge.rawValue, stored.flatMap { validFormats.contains($0) ? $0 : nil } ?? gauge.valueFormats[0].rawValue)
        })
        let storedStyles = defaults.dictionary(forKey: Keys.menuBarGaugeDisplayStyles) as? [String: String] ?? [:]
        let legacyStyle = defaults.string(forKey: Keys.legacyMenuBarGaugeDisplayStyle)
            .flatMap(MenuBarGaugeDisplayStyle.init(rawValue:)) ?? .battery
        menuBarGaugeDisplayStyles = Dictionary(uniqueKeysWithValues: MenuBarGauge.allCases.map { gauge in
            let stored = storedStyles[gauge.rawValue].flatMap(MenuBarGaugeDisplayStyle.init(rawValue:))
            return (gauge.rawValue, (stored ?? legacyStyle).rawValue)
        })
        let validModuleIDs = Set(MenuBarDashboardModule.allCases.map(\.rawValue))
        let storedModules = defaults.stringArray(forKey: Keys.menuBarDashboardModules)
            ?? MenuBarDashboardModule.allCases.map(\.rawValue)
        menuBarDashboardModuleIDs = storedModules.filter(validModuleIDs.contains)
        clipboardHistoryInMenuBar = defaults.object(forKey: Keys.clipboardHistoryInMenuBar) as? Bool ?? true
    }

    func isEnabled(_ tool: UtilityToolID) -> Bool {
        tool == .welcome || enabledToolIDs.contains(tool.rawValue)
    }

    func setEnabled(_ enabled: Bool, for tool: UtilityToolID) {
        guard tool.isAvailableInTools else {
            enabledToolIDs.remove(tool.rawValue)
            menuBarToolIDs.remove(tool.rawValue)
            return
        }
        if enabled { enabledToolIDs.insert(tool.rawValue) }
        else {
            enabledToolIDs.remove(tool.rawValue)
            menuBarToolIDs.remove(tool.rawValue)
        }
    }

    func isInMenuBar(_ tool: UtilityToolID) -> Bool {
        menuBarToolIDs.contains(tool.rawValue)
    }

    func setInMenuBar(_ enabled: Bool, for tool: UtilityToolID) {
        guard tool.supportsMenuBar else { return }
        if enabled {
            enabledToolIDs.insert(tool.rawValue)
            menuBarToolIDs.insert(tool.rawValue)
        } else {
            menuBarToolIDs.remove(tool.rawValue)
        }
    }

    func isGaugeEnabled(_ gauge: MenuBarGauge) -> Bool {
        menuBarGaugeIDs.contains(gauge.rawValue)
    }

    func setGaugeEnabled(_ enabled: Bool, gauge: MenuBarGauge) {
        if enabled, !menuBarGaugeIDs.contains(gauge.rawValue) { menuBarGaugeIDs.append(gauge.rawValue) }
        if !enabled { menuBarGaugeIDs.removeAll { $0 == gauge.rawValue } }
    }

    func moveGauge(_ sourceRawValue: String, to targetRawValue: String) {
        guard
            sourceRawValue != targetRawValue,
            let sourceIndex = menuBarGaugeIDs.firstIndex(of: sourceRawValue),
            let targetIndex = menuBarGaugeIDs.firstIndex(of: targetRawValue)
        else { return }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        menuBarGaugeIDs.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
    }

    func valueFormat(for gauge: MenuBarGauge) -> MenuBarGaugeValueFormat {
        let rawValue = menuBarGaugeFormats[gauge.rawValue]
        return rawValue.flatMap(MenuBarGaugeValueFormat.init(rawValue:)) ?? gauge.valueFormats[0]
    }

    func setValueFormat(_ format: MenuBarGaugeValueFormat, for gauge: MenuBarGauge) {
        guard gauge.valueFormats.contains(format) else { return }
        menuBarGaugeFormats[gauge.rawValue] = format.rawValue
    }

    func displayStyle(for gauge: MenuBarGauge) -> MenuBarGaugeDisplayStyle {
        let rawValue = menuBarGaugeDisplayStyles[gauge.rawValue]
        return rawValue.flatMap(MenuBarGaugeDisplayStyle.init(rawValue:)) ?? .battery
    }

    func setDisplayStyle(_ style: MenuBarGaugeDisplayStyle, for gauge: MenuBarGauge) {
        menuBarGaugeDisplayStyles[gauge.rawValue] = style.rawValue
    }

    func moveMenuBarDashboardModule(_ sourceRawValue: String, to targetRawValue: String) {
        guard
            sourceRawValue != targetRawValue,
            let sourceIndex = menuBarDashboardModuleIDs.firstIndex(of: sourceRawValue),
            let targetIndex = menuBarDashboardModuleIDs.firstIndex(of: targetRawValue)
        else { return }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        menuBarDashboardModuleIDs.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
    }

    func setMenuBarDashboardModuleOrder(_ modules: [MenuBarDashboardModule]) {
        let rawValues = modules.map(\.rawValue)
        guard
            rawValues.count == menuBarDashboardModuleIDs.count,
            Set(rawValues) == Set(menuBarDashboardModuleIDs)
        else { return }
        menuBarDashboardModuleIDs = rawValues
    }

    func removeMenuBarDashboardModule(_ module: MenuBarDashboardModule) {
        menuBarDashboardModuleIDs.removeAll { $0 == module.rawValue }
    }

    func restoreMenuBarDashboardModule(_ module: MenuBarDashboardModule) {
        guard !menuBarDashboardModuleIDs.contains(module.rawValue) else { return }
        menuBarDashboardModuleIDs.append(module.rawValue)
    }
}
