import AVFoundation
import CoreAudio
import Foundation

private struct StoredDiagnosticPayload<Value: Codable>: Codable {
    let value: Value?
    let lastUsedAt: Date
}

private enum DiagnosticPersistence {
    static func load<Value: Codable>(_ type: Value.Type, key: String) -> StoredDiagnosticPayload<Value>? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StoredDiagnosticPayload<Value>.self, from: data)
    }

    @discardableResult
    static func save<Value: Codable>(_ value: Value?, key: String, at date: Date = Date()) -> Date {
        let payload = StoredDiagnosticPayload(value: value, lastUsedAt: date)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return date
    }
}

enum SpeakerTestMode: String, CaseIterable, Identifiable, Codable {
    case left
    case stereo
    case right
    case sweep
    case rattle
    case pinkNoise
    case impulse

    var id: Self { self }

    static let quickModes: [SpeakerTestMode] = [.left, .stereo, .right]
    static let diagnosticModes: [SpeakerTestMode] = [.sweep, .rattle, .pinkNoise, .impulse]

    var title: String {
        switch self {
        case .left: return "Left"
        case .stereo: return "Stereo"
        case .right: return "Right"
        case .sweep: return "Frequency Sweep"
        case .rattle: return "Rattle Test"
        case .pinkNoise: return "Pink Noise"
        case .impulse: return "Impulse"
        }
    }

    var icon: String {
        switch self {
        case .left: return "speaker.wave.2"
        case .stereo: return "speaker.wave.3"
        case .right: return "speaker.wave.2"
        case .sweep: return "waveform.path"
        case .rattle: return "speaker.badge.exclamationmark"
        case .pinkNoise: return "sparkles"
        case .impulse: return "dot.radiowaves.left.and.right"
        }
    }

    var description: String {
        switch self {
        case .left: return "Only the left channel should play."
        case .stereo: return "Both speakers should sound balanced."
        case .right: return "Only the right channel should play."
        case .sweep: return "80 Hz to 16 kHz to catch missing ranges."
        case .rattle: return "Low tones expose buzz and body vibration."
        case .pinkNoise: return "Broad noise makes uneven tone easy to hear."
        case .impulse: return "Short clicks reveal crackle or dropouts."
        }
    }

    var duration: Double {
        switch self {
        case .left, .stereo, .right: return 1.15
        case .sweep: return 5.0
        case .rattle: return 4.8
        case .pinkNoise: return 3.5
        case .impulse: return 1.7
        }
    }
}

