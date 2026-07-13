import AppKit
import SwiftUI

struct SpeakerTestPanel: View {
    @ObservedObject private var service: SpeakerTestService

    init(service: SpeakerTestService) {
        self._service = ObservedObject(wrappedValue: service)
    }

    var body: some View {
        DiagnosticPanelShell(
            icon: "speaker.wave.3",
            title: "Audio System Check",
            subtitle: "Output route, channel balance, sweep and rattle checks.",
            status: service.isPlaying ? "Playing" : service.healthStatus,
            statusColor: statusColor
        ) {
            VStack(alignment: .leading, spacing: 12) {
                outputOverview

                HStack(alignment: .top, spacing: 12) {
                    testGroup(
                        title: "Channel Check",
                        subtitle: "Confirm left, right and stereo routing.",
                        modes: SpeakerTestMode.quickModes
                    )

                    testGroup(
                        title: "Sound Quality",
                        subtitle: "Listen for buzz, crackle or missing ranges.",
                        modes: SpeakerTestMode.diagnosticModes
                    )
                }

                resultBanner
            }
        }
        .onAppear {
            service.refreshOutput()
        }
        .onDisappear {
            service.stop()
        }
    }

    private var outputOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: service.outputInfo.isBuiltIn ? "laptopcomputer" : "hifispeaker")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(statusColor.opacity(0.10)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(service.outputInfo.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                    Text("Testing \(service.outputInfo.routeSummary) output · \(service.outputInfo.formatSummary)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                }

                Spacer()

                lastUsedBadge(service.lastUsedAt)

                Button {
                    service.refreshOutput()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondaryLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.045)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                metricTile("Route", service.outputInfo.routeSummary, statusColor, info: "Shows where macOS is sending sound right now.\nFor MacBook speaker checks, Built-in is the expected route. Bluetooth, HDMI or USB means you are testing an external output instead.")
                metricTile("Format", service.outputInfo.formatSummary, .accentBlue, info: "Shows the current audio channel count and sample rate.\nFor left/right checks, 2 ch stereo is required. 44.1 or 48 kHz is normal; fewer than 2 channels makes the channel test unreliable.")
                metricTile("Volume", service.outputInfo.volumeSummary, volumeColor, info: "Shows how loud the speaker test will be.\n30-70% is usually clear without being harsh. Below 20% can hide quiet crackle or a weak channel. Muted or near 0% makes the test invalid.")
                metricTile("Balance", service.outputInfo.balance, balanceColor, info: "Shows how sound is split between left and right.\nCenter, or a difference under about 6%, is normal. A strong left/right shift can make a healthy speaker seem broken.")
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.black.opacity(0.026))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.borderLight, lineWidth: 1))
        )
    }

    private func testGroup(title: String, subtitle: String, modes: [SpeakerTestMode]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(1)
            }

            VStack(spacing: 7) {
                ForEach(modes) { mode in
                    speakerTestButton(for: mode)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speakerTestButton(for mode: SpeakerTestMode) -> some View {
        let active = service.activeMode == mode
        return Button {
            service.play(mode)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? Color.white : Color.accentBlue)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color.white.opacity(0.18) : Color.accentBlue.opacity(0.10)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Color.white : Color.textPrimaryLight)
                    Text(mode.description)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(active ? Color.white.opacity(0.78) : Color.textTertiaryLight)
                        .lineLimit(1)
                }

                Spacer()

                Text(active ? "Playing" : "\(Int(mode.duration))s")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(active ? Color.white : Color.textTertiaryLight)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Color.accentBlue : Color.black.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.clear : Color.borderLight, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var resultBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: resultIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(statusColor.opacity(0.10)))

            VStack(alignment: .leading, spacing: 2) {
                Text(service.isPlaying ? service.status : "Result")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(service.isPlaying ? "Listen carefully and stop if you hear harsh distortion." : service.resultSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                service.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                    .frame(width: 31, height: 31)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.045)))
            }
            .buttonStyle(.plain)
            .disabled(!service.isPlaying)
            .opacity(service.isPlaying ? 1 : 0.55)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(statusColor.opacity(0.065))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(statusColor.opacity(0.18), lineWidth: 1))
        )
    }

    private var statusColor: Color {
        if service.isPlaying { return .accentBlue }
        switch service.outputInfo.issueLevel {
        case .good: return .accentGreen
        case .notice: return .accentAmber
        case .warning: return .accentRed
        }
    }

    private var volumeColor: Color {
        if service.outputInfo.isMuted == true { return .accentRed }
        guard let volume = service.outputInfo.volumePercent else { return .textTertiaryLight }
        if volume < 20 { return .accentAmber }
        return .accentGreen
    }

    private var balanceColor: Color {
        service.outputInfo.balance == "Center" ? .accentGreen : .accentAmber
    }

    private var resultIcon: String {
        switch service.outputInfo.issueLevel {
        case .good: return service.lastCompletedMode == nil ? "checkmark.circle" : "checkmark.seal"
        case .notice: return "exclamationmark.triangle"
        case .warning: return "xmark.octagon"
        }
    }
}

struct PointerInputTestPanel: View {
    @State private var position = CGPoint(x: 0.5, y: 0.5)
    @State private var movement: CGFloat
    @State private var lastPoint: CGPoint?
    @State private var clicks: Int
    @State private var scrollAmount: CGFloat
    @State private var lastAction: String
    @State private var lastUsedAt: Date?
    @State private var lastPersistedUse = Date.distantPast

    init() {
        let snapshot = PointerInputSnapshot.load()
        self._movement = State(initialValue: CGFloat(snapshot?.movement ?? 0))
        self._clicks = State(initialValue: snapshot?.clicks ?? 0)
        self._scrollAmount = State(initialValue: CGFloat(snapshot?.scrollAmount ?? 0))
        self._lastAction = State(initialValue: snapshot?.lastAction ?? "Move pointer over the pad")
        self._lastUsedAt = State(initialValue: snapshot?.lastUsedAt)
    }

