import CryptoKit
import Darwin
import Foundation

enum StartupItemLocation: String, Sendable {
    case enabled = "Enabled"
    case disabled = "Disabled by MacCleaner"
}

enum StartupImpact: String, Sendable {
    case high = "High impact"
    case medium = "Medium impact"
    case low = "Low impact"
}

struct StartupAgentItem: Identifiable, Hashable, Sendable {
    var id: String { url.standardizedFileURL.path }
    let url: URL
    let label: String
    let displayName: String
    let executablePath: String?
    let runAtLoad: Bool
    let keepAlive: Bool
    let startInterval: Int?
    let hasCalendarSchedule: Bool
    let location: StartupItemLocation
    let snapshotDigest: String
    let runningPID: Int32?
    let currentMemoryBytes: UInt64
    let currentCPUPercent: Double
    let impactScore: Int
    let parseWarning: String?

    var impact: StartupImpact {
        if impactScore >= 60 { return .high }
        if impactScore >= 30 { return .medium }
        return .low
    }

    var isRunning: Bool { runningPID != nil }

    var isProtected: Bool {
        let lower = label.lowercased()
        return lower.isEmpty
            || lower.hasPrefix("com.apple.")
            || lower == "com.maccleaner.app"
            || lower.contains("maccleaner")
            || !StartupOptimizerService.isValidLaunchdLabel(label)
    }

    var canDisable: Bool { location == .enabled && !isProtected && parseWarning == nil }
    var canRestore: Bool { location == .disabled }

    var scheduleSummary: String {
        var values: [String] = []
        if runAtLoad { values.append("at login") }
        if keepAlive { values.append("kept alive") }
        if let startInterval, startInterval > 0 {
            values.append("every \(StartupOptimizerService.formatInterval(startInterval))")
        }
        if hasCalendarSchedule { values.append("scheduled") }
        return values.isEmpty ? "on demand" : values.joined(separator: " · ")
    }

    var recommendation: String {
        if location == .disabled {
            return "Stored reversibly by MacCleaner. Restore it if the related app loses background sync, updates, or notifications."
        }
        if isProtected {
            return "Protected because the item belongs to macOS, MacCleaner, or lacks a valid launchd label."
        }
        if keepAlive && isRunning {
            return "launchd is configured to keep this process alive. Disable it only if you do not need its background sync or helper features."
        }
        if isRunning && currentMemoryBytes > 0 {
            return "Currently active. Disabling can stop its automatic relaunch and may release the measured RAM after launchd confirms shutdown."
        }
        if runAtLoad {
            return "Not consuming measured RAM now, but it is configured to start automatically at the next login."
        }
        return "Low current impact. Keep it enabled unless you recognize the owning app and do not need its background behavior."
    }
}

struct StartupScanResult: Sendable {
    let items: [StartupAgentItem]
    let runningCount: Int
    let highImpactCount: Int
    let measuredMemoryBytes: UInt64
    let duration: TimeInterval
}

@MainActor
final class StartupOptimizerService: ObservableObject {
    @Published private(set) var items: [StartupAgentItem] = []
    @Published var selectedItemIDs: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isMutating = false
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var confirmedReleasedBytes: UInt64 = 0
    @Published private(set) var resultMessage: String?

    private var scanTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?

    var enabledItems: [StartupAgentItem] { items.filter { $0.location == .enabled } }
    var disabledItems: [StartupAgentItem] { items.filter { $0.location == .disabled } }
    var runningCount: Int { items.filter { $0.location == .enabled && $0.isRunning }.count }
    var highImpactCount: Int { items.filter { $0.location == .enabled && $0.impact == .high }.count }
    var measuredMemoryBytes: UInt64 {
        var seenPIDs: Set<Int32> = []
        return items.reduce(0) { total, item in
            guard item.location == .enabled,
                  let pid = item.runningPID,
                  seenPIDs.insert(pid).inserted else { return total }
            return total &+ item.currentMemoryBytes
        }
    }
    var selectedCount: Int { selectedItemIDs.count }
    var selectedMeasuredMemoryBytes: UInt64 {
        var seenPIDs: Set<Int32> = []
        return items.filter { selectedItemIDs.contains($0.id) }.reduce(0) { total, item in
            guard let pid = item.runningPID, seenPIDs.insert(pid).inserted else { return total }
            return total &+ item.currentMemoryBytes
        }
    }