@MainActor
final class SpeakerTestService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var status = "Ready"
    @Published private(set) var outputSummary = "Default output"
    @Published private(set) var outputInfo = SpeakerOutputInfo.placeholder
    @Published private(set) var activeMode: SpeakerTestMode?
    @Published private(set) var lastCompletedMode: SpeakerTestMode?
    @Published private(set) var lastUsedAt: Date?

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var stopTask: Task<Void, Never>?
    private static let persistenceKey = "MacCleaner.Diagnostics.SpeakerTest.lastSnapshot"

    init() {
        guard let stored = DiagnosticPersistence.load(SpeakerTestSnapshot.self, key: Self.persistenceKey) else { return }
        lastUsedAt = stored.lastUsedAt
        guard let snapshot = stored.value else { return }
        outputSummary = snapshot.outputSummary
        outputInfo = snapshot.outputInfo
        lastCompletedMode = snapshot.lastCompletedMode
        status = snapshot.status
    }

    func refreshOutput() {
        let engine = currentEngine()
        let format = engine.outputNode.outputFormat(forBus: 0)
        let channels = max(1, Int(format.channelCount))
        outputSummary = "\(channels) ch · \(Int(format.sampleRate.rounded())) Hz"
        outputInfo = Self.readOutputInfo(format: format, fallbackChannels: channels)
    }

    func play(_ mode: SpeakerTestMode) {
        stop()
        refreshOutput()

        let engine = currentEngine()
        let player = currentPlayer(attachedTo: engine)
        let sampleRate = max(44_100, engine.outputNode.outputFormat(forBus: 0).sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = Self.makeAudioBuffer(mode: mode, format: format)
        else {
            status = "Audio format unavailable"
            persistSnapshot()
            return
        }

        do {
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.prepare()
            try engine.start()

            isPlaying = true
            activeMode = mode
            status = "Playing \(mode.title)"
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                DispatchQueue.main.async {
                    self?.completePlayback(for: mode)
                }
            }
            player.play()

            stopTask = Task { [weak self] in
                let timeout = UInt64((mode.duration + 0.25) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeout)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.completePlayback(for: mode)
                }
            }
        } catch {
            isPlaying = false
            activeMode = nil
            status = "Audio failed"
            persistSnapshot()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        let wasPlaying = isPlaying
        haltAudioEngine()
        if wasPlaying {
            status = "Stopped"
            persistSnapshot()
        }
        activeMode = nil
        isPlaying = false
    }

    var healthStatus: String {
        switch outputInfo.issueLevel {
        case .good:
            return lastCompletedMode == nil ? "Ready" : "Checked"
        case .notice:
            return "Check route"
        case .warning:
            return "Needs action"
        }
    }

    var resultSummary: String {
        if let blockingIssue = outputInfo.blockingIssue {
            return blockingIssue
        }
        if let lastCompletedMode {
            return "\(lastCompletedMode.title) finished. If you heard buzzing, missing sound or swapped channels, check Sound Settings or inspect the speaker grille."
        }
        return "Start with Left, Right and Sweep. If one side is quieter, check macOS Sound Balance before assuming speaker damage."
    }

    private func haltAudioEngine() {
        guard let engine, let player else {
            isPlaying = false
            return
        }
        if player.isPlaying {
            player.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
    }

    private func currentEngine() -> AVAudioEngine {
        if let engine { return engine }
        let created = AVAudioEngine()
        engine = created
        return created
    }

    private func currentPlayer(attachedTo engine: AVAudioEngine) -> AVAudioPlayerNode {
        if let player { return player }
        let created = AVAudioPlayerNode()
        engine.attach(created)
        player = created
        return created
    }

    private func completePlayback(for mode: SpeakerTestMode) {
        guard isPlaying, activeMode == mode else { return }
        stopTask?.cancel()
        stopTask = nil
        haltAudioEngine()
        lastCompletedMode = mode
        activeMode = nil
        isPlaying = false
        status = "Complete"
        persistSnapshot()
    }

    private func persistSnapshot() {
        lastUsedAt = DiagnosticPersistence.save(
            SpeakerTestSnapshot(
                outputSummary: outputSummary,
                outputInfo: outputInfo,
                lastCompletedMode: lastCompletedMode,
                status: status
            ),
            key: Self.persistenceKey
        )
    }

    private static func makeAudioBuffer(mode: SpeakerTestMode, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = mode.duration
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = frameCount
        let frames = Int(frameCount)
        var pinkNoiseState = PinkNoiseState()

        for frame in 0..<frames {
            let t = Double(frame) / format.sampleRate
            let envelope = Float(max(0, min(1.0, min(t / 0.04, (duration - t) / 0.08))))
            let rawSample = mode == .pinkNoise
                ? pinkNoiseState.next(amplitude: 0.08)
                : sampleValue(for: mode, at: t, duration: duration)
            let sample = rawSample * envelope
            let gains = channelGains(for: mode, at: t)
            channels[0][frame] = sample * gains.left
            channels[1][frame] = sample * gains.right
        }

        return buffer
    }

    private static func sampleValue(for mode: SpeakerTestMode, at time: Double, duration: Double) -> Float {
        switch mode {
        case .left, .right:
            return sine(frequency: 520, time: time, amplitude: 0.22)
        case .stereo:
            return sine(frequency: 660, time: time, amplitude: 0.20)
        case .sweep:
            let start = 80.0
            let end = 16_000.0
            let progress = min(1.0, max(0.0, time / duration))
            let frequency = start * pow(end / start, progress)
            return sine(frequency: frequency, time: time, amplitude: 0.14)
        case .rattle:
            let tones = [85.0, 110.0, 140.0, 180.0, 220.0]
            let slot = min(tones.count - 1, Int(time / max(0.1, duration / Double(tones.count))))
            return sine(frequency: tones[slot], time: time, amplitude: 0.18)
        case .pinkNoise:
            return 0
        case .impulse:
            return impulseSample(at: time)
        }
    }

    private static func channelGains(for mode: SpeakerTestMode, at time: Double) -> (left: Float, right: Float) {
        switch mode {
        case .left:
            return (1, 0)
        case .right:
            return (0, 1)
        case .impulse:
            if time < 0.55 { return (1, 0) }
            if time < 1.1 { return (0, 1) }
            return (1, 1)
        default:
            return (1, 1)
        }
    }

    private static func sine(frequency: Double, time: Double, amplitude: Float) -> Float {
        Float(sin(2.0 * Double.pi * frequency * time)) * amplitude
    }

    private static func impulseSample(at time: Double) -> Float {
        let clickTimes = [0.18, 0.48, 0.78, 1.12, 1.42]
        for click in clickTimes where abs(time - click) < 0.0025 {
            return Float((time - click) >= 0 ? 0.35 : -0.35)
        }
        return 0
    }

    private static func readOutputInfo(format: AVAudioFormat, fallbackChannels: Int) -> SpeakerOutputInfo {
        guard let deviceID = defaultOutputDeviceID() else {
            return SpeakerOutputInfo(
                name: "Default Output",
                transport: "System",
                channels: fallbackChannels,
                sampleRate: format.sampleRate,
                volumePercent: nil,
                isMuted: nil,
                balance: "Unknown",
                isBuiltIn: false
            )
        }

        let name = stringProperty(kAudioObjectPropertyName, deviceID: deviceID) ?? "Default Output"
        let transport = transportName(uintProperty(kAudioDevicePropertyTransportType, deviceID: deviceID))
        let volume = outputVolumePercent(deviceID: deviceID)
        let muted = boolProperty(kAudioDevicePropertyMute, deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
        let balance = outputBalance(deviceID: deviceID)

        return SpeakerOutputInfo(
            name: name,
            transport: transport,
            channels: fallbackChannels,
            sampleRate: format.sampleRate,
            volumePercent: volume,
            isMuted: muted,
            balance: balance,
            isBuiltIn: transport == "Built-in"
        )
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value?.takeRetainedValue() as String? : nil
    }

    private static func uintProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func floatProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func boolProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Bool? {
        guard let raw = uintProperty(selector, deviceID: deviceID, scope: scope) else { return nil }
        return raw != 0
    }

    private static func outputVolumePercent(deviceID: AudioDeviceID) -> Int? {
        if let main = floatProperty(kAudioDevicePropertyVolumeScalar, deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return Int((max(0, min(1, main)) * 100).rounded())
        }
        let left = floatProperty(kAudioDevicePropertyVolumeScalar, deviceID: deviceID, element: 1)
        let right = floatProperty(kAudioDevicePropertyVolumeScalar, deviceID: deviceID, element: 2)
        let values = [left, right].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Float32(values.count)
        return Int((max(0, min(1, average)) * 100).rounded())
    }

    private static func outputBalance(deviceID: AudioDeviceID) -> String {
        guard let left = floatProperty(kAudioDevicePropertyVolumeScalar, deviceID: deviceID, element: 1),
              let right = floatProperty(kAudioDevicePropertyVolumeScalar, deviceID: deviceID, element: 2)
        else { return "Unknown" }

        let difference = left - right
        guard abs(difference) >= 0.06 else { return "Center" }
        let percent = Int((abs(difference) * 100).rounded())
        return difference > 0 ? "Left +\(percent)%" : "Right +\(percent)%"
    }

    private static func transportName(_ value: UInt32?) -> String {
        guard let value else { return "External" }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay:
            return "AirPlay"
        case kAudioDeviceTransportTypeVirtual:
            return "Virtual"
        case kAudioDeviceTransportTypeAggregate:
            return "Aggregate"
        default:
            return "External"
        }
    }
}