    var body: some View {
        DiagnosticPanelShell(
            icon: "cursorarrow.motionlines",
            title: "Trackpad / Mouse Test",
            subtitle: "Movement, clicks and scroll events in one compact pad.",
            status: lastAction,
            statusColor: clicks > 0 || movement > 0 ? .accentGreen : .textTertiaryLight
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    metricTile("Movement", "\(Int(movement)) px", .accentBlue)
                    metricTile("Clicks", "\(clicks)", clicks > 0 ? .accentGreen : .textTertiaryLight)
                    metricTile("Scroll", "\(Int(scrollAmount))", abs(scrollAmount) > 0 ? .accentAmber : .textTertiaryLight)
                    Spacer()
                    lastUsedBadge(lastUsedAt)
                    Button {
                        reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondaryLight)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.045)))
                    }
                    .buttonStyle(.plain)
                }

                pointerPad
            }
        }
    }

    private var pointerPad: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.borderLight, lineWidth: 1))

                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(Color.borderLight.opacity(0.75))
                        .frame(height: 1)
                        .offset(y: CGFloat(index - 2) * geo.size.height / 5)
                    Rectangle()
                        .fill(Color.borderLight.opacity(0.75))
                        .frame(width: 1)
                        .offset(x: CGFloat(index - 2) * geo.size.width / 5)
                }

                Circle()
                    .fill(Color.accentBlue)
                    .frame(width: 14, height: 14)
                    .shadow(color: Color.accentBlue.opacity(0.35), radius: 8)
                    .position(x: position.x * geo.size.width, y: position.y * geo.size.height)

                Text("Move, click, right-click or scroll here")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.surfaceCardLight.opacity(0.92)))
                    .position(x: geo.size.width / 2, y: 20)

                PointerEventSurface(
                    onMove: { point, size in
                        updatePointer(point: point, size: size)
                    },
                    onClick: { action in
                        clicks += 1
                        lastAction = action
                        markUsed()
                    },
                    onScroll: { delta in
                        scrollAmount += delta
                        lastAction = "Scroll \(Int(delta))"
                        markUsed()
                    }
                )
            }
        }
        .frame(height: 260)
    }

    private func updatePointer(point: CGPoint, size: CGSize) {
        let normalized = CGPoint(
            x: min(1, max(0, point.x / max(1, size.width))),
            y: min(1, max(0, 1 - point.y / max(1, size.height)))
        )
        if let lastPoint {
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y
            movement += sqrt(dx * dx + dy * dy)
        }
        self.lastPoint = point
        position = normalized
        lastAction = "Pointer moving"
        markUsed(throttled: true)
    }

    private func reset() {
        position = CGPoint(x: 0.5, y: 0.5)
        movement = 0
        lastPoint = nil
        clicks = 0
        scrollAmount = 0
        lastAction = "Move pointer over the pad"
        markUsed()
    }

    private func markUsed(throttled: Bool = false) {
        let now = Date()
        lastUsedAt = now
        if throttled, now.timeIntervalSince(lastPersistedUse) < 1.0 {
            return
        }
        lastPersistedUse = now
        let snapshot = PointerInputSnapshot(
            movement: Double(movement),
            clicks: clicks,
            scrollAmount: Double(scrollAmount),
            lastAction: lastAction,
            lastUsedAt: now
        )
        snapshot.save()
    }
}

struct PointerInputSnapshot: Codable {
    let movement: Double
    let clicks: Int
    let scrollAmount: Double
    let lastAction: String
    let lastUsedAt: Date

    private static let persistenceKey = "MacCleaner.Diagnostics.PointerInput.lastState"

    static func load() -> PointerInputSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(PointerInputSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }
}

struct DeviceHealthPanel: View {
    @ObservedObject private var storageService: StorageHealthService
    @ObservedObject private var diskService: DiskIntegrityService
    @ObservedObject private var advancedSSDService: AdvancedSSDService
    @ObservedObject private var thermalService: ThermalPowerService

    init(storageService: StorageHealthService,
         diskService: DiskIntegrityService,
         advancedSSDService: AdvancedSSDService,
         thermalService: ThermalPowerService) {
        self._storageService = ObservedObject(wrappedValue: storageService)
        self._diskService = ObservedObject(wrappedValue: diskService)
        self._advancedSSDService = ObservedObject(wrappedValue: advancedSSDService)
        self._thermalService = ObservedObject(wrappedValue: thermalService)
    }

    var body: some View {
        VStack(spacing: 10) {
            StorageHealthPanel(service: storageService)
            DiskIntegrityPanel(service: diskService)
            AdvancedSSDPanel(service: advancedSSDService)
            ThermalPowerPanel(service: thermalService)
        }
    }
}

private struct StorageHealthPanel: View {
    @ObservedObject private var service: StorageHealthService

    init(service: StorageHealthService) {
        self._service = ObservedObject(wrappedValue: service)
    }

