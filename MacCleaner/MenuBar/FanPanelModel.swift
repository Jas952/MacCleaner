import Foundation

struct FanTemperatureSample: Identifiable {
    let id = UUID()
    let date: Date
    let values: [String: Double]
}

enum FanTimelineEventKind: Equatable {
    case enabled, disabled, manual, automatic, rpmIncrease, stopped
}

struct FanTimelineEvent: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let kind: FanTimelineEventKind
}

@MainActor
private final class FanThermalTimelineStore {
    static let shared = FanThermalTimelineStore()
    var samples: [FanTemperatureSample] = []
    var events: [FanTimelineEvent] = []
    private var lastFanRPM: [Int: Int] = [:]

    func append(thermal sensors: [SensorReading], fans: [FanInfo]) {
        if !sensors.isEmpty {
            samples.append(FanTemperatureSample(
                date: Date(),
                values: Dictionary(uniqueKeysWithValues: sensors.map { ($0.id, $0.value) })
            ))
            if samples.count > 1_800 { samples.removeFirst(samples.count - 1_800) }
        }
        for fan in fans {
            if let previous = lastFanRPM[fan.id] {
                if previous == 0, fan.actualRPM > 0 {
                    record("Fan \(fan.id + 1) started · \(fan.actualRPM) RPM", kind: .enabled)
                } else if previous > 0, fan.actualRPM == 0 {
                    record("Fan \(fan.id + 1) stopped", kind: .stopped)
                } else if fan.actualRPM - previous >= 250 {
                    let mode = fan.mode == 1 ? "Manual" : "Auto"
                    record("Fan \(fan.id + 1) increased · \(fan.actualRPM) RPM · \(mode)", kind: .rpmIncrease)
                }
            }
            lastFanRPM[fan.id] = fan.actualRPM
        }
    }

    func record(_ label: String, kind: FanTimelineEventKind) {
        events.append(FanTimelineEvent(date: Date(), label: label, kind: kind))
        if events.count > 120 { events.removeFirst(events.count - 120) }
    }
}

@MainActor
final class FanPanelModel: ObservableObject {
    private static let disabledChannelsKey = "FanPanelDisabledChannels"
    @Published var fans: [FanInfo] = []
    @Published var ready = false
    @Published private(set) var accessChecked = false
    @Published var busy = false
    @Published var boostSeconds = 0
    @Published var message: String?
    @Published var hasError = false
    @Published var temperatureSensors: [SensorReading] = []
    @Published var temperatureHistory: [FanTemperatureSample] = []
    @Published var timelineEvents: [FanTimelineEvent] = []
    @Published private var desiredModes: [Int: Int] = [:]
    @Published private var controlledFanIDs: Set<Int> = []
    @Published private var disabledChannels: Set<Int>
    private var pendingFanIDs: Set<Int> = []
    private var timer: Timer?
    private var reading = false
    private var polling = false
    private let client = FanControlXPCClient.shared
    private let queue = DispatchQueue(label: "com.maccleaner.fan-panel.telemetry", qos: .utility)
    private let timeline = FanThermalTimelineStore.shared

    var shouldOfferControlAccess: Bool { accessChecked && !ready }