private struct SpeakerTestSnapshot: Codable {
    let outputSummary: String
    let outputInfo: SpeakerOutputInfo
    let lastCompletedMode: SpeakerTestMode?
    let status: String
}

private struct PinkNoiseState {
    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var b3: Float = 0
    private var b4: Float = 0
    private var b5: Float = 0
    private var b6: Float = 0

    mutating func next(amplitude: Float) -> Float {
        let white = Float.random(in: -1...1)
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return max(-1, min(1, pink * 0.11)) * amplitude
    }
}

enum SpeakerOutputIssue {
    case good
    case notice
    case warning
}

struct SpeakerOutputInfo: Codable {
    let name: String
    let transport: String
    let channels: Int
    let sampleRate: Double
    let volumePercent: Int?
    let isMuted: Bool?
    let balance: String
    let isBuiltIn: Bool

    static let placeholder = SpeakerOutputInfo(
        name: "Default Output",
        transport: "System",
        channels: 2,
        sampleRate: 44_100,
        volumePercent: nil,
        isMuted: nil,
        balance: "Unknown",
        isBuiltIn: false
    )

    var formatSummary: String {
        let rate = sampleRate >= 1_000 ? "\(Int((sampleRate / 1_000).rounded())) kHz" : "\(Int(sampleRate.rounded())) Hz"
        return "\(channels) ch · \(rate)"
    }

    var volumeSummary: String {
        if isMuted == true { return "Muted" }
        guard let volumePercent else { return "Unknown" }
        return "\(volumePercent)%"
    }

    var routeSummary: String {
        isBuiltIn ? "Built-in" : transport
    }

    var issueLevel: SpeakerOutputIssue {
        if isMuted == true { return .warning }
        if channels < 2 { return .warning }
        if let volumePercent, volumePercent < 20 { return .notice }
        if !isBuiltIn { return .notice }
        return .good
    }

    var blockingIssue: String? {
        if isMuted == true {
            return "Output is muted. Turn sound on, then run Left and Right again."
        }
        if channels < 2 {
            return "Current output is not stereo. Select MacBook Speakers or another stereo output before judging left/right balance."
        }
        if let volumePercent, volumePercent < 20 {
            return "Volume is low. Raise it above 30% so rattle and missing-channel problems are easier to hear."
        }
        if !isBuiltIn {
            return "Sound is routed to \(name). Select MacBook Speakers if you want to test the laptop speakers."
        }
        return nil
    }
}