    func startScan() {
        guard !isScanning, !isMutating else { return }
        isScanning = true
        resultMessage = nil
        let home = FileManager.default.homeDirectoryForCurrentUser
        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.performScan(home: home)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(result)
            self.isScanning = false
            self.scanTask = nil
        }
    }

    func toggleSelection(_ item: StartupAgentItem) {
        guard item.canDisable, !isScanning, !isMutating else { return }
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func clearSelection() {
        selectedItemIDs = []
    }

    func disableSelected() {
        guard !isScanning, !isMutating else { return }
        let selected = items.filter { selectedItemIDs.contains($0.id) && $0.canDisable }
        guard !selected.isEmpty else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        isMutating = true
        resultMessage = nil
        mutationTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.performDisable(items: selected, home: home)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(result.scan)
            self.selectedItemIDs = []
            self.confirmedReleasedBytes = result.confirmedReleasedBytes
            self.isMutating = false
            self.mutationTask = nil

            var parts = ["Disabled \(result.disabledCount) startup item\(result.disabledCount == 1 ? "" : "s") reversibly"]
            if result.confirmedReleasedBytes > 0 {
                parts.append("matched processes with \(MemoryInfo.formatted(result.confirmedReleasedBytes)) of measured RSS exited")
            }
            if result.stillRunningCount > 0 {
                parts.append("\(result.stillRunningCount) will remain active until its app quits or the next login")
            }
            if result.failedCount > 0 { parts.append("\(result.failedCount) could not be changed") }
            self.resultMessage = parts.joined(separator: "; ") + "."
        }
    }

    func restore(_ item: StartupAgentItem) {
        guard item.canRestore, !isScanning, !isMutating else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        isMutating = true
        resultMessage = nil
        mutationTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.performRestore(item: item, home: home)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(result.scan)
            self.isMutating = false
            self.mutationTask = nil
            if result.restored {
                self.resultMessage = result.startedNow
                    ? "Restored \(item.displayName) and loaded it for this login session."
                    : "Restored \(item.displayName). launchd did not load it now, but it is enabled for its next scheduled start or login."
            } else {
                self.resultMessage = "Could not restore \(item.displayName): the file changed, its original path is occupied, or access was denied."
            }
        }
    }

    private func apply(_ result: StartupScanResult) {
        items = result.items
        lastScanDuration = result.duration
        let validIDs = Set(result.items.filter(\.canDisable).map(\.id))
        selectedItemIDs.formIntersection(validIDs)
    }

    deinit {
        scanTask?.cancel()
        mutationTask?.cancel()
    }
}

private struct StartupDisableResult: Sendable {
    let scan: StartupScanResult
    let disabledCount: Int
    let failedCount: Int
    let stillRunningCount: Int
    let confirmedReleasedBytes: UInt64
}

private struct StartupRestoreResult: Sendable {
    let scan: StartupScanResult
    let restored: Bool
    let startedNow: Bool
}

private struct StartupDisableOutcome: Sendable {
    let item: StartupAgentItem
    let moved: Bool
    let processStopped: Bool
}

