import Foundation

extension Notification.Name {
    static let macCleanerOpenDestination = Notification.Name("MacCleaner.openDestination")
}

struct ThermalLoadAlert: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let destination: String
    let cpuUsage: Double
    let temperature: Double
    let temperatureLabel: String
    let topProcesses: [String]
}

enum ThermalAlertPreferences {
    static let enabledKey = "MacCleaner.ThermalAlerts.enabled"
    static let cpuThresholdKey = "MacCleaner.ThermalAlerts.cpuThreshold"
    static let temperatureThresholdKey = "MacCleaner.ThermalAlerts.temperatureThreshold"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var cpuThreshold: Double {
        let value = UserDefaults.standard.object(forKey: cpuThresholdKey) as? Double ?? 85
        return min(max(value, 50), 100)
    }

    static var temperatureThreshold: Double {
        let value = UserDefaults.standard.object(forKey: temperatureThresholdKey) as? Double ?? 85
        return min(max(value, 50), 110)
    }
}

@MainActor
final class ThermalLoadAlertService {
    static let shared = ThermalLoadAlertService()

    private var sustainedLoadSamples = 0
    private var sustainedThermalSamples = 0
    private var didNotifyForCurrentEvent = false
    private let sampleThreshold = 3

    private init() {}

    #if DEBUG
    /// Deterministic UI test hook. It exercises the same notification and deep-link path
    /// without requiring the machine to actually overheat.
    func triggerTestAlert() {
        didNotifyForCurrentEvent = false
        sustainedLoadSamples = 0
        sustainedThermalSamples = 0
        let sampleThermal = ThermalInfo(cpuTemp: 92)
        let sampleProcesses = [
            AppProcessInfo(id: 1, name: "Test build process", cpuUsage: 96, memoryBytes: 0),
            AppProcessInfo(id: 2, name: "Test indexer", cpuUsage: 88, memoryBytes: 0),
            AppProcessInfo(id: 3, name: "Test agent", cpuUsage: 81, memoryBytes: 0)
        ]
        evaluate(cpuUsage: 96, thermal: sampleThermal, topProcesses: sampleProcesses)
        evaluate(cpuUsage: 96, thermal: sampleThermal, topProcesses: sampleProcesses)
        evaluate(cpuUsage: 96, thermal: sampleThermal, topProcesses: sampleProcesses)
    }
    #endif

    func evaluate(cpuUsage: Double, thermal: ThermalInfo, topProcesses: [AppProcessInfo]) {
        guard ThermalAlertPreferences.enabled else {
            sustainedLoadSamples = 0
            sustainedThermalSamples = 0
            didNotifyForCurrentEvent = false
            return
        }

        let highCPU = cpuUsage >= ThermalAlertPreferences.cpuThreshold
        let highThermal = max(thermal.cpuTemp, thermal.socTemp) >= ThermalAlertPreferences.temperatureThreshold
        sustainedLoadSamples = highCPU ? sustainedLoadSamples + 1 : 0
        sustainedThermalSamples = highThermal ? sustainedThermalSamples + 1 : 0

        let sustained = sustainedLoadSamples >= sampleThreshold || sustainedThermalSamples >= sampleThreshold
        guard sustained else {
            if !highCPU && !highThermal { didNotifyForCurrentEvent = false }
            return
        }
        guard !didNotifyForCurrentEvent else { return }
        didNotifyForCurrentEvent = true

        let top = topProcesses.prefix(3).map { $0.name }.joined(separator: ", ")
        let reason = highThermal ? "Thermal pressure is high" : "CPU load has stayed high"
        let body = top.isEmpty ? "\(reason). Open MacCleaner to inspect Processes or Fans." : "\(reason). Top processes: \(top)."
        let destination = highThermal ? "fans" : "processes"
        let alert = ThermalLoadAlert(
            title: "MacCleaner warning",
            body: body,
            destination: destination,
            cpuUsage: cpuUsage,
            temperature: max(thermal.cpuTemp, thermal.socTemp),
            temperatureLabel: thermal.socTemp > thermal.cpuTemp ? "SoC TEMP" : "CPU TEMP",
            topProcesses: Array(topProcesses.prefix(3).map(\.name))
        )
        ThermalLoadAlertPanelController.shared.show(alert)

        DiagnosticLogStore.shared.append(
            level: .warning,
            category: "alerts",
            message: "Sustained thermal/load warning",
            metadata: ["cpu": String(format: "%.1f", cpuUsage), "topProcesses": top]
        )

    }
}