private enum HardwareDiagnosticValue {
    static func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    static func uint(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 { return value }
        if let value = value as? NSNumber { return value.uint64Value }
        if let value = value as? String { return UInt64(value) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}

private enum HardwareDiagnosticCommand {
    static func runData(_ executable: String, arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    static func runString(_ executable: String, arguments: [String], timeout: TimeInterval) -> (output: String, exitCode: Int32)? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }

    static func runAdminString(_ executable: String, arguments: [String], timeout: TimeInterval) -> (output: String, exitCode: Int32)? {
        let command = ([executable] + arguments).map(shellQuote).joined(separator: " ")
        let script = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        return runString("/usr/bin/osascript", arguments: ["-e", script], timeout: timeout)
    }

    static func propertyList(_ executable: String, arguments: [String], timeout: TimeInterval) -> Any? {
        guard let data = runData(executable, arguments: arguments, timeout: timeout) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct StorageHealthSnapshot: Codable {
    let deviceName: String
    let smartStatus: String
    let isSolidState: Bool?
    let percentageUsed: Int?
    let availableSpare: Int?
    let availableSpareThreshold: Int?
    let mediaErrors: Int?
    let errorLogEntries: Int?
    let temperatureCelsius: Int?
    let writtenTB: Double?
    let powerOnHours: Int?
    let unsafeShutdowns: Int?

    var healthLabel: String {
        if smartStatus != "Verified" { return "Attention" }
        if let mediaErrors, mediaErrors > 0 { return "Media errors" }
        if let availableSpare, let availableSpareThreshold, availableSpare <= availableSpareThreshold { return "Low spare" }
        if let percentageUsed, percentageUsed >= 80 { return "High wear" }
        if let percentageUsed, percentageUsed >= 50 { return "Moderate wear" }
        return "Healthy"
    }

    var wearLabel: String {
        guard let percentageUsed else { return "Unknown" }
        return "\(percentageUsed)% used"
    }

    var spareLabel: String {
        guard let availableSpare else { return "Unknown" }
        return "\(availableSpare)%"
    }

    var errorLabel: String {
        guard let mediaErrors else { return "Unknown" }
        return "\(mediaErrors)"
    }

    var detailLabel: String {
        var parts: [String] = []
        if let isSolidState {
            parts.append(isSolidState ? "SSD confirmed" : "Not reported as SSD")
        }
        if let temperatureCelsius {
            parts.append("\(temperatureCelsius) C")
        }
        if let availableSpareThreshold {
            parts.append("spare threshold \(availableSpareThreshold)%")
        }
        if let writtenTB {
            parts.append(String(format: "%.1f TB written", writtenTB))
        }
        if let errorLogEntries {
            parts.append("\(errorLogEntries) error log entries")
        }
        if let powerOnHours {
            parts.append("\(powerOnHours) h powered")
        }
        if let unsafeShutdowns {
            parts.append("\(unsafeShutdowns) unsafe shutdowns")
        }
        return parts.isEmpty ? "Wear details depend on drive SMART support." : parts.joined(separator: " · ")
    }
}

@MainActor
final class StorageHealthService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var snapshot: StorageHealthSnapshot?
    @Published private(set) var status = "Ready"
    @Published private(set) var lastUsedAt: Date?

    private var checkTask: Task<Void, Never>?
    private static let persistenceKey = "MacCleaner.Diagnostics.StorageHealth.lastSnapshot"

    init() {
        guard let stored = DiagnosticPersistence.load(StorageHealthSnapshot.self, key: Self.persistenceKey) else { return }
        lastUsedAt = stored.lastUsedAt
        snapshot = stored.value
        status = stored.value?.healthLabel ?? "Storage unavailable"
    }

    func runQuickCheck() {
        guard !isRunning else { return }
        isRunning = true
        status = "Checking storage"

        checkTask?.cancel()
        checkTask = Task {
            let result = await Self.collectSnapshot()
            guard !Task.isCancelled else { return }
            snapshot = result
            status = result == nil ? "Storage unavailable" : "Complete"
            lastUsedAt = DiagnosticPersistence.save(result, key: Self.persistenceKey)
            isRunning = false
            checkTask = nil
        }
    }

    func cancel() {
        checkTask?.cancel()
        checkTask = nil
        if isRunning {
            status = "Ready"
            isRunning = false
        }
    }

    nonisolated private static func collectSnapshot() async -> StorageHealthSnapshot? {
        await Task.detached(priority: .utility) {
            guard let info = HardwareDiagnosticCommand.propertyList("/usr/sbin/diskutil", arguments: ["info", "-plist", "/"], timeout: 3) as? [String: Any]
            else { return nil }

            let smart = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any]
            let percentageUsed = intValue(smart?["PERCENTAGE_USED"])
            let availableSpare = intValue(smart?["AVAILABLE_SPARE"])
            let availableSpareThreshold = intValue(smart?["AVAILABLE_SPARE_THRESHOLD"])
            let mediaErrors = intValue(smart?["MEDIA_ERRORS_0"])
            let errorLogEntries = intValue(smart?["NUM_ERROR_INFO_LOG_ENTRIES_0"])
            let rawTemperature = intValue(smart?["TEMPERATURE"])
            let temperatureCelsius = rawTemperature.map { $0 > 200 ? $0 - 273 : $0 }
            let writtenUnits = nvmeCounter(smart, "DATA_UNITS_WRITTEN")
            let writtenTB = writtenUnits.map { Double($0) * 512_000.0 / 1_000_000_000_000.0 }
            let powerOnHours = intValue(smart?["POWER_ON_HOURS_0"])
            let unsafeShutdowns = intValue(smart?["UNSAFE_SHUTDOWNS_0"])

            return StorageHealthSnapshot(
                deviceName: stringValue(info["MediaName"]) ?? stringValue(info["VolumeName"]) ?? stringValue(info["ParentWholeDisk"]) ?? "Internal SSD",
                smartStatus: stringValue(info["SMARTStatus"]) ?? "Unknown",
                isSolidState: boolValue(info["SolidState"]),
                percentageUsed: percentageUsed,
                availableSpare: availableSpare,
                availableSpareThreshold: availableSpareThreshold,
                mediaErrors: mediaErrors,
                errorLogEntries: errorLogEntries,
                temperatureCelsius: temperatureCelsius,
                writtenTB: writtenTB,
                powerOnHours: powerOnHours,
                unsafeShutdowns: unsafeShutdowns
            )
        }.value
    }

    nonisolated private static func nvmeCounter(_ smart: [String: Any]?, _ key: String) -> UInt64? {
        guard let low = uintValue(smart?["\(key)_0"]) else { return nil }
        let high = uintValue(smart?["\(key)_1"]) ?? 0
        return (high << 32) + low
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        return nil
    }

    nonisolated private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    nonisolated private static func uintValue(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 { return value }
        if let value = value as? NSNumber { return value.uint64Value }
        if let value = value as? String { return UInt64(value) }
        return nil
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}

struct DiskIntegritySnapshot: Codable {
    let exitCode: Int32
    let summary: String

    var statusLabel: String {
        exitCode == 0 && summary.localizedCaseInsensitiveContains("appears to be OK") ? "Verified" : "Review"
    }
}

@MainActor
final class DiskIntegrityService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var snapshot: DiskIntegritySnapshot?
    @Published private(set) var status = "Ready"
    @Published private(set) var lastUsedAt: Date?

    private var checkTask: Task<Void, Never>?
    private static let persistenceKey = "MacCleaner.Diagnostics.DiskIntegrity.lastSnapshot"

    init() {
        guard let stored = DiagnosticPersistence.load(DiskIntegritySnapshot.self, key: Self.persistenceKey) else { return }
        lastUsedAt = stored.lastUsedAt
        snapshot = stored.value
        status = stored.value?.statusLabel ?? "Verification unavailable"
    }

    func runVerify() {
        guard !isRunning else { return }
        isRunning = true
        status = "Verifying APFS"

        checkTask?.cancel()
        checkTask = Task {
            let result = await Self.verifyVolume()
            guard !Task.isCancelled else { return }
            snapshot = result
            status = result == nil ? "Verification unavailable" : "Complete"
            lastUsedAt = DiagnosticPersistence.save(result, key: Self.persistenceKey)
            isRunning = false
            checkTask = nil
        }
    }

    func cancel() {
        checkTask?.cancel()
        checkTask = nil
        if isRunning {
            status = "Ready"
            isRunning = false
        }
    }

    nonisolated private static func verifyVolume() async -> DiskIntegritySnapshot? {
        await Task.detached(priority: .utility) {
            guard let result = HardwareDiagnosticCommand.runString("/usr/sbin/diskutil", arguments: ["verifyVolume", "/"], timeout: 25) else {
                return nil
            }
            let lines = result.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let summary = lines.last(where: { $0.localizedCaseInsensitiveContains("appears to be OK") })
                ?? lines.last(where: { $0.localizedCaseInsensitiveContains("error") })
                ?? lines.last
                ?? "No verification output"
            return DiskIntegritySnapshot(exitCode: result.exitCode, summary: summary)
        }.value
    }
}

struct AdvancedSSDSnapshot: Codable {
    let isAvailable: Bool
    let status: String
    let criticalWarning: String?
    let percentageUsed: String?
    let availableSpare: String?
    let availableSpareThreshold: String?
    let temperature: String?
    let dataWritten: String?
    let mediaErrors: String?
    let errorLogEntries: String?
    let detail: String

    var statusLabel: String {
        guard isAvailable else { return "Not installed" }
        if let criticalWarning, criticalWarning != "0x00" { return "Warning" }
        if let mediaErrors, Int(mediaErrors) ?? 0 > 0 { return "Media errors" }
        if let availableSparePercent, let availableSpareThresholdPercent, availableSparePercent <= availableSpareThresholdPercent { return "Low spare" }
        if let usedPercent, usedPercent >= 80 { return "High wear" }
        if let usedPercent, usedPercent >= 50 { return "Moderate wear" }
        if status.localizedCaseInsensitiveContains("PASSED") { return "Passed" }
        return status.isEmpty ? "Complete" : status
    }

    var usedPercent: Int? {
        Self.percentValue(percentageUsed)
    }

    var availableSparePercent: Int? {
        Self.percentValue(availableSpare)
    }

    var availableSpareThresholdPercent: Int? {
        Self.percentValue(availableSpareThreshold)
    }

    private static func percentValue(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}

@MainActor
final class AdvancedSSDService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var snapshot: AdvancedSSDSnapshot?
    @Published private(set) var status = "Requires smartmontools"
    @Published private(set) var lastUsedAt: Date?

    private var checkTask: Task<Void, Never>?
    private static let persistenceKey = "MacCleaner.Diagnostics.AdvancedSSD.lastSnapshot"

    init() {
        guard let stored = DiagnosticPersistence.load(AdvancedSSDSnapshot.self, key: Self.persistenceKey) else { return }
        lastUsedAt = stored.lastUsedAt
        snapshot = stored.value
        status = stored.value?.statusLabel ?? "Requires smartmontools"
    }

    func runDeepCheck() {
        guard !isRunning else { return }
        isRunning = true
        status = "Requesting admin"

        checkTask?.cancel()
        checkTask = Task {
            let result = await Self.collectSnapshot()
            guard !Task.isCancelled else { return }
            snapshot = result
            status = result.statusLabel
            lastUsedAt = DiagnosticPersistence.save(result, key: Self.persistenceKey)
            isRunning = false
            checkTask = nil
        }
    }

    func cancel() {
        checkTask?.cancel()
        checkTask = nil
        if isRunning {
            status = snapshot?.statusLabel ?? "Requires smartmontools"
            isRunning = false
        }
    }

    nonisolated private static func collectSnapshot() async -> AdvancedSSDSnapshot {
        await Task.detached(priority: .utility) {
            guard let smartctl = smartctlPath() else {
                return AdvancedSSDSnapshot(
                    isAvailable: false,
                    status: "Not installed",
                    criticalWarning: nil,
                    percentageUsed: nil,
                    availableSpare: nil,
                    availableSpareThreshold: nil,
                    temperature: nil,
                    dataWritten: nil,
                    mediaErrors: nil,
                    errorLogEntries: nil,
                    detail: "Install smartmontools with Homebrew to enable deep NVMe SMART."
                )
            }

            guard let result = HardwareDiagnosticCommand.runAdminString(smartctl, arguments: ["-a", "/dev/disk0"], timeout: 45) else {
                return AdvancedSSDSnapshot(
                    isAvailable: true,
                    status: "Permission denied",
                    criticalWarning: nil,
                    percentageUsed: nil,
                    availableSpare: nil,
                    availableSpareThreshold: nil,
                    temperature: nil,
                    dataWritten: nil,
                    mediaErrors: nil,
                    errorLogEntries: nil,
                    detail: "Admin permission is required to run smartctl."
                )
            }

            let output = result.output
            return AdvancedSSDSnapshot(
                isAvailable: true,
                status: firstValue(in: output, prefixes: ["SMART overall-health self-assessment test result:"]) ?? (result.exitCode == 0 ? "Complete" : "Review"),
                criticalWarning: firstValue(in: output, prefixes: ["Critical Warning:"]),
                percentageUsed: firstValue(in: output, prefixes: ["Percentage Used:"]),
                availableSpare: firstValue(in: output, prefixes: ["Available Spare:"]),
                availableSpareThreshold: firstValue(in: output, prefixes: ["Available Spare Threshold:"]),
                temperature: firstValue(in: output, prefixes: ["Temperature:"]),
                dataWritten: firstValue(in: output, prefixes: ["Data Units Written:"]),
                mediaErrors: firstValue(in: output, prefixes: ["Media and Data Integrity Errors:"]),
                errorLogEntries: firstValue(in: output, prefixes: ["Error Information Log Entries:"]),
                detail: "Deep SMART via smartctl. Exit \(result.exitCode). Requires admin."
            )
        }.value
    }

    nonisolated private static func smartctlPath() -> String? {
        [
            "/opt/homebrew/sbin/smartctl",
            "/opt/homebrew/bin/smartctl",
            "/usr/local/sbin/smartctl",
            "/usr/local/bin/smartctl",
            "/usr/sbin/smartctl",
            "/usr/bin/smartctl"
        ]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func firstValue(in output: String, prefixes: [String]) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in prefixes where trimmed.hasPrefix(prefix) {
                let value = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}

struct ThermalPowerSnapshot: Codable {
    let thermalPressure: String?
    let cpuPower: String?
    let gpuPower: String?
    let packagePower: String?
    let exitCode: Int32?
    let detail: String

    var statusLabel: String {
        if let exitCode, exitCode != 0 { return "Review" }
        guard let thermalPressure else { return "Unavailable" }
        if thermalPressure.localizedCaseInsensitiveContains("critical") { return "Critical" }
        if thermalPressure.localizedCaseInsensitiveContains("heavy") { return "Heavy" }
        if thermalPressure.localizedCaseInsensitiveContains("serious") { return "Serious" }
        return thermalPressure
    }
}

@MainActor
final class ThermalPowerService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var snapshot: ThermalPowerSnapshot?
    @Published private(set) var status = "Requires admin"
    @Published private(set) var lastUsedAt: Date?

    private var checkTask: Task<Void, Never>?
    private static let persistenceKey = "MacCleaner.Diagnostics.ThermalPower.lastSnapshot"

    init() {
        guard let stored = DiagnosticPersistence.load(ThermalPowerSnapshot.self, key: Self.persistenceKey) else { return }
        lastUsedAt = stored.lastUsedAt
        snapshot = stored.value
        status = stored.value?.statusLabel ?? "Requires admin"
    }

    func runSnapshot() {
        guard !isRunning else { return }
        isRunning = true
        status = "Requesting admin"

        checkTask?.cancel()
        checkTask = Task {
            let result = await Self.collectSnapshot()
            guard !Task.isCancelled else { return }
            snapshot = result
            status = result?.statusLabel ?? "Unavailable"
            lastUsedAt = DiagnosticPersistence.save(result, key: Self.persistenceKey)
            isRunning = false
            checkTask = nil
        }
    }

    func cancel() {
        checkTask?.cancel()
        checkTask = nil
        if isRunning {
            status = snapshot?.statusLabel ?? "Requires admin"
            isRunning = false
        }
    }

    nonisolated private static func collectSnapshot() async -> ThermalPowerSnapshot? {
        await Task.detached(priority: .utility) {
            guard let result = HardwareDiagnosticCommand.runAdminString(
                "/usr/bin/powermetrics",
                arguments: ["--samplers", "cpu_power,gpu_power,thermal", "-i", "1000", "-n", "3"],
                timeout: 45
            ) else {
                return ThermalPowerSnapshot(
                    thermalPressure: nil,
                    cpuPower: nil,
                    gpuPower: nil,
                    packagePower: nil,
                    exitCode: nil,
                    detail: "Admin permission is required to run powermetrics."
                )
            }

            let output = result.output
            return ThermalPowerSnapshot(
                thermalPressure: lastValue(in: output, contains: "Thermal pressure:"),
                cpuPower: lastValue(in: output, contains: "CPU Power:"),
                gpuPower: lastValue(in: output, contains: "GPU Power:"),
                packagePower: lastValue(in: output, contains: "Combined Power"),
                exitCode: result.exitCode,
                detail: "powermetrics sample. Exit \(result.exitCode). Requires admin."
            )
        }.value
    }

    nonisolated private static func lastValue(in output: String, contains marker: String) -> String? {
        var found: String?
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = trimmed.range(of: marker, options: .caseInsensitive) else { continue }
            let value = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                found = value
            }
        }
        return found
    }
}

struct NetworkDiagnosticSnapshot: Codable {
    let publicIP: String?
    let provider: String?
    let location: String?
    let edge: String?
    let httpProtocol: String?
    let tlsVersion: String?
    let latencyMS: Double?
    let jitterMS: Double?
    let downloadMbps: Double?
    let uploadMbps: Double?
    let packetLossPercent: Double?