    var body: some View {
        DiagnosticPanelShell(
            icon: "internaldrive",
            title: "SSD / Storage Health",
            subtitle: "SMART status, wear estimate and degradation signals.",
            status: service.snapshot?.healthLabel ?? service.status,
            statusColor: storageColor
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    metricTile("SMART", service.snapshot?.smartStatus ?? "-", storageColor, info: "SMART is the SSD's built-in self-check.\nVerified means the drive is not reporting a problem. Unknown should be checked with another test. Failure or attention means back up and recheck.")
                    metricTile("Wear", service.snapshot?.wearLabel ?? "-", storageColor, info: "Shows how much of the SSD's estimated lifetime is already used.\nUnder 50% is usually calm. 50-79% deserves closer watching. 80% or more is high wear and makes backups more important.")
                    metricTile("Spare", service.snapshot?.spareLabel ?? "-", spareColor, info: "Shows reserve SSD cells used when older cells wear out.\nHigher is better. The important comparison is the spare threshold reported by the SSD; at or below that threshold, back up and recheck.")
                    metricTile("Errors", service.snapshot?.errorLabel ?? "-", errorColor, info: "Shows storage or media errors reported by the drive.\n0 is the expected result. Anything above 0 should be rechecked; a growing count is more serious than an old single event.")
                    Spacer()
                    runButton(title: service.isRunning ? "Checking" : "Check SSD", icon: "stethoscope", disabled: service.isRunning) {
                        service.runQuickCheck()
                    }
                }

                HStack(spacing: 8) {
                    Text(service.snapshot?.detailLabel ?? "Reads drive SMART data when supported by macOS and the SSD controller.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    lastUsedBadge(service.lastUsedAt)
                }
            }
        }
    }

    private var storageColor: Color {
        guard let snapshot = service.snapshot else { return .textTertiaryLight }
        if snapshot.smartStatus != "Verified" { return .accentRed }
        if let errors = snapshot.mediaErrors, errors > 0 { return .accentRed }
        if let spare = snapshot.availableSpare,
           let threshold = snapshot.availableSpareThreshold,
           spare <= threshold { return .accentRed }
        if let wear = snapshot.percentageUsed, wear >= 80 { return .accentRed }
        if let wear = snapshot.percentageUsed, wear >= 50 { return .accentAmber }
        return .accentGreen
    }

    private var spareColor: Color {
        guard let spare = service.snapshot?.availableSpare else { return .textTertiaryLight }
        if let threshold = service.snapshot?.availableSpareThreshold {
            return spare <= threshold ? .accentRed : .accentGreen
        }
        if spare < 10 { return .accentRed }
        if spare < 25 { return .accentAmber }
        return .accentGreen
    }

    private var errorColor: Color {
        guard let errors = service.snapshot?.mediaErrors else { return .textTertiaryLight }
        return errors == 0 ? .accentGreen : .accentRed
    }
}

private struct DiskIntegrityPanel: View {
    @ObservedObject private var service: DiskIntegrityService

    init(service: DiskIntegrityService) {
        self._service = ObservedObject(wrappedValue: service)
    }

    var body: some View {
        DiagnosticPanelShell(
            icon: "checkmark.seal",
            title: "APFS Integrity",
            subtitle: "Read-only file system verification for the boot volume.",
            status: service.snapshot?.statusLabel ?? service.status,
            statusColor: integrityColor
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    metricTile("Result", service.snapshot?.statusLabel ?? "-", integrityColor, info: "APFS is the macOS file system: the way files and folders are organized on disk.\nVerified or OK means the volume map was checked without found errors. Review or error output means repeat the check and open Disk Utility.")
                    metricTile("Exit", service.snapshot.map { "\($0.exitCode)" } ?? "-", integrityColor, info: "This is the technical exit code from diskutil.\n0 usually means the verification finished successfully. Any other value means the command ended with an error, warning or incomplete result.")
                    Spacer()
                    runButton(title: service.isRunning ? "Verifying" : "Verify APFS", icon: "doc.text.magnifyingglass", disabled: service.isRunning) {
                        service.runVerify()
                    }
                }

                HStack(spacing: 8) {
                    Text(service.snapshot?.summary ?? "Runs diskutil verifyVolume in live read-only mode when requested.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    lastUsedBadge(service.lastUsedAt)
                }
            }
        }
    }

    private var integrityColor: Color {
        guard let snapshot = service.snapshot else { return .textTertiaryLight }
        return snapshot.statusLabel == "Verified" ? .accentGreen : .accentRed
    }
}

private struct AdvancedSSDPanel: View {
    @ObservedObject private var service: AdvancedSSDService

    init(service: AdvancedSSDService) {
        self._service = ObservedObject(wrappedValue: service)
    }