    init(initialFans: [FanInfo] = [], initialThermal: ThermalInfo? = nil) {
        let stored = UserDefaults.standard.array(forKey: Self.disabledChannelsKey) as? [Int] ?? []
        disabledChannels = Set(stored)
        fans = initialFans
        temperatureHistory = timeline.samples
        timelineEvents = timeline.events
        if let initialThermal {
            updateTemperatures(initialThermal)
        }
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.15
        Task {
            let installed = await Task.detached { FanControlXPCClient.shared.availability == .ready }.value
            guard installed else {
                ready = false
                accessChecked = true
                return
            }
            client.checkStatus { [weak self] success, error in
                self?.ready = success
                self?.accessChecked = true
                if let error { self?.message = error }
            }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }

    func refresh() {
        if !reading {
            reading = true
            queue.async { [weak self] in
                let service = SMCService.shared
                let fans = service.readFans()
                let thermal = service.readThermal()
                DispatchQueue.main.async {
                    guard let self else { return }
                    for fan in fans {
                        guard let desired = self.desiredModes[fan.id] else { continue }
                        let confirmed = desired == 1 ? fan.mode == 1 : fan.mode == 0 || fan.mode == 3
                        if confirmed { self.desiredModes.removeValue(forKey: fan.id) }
                    }
                    self.fans = fans
                    self.updateTemperatures(thermal)
                    self.reading = false
                }
            }
        }
        guard ready, !polling else { return }
        polling = true
        client.controlState { [weak self] seconds, controlledFanIDs, error in
            guard let self else { return }
            if boostSeconds > 0 && seconds == 0 && error == nil { message = "Boost complete · macOS Auto" }
            boostSeconds = seconds
            if error == nil { self.controlledFanIDs = controlledFanIDs }
            polling = false
            if let error { message = error; hasError = true }
        }
    }
    private func updateTemperatures(_ thermal: ThermalInfo) {
        let valid = thermal.sensors.filter { $0.value.isFinite && $0.value > 1 && $0.value < 130 }
        var selected = valid
        if selected.isEmpty {
            let summaries: [(String, Double, SensorCategory)] = [
                ("CPU", thermal.cpuTemp, .cpuCore), ("SoC", thermal.socTemp, .soc),
                ("GPU", thermal.gpuTemp, .soc), ("Battery", thermal.batteryTemp, .battery)
            ]
            selected = summaries.compactMap { name, value, category in
                guard value.isFinite, value > 1 else { return nil }
                return SensorReading(name: name, value: value, category: category, sourceID: name, source: "Summary")
            }
        }
        temperatureSensors = selected
        guard !temperatureSensors.isEmpty else { return }
        timeline.append(thermal: temperatureSensors, fans: fans)
        temperatureHistory = timeline.samples
        timelineEvents = timeline.events
    }

    private func recordEvent(_ label: String, kind: FanTimelineEventKind) {
        timeline.record(label, kind: kind)
        timelineEvents = timeline.events
    }
    func install() {
        busy = true; message = "Waiting for administrator approval…"
        client.installHelper { [weak self] success, error in
            self?.busy = false; self?.ready = success
            self?.accessChecked = true
            self?.message = success ? "Fan control ready" : error
            self?.hasError = !success
            self?.refresh()
        }
    }
    private func perform(_ successMessage: String, _ action: (@escaping (Bool, String?) -> Void) -> Void) {
        guard !busy else { return }
        busy = true
        message = "Applying fan mode…"
        hasError = false
        action { [weak self] success, error in
            self?.busy = false
            self?.message = success ? successMessage : error
            self?.hasError = !success
            self?.refresh()
        }
    }
    func displayedMode(for fan: FanInfo) -> Int? {
        if let desired = desiredModes[fan.id] { return desired }
        guard ready else { return fan.mode }
        if controlledFanIDs.contains(fan.id) { return 1 }
        if controlledFanIDs.isEmpty, fan.mode == 1 { return nil }
        return 0
    }
    func isControlEnabled(for fan: FanInfo) -> Bool { !disabledChannels.contains(fan.id) }
    private func persistDisabledChannels() {
        UserDefaults.standard.set(Array(disabledChannels).sorted(), forKey: Self.disabledChannelsKey)
    }

    private func performFan(
        _ fan: FanInfo,
        mode: Int,
        successMessage: String,
        completion: ((Bool) -> Void)? = nil,
        action: (@escaping (Bool, String?) -> Void) -> Void
    ) {
        guard !pendingFanIDs.contains(fan.id) else { return }
        pendingFanIDs.insert(fan.id)
        desiredModes[fan.id] = mode
        hasError = false
        action { [weak self] success, error in
            guard let self else { return }
            pendingFanIDs.remove(fan.id)
            if success {
                if mode == 1 { controlledFanIDs.insert(fan.id) }
                else { controlledFanIDs.remove(fan.id) }
            } else {
                desiredModes.removeValue(forKey: fan.id)
            }
            message = success ? successMessage : error
            hasError = !success
            completion?(success)
            refresh()
        }
    }
    func toggleControl(for fan: FanInfo) {
        if disabledChannels.contains(fan.id) {
            disabledChannels.remove(fan.id)
            persistDisabledChannels()
            hasError = false
            message = "Fan \(fan.id + 1) · control enabled"
            recordEvent("Fan \(fan.id + 1) control enabled · Auto", kind: .enabled)
            return
        }
        guard !pendingFanIDs.contains(fan.id) else { return }
        disabledChannels.insert(fan.id)
        persistDisabledChannels()
        recordEvent("Fan \(fan.id + 1) control disabled · system", kind: .disabled)
        performFan(
            fan,
            mode: 0,
            successMessage: "Fan \(fan.id + 1) · returned to system control",
            completion: { [weak self] success in
                if !success {
                    self?.disabledChannels.remove(fan.id)
                    self?.persistDisabledChannels()
                }
            }
        ) { done in
            client.setAutomatic(fanIndex: fan.id, completion: done)
        }
    }
    func manual(_ fan: FanInfo, rpm: Int) {
        guard !disabledChannels.contains(fan.id) else { return }
        guard fan.minRPM > 0, fan.maxRPM >= fan.minRPM else { return }
        let target = min(fan.maxRPM, max(fan.minRPM, rpm))
        recordEvent("Fan \(fan.id + 1) set · \(target) RPM · Manual", kind: .manual)
        performFan(fan, mode: 1, successMessage: "Fan \(fan.id + 1) · \(target) RPM confirmed") { done in
            client.setManualRPM(target, fanIndex: fan.id, completion: done)
        }
    }
    func automatic(_ fan: FanInfo) {
        recordEvent("Fan \(fan.id + 1) switched to Auto", kind: .automatic)
        performFan(fan, mode: 0, successMessage: "Fan \(fan.id + 1) · macOS Auto") { done in
            client.setAutomatic(fanIndex: fan.id, completion: done)
        }
    }
    func boost() {
        perform("Maximum cooling · 10 seconds") { done in client.boostForTenSeconds(completion: done) }
    }
    func allAuto() {
        perform("Both fans · macOS Auto") { done in client.setAllAutomatic(completion: done) }
    }
}