    var internetReachable: Bool {
        latencyMS != nil || downloadMbps != nil || uploadMbps != nil
    }

    var statusLabel: String {
        if downloadMbps != nil, uploadMbps != nil { return "Complete" }
        if internetReachable { return "Partial" }
        return "Offline"
    }

    var detailLabel: String {
        var parts: [String] = []
        if let provider { parts.append(provider) }
        if let location { parts.append(location) }
        if let edge { parts.append("Cloudflare \(edge)") }
        if let httpProtocol { parts.append(httpProtocol) }
        if let tlsVersion { parts.append(tlsVersion) }
        return parts.isEmpty ? "Uses Cloudflare endpoints for speed and trace checks." : parts.joined(separator: " · ")
    }
}

@MainActor
final class NetworkDiagnosticService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var snapshot: NetworkDiagnosticSnapshot?
    @Published private(set) var status = "Ready"
    @Published private(set) var lastUsedAt: Date?

    private var checkTask: Task<Void, Never>?
    private static let persistenceKey = "MacCleaner.Diagnostics.Network.lastSnapshot"

    init() {
        guard let stored = DiagnosticPersistence.load(NetworkDiagnosticSnapshot.self, key: Self.persistenceKey) else { return }
        lastUsedAt = stored.lastUsedAt
        snapshot = stored.value
        status = stored.value?.statusLabel ?? "Offline"
    }