    var body: some View {
        DiagnosticPanelShell(
            icon: "lock.shield",
            title: "Deep SSD SMART",
            subtitle: "Detailed smartctl report. Requires admin and smartmontools.",
            status: service.snapshot?.statusLabel ?? service.status,
            statusColor: smartColor
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    metricTile("Health", service.snapshot?.statusLabel ?? "-", smartColor, info: "This reads deeper SSD SMART data through smartctl.\nPassed is a good sign: the SSD is not reporting critical faults. Complete without details should be compared with Warning, Used and Errors. Warning, failed or permission error means recheck with access and back up.")
                    metricTile("Warning", service.snapshot?.criticalWarning ?? "-", warningColor, info: "This is the NVMe hardware warning flag from the SSD.\n0x00 means no critical warning is raised. Any other value should be treated seriously: back up and repeat the SMART check.")
                    metricTile("Used", service.snapshot?.percentageUsed ?? "-", usedColor, info: "Shows the SSD wear estimate reported by firmware.\nUnder 50% is usually fine. 50-79% should be watched. 80% or more is high wear, especially if errors or warnings are also present.")
                    metricTile("Errors", service.snapshot?.mediaErrors ?? "-", errorColor, info: "Shows media or data integrity errors from SMART.\n0 is the expected result. Anything above 0 matters, especially if the number appears again after a fresh check.")
                    Spacer()
                    runButton(title: service.isRunning ? "Running" : "Run SMART", icon: "lock.open", disabled: service.isRunning) {
                        service.runDeepCheck()
                    }
                }

                HStack(spacing: 8) {
                    Text(detailText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    lastUsedBadge(service.lastUsedAt)
                }
            }
        }
    }

    private var detailText: String {
        guard let snapshot = service.snapshot else {
            return "Requires admin privileges. If unavailable, install smartmontools with Homebrew."
        }
        var parts = [snapshot.detail]
        if let spare = snapshot.availableSpare {
            if let threshold = snapshot.availableSpareThreshold {
                parts.append("Spare \(spare) / threshold \(threshold)")
            } else {
                parts.append("Spare \(spare)")
            }
        }
        if let temperature = snapshot.temperature {
            parts.append("Temp \(temperature)")
        }
        if let written = snapshot.dataWritten {
            parts.append("Written \(written)")
        }
        if let entries = snapshot.errorLogEntries {
            parts.append("Log \(entries)")
        }
        return parts.joined(separator: " · ")
    }

    private var smartColor: Color {
        guard let snapshot = service.snapshot else { return .textTertiaryLight }
        if !snapshot.isAvailable { return .accentAmber }
        if snapshot.statusLabel == "Passed" { return .accentGreen }
        if snapshot.statusLabel == "Moderate wear" { return .accentAmber }
        return snapshot.statusLabel == "Complete" ? .accentGreen : .accentRed
    }

    private var usedColor: Color {
        guard let used = service.snapshot?.usedPercent else { return .textTertiaryLight }
        if used >= 80 { return .accentRed }
        if used >= 50 { return .accentAmber }
        return .accentGreen
    }

    private var warningColor: Color {
        guard let warning = service.snapshot?.criticalWarning else { return .textTertiaryLight }
        return warning == "0x00" ? .accentGreen : .accentRed
    }

    private var errorColor: Color {
        guard let errors = service.snapshot?.mediaErrors, let count = Int(errors) else { return .textTertiaryLight }
        return count == 0 ? .accentGreen : .accentRed
    }
}

private struct ThermalPowerPanel: View {
    @ObservedObject private var service: ThermalPowerService

    init(service: ThermalPowerService) {
        self._service = ObservedObject(wrappedValue: service)
    }

    var body: some View {
        DiagnosticPanelShell(
            icon: "thermometer.medium",
            title: "Thermal / Power Snapshot",
            subtitle: "powermetrics sample for thermal pressure and power draw. Requires admin.",
            status: service.snapshot?.statusLabel ?? service.status,
            statusColor: thermalColor
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    metricTile("Thermal", service.snapshot?.thermalPressure ?? "-", thermalColor, info: "Shows how strongly macOS is managing heat.\nNominal or Fair is calm. Serious means check again after cooling. Heavy or Critical means the Mac is already limiting work because of temperature.")
                    metricTile("CPU", service.snapshot?.cpuPower ?? "-", .accentBlue, info: "Shows processor power during the sample.\nAt idle, under 10 W is usually calm. 10-25 W looks like active work. Above 25 W without a heavy task can explain heat and fan noise.")
                    metricTile("GPU", service.snapshot?.gpuPower ?? "-", .accentPurple, info: "Shows graphics power during the sample.\nAt idle, under 5 W is usually calm. 5-15 W can happen with graphics work. Above 15 W without video, games or 3D means check what is using the GPU.")
                    metricTile("Total", service.snapshot?.packagePower ?? "-", packageColor, info: "Shows combined package power from powermetrics when macOS reports it.\nIt is useful for judging overall heat load. A high value at idle usually means another process is working in the background.")
                    Spacer()
                    runButton(title: service.isRunning ? "Sampling" : "Sample", icon: "lock.open", disabled: service.isRunning) {
                        service.runSnapshot()
                    }
                }

                HStack(spacing: 8) {
                    Text(service.snapshot?.detail ?? "Runs a short powermetrics sample after macOS admin confirmation.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    lastUsedBadge(service.lastUsedAt)
                }
            }
        }
    }

    private var thermalColor: Color {
        guard let status = service.snapshot?.statusLabel else { return .textTertiaryLight }
        if ["Critical", "Heavy", "Serious"].contains(status) { return .accentRed }
        return .accentGreen
    }

    private var packageColor: Color {
        service.snapshot?.packagePower == nil ? .textTertiaryLight : .accentGreen
    }
}

struct NetworkTestPanel: View {
    @ObservedObject private var service: NetworkDiagnosticService
    @State private var testMode: NetworkDiagnosticService.TestMode = .quick
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator
    private let minimumContentHeight: CGFloat

    init(service: NetworkDiagnosticService, minimumContentHeight: CGFloat = 400) {
        self._service = ObservedObject(wrappedValue: service)
        self.minimumContentHeight = minimumContentHeight
    }

    var body: some View {
        DiagnosticPanelShell(
            icon: "network",
            title: "Network Speed Test",
            subtitle: "Cloudflare HTTP latency, download and upload check.",
            status: service.snapshot?.statusLabel ?? service.status,
            statusColor: networkColor
        ) {
            VStack(alignment: .leading, spacing: 14) {
                speedConsole
                Spacer(minLength: 0)
                latencyStrip
                Spacer(minLength: 0)
                networkProfile
            }
            .frame(minHeight: minimumContentHeight, alignment: .top)
        }
    }