extension StartupOptimizerService {
    nonisolated static func enabledRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    nonisolated static func disabledRoot(home: URL) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/MacCleaner/Disabled Startup Items",
            isDirectory: true
        )
    }

    nonisolated static func performScan(
        home: URL,
        processes suppliedProcesses: [ProcessNode]? = nil
    ) -> StartupScanResult {
        let startedAt = Date()
        let processes = suppliedProcesses ?? ProcessTreeService.fetchFlatProcesses(cachedWindows: [])
        var items: [StartupAgentItem] = []
        items.append(contentsOf: scanFolder(
            enabledRoot(home: home),
            location: .enabled,
            processes: processes
        ))
        items.append(contentsOf: scanFolder(
            disabledRoot(home: home),
            location: .disabled,
            processes: processes
        ))
        items.sort { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location == .enabled }
            if lhs.impactScore != rhs.impactScore { return lhs.impactScore > rhs.impactScore }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }

        var seenPIDs: Set<Int32> = []
        let measured = items.reduce(UInt64(0)) { total, item in
            guard item.location == .enabled,
                  let pid = item.runningPID,
                  seenPIDs.insert(pid).inserted else { return total }
            return total &+ item.currentMemoryBytes
        }
        return StartupScanResult(
            items: items,
            runningCount: items.filter { $0.location == .enabled && $0.isRunning }.count,
            highImpactCount: items.filter { $0.location == .enabled && $0.impact == .high }.count,
            measuredMemoryBytes: measured,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    nonisolated static func parseItem(
        at url: URL,
        location: StartupItemLocation,
        processes: [ProcessNode]
    ) -> StartupAgentItem? {
        guard url.pathExtension.lowercased() == "plist",
              let snapshot = fileSnapshot(url), snapshot.size <= 1_048_576,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else { return nil }

        let label = (dictionary["Label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let program = (dictionary["Program"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = dictionary["ProgramArguments"] as? [String]
        let executable = (program?.isEmpty == false ? program : arguments?.first)
        let runAtLoad = dictionary["RunAtLoad"] as? Bool ?? false
        let keepAlive = keepAliveIsEnabled(dictionary["KeepAlive"])
        let interval = (dictionary["StartInterval"] as? NSNumber)?.intValue
        let hasCalendarSchedule = dictionary["StartCalendarInterval"] != nil
        let matchedProcess = location == .enabled
            ? matchProcess(executablePath: executable, arguments: arguments ?? [], processes: processes)
            : nil
        let warning: String?
        if label.isEmpty {
            warning = "Missing launchd Label"
        } else if !isValidLaunchdLabel(label) {
            warning = "Invalid launchd Label"
        } else if executable == nil {
            warning = "Executable could not be identified"
        } else {
            warning = nil
        }
        let displayName = displayName(label: label, executablePath: executable, fallback: url.deletingPathExtension().lastPathComponent)
        let score = impactScore(
            memoryBytes: matchedProcess?.memoryBytes ?? 0,
            cpuPercent: matchedProcess?.cpuUsage ?? 0,
            isRunning: matchedProcess != nil,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            startInterval: interval,
            hasCalendarSchedule: hasCalendarSchedule
        )
        return StartupAgentItem(
            url: url.standardizedFileURL,
            label: label,
            displayName: displayName,
            executablePath: executable,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            startInterval: interval,
            hasCalendarSchedule: hasCalendarSchedule,
            location: location,
            snapshotDigest: snapshot.digest,
            runningPID: matchedProcess?.id,
            currentMemoryBytes: matchedProcess?.memoryBytes ?? 0,
            currentCPUPercent: matchedProcess?.cpuUsage ?? 0,
            impactScore: score,
            parseWarning: warning
        )
    }

    nonisolated static func impactScore(
        memoryBytes: UInt64,
        cpuPercent: Double,
        isRunning: Bool,
        runAtLoad: Bool,
        keepAlive: Bool,
        startInterval: Int?,
        hasCalendarSchedule: Bool = false
    ) -> Int {
        var score = isRunning ? 20 : 0
        score += min(Int(memoryBytes / (5 * 1_048_576)), 35)
        score += min(Int(max(cpuPercent, 0) * 2), 20)
        if keepAlive { score += 15 }
        if runAtLoad { score += 10 }
        if let startInterval, startInterval > 0, startInterval <= 900 { score += 10 }
        if hasCalendarSchedule { score += 5 }
        return min(score, 100)
    }

    nonisolated static func snapshotMatches(_ item: StartupAgentItem) -> Bool {
        fileSnapshot(item.url)?.digest == item.snapshotDigest
    }

    nonisolated static func isValidLaunchdLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 200 else { return false }
        return label.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || ".-_".unicodeScalars.contains($0)
        }
    }

    nonisolated static func formatInterval(_ seconds: Int) -> String {
        if seconds >= 3_600, seconds.isMultiple(of: 3_600) { return "\(seconds / 3_600)h" }
        if seconds >= 60, seconds.isMultiple(of: 60) { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    nonisolated private static func scanFolder(
        _ root: URL,
        location: StartupItemLocation,
        processes: [ProcessNode]
    ) -> [StartupAgentItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.prefix(500).compactMap { url in
            parseItem(at: url, location: location, processes: processes)
        }
    }

    nonisolated private static func performDisable(
        items: [StartupAgentItem],
        home: URL
    ) -> StartupDisableResult {
        let fm = FileManager.default
        let sourceRoot = enabledRoot(home: home)
        let destinationRoot = disabledRoot(home: home)
        try? fm.createDirectory(
            at: destinationRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var outcomes: [StartupDisableOutcome] = []
        let domain = "gui/\(getuid())"

        for item in items {
            guard item.canDisable,
                  SafeDeletionService.isPath(item.url.path, inside: sourceRoot.path),
                  snapshotMatches(item) else {
                outcomes.append(StartupDisableOutcome(item: item, moved: false, processStopped: false))
                continue
            }
            let destination = destinationRoot.appendingPathComponent(item.url.lastPathComponent)
            guard !fm.fileExists(atPath: destination.path) else {
                outcomes.append(StartupDisableOutcome(item: item, moved: false, processStopped: false))
                continue
            }
            do {
                try fm.moveItem(at: item.url, to: destination)
                _ = runLaunchctl(["bootout", "\(domain)/\(item.label)"])
                outcomes.append(StartupDisableOutcome(item: item, moved: true, processStopped: false))
            } catch {
                outcomes.append(StartupDisableOutcome(item: item, moved: false, processStopped: false))
            }
        }

        let runningPIDs = outcomes.compactMap { $0.moved ? $0.item.runningPID : nil }
        if !runningPIDs.isEmpty {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline, runningPIDs.contains(where: processExists) {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        outcomes = outcomes.map { outcome in
            guard outcome.moved, let pid = outcome.item.runningPID else { return outcome }
            return StartupDisableOutcome(item: outcome.item, moved: true, processStopped: !processExists(pid))
        }
        var countedPIDs: Set<Int32> = []
        let released = outcomes.reduce(UInt64(0)) { total, outcome in
            guard outcome.processStopped,
                  let pid = outcome.item.runningPID,
                  countedPIDs.insert(pid).inserted else { return total }
            return total &+ outcome.item.currentMemoryBytes
        }
        let scan = performScan(home: home)
        return StartupDisableResult(
            scan: scan,
            disabledCount: outcomes.filter(\.moved).count,
            failedCount: outcomes.filter { !$0.moved }.count,
            stillRunningCount: outcomes.filter { $0.moved && $0.item.runningPID != nil && !$0.processStopped }.count,
            confirmedReleasedBytes: released
        )
    }

    nonisolated private static func performRestore(
        item: StartupAgentItem,
        home: URL
    ) -> StartupRestoreResult {
        let fm = FileManager.default
        let disabled = disabledRoot(home: home)
        let enabled = enabledRoot(home: home)
        var restored = false
        var startedNow = false
        if item.canRestore,
           SafeDeletionService.isPath(item.url.path, inside: disabled.path),
           snapshotMatches(item) {
            try? fm.createDirectory(
                at: enabled,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            let destination = enabled.appendingPathComponent(item.url.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) {
                do {
                    try fm.moveItem(at: item.url, to: destination)
                    restored = true
                    startedNow = runLaunchctl(["bootstrap", "gui/\(getuid())", destination.path]).success
                } catch {
                    restored = false
                }
            }
        }
        return StartupRestoreResult(
            scan: performScan(home: home),
            restored: restored,
            startedNow: startedNow
        )
    }

    nonisolated private static func fileSnapshot(_ url: URL) -> (digest: String, size: UInt64)? {
        var information = stat()
        let result = url.path.withCString { lstat($0, &information) }
        guard result == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_size >= 0,
              information.st_size <= 1_048_576,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (digest, UInt64(information.st_size))
    }

    nonisolated private static func keepAliveIsEnabled(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let dictionary = value as? [String: Any] { return !dictionary.isEmpty }
        return false
    }

    nonisolated private static func matchProcess(
        executablePath: String?,
        arguments: [String],
        processes: [ProcessNode]
    ) -> ProcessNode? {
        guard var executable = executablePath, !executable.isEmpty else { return nil }
        executable = NSString(string: executable).expandingTildeInPath
        let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        let genericExecutables: Set<String> = [
            "bash", "sh", "zsh", "env", "node", "python", "python3", "ruby", "osascript", "open"
        ]
        let identifier = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }).map {
            NSString(string: $0).expandingTildeInPath
        }
        let exact = processes.filter { process in
            let executableMatches = process.commandLine == executable
                || process.commandLine.hasPrefix(executable + " ")
                || (!genericExecutables.contains(name)
                    && process.name.localizedCaseInsensitiveCompare(name) == .orderedSame)
            guard executableMatches else { return false }
            if genericExecutables.contains(name) {
                guard let identifier else { return false }
                return process.commandLine.contains(identifier)
            }
            return true
        }
        return exact.max { $0.memoryBytes < $1.memoryBytes }
    }

    nonisolated private static func displayName(
        label: String,
        executablePath: String?,
        fallback: String
    ) -> String {
        if let executablePath {
            let name = URL(fileURLWithPath: executablePath).deletingPathExtension().lastPathComponent
            let generic: Set<String> = ["bash", "sh", "zsh", "env", "node", "python", "python3", "ruby", "osascript", "open"]
            if !name.isEmpty, !generic.contains(name.lowercased()) { return name }
        }
        let component = label.split(separator: ".").last.map(String.init) ?? ""
        return component.isEmpty ? fallback : component
    }

    nonisolated private static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    nonisolated private static func runLaunchctl(_ arguments: [String]) -> (success: Bool, output: String) {
        let task = Process()
        let pipe = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe
        task.terminationHandler = { _ in semaphore.signal() }
        do {
            try task.run()
            if semaphore.wait(timeout: .now() + 5) == .timedOut {
                task.terminate()
                _ = semaphore.wait(timeout: .now() + 1)
                return (false, "launchctl timed out")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile().prefix(8_192)
            return (task.terminationStatus == 0, String(decoding: data, as: UTF8.self))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