    func runQuickTest() {
        guard !isRunning else { return }
        isRunning = true
        status = "Resolving IP"

        checkTask?.cancel()
        checkTask = Task {
            let result = await Self.collectSnapshot { [weak self] phase in
                Task { @MainActor in
                    self?.status = phase
                }
            }
            guard !Task.isCancelled else { return }
            snapshot = result
            status = result.statusLabel
            lastUsedAt = DiagnosticPersistence.save(result, key: Self.persistenceKey)
            isRunning = false
            checkTask = nil
        }
    }

    func cancel() {
        checkTask?.cancel()
        checkTask = nil
        if isRunning {
            status = "Ready"
            isRunning = false
        }
    }

    nonisolated private static func collectSnapshot(_ progress: @escaping @Sendable (String) -> Void) async -> NetworkDiagnosticSnapshot {
        progress("Resolving IP")
        async let traceTask = fetchCloudflareTrace()
        async let ipInfoTask = fetchIPInfo()

        progress("Measuring latency")
        let latency = await measureLatency()

        progress("Testing download")
        let download = await measureDownload()

        progress("Testing upload")
        let upload = await measureUpload()

        let trace = await traceTask
        let ipInfo = await ipInfoTask
        let location = [ipInfo["city"], ipInfo["region"], ipInfo["country"]]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")

        return NetworkDiagnosticSnapshot(
            publicIP: trace["ip"] ?? ipInfo["ip"],
            provider: ipInfo["org"],
            location: location.isEmpty ? trace["loc"] : location,
            edge: trace["colo"],
            httpProtocol: trace["http"],
            tlsVersion: trace["tls"],
            latencyMS: latency.average,
            jitterMS: latency.jitter,
            downloadMbps: download,
            uploadMbps: upload,
            packetLossPercent: latency.packetLossPercent
        )
    }