    private var speedConsole: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(networkHeadline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                    Text(service.snapshot?.detailLabel ?? "Cloudflare edge sample with IP, latency and throughput checks.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                }

                Spacer()
                HStack(spacing: 7) {
                    Button {
                        modalCoordinator.present(title: "Network Test Mode", subtitle: "Choose the measurement depth") {
                            VStack(spacing: 8) {
                                ForEach(NetworkDiagnosticService.TestMode.allCases) { mode in
                                    Button {
                                        testMode = mode
                                        modalCoordinator.dismiss()
                                    } label: {
                                        HStack {
                                            Text(mode.rawValue); Spacer()
                                            if testMode == mode { Image(systemName: "checkmark").foregroundStyle(Color.accentBlue) }
                                        }
                                        .foregroundStyle(Color.textPrimaryLight)
                                        .padding(.horizontal, 14).frame(height: 42)
                                        .background(testMode == mode ? Color.accentBlue.opacity(0.08) : Color.surfaceCardLight)
                                        .overlay(Rectangle().strokeBorder(Color.borderLight))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    } label: {
                        HStack { Text(testMode.rawValue); Spacer(); Image(systemName: "rectangle.on.rectangle") }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondaryLight)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Color.surfaceCardLight)
                            .overlay(Rectangle().strokeBorder(Color.borderLight))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 138)
                    .disabled(service.isRunning)
                    lastUsedBadge(service.lastUsedAt)
                    qualityBadge
                }
            }

            HStack(alignment: .center, spacing: 10) {
                speedReadout(
                    title: "Download",
                    value: service.snapshot?.downloadMbps,
                    icon: "arrow.down.circle.fill",
                    color: .accentGreen,
                    info: "Shows how quickly this Mac receives data from the internet.\nThe app runs several Cloudflare transfers and shows a representative median result, not the single best spike. 50+ Mbps is comfortable for video, updates and large downloads."
                )

                startDial

                speedReadout(
                    title: "Upload",
                    value: service.snapshot?.uploadMbps,
                    icon: "arrow.up.circle.fill",
                    color: .accentAmber,
                    info: "Shows how quickly this Mac sends data to the internet.\nThe app runs several Cloudflare uploads and shows a representative median result, not the single best spike. 10+ Mbps is comfortable for calls and cloud sync."
                )
            }
        }
        .frame(minHeight: 224)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color.accentBlue.opacity(0.070), Color.accentGreen.opacity(0.045), Color.black.opacity(0.018)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentBlue.opacity(0.14), lineWidth: 1))
        )
    }

    private var startDial: some View {
        Button {
            service.runTest(mode: testMode)
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.055), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: testProgress)
                    .stroke(
                        LinearGradient(colors: [.accentBlue, .accentGreen], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: testProgress)

                VStack(spacing: 4) {
                    Text(service.isRunning ? "TESTING" : "GO")
                        .font(.system(size: service.isRunning ? 14 : 23, weight: .bold, design: .rounded))
                        .foregroundStyle(service.isRunning ? Color.accentBlue : Color.textPrimaryLight)
                        .tracking(0.8)
                    Text(service.isRunning ? service.status : "Start test")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                }
                .frame(width: 88)
            }
            .frame(width: 140, height: 140)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(service.isRunning)
        .help("Run \(testMode.rawValue.lowercased()) network test")
    }

    private func speedReadout(title: String, value: Double?, icon: String, color: Color, info: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiaryLight)
                MetricInfoButton(title: title, text: info)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(speedNumber(value))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(value == nil ? Color.textTertiaryLight : color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text("Mbps")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiaryLight)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.045))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * speedProgress(value))
                }
            }
            .frame(height: 4)

            Text(speedInterpretation(title: title, value: value))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 104)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.surfaceCardLight.opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.14), lineWidth: 1))
        )
    }

    private var latencyStrip: some View {
        HStack(spacing: 8) {
            latencyCard("Ping", msLabel(service.snapshot?.latencyMS), "speedometer", .accentBlue, "Shows HTTP request round-trip delay to Cloudflare, not raw ICMP ping.\nUnder 50 ms feels responsive. 50-120 ms is usable but less snappy. Above 120 ms is noticeable delay.")
            latencyCard("Jitter", msLabel(service.snapshot?.jitterMS), "waveform.path.ecg", jitterColor, "Shows how much ping changes between samples.\nUnder 20 ms is stable. 20-50 ms can cause call glitches. Above 50 ms often causes stutter.")
            latencyCard("Loss", lossLabel(service.snapshot?.packetLossPercent), "exclamationmark.triangle", lossColor, "Shows failed HTTP test requests during latency sampling, not low-level packet loss.\n0% is expected. Any non-zero value should be rechecked because it can indicate instability.")
            latencyCard("Protocol", service.snapshot?.httpProtocol ?? "-", "lock.icloud", .textSecondaryLight, "Shows the HTTP version used by the trace test.\nHTTP/3 and HTTP/2 are normal modern paths. HTTP/1.1 still works, but can indicate an older or limited route.")
        }
        .frame(minHeight: 54)
    }

    private func latencyCard(_ label: String, _ value: String, _ icon: String, _ color: Color, _ info: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
                MetricInfoButton(title: label, text: info)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.026))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight, lineWidth: 1))
        )
    }

    private var networkProfile: some View {
        HStack(spacing: 8) {
            profileItem("Public IP", service.snapshot?.publicIP ?? "-", "globe", .accentBlue, "Shows the address websites see from this connection.\nIt is expected to match your ISP, office network or VPN. An unexpected country or network usually means VPN, proxy or a different route.")
            profileItem("Provider / ASN", providerName, "building.2", .textSecondaryLight, "Shows who owns the public IP network.\nYour ISP, office network or VPN provider is normal. An unknown owner is a reason to check which network is active.")
            profileItem("Server", serverLabel, "server.rack", .accentGreen, "Shows the Cloudflare edge used for this test.\nA nearby city or region usually gives lower ping. A far server plus high ping can point to a routing issue.")
            profileItem("IP Location", service.snapshot?.location ?? "-", "location", .accentPurple, "Shows an approximate location from the public IP.\nIt can be wrong at city level. Country, provider and VPN status are the useful diagnostic signals.")
        }
        .frame(minHeight: 50)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.022))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight, lineWidth: 1))
        )
    }

    private func profileItem(_ label: String, _ value: String, _ icon: String, _ color: Color, _ info: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.10)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                    MetricInfoButton(title: label, text: info)
                }
                Text(value)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var networkHeadline: String {
        if service.isRunning { return service.status }
        guard let snapshot = service.snapshot else { return "Ready to measure connection quality" }
        if snapshot.statusLabel == "Complete" { return "Connection profile captured" }
        return snapshot.statusLabel
    }

    private var qualityText: String {
        guard let snapshot = service.snapshot, snapshot.internetReachable else { return "Not tested" }
        if let loss = snapshot.packetLossPercent, loss > 5 { return "Unstable" }
        if let jitter = snapshot.jitterMS, jitter > 50 { return "Unstable" }
        if let ping = snapshot.latencyMS, ping > 120 { return "Slow latency" }
        if let down = snapshot.downloadMbps, let up = snapshot.uploadMbps, down >= 50, up >= 10 { return "Strong" }
        return "Usable"
    }

    private var qualityColor: Color {
        switch qualityText {
        case "Strong": return .accentGreen
        case "Usable", "Slow latency": return .accentAmber
        case "Unstable": return .accentRed
        default: return .textTertiaryLight
        }
    }

    private var qualityBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(qualityColor)
                .frame(width: 8, height: 8)
            Text(qualityText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(qualityColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(qualityColor.opacity(0.10))
                .overlay(Capsule().strokeBorder(qualityColor.opacity(0.18), lineWidth: 1))
        )
        .help("Quality: A simple summary from speed, ping, jitter and packet loss. It is meant for quick troubleshooting, not provider billing.")
    }

    private var networkColor: Color {
        guard let snapshot = service.snapshot else { return .textTertiaryLight }
        if !snapshot.internetReachable { return .accentRed }
        return snapshot.statusLabel == "Complete" ? .accentGreen : .accentAmber
    }

    private var jitterColor: Color {
        guard let jitter = service.snapshot?.jitterMS else { return .textTertiaryLight }
        if jitter > 50 { return .accentRed }
        if jitter > 20 { return .accentAmber }
        return .accentGreen
    }

    private var lossColor: Color {
        guard let loss = service.snapshot?.packetLossPercent else { return .textTertiaryLight }
        if loss > 5 { return .accentRed }
        if loss > 0 { return .accentAmber }
        return .accentGreen
    }

    private var serverLabel: String {
        guard let edge = service.snapshot?.edge, !edge.isEmpty else { return "Cloudflare" }
        return "Cloudflare \(edge)"
    }

    private var providerName: String {
        guard let provider = service.snapshot?.provider, !provider.isEmpty else { return "-" }
        return provider.replacingOccurrences(of: #"^AS\d+\s+"#, with: "", options: .regularExpression)
    }

    private var testProgress: CGFloat {
        if service.isRunning {
            switch service.status {
            case "Resolving IP": return 0.16
            case "Measuring latency": return 0.34
            case "Testing download": return 0.66
            case "Testing upload": return 0.88
            default: return 0.22
            }
        }
        guard let snapshot = service.snapshot else { return 0.0 }
        return snapshot.statusLabel == "Complete" ? 1.0 : 0.52
    }

    private func speedNumber(_ value: Double?) -> String {
        guard let value else { return "-" }
        if value >= 100 { return "\(Int(value.rounded()))" }
        return String(format: "%.1f", value)
    }

    private func speedProgress(_ value: Double?) -> CGFloat {
        guard let value else { return 0 }
        return CGFloat(max(0.04, min(1, value / 500)))
    }

    private func speedInterpretation(title: String, value: Double?) -> String {
        guard let value else { return "Waiting for measurement" }
        if title == "Download" {
            if value < 10 { return "Slow for streaming and large downloads" }
            if value < 50 { return "Usable for browsing and HD video" }
            if value < 100 { return "Good for daily work" }
            return "Fast connection"
        }
        if value < 3 { return "Weak for video calls and cloud sync" }
        if value < 10 { return "Usable for light uploads" }
        if value < 30 { return "Good for calls and sync" }
        return "Strong upload"
    }

    private func msLabel(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(Int(value.rounded())) ms"
    }

    private func lossLabel(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value == 0 ? "0%" : String(format: "%.1f%%", value)
    }
}