    nonisolated private static func fetchCloudflareTrace() async -> [String: String] {
        guard let text = await fetchText("https://cloudflare.com/cdn-cgi/trace", timeout: 5) else { return [:] }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0]] = parts[1]
        }
        return values
    }

    nonisolated private static func fetchIPInfo() async -> [String: String] {
        guard let data = await fetchData("https://ipinfo.io/json", timeout: 5, method: "GET", body: nil)?.data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object.compactMapValues { value in
            if let string = value as? String, !string.isEmpty { return string }
            return nil
        }
    }

    nonisolated private static func measureLatency() async -> (average: Double?, jitter: Double?, packetLossPercent: Double?) {
        var samples: [Double] = []
        let attempts = 5
        for index in 0..<attempts {
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=1000&r=\(UUID().uuidString)-\(index)") else { continue }
            let started = Date()
            guard let result = await fetchData(url.absoluteString, timeout: 5, method: "GET", body: nil),
                  (200..<400).contains(result.statusCode)
            else { continue }
            samples.append(Date().timeIntervalSince(started) * 1000)
        }
        guard !samples.isEmpty else { return (nil, nil, 100) }
        let average = samples.reduce(0, +) / Double(samples.count)
        let jitter: Double
        if samples.count > 1 {
            let deltas = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
            jitter = deltas.reduce(0, +) / Double(deltas.count)
        } else {
            jitter = 0
        }
        let loss = Double(attempts - samples.count) / Double(attempts) * 100
        return (average, jitter, loss)
    }

    nonisolated private static func measureDownload() async -> Double? {
        let sizes = [1_000_000, 5_000_000, 10_000_000]
        var results: [Double] = []
        for size in sizes {
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(size)&r=\(UUID().uuidString)") else { continue }
            let started = Date()
            guard let result = await fetchData(url.absoluteString, timeout: 20, method: "GET", body: nil),
                  (200..<400).contains(result.statusCode),
                  result.data.count > 0
            else { continue }
            let seconds = max(0.001, Date().timeIntervalSince(started))
            results.append((Double(result.data.count) * 8) / seconds / 1_000_000)
        }
        return representativeMbps(results)
    }

    nonisolated private static func measureUpload() async -> Double? {
        let sizes = [500_000, 1_000_000, 2_000_000]
        var results: [Double] = []
        for size in sizes {
            let body = Data(repeating: 0xA5, count: size)
            let started = Date()
            guard let result = await fetchData("https://speed.cloudflare.com/__up?r=\(UUID().uuidString)", timeout: 20, method: "POST", body: body),
                  (200..<400).contains(result.statusCode)
            else { continue }
            let seconds = max(0.001, Date().timeIntervalSince(started))
            results.append((Double(size) * 8) / seconds / 1_000_000)
        }
        return representativeMbps(results)
    }

    nonisolated private static func representativeMbps(_ samples: [Double]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    nonisolated private static func fetchText(_ urlString: String, timeout: TimeInterval) async -> String? {
        guard let result = await fetchData(urlString, timeout: timeout, method: "GET", body: nil) else { return nil }
        return String(data: result.data, encoding: .utf8)
    }

    nonisolated private static func fetchData(_ urlString: String, timeout: TimeInterval, method: String, body: Data?) async -> (data: Data, statusCode: Int)? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.httpBody = body
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            let session = URLSession(configuration: configuration)
            let (data, response) = try await session.data(for: request)
            session.invalidateAndCancel()
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, statusCode)
        } catch {
            return nil
        }
    }
}