private func lastUsedBadge(_ date: Date?) -> some View {
    HStack(spacing: 5) {
        Image(systemName: "clock")
            .font(.system(size: 9, weight: .semibold))
        Text(diagnosticLastUsedText(date))
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
    }
    .foregroundStyle(Color.textTertiaryLight)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
        Capsule()
            .fill(Color.black.opacity(0.035))
            .overlay(Capsule().strokeBorder(Color.borderLight, lineWidth: 1))
    )
    .help(diagnosticLastUsedHelp(date))
}

private func diagnosticLastUsedText(_ date: Date?) -> String {
    guard let date else { return "Last used: Never" }
    return "Last used: \(DiagnosticLastUsedFormatter.shared.string(from: date))"
}

private func diagnosticLastUsedHelp(_ date: Date?) -> String {
    guard let date else { return "This test has not been used yet." }
    return "Last used at \(DiagnosticLastUsedFormatter.shared.string(from: date))."
}

private enum DiagnosticLastUsedFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct DiagnosticPanelShell<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: String
    let statusColor: Color
    let content: Content

    init(icon: String,
         title: String,
         subtitle: String,
         status: String,
         statusColor: Color,
         @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.statusColor = statusColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentBlue.opacity(0.10)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondaryLight)
                }

                Spacer()

                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(statusColor.opacity(0.10)))
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceCardLight)
                .shadow(color: Color.shadowMedium, radius: 5, x: 0, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
    }
}

private func metricTile(_ label: String, _ value: String, _ color: Color, info: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
            if let info {
                MetricInfoButton(title: label, text: info)
            }
            Spacer(minLength: 0)
        }
        Text(value)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
    .frame(width: 110, alignment: .leading)
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.black.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight, lineWidth: 1))
    )
}

private struct MetricInfoButton: View {
    let title: String
    let text: String
    @State private var language: MetricInfoLanguage = .russian
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator

    var body: some View {
        Button {
            modalCoordinator.present(title: title, subtitle: "Metric information") {
                MetricInfoPopover(
                    title: title,
                    text: text,
                    language: $language,
                    close: modalCoordinator.dismiss
                )
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiaryLight)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Metric information")
    }
}

private enum MetricInfoLanguage: String, CaseIterable, Identifiable {
    case russian = "RU"
    case english = "EN"

    var id: String { rawValue }
}

private struct MetricInfoPopover: View {
    let title: String
    let text: String
    @Binding var language: MetricInfoLanguage
    let close: () -> Void

    private var localizedTitle: String {
        language == .english ? title : MetricInfoCopy.russianTitle(for: title)
    }

    private var localizedText: String {
        language == .english ? text : MetricInfoCopy.russianText(title: title, english: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(localizedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }

            AppSegmentedControl(
                selection: $language,
                options: MetricInfoLanguage.allCases,
                accentColor: .accentBlue,
                title: \.rawValue
            )
            .frame(width: 92)

            Text(localizedText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 334, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum MetricInfoCopy {
    static func russianTitle(for title: String) -> String {
        switch title {
        case "Download": return "Загрузка"
        case "Upload": return "Отдача"
        case "Ping": return "Пинг"
        case "Jitter": return "Дрожание"
        case "Loss": return "Потери"
        case "Protocol": return "Протокол"
        case "Public IP": return "Публичный IP"
        case "Provider / ASN": return "Провайдер / ASN"
        case "Server": return "Сервер"
        case "IP Location": return "Геолокация IP"
        case "Route": return "Маршрут"
        case "Format": return "Формат"
        case "Volume": return "Громкость"
        case "Balance": return "Баланс"
        case "SMART": return "SMART"
        case "Wear": return "Износ"
        case "Spare": return "Резерв"
        case "Errors": return "Ошибки"
        case "Result": return "Результат"
        case "Exit": return "Код выхода"
        case "Health": return "Состояние"
        case "Warning": return "Предупреждение"
        case "Used": return "Использовано"
        case "Thermal": return "Температура"
        case "CPU": return "CPU"
        case "GPU": return "GPU"
        case "Total": return "Всего"
        default: return title
        }
    }

    static func russianText(title: String, english: String) -> String {
        switch title {
        case "Download":
            return "Показывает, как быстро Mac получает данные из интернета.\nПриложение делает несколько загрузок через Cloudflare и показывает медианный результат, а не лучший всплеск. 50+ Мбит/с обычно хватает для видео, обновлений и больших загрузок."
        case "Upload":
            return "Показывает, как быстро Mac отправляет данные наружу.\nПриложение делает несколько отправок через Cloudflare и показывает медианный результат, а не лучший всплеск. 10+ Мбит/с комфортно для видеозвонков и облака."
        case "Ping":
            return "Это HTTP-задержка до Cloudflare: сколько занимает тестовый запрос туда и обратно.\nЭто не низкоуровневый ICMP ping. До 50 мс связь ощущается быстрой, 50–120 мс еще рабоче, выше 120 мс уже заметная задержка."
        case "Jitter":
            return "Jitter показывает, насколько пинг скачет между замерами.\nДо 20 мс соединение стабильное. 20–50 мс стоит проверить, если есть рывки в звонках. Выше 50 мс часто дает заикания и нестабильный звук."
        case "Loss":
            return "Показывает процент неуспешных HTTP-запросов во время проверки задержки.\nЭто не низкоуровневый packet loss. 0% — нормальный результат. Любое ненулевое значение лучше перепроверить: оно может указывать на нестабильность."
        case "Protocol":
            return "Это версия HTTP, через которую прошла проверка.\nHTTP/3 и HTTP/2 — современные нормальные варианты. HTTP/1.1 тоже работает, но иногда говорит о более старом или ограниченном маршруте."
        case "Public IP":
            return "Это адрес, под которым ваш Mac виден сайтам в интернете.\nЕсли он относится к вашему провайдеру, офисной сети или VPN — все ожидаемо. Неожиданная страна или сеть обычно означает включенный VPN, прокси или другой маршрут."
        case "Provider / ASN":
            return "Показывает, кому принадлежит публичная сеть этого IP.\nНормально видеть своего провайдера, офисную сеть или VPN. Если владелец незнакомый, проверьте, через какую сеть сейчас идет подключение."
        case "Server":
            return "Это ближайший edge-сервер Cloudflare, который использовался в тесте.\nБлизкий город или регион обычно дает низкий ping. Если сервер далеко и задержка высокая, маршрут сети может быть неоптимальным."
        case "IP Location":
            return "Это примерная география по публичному IP, а не точное место Mac.\nГород может быть неточным. Страна, провайдер и наличие VPN обычно важнее для диагностики."
        case "Route":
            return "Показывает, куда macOS сейчас отправляет звук.\nДля проверки динамиков MacBook ожидается Built-in. Если выбран Bluetooth, HDMI или USB, вы проверяете внешний выход, а не встроенные динамики."
        case "Format":
            return "Это формат текущего аудиовыхода: число каналов и частота.\nДля проверки левого и правого динамика нужен стереовыход 2 ch. 44.1 или 48 кГц — обычная норма; меньше 2 каналов делает L/R-тест бессмысленным."
        case "Volume":
            return "Показывает громкость, с которой будет слышен тест.\n30–70% обычно достаточно: звук слышен, но не перегружен. Ниже 20% легко пропустить треск или тихий канал. Muted или почти 0% делает тест недостоверным."
        case "Balance":
            return "Баланс распределяет звук между левым и правым каналом.\nCenter или разница до 6% выглядит нормально. Сильный сдвиг влево или вправо может создать ощущение, что один динамик сломан."
        case "SMART":
            return "SMART — встроенная самодиагностика SSD.\nVerified означает, что накопитель не сообщает о проблемах. Unknown стоит перепроверить другой диагностикой. Failure или attention — повод сделать резервную копию и повторить проверку."
        case "Wear":
            return "Это оценка уже использованного ресурса SSD.\nДо 50% обычно спокойно. 50–79% стоит наблюдать чаще. 80% и выше означает заметный износ: важны backup и повторная проверка."
        case "Spare":
            return "Spare — запасные ячейки SSD, которые заменяют изношенные.\nЧем выше значение, тем лучше. Важнее всего сравнение с threshold, который сообщает сам SSD: если spare на пороге или ниже него, нужен backup и повторная проверка."
        case "Errors":
            if english.localizedCaseInsensitiveContains("media") {
                return "Это ошибки носителя или целостности данных, которые сообщил SSD.\n0 — нормальный результат. Любое число больше 0 важно перепроверить; рост счетчика опаснее единичного старого события."
            }
            return "Это ошибки хранения, которые накопитель отдал в диагностике.\n0 — хороший результат. Если значение больше 0 или повторяется после новой проверки, лучше сделать backup и проверить SSD глубже."
        case "Result":
            return "APFS — файловая система macOS, то есть способ, которым диск хранит файлы и папки.\nVerified или OK означает, что карта тома читается корректно и проверка не нашла ошибок. Review или error — повод повторить проверку и открыть Disk Utility."
        case "Exit":
            return "Это технический код завершения команды diskutil.\n0 обычно значит, что проверка прошла успешно. Любое другое число означает, что команда завершилась с ошибкой, предупреждением или неполным результатом."
        case "Health":
            return "Эта проверка читает глубокие SMART-данные SSD через smartctl.\nPassed — хороший знак: SSD не сообщает о критичных сбоях. Complete без деталей лучше сверить с Warning, Used и Errors. Warning, failed или permission error — повод повторить проверку с доступом и сделать backup."
        case "Warning":
            return "Это аппаратный warning-флаг NVMe SSD.\n0x00 означает, что диск не поднял критическое предупреждение. Любое другое значение лучше считать тревожным: сделайте backup и повторите SMART-проверку."
        case "Used":
            return "Это оценка износа SSD, которую сообщает прошивка накопителя.\nДо 50% обычно нормально. 50–79% требует наблюдения. 80% и выше — высокий износ, особенно если рядом есть ошибки или warning."
        case "Thermal":
            return "Thermal pressure показывает, насколько macOS приходится сдерживать нагрев.\nNominal или Fair — спокойное состояние. Serious стоит проверить после охлаждения. Heavy или Critical означает, что Mac уже сильно ограничивает работу из-за температуры."
        case "CPU":
            return "Показывает, сколько мощности потреблял процессор во время замера.\nВ простое до 10 Вт обычно нормально. 10–25 Вт похоже на активную работу. 25+ Вт без тяжелой задачи может объяснять нагрев и шум."
        case "GPU":
            return "Показывает, сколько мощности потребляла графика во время замера.\nВ простое до 5 Вт обычно спокойно. 5–15 Вт бывает при активной графике. 15+ Вт без видео, игр или 3D — повод проверить нагрузку."
        case "Total":
            return "Показывает суммарную мощность package из powermetrics, если macOS ее отдала.\nЭто полезно для общей оценки тепловой нагрузки. Высокое значение в простое обычно означает, что какой-то процесс работает в фоне."
        default:
            return english
        }
    }
}

private func runButton(title: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(disabled ? Color.textTertiaryLight : Color.accentBlue))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
}

private struct PointerEventSurface: NSViewRepresentable {
    let onMove: (CGPoint, CGSize) -> Void
    let onClick: (String) -> Void
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onMove = onMove
        view.onClick = onClick
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: SurfaceView, context: Context) {
        nsView.onMove = onMove
        nsView.onClick = onClick
        nsView.onScroll = onScroll
    }

    final class SurfaceView: NSView {
        var onMove: ((CGPoint, CGSize) -> Void)?
        var onClick: ((String) -> Void)?
        var onScroll: ((CGFloat) -> Void)?
        private var tracking: NSTrackingArea?
        private var lastMoveReport = Date.distantPast

        override var acceptsFirstResponder: Bool { true }

        deinit {
            removeCurrentTrackingArea()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                removeCurrentTrackingArea()
                onMove = nil
                onClick = nil
                onScroll = nil
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            removeCurrentTrackingArea()
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tracking = area
        }

        override func mouseMoved(with event: NSEvent) { reportMove(event) }
        override func mouseDragged(with event: NSEvent) { reportMove(event) }
        override func rightMouseDragged(with event: NSEvent) { reportMove(event) }
        override func otherMouseDragged(with event: NSEvent) { reportMove(event) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onClick?("Left click")
        }

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onClick?("Right click")
        }

        override func otherMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onClick?("Aux click")
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY)
        }

        private func reportMove(_ event: NSEvent) {
            let now = Date()
            guard now.timeIntervalSince(lastMoveReport) >= 0.025 else { return }
            lastMoveReport = now
            let point = convert(event.locationInWindow, from: nil)
            onMove?(point, bounds.size)
        }

        private func removeCurrentTrackingArea() {
            guard let tracking else { return }
            if trackingAreas.contains(where: { $0 === tracking }) {
                removeTrackingArea(tracking)
            }
            self.tracking = nil
        }
    }
}
