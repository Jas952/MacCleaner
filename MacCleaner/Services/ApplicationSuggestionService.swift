import AppKit
import Foundation

private final class AssistantDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// Conservative discovery scope; not an assertion that a file is unnecessary.
enum AssistantFileScope {
    static func includes(_ url: URL, home: URL, allowCaches: Bool = false) -> Bool {
        let base = home.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base), url.resolvingSymlinksInPath().path == path else { return false }
        let parts = path.dropFirst(base.count).split(separator: "/").map { $0.lowercased() }
        guard let first = parts.first else { return false }
        let roots: Set<String> = ["desktop", "downloads", "documents", "docs", "movies", "pictures", "music"]
        let cache = allowCaches && parts.count >= 2 && first == "library" && parts[1] == "caches"
        guard roots.contains(first) || cache else { return false }
        let excluded: Set<String> = ["node_modules", "vendor", "pods", "carthage", "deriveddata", "venv", "env", "site-packages", "__pycache__", "target", "build", "dist", "go", "pkg", "mod"]
        return !parts.contains { $0.hasPrefix(".") || $0.hasSuffix(".app") || $0.hasSuffix(".photoslibrary") || excluded.contains($0) }
    }
}

/// Development bridge to the local trained model. It only proposes a tool call;
/// execution is owned by the chat confirmation flow.
enum AssistantModelBridge {
    private static let requiredArguments: [String: (key: String, question: String)] = [
        "scan_large_files": ("minimum_size", "What minimum file size should I search for?"),
        "uninstall_app": ("app_name", "Which application should I prepare for removal?"),
        "show_app_related_files": ("app_name", "Which application should I inspect?"),
        "disable_startup_item": ("item", "Which startup item should I disable?"),
        "restore_startup_item": ("item", "Which startup item should I restore?"),
        "search_files": ("query", "What file name or extension should I search for?"),
        "organize_folder": ("target", "Which folder should I organize: Desktop or Downloads?")
    ]

    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["MACCLEANER_NEEDLE_DIR"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("NeedleAI")
    }
    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("venv/bin/python").path)
            && FileManager.default.fileExists(atPath: directory.appendingPathComponent("maccleaner_agent_retrieval_v5.cact").path)
    }
    static func propose(to query: String, completion: @escaping (AssistantModelDecision) -> Void) {
        // Preserve explicit values before fuzzy/model routing. A phrase such as
        // "files heavier than 5 GB" must never be confused with heavy processes.
        if let decision = deterministicDecision(for: query) {
            DispatchQueue.main.async { completion(decision) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = directory.appendingPathComponent("venv/bin/python")
            process.arguments = [directory.appendingPathComponent("agent_runtime.py").path, query]
            process.currentDirectoryURL = directory
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()
                guard process.terminationStatus == 0,
                      let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async {
                        completion(.failed("The local model could not complete this request. No action was performed."))
                    }
                    return
                }
                let decision = decision(from: result)
                DispatchQueue.main.async { completion(decision) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failed("Could not start the local model: \(error.localizedDescription)"))
                }
            }
        }
    }

    static func deterministicDecision(for query: String) -> AssistantModelDecision? {
        let text = query.lowercased().replacingOccurrences(of: ",", with: ".")
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Built-in prompts are part of the UI contract, not a probabilistic model test.
        if let prompt = AssistantPrompt.all.first(where: { $0.text.lowercased() == normalized }), prompt.tool != "scan_large_files" {
            if prompt.tool == "uninstall_app" { return .clarification("Which application would you like to remove?") }
            return .command(.init(name: prompt.tool, arguments: prompt.tool == "organize_folder" ? ["target": normalized.contains("downloads") ? "Downloads" : "Desktop"] : [:]))
        }
        if ["find large files", "show large files", "find big files", "найди большие файлы", "покажи большие файлы"].contains(normalized) {
            return .command(.init(name: "scan_large_files", arguments: ["minimum_size": "100 MB"]))
        }
        let mentionsFile = ["file", "files", "файл", "файлы", "файлов"].contains { text.contains($0) }
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(kb|mb|gb|tb|кб|мб|гб|тб)"#
        guard mentionsFile,
              let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        if ["<", "less than", "smaller than", "under ", "меньше", "менее"].contains(where: text.contains) {
            return .clarification("This search finds files above a minimum size. Which minimum should I use? Smaller-than filtering is not available here yet.")
        }

        let rawValue = String(text[match])
        guard let valueMatch = rawValue.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression),
              let unitMatch = rawValue.range(of: #"(kb|mb|gb|tb|кб|мб|гб|тб)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let units = ["кб": "KB", "мб": "MB", "гб": "GB", "тб": "TB"]
        let unit = units[String(rawValue[unitMatch]).lowercased()] ?? String(rawValue[unitMatch]).uppercased()
        return .command(AssistantToolCall(
            name: "scan_large_files",
            arguments: ["minimum_size": "\(rawValue[valueMatch]) \(unit)"]
        ))
    }

    static func respond(to query: String, completion: @escaping (String) -> Void) {
        propose(to: query) { completion(displayText(for: $0)) }
    }

    static func decision(from result: [String: Any]) -> AssistantModelDecision {
        if result["reason"] as? String == "out_of_scope_guard" {
            let text = (result["response"] as? [String: Any])?["text"] as? String
                ?? "Please ask about MacCleaner tasks."
            return .rejected(text)
        }
        guard result["ok"] as? Bool == true,
              let rawCall = result["tool_call"] as? [String: Any],
              let name = rawCall["name"] as? String else {
            return .failed("I could not reliably select an action. Please rephrase your request. No action was performed.")
        }
        let rawArguments = rawCall["arguments"] as? [String: Any] ?? [:]
        let arguments = rawArguments.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = String(describing: pair.value)
        }
        if name == "request_clarification" {
            return .clarification(arguments["question"] ?? "Which item do you mean?")
        }
        guard AssistantToolPresentation.all.contains(where: { $0.id == name }) else {
            return .failed("The model proposed an unsupported action. Nothing was performed.")
        }
        if let requirement = requiredArguments[name],
           arguments[requirement.key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return .clarification(requirement.question)
        }
        return .command(AssistantToolCall(name: name, arguments: arguments))
    }

    static func displayText(for decision: AssistantModelDecision) -> String {
        switch decision {
        case .command(let call):
            return proposalText(for: call)
        case .clarification(let question), .rejected(let question), .failed(let question):
            return question
        }
    }

    private static func proposalText(for call: AssistantToolCall) -> String {
        let target = call.arguments.keys.sorted().compactMap { call.arguments[$0] }.joined(separator: ", ")
        switch call.name {
        case "check_thermal_state": return "I can check the live temperature sensors and tell you whether the Mac is running hot."
        case "check_battery_health": return "I'll check battery health, current charge, and cycle count."
        case "list_processes": return "I'll refresh the process list and show what's running now."
        case "find_heavy_processes": return "I'll measure current CPU and memory use and show the heaviest processes."
        case "scan_large_files": return "I'll look for files larger than \(target.isEmpty ? "the size you choose" : target) and show the matches."
        case "scan_duplicates": return "I'll verify exact duplicate files and show the groups without deleting anything."
        case "uninstall_app": return "I'll locate \(target.isEmpty ? "the application" : target) and calculate what would be removed."
        case "show_app_related_files": return "I'll find support files and leftovers associated with \(target.isEmpty ? "that application" : target)."
        case "run_network_test": return "I'll test reachability and measure the current connection latency."
        case "organize_folder": return "I'll inspect \(target.isEmpty ? "the folder" : target.capitalized) and prepare an organization preview."
        case "search_files": return "I'll search for \(target.isEmpty ? "the file you specify" : target) and show where it is located."
        case "flush_dns": return "I can clear the DNS cache and then report whether it succeeded."
        default: return "I'll run \(call.presentationTitle.lowercased()) and show the result here."
        }
    }

    static func displayText(_ result: [String: Any]) -> String {
        displayText(for: decision(from: result))
    }
}

@MainActor
final class AssistantCommandExecutor: ObservableObject {
    private let monitor: SystemMonitor
    private let analyzer: StorageAnalyzerService
    private let workspace: StorageWorkspaceService
    private let uninstaller: UninstallerService
    private let startup: StartupOptimizerService
    private let updates: UpdateService
    private let network = NetworkDiagnosticService()
    private let storageHealth = StorageHealthService()
    private var additionalStartupRows: [AssistantCardRow] = []
    private var isLoadingAdditionalStartup = false

    init(
        monitor: SystemMonitor,
        analyzer: StorageAnalyzerService,
        workspace: StorageWorkspaceService,
        uninstaller: UninstallerService,
        startup: StartupOptimizerService,
        updates: UpdateService
    ) {
        self.monitor = monitor
        self.analyzer = analyzer
        self.workspace = workspace
        self.uninstaller = uninstaller
        self.startup = startup
        self.updates = updates
    }

    func execute(
        _ call: AssistantToolCall,
        completion completionResult: @escaping (AssistantExecutionResult) -> Void
    ) {
        let completion: (String) -> Void = { text in
            let lowered = text.lowercased()
            completionResult(AssistantExecutionResult(
                text: text,
                failed: lowered.contains("not connected") || lowered.contains("could not") || lowered.contains("unknown tool")
            ))
        }
        switch call.name {
        case "check_system_status":
            monitor.refresh(forceProcesses: true, forceSensors: true, forceBattery: true)
            finishAfterRefresh(completionResult) { [monitor] in
                AssistantExecutionResult(
                    text: "Your Mac is using \(Self.percent(monitor.cpu.totalUsage)) CPU and \(Self.percent(monitor.memory.usedPercent)) memory right now.",
                    rows: Self.healthRows(monitor),
                    actionTitle: "Open Dashboard",
                    destination: "dashboard"
                )
            }
        case "list_processes":
            monitor.refresh(forceProcesses: true)
            finishAfterRefresh(completionResult) { [monitor] in
                let rows = Self.rankedProcessGroups(monitor.processNodes)
                    .prefix(8)
                    .map(Self.processRow)
                return AssistantExecutionResult(
                    text: rows.isEmpty
                        ? "I couldn't read the process list. Nothing was changed."
                        : Self.loadSummary(monitor) + " Top \(rows.count) application groups. Bars show share of total CPU capacity; Quit asks for confirmation.",
                    rows: rows,
                    actionTitle: "Manage Processes",
                    destination: "processes",
                    failed: rows.isEmpty
                )
            }
        case "find_heavy_processes":
            monitor.refresh(forceProcesses: true)
            finishAfterRefresh(completionResult) { [monitor] in
                let rows = Self.rankedProcessGroups(monitor.processNodes)
                    .prefix(8)
                    .map(Self.processRow)
                return AssistantExecutionResult(
                    text: rows.isEmpty
                        ? "No process measurements were available. Nothing was changed."
                        : Self.loadSummary(monitor) + " Top \(rows.count) application groups. Bars show share of total CPU capacity.",
                    rows: rows,
                    actionTitle: "Review and Quit…",
                    destination: "processes",
                    failed: rows.isEmpty
                )
            }
        case "show_windows":
            monitor.refresh(forceProcesses: true)
            finishAfterRefresh(completion) { [monitor] in
                let owners = Array(Set(monitor.windows.map(\.ownerName))).sorted().prefix(5).joined(separator: ", ")
                return "Window refresh complete. Found \(monitor.windows.count) windows\(owners.isEmpty ? "." : " from \(owners).")"
            }
        case "show_ai_workloads":
            monitor.refresh(forceProcesses: true)
            finishAfterRefresh(completionResult) { [monitor] in
                let snapshot = AIWorkloadService.snapshot(from: monitor.processNodes, memory: monitor.memory)
                let activeAgents = snapshot.agents.filter { !$0.loadProcesses.isEmpty }
                let rows = activeAgents.prefix(12).map { agent in
                    let capacity = agent.cpuTotal / Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
                    return AssistantCardRow(
                        id: agent.id,
                        title: agent.name,
                        detail: "\(agent.loadProcesses.count) processes · \(agent.activityState.label) · \(MemoryInfo.formatted(agent.memoryTotal)) memory",
                        value: "\(String(format: "%.1f", capacity))% capacity",
                        fallbackIcon: "brain.head.profile",
                        loadFraction: min(1, capacity / 100)
                    )
                }
                return .init(
                    text: rows.isEmpty ? "No active local AI agents or model runtimes were detected." : "Detected \(rows.count) active local AI agent profile\(rows.count == 1 ? "" : "s") using \(MemoryInfo.formatted(snapshot.agentMemoryBytes)).",
                    rows: rows,
                    actionTitle: "Open Agents",
                    destination: "agents"
                )
            }
        case "show_fan_status":
            monitor.refresh(forceSensors: true)
            finishAfterRefresh(completionResult) { [monitor] in
                .init(text: "\(monitor.fans.count) fan readings. Fan control was not changed.",
                    rows: monitor.fans.enumerated().map { index, fan in .init(id: "fan-\(index)", title: fan.label, detail: "Current rotation speed", value: "\(fan.actualRPM) RPM") },
                    actionTitle: "Fan controls", destination: "fans")
            }
        case "check_thermal_state":
            monitor.refresh(forceSensors: true)
            finishAfterRefresh(completionResult) { [monitor] in
                let sensors = monitor.thermal.sensors.filter { $0.value > 0 }.sorted {
                    let lhs = Self.sensorGroup($0.name), rhs = Self.sensorGroup($1.name)
                    return lhs == rhs ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs < rhs
                }
                let hottest = sensors.map(\.value).max() ?? 0
                let summary = sensors.isEmpty
                    ? "I couldn't read the temperature sensors."
                    : "\(sensors.count) sensor readings, grouped by component. Highest reading: \(String(format: "%.1f", hottest)) °C. Sensor numbers are hardware identifiers, not verified core numbers."
                return AssistantExecutionResult(
                    text: summary,
                    rows: sensors.map {
                        .init(
                            id: $0.name,
                            title: Self.sensorGroup($0.name) + " · " + Self.readableSensorName($0.name),
                            detail: $0.name,
                            value: String(format: "%.1f °C", $0.value)
                        )
                    },
                    actionTitle: "View temperature details",
                    destination: "fans",
                    failed: sensors.isEmpty
                )
            }
        case "check_battery_health":
            monitor.refresh(forceBattery: true)
            finishAfterRefresh(completionResult) { [monitor] in
                let health = monitor.battery.healthPercent
                let assessment = health >= 80 ? "Your battery condition looks acceptable." : "Your battery is noticeably worn and may need service soon."
                return AssistantExecutionResult(
                    text: "\(assessment) Health is \(String(format: "%.0f", health))%, charge is \(monitor.battery.chargePercent)%, with \(monitor.battery.cycleCount) cycles.",
                    rows: [
                        .init(id: "health", title: "Health", detail: "Maximum capacity", value: String(format: "%.0f%%", health)),
                        .init(id: "charge", title: "Charge", detail: "Current level", value: "\(monitor.battery.chargePercent)%"),
                        .init(id: "cycles", title: "Cycles", detail: "Charge cycles", value: "\(monitor.battery.cycleCount)")
                    ],
                    actionTitle: "Open Battery Details",
                    destination: "dashboard"
                )
            }
        case "scan_junk_files":
            analyzer.scanJunk()
            waitWhile({ self.analyzer.isScanningJunk }, completion: completionResult) {
                .init(text: "Cleanup candidates, not automatic deletion. Review categories in Storage." + (self.analyzer.junkScanWasLimited ? " Partial scan." : ""),
                    rows: self.analyzer.junkCategories.map { .init(id: String(describing: $0.id), title: $0.name, detail: "Review before removal", value: MemoryInfo.formatted($0.size)) },
                    actionTitle: "Review cleanup", destination: "storage")
            }
        case "scan_large_files":
            let minimum = Self.byteCount(from: call.arguments["minimum_size"]) ?? 10 * 1_048_576
            scanLargeFilesUsingMetadata(
                minimum: minimum,
                displaySize: call.arguments["minimum_size"] ?? MemoryInfo.formatted(minimum),
                completion: completionResult
            )
        case "show_disk_map", "scan_storage":
            analyzer.scan()
            waitWhile({ self.analyzer.isScanning }, completion: completionResult) {
                .init(text: "Storage usage by folder. No files were changed." + (self.analyzer.scanWasLimited ? " Partial scan." : ""),
                    rows: (self.analyzer.rootNode?.children ?? []).sorted { $0.size > $1.size }.prefix(12).map {
                        .init(id: $0.url.path, title: $0.name, detail: $0.url.path, value: MemoryInfo.formatted($0.size), iconPath: $0.url.path)
                    }, actionTitle: "Storage map", destination: "storage")
            }
        case "scan_duplicates":
            workspace.duplicateFinder.startScan()
            waitWhile({ self.workspace.duplicateFinder.isScanning }, completion: completionResult) {
                let groups = self.workspace.duplicateFinder.groups
                let rows = groups.prefix(10).map { group in
                    AssistantCardRow(
                        id: group.id,
                        title: group.files.first?.displayName ?? "Duplicate group",
                        detail: "\(group.files.count) verified copies · \(group.files.first?.url.deletingLastPathComponent().path ?? "")",
                        value: MemoryInfo.formatted(group.potentialReclaimBytes),
                        iconPath: group.files.first?.url.path,
                        fallbackIcon: "doc.on.doc"
                    )
                }
                let reclaim = groups.reduce(UInt64(0)) { $0 &+ $1.potentialReclaimBytes }
                return AssistantExecutionResult(
                    text: (groups.isEmpty ? "No duplicate user files verified." : "\(groups.count) verified groups · \(MemoryInfo.formatted(reclaim)) in additional copies. Review paths before removal; identical does not mean unnecessary.") + (self.workspace.duplicateFinder.scanWasLimited ? " Partial scan: the scan limit was reached." : "") + " System, Library and dependency folders excluded.",
                    rows: rows,
                    actionTitle: groups.isEmpty ? nil : "Review Duplicates…",
                    destination: groups.isEmpty ? nil : "storage-duplicates"
                )
            }
        case "scan_similar_photos":
            workspace.similarPhotos.startScan()
            waitWhile({ self.workspace.similarPhotos.isScanning }, completion: completion) {
                "Similar-photo scan complete. Found \(self.workspace.similarPhotos.groups.count) groups; no photos were changed."
            }
        case "reclaim_cloud_storage":
            workspace.cloudReclaim.scan()
            waitWhile({ self.workspace.cloudReclaim.isScanning }, completion: completion) {
                "Cloud-storage scan complete. Found \(self.workspace.cloudReclaim.items.count) candidates; no local copies were removed."
            }
        case "list_installed_apps", "show_app_related_files", "uninstall_app":
            uninstaller.scan()
            waitWhile({ self.uninstaller.isScanning }, completion: completionResult) {
                let requested = call.arguments["app_name"]
                let match = requested.flatMap { name in
                    self.uninstaller.apps.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                }
                if call.name == "list_installed_apps" {
                    let rows = self.uninstaller.apps.prefix(10).map {
                        AssistantCardRow(
                            id: $0.bundleIdentifier,
                            title: $0.name,
                            detail: $0.version.isEmpty ? $0.bundleIdentifier : "Version \($0.version)",
                            value: MemoryInfo.formatted($0.totalSize),
                            iconPath: $0.appPath.path,
                            fallbackIcon: "app"
                        )
                    }
                    return AssistantExecutionResult(
                        text: "I found \(self.uninstaller.apps.count) applications that can be reviewed.",
                        rows: rows,
                        actionTitle: "Review Applications…",
                        destination: "storage-uninstaller"
                    )
                }
                guard let requested else { return AssistantExecutionResult(text: "Tell me which application you mean.", failed: true) }
                guard let match else { return AssistantExecutionResult(text: "I couldn't find \(requested) among removable applications.", failed: true) }
                self.uninstaller.requestedSelectionBundleIdentifier = match.bundleIdentifier
                let related = (match.autoSelected + match.needsReview).prefix(10).map {
                    AssistantCardRow(
                        id: $0.url.path,
                        title: $0.url.lastPathComponent,
                        detail: $0.label,
                        value: MemoryInfo.formatted($0.size),
                        iconPath: $0.url.path
                    )
                }
                return AssistantExecutionResult(
                    text: call.name == "uninstall_app"
                        ? "I found \(match.name). It uses \(MemoryInfo.formatted(match.totalSize)) including related data. Nothing has been removed yet."
                        : "I found \(related.count) related items for \(match.name). Nothing has been removed.",
                    rows: call.name == "uninstall_app" ? [
                        .init(
                            id: match.bundleIdentifier,
                            title: match.name,
                            detail: match.version.isEmpty ? match.bundleIdentifier : "Version \(match.version)",
                            value: MemoryInfo.formatted(match.totalSize),
                            iconPath: match.appPath.path,
                            fallbackIcon: "app",
                            action: .uninstallApplication(
                                bundleIdentifier: match.bundleIdentifier,
                                name: match.name
                            )
                        )
                    ] : Array(related),
                    actionTitle: call.name == "uninstall_app" ? "Open Uninstaller" : "Review related files",
                    destination: "storage-uninstaller"
                )
            }
        case "list_startup_items":
            isLoadingAdditionalStartup = true
            DispatchQueue.global(qos: .utility).async {
                let extra = Self.globalStartupRows()
                DispatchQueue.main.async {
                    self.additionalStartupRows = extra
                    self.isLoadingAdditionalStartup = false
                }
            }
            startup.startScan()
            waitWhile({ self.startup.isScanning || self.isLoadingAdditionalStartup }, completion: completionResult) {
                let rows = self.startup.items.map {
                    AssistantCardRow(id: $0.id, title: $0.displayName, detail: "User LaunchAgent · " + $0.scheduleSummary, value: $0.canRestore ? "Disabled" : "Enabled",
                        iconPath: Self.applicationIconPath($0.executablePath), fallbackIcon: "gearshape.2",
                        action: $0.canDisable ? .disableStartup(id: $0.id) : nil)
                }
                return AssistantExecutionResult(
                    text: "\(self.startup.items.count) user LaunchAgents and \(self.additionalStartupRows.count) global service definitions. Installed definitions do not necessarily run at login. App-managed login items and restored windows are managed in macOS Login Items; they are not fully inventoried here. Nothing has been disabled.",
                    rows: rows + self.additionalStartupRows,
                    actionTitle: "Manage Startup Items…",
                    destination: "startup"
                )
            }
        case "check_for_updates":
            updates.checkForUpdates()
            completion("The application update check was started.")
        case "run_network_test":
            network.runTest()
            waitWhile({ self.network.isRunning }, timeout: 60, completion: completionResult) {
                guard let snapshot = self.network.snapshot else { return AssistantExecutionResult(text: "The connection test finished without measurable results.", failed: true) }
                let latency = snapshot.latencyMS.map { String(format: "%.0f ms", $0) } ?? "unavailable"
                let assessment: String
                if let value = snapshot.latencyMS {
                    assessment = value < 100 ? "Your connection is responsive." : value < 500 ? "Your connection works, but latency is elevated." : "Your connection works, but latency is very high."
                } else {
                    assessment = "The connection responded, but latency could not be measured."
                }
                return AssistantExecutionResult(
                    text: "\(assessment) Status: \(snapshot.statusLabel); latency: \(latency).",
                    rows: [
                        .init(id: "status", title: "Connection", detail: "Reachability", value: snapshot.statusLabel),
                        .init(id: "latency", title: "HTTP latency", detail: "Endpoint response, not ICMP ping", value: latency),
                        .init(id: "ip", title: "Public IP", detail: "Egress address seen by endpoint", value: snapshot.publicIP ?? "Unavailable"),
                        .init(id: "location", title: "Egress location", detail: "IP-based estimate, not device location", value: snapshot.location ?? "Unavailable"),
                        .init(id: "provider", title: "Provider", detail: "Network operator", value: snapshot.provider ?? "Unavailable"),
                        .init(id: "local", title: "Local IP", detail: self.monitor.network.interfaceName, value: self.monitor.network.address),
                        .init(id: "down", title: "Download test", detail: "Short endpoint test", value: snapshot.downloadMbps.map { String(format: "%.1f Mbps", $0) } ?? "Unavailable"),
                        .init(id: "up", title: "Upload test", detail: "Short endpoint test", value: snapshot.uploadMbps.map { String(format: "%.1f Mbps", $0) } ?? "Unavailable"),
                        .init(id: "in", title: "Incoming now", detail: "Active interface traffic", value: NetworkInfo.formattedRate(self.monitor.network.downloadBytesPerSecond)),
                        .init(id: "out", title: "Outgoing now", detail: "Active interface traffic", value: NetworkInfo.formattedRate(self.monitor.network.uploadBytesPerSecond)),
                        .init(id: "vpn", title: "VPN / tunnel", detail: "Virtual interface is an indicator, not proof of VPN protection", value: self.monitor.network.interfaceName.hasPrefix("utun") ? "Tunnel interface active" : "Not verified")
                    ],
                    actionTitle: "Open Network Tools",
                    destination: "maintenance"
                )
            }
        case "flush_dns":
            DNSCleaner.flush { _, message in completion(message + ".") }
        case "find_old_installers":
            scanInstallers(completion: completionResult)
        case "find_developer_caches":
            scanKnownFolders(Self.developerCachePaths(), label: "developer cache", completion: completionResult)
        case "find_ai_caches":
            scanKnownFolders(Self.aiCachePaths(), label: "AI cache", completion: completionResult)
        case "run_doctor_mode":
            monitor.refresh(forceProcesses: true, forceSensors: true, forceBattery: true)
            finishAfterRefresh(completionResult) { [monitor] in
                let concerns = [
                    monitor.cpu.totalUsage > 0.85 ? "CPU load is high" : nil,
                    monitor.memory.usedPercent > 0.9 ? "Memory pressure may be high" : nil,
                    monitor.thermal.cpuTemp > 85 ? "CPU temperature is high" : nil,
                    monitor.battery.designCapacity > 0 && monitor.battery.healthPercent < 80 ? "Battery health is below 80%" : nil
                ].compactMap { $0 }
                return .init(
                    text: concerns.isEmpty ? "Quick diagnostic found no immediate warning in the current snapshot." : "Quick diagnostic found \(concerns.count) item\(concerns.count == 1 ? "" : "s") to review: \(concerns.joined(separator: "; ")).",
                    rows: Self.healthRows(monitor),
                    actionTitle: "Open Diagnostics",
                    destination: "maintenance"
                )
            }
        case "run_maintenance":
            completionResult(.init(text: "Maintenance includes separate, reviewable tools. Open Utilities and choose the exact operation; no maintenance action was started automatically.", actionTitle: "Open Utilities", destination: "maintenance"))
        case "check_ssd_health":
            storageHealth.runQuickCheck()
            waitWhile({ self.storageHealth.isRunning }, timeout: 8, completion: completionResult) {
                guard let snapshot = self.storageHealth.snapshot else {
                    return .init(text: "macOS did not return SSD health data. Open Diagnostics for the detailed checks.", actionTitle: "Open SSD Diagnostics", destination: "maintenance", failed: true)
                }
                return .init(text: "SSD quick check complete. SMART status: \(snapshot.smartStatus).",
                    rows: [
                        .init(id: "device", title: "Drive", detail: snapshot.isSolidState == true ? "Solid-state drive" : "Storage device", value: snapshot.deviceName),
                        .init(id: "smart", title: "SMART", detail: "Status reported by macOS", value: snapshot.smartStatus),
                        .init(id: "wear", title: "Wear", detail: "Percentage used", value: snapshot.wearLabel),
                        .init(id: "spare", title: "Spare cells", detail: "Available reserve", value: snapshot.spareLabel),
                        .init(id: "errors", title: "Media errors", detail: "Drive-reported errors", value: snapshot.errorLabel)
                    ], actionTitle: "Open SSD Diagnostics", destination: "maintenance")
            }
        case "run_speaker_test":
            completionResult(.init(text: "Speaker testing needs you to hear and compare the left and right channels. Open Utilities to start it; no sound was played automatically.", actionTitle: "Open Speaker Test", destination: "maintenance"))
        case "run_keyboard_test":
            completionResult(.init(text: "Keyboard testing needs live key presses. Open Utilities to start the visual key test; input capture was not enabled automatically.", actionTitle: "Open Keyboard Test", destination: "maintenance"))
        case "navigate_to":
            let requested = (call.arguments["destination"] ?? call.arguments["section"] ?? call.arguments["target"] ?? "").lowercased()
            let destination: String
            if requested.contains("process") { destination = "processes" }
            else if requested.contains("fan") || requested.contains("thermal") { destination = "fans" }
            else if requested.contains("startup") { destination = "startup" }
            else if requested.contains("agent") { destination = "agents" }
            else if requested.contains("tool") || requested.contains("maintenance") || requested.contains("diagnostic") { destination = "maintenance" }
            else if requested.contains("desktop") { destination = "desktop" }
            else if requested.contains("storage") || requested.contains("disk") { destination = "storage" }
            else { destination = "dashboard" }
            completionResult(.init(text: "Ready to open the requested MacCleaner section.", actionTitle: "Open section", destination: destination))
        case "inspect_homebrew":
            inspectHomebrew(completion: completionResult)
        case "search_files":
            searchFiles(call.arguments["query"] ?? "", completion: completionResult)
        case "organize_folder":
            prepareOrganization(call.arguments["target"] ?? "", completion: completionResult)
        case "clean_selected_items", "move_items_to_trash", "disable_startup_item", "restore_startup_item":
            completion("The command was confirmed, but no concrete item is selected. Nothing was changed.")
        default:
            completion("Unknown tool \(call.name). Nothing was changed.")
        }
    }

    private static func byteCount(from value: String?) -> UInt64? {
        guard let value else { return nil }
        let normalized = value.lowercased().replacingOccurrences(of: " ", with: "")
        guard let number = Double(normalized.prefix { $0.isNumber || $0 == "." }) else { return nil }
        if normalized.contains("tb") { return UInt64(number * 1_099_511_627_776) }
        if normalized.contains("gb") { return UInt64(number * 1_073_741_824) }
        if normalized.contains("mb") { return UInt64(number * 1_048_576) }
        return UInt64(number)
    }

    private func searchFiles(
        _ rawQuery: String,
        completion: @escaping (AssistantExecutionResult) -> Void
    ) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            completion(AssistantExecutionResult(text: "Tell me a file name or extension to search for.", failed: true))
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let root = FileManager.default.homeDirectoryForCurrentUser
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
            let startedAt = Date()
            var scanned = 0
            var matches: [(URL, UInt64)] = []
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )
            while let url = enumerator?.nextObject() as? URL,
                  scanned < 100_000,
                  Date().timeIntervalSince(startedAt) < 5 {
                scanned += 1
                guard url.lastPathComponent.lowercased().contains(query),
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                let size = UInt64(max(values.totalFileAllocatedSize ?? values.fileSize ?? 0, 0))
                matches.append((url, size))
                if matches.count >= 20 { break }
            }
            let rows = matches.map {
                AssistantCardRow(
                    id: $0.0.path,
                    title: $0.0.lastPathComponent,
                    detail: $0.0.deletingLastPathComponent().path,
                    value: MemoryInfo.formatted($0.1),
                    iconPath: $0.0.path
                )
            }
            DispatchQueue.main.async {
                completion(AssistantExecutionResult(
                    text: rows.isEmpty ? "I couldn't find a file matching \(rawQuery)." : "I found \(rows.count) files matching \(rawQuery).",
                    rows: rows
                ))
            }
        }
    }

    private func scanInstallers(completion: @escaping (AssistantExecutionResult) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let roots = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
            var paths: [String] = []
            var limited = false
            for root in roots where FileManager.default.fileExists(atPath: root.path) {
                let result = Self.runBoundedCommand(
                    executable: "/usr/bin/find",
                    arguments: [root.path, "-type", "f", "(", "-iname", "*.dmg", "-o", "-iname", "*.pkg", "-o", "-iname", "*.iso", ")", "-print0"],
                    timeout: 1
                )
                paths.append(contentsOf: Self.nullSeparatedStrings(in: result.data))
                limited = limited || result.timedOut
            }
            let cutoff = Date().addingTimeInterval(-30 * 86_400)
            let rows = paths.compactMap { path -> AssistantCardRow? in
                let url = URL(fileURLWithPath: path)
                guard AssistantFileScope.includes(url, home: home),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      values.isRegularFile == true, (values.contentModificationDate ?? .distantFuture) < cutoff else { return nil }
                return .init(id: path, title: url.lastPathComponent,
                    detail: "Installer · last changed \((values.contentModificationDate ?? cutoff).formatted(date: .abbreviated, time: .omitted)) · \(url.deletingLastPathComponent().path)",
                    value: MemoryInfo.formatted(UInt64(max(0, values.fileSize ?? 0))), iconPath: path)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            DispatchQueue.main.async {
                completion(.init(
                    text: rows.isEmpty ? "No installers older than 30 days were found in your Downloads, Desktop, or Documents folders." : "Found \(rows.count) installers older than 30 days. Nothing was deleted; review each file before removal." + (limited ? " Some folders reached the scan time limit." : ""),
                    rows: Array(rows.prefix(20)),
                    actionTitle: rows.isEmpty ? nil : "Review installers",
                    destination: rows.isEmpty ? nil : "storage-large"
                ))
            }
        }
    }

    nonisolated static func developerCachePaths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            home.appendingPathComponent("Library/Developer/Xcode/Archives"),
            home.appendingPathComponent("Library/Caches/Homebrew"),
            home.appendingPathComponent(".gradle/caches"),
            home.appendingPathComponent(".cargo/registry/cache")
        ]
    }

    nonisolated static func aiCachePaths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Library/Caches/com.openai.chat"),
            home.appendingPathComponent("Library/Caches/com.openai.codex"),
            home.appendingPathComponent(".cache/huggingface/assets"),
            home.appendingPathComponent(".cache/torch"),
            home.appendingPathComponent(".cache/transformers")
        ]
    }

    private func scanKnownFolders(
        _ folders: [URL],
        label: String,
        completion: @escaping (AssistantExecutionResult) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let rows = folders.compactMap { url -> AssistantCardRow? in
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let result = Self.runBoundedCommand(executable: "/usr/bin/du", arguments: ["-sk", url.path], timeout: 1.5)
                guard result.succeeded,
                      let first = Self.lines(in: result.data).first,
                      let kilobytes = UInt64(first.split(whereSeparator: { $0 == "\t" || $0 == " " }).first ?? "") else { return nil }
                return .init(id: url.path, title: url.lastPathComponent,
                    detail: "\(label.capitalized) · \(url.path)", value: MemoryInfo.formatted(kilobytes * 1_024),
                    iconPath: url.path, fallbackIcon: "folder")
            }.sorted { $0.value > $1.value }
            DispatchQueue.main.async {
                completion(.init(
                    text: rows.isEmpty ? "No known \(label) folders were available." : "Found \(rows.count) known \(label) folders. Model folders and project dependencies are excluded. Nothing was removed.",
                    rows: rows,
                    actionTitle: "Open Storage",
                    destination: "storage"
                ))
            }
        }
    }

    private func inspectHomebrew(completion: @escaping (AssistantExecutionResult) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.isExecutableFile(atPath:)) else {
                DispatchQueue.main.async { completion(.init(text: "Homebrew is not installed in a standard location.", actionTitle: "Open Utilities", destination: "maintenance")) }
                return
            }
            let result = Self.runBoundedCommand(executable: brew, arguments: ["list", "--versions"], timeout: 6)
            let rows = Self.lines(in: result.data).prefix(30).compactMap { line -> AssistantCardRow? in
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard let name = parts.first else { return nil }
                return .init(id: name, title: name, detail: "Installed Homebrew package", value: parts.count > 1 ? parts[1] : "Installed", fallbackIcon: "shippingbox")
            }
            DispatchQueue.main.async {
                completion(.init(text: result.timedOut ? "Homebrew inventory reached its 6-second limit; showing partial results." : "Homebrew inventory found \(rows.count) packages in this preview. Nothing was upgraded or removed.", rows: Array(rows), actionTitle: "Open Utilities", destination: "maintenance", failed: !result.succeeded && rows.isEmpty))
            }
        }
    }

    private func scanLargeFilesUsingMetadata(
        minimum: UInt64,
        displaySize: String,
        completion: @escaping (AssistantExecutionResult) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let roots = ["Downloads", "Desktop", "Documents", "Docs", "Movies", "Pictures", "Music", "Library/Caches"]
                .map { home.appendingPathComponent($0) }
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
                .fileSizeKey, .creationDateKey, .contentAccessDateKey, .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey]
            let policy = SafeDeletionService.currentProtectionPolicy()
            var nodes: [FSNode] = []
            var seen = Set<String>()
            var inaccessible = 0
            var limited = false
            var candidatePaths: [String] = []

            // Never enumerate protected folders in-process. macOS privacy checks can
            // block NSURLDirectoryEnumerator inside open(2), which previously left
            // Quick Assist apparently frozen. Child searches are bounded and can be
            // stopped without blocking SwiftUI.
            let spotlight = Self.runBoundedCommand(
                executable: "/usr/bin/mdfind",
                arguments: ["-onlyin", home.path, "kMDItemFSSize >= \(minimum)"],
                timeout: 2
            )
            candidatePaths.append(contentsOf: Self.lines(in: spotlight.data))
            limited = spotlight.timedOut
            if !spotlight.succeeded && !spotlight.timedOut { inaccessible += 1 }

            for root in roots {
                guard fm.fileExists(atPath: root.path) else { continue }
                let search = Self.runBoundedCommand(
                    executable: "/usr/bin/find",
                    arguments: [root.path, "-type", "f", "-size", "+\(minimum)c", "-print0"],
                    timeout: 0.9
                )
                candidatePaths.append(contentsOf: Self.nullSeparatedStrings(in: search.data))
                limited = limited || search.timedOut
                if !search.succeeded && !search.timedOut { inaccessible += 1 }
            }

            for path in candidatePaths.prefix(5_000) {
                let url = URL(fileURLWithPath: path)
                guard AssistantFileScope.includes(url, home: home, allowCaches: true),
                      !SafeDeletionService.isApplicationOwnedPath(url, policy: policy),
                      isDeletablePath(url.path),
                      let value = try? url.resourceValues(forKeys: keys), value.isRegularFile == true,
                      value.isSymbolicLink != true,
                      value.isUbiquitousItem != true || value.ubiquitousItemDownloadingStatus == .current else {
                    continue
                }
                let size = UInt64(max(0, value.fileSize ?? 0))
                guard size >= minimum, seen.insert(url.path).inserted else { continue }
                nodes.append(FSNode(url: url, name: url.lastPathComponent, isDirectory: false, size: size,
                    creationDate: value.creationDate, lastAccessDate: value.contentAccessDate,
                    category: Self.fileCategory(for: url), isDeletable: true, children: nil))
            }
            let sorted = nodes.sorted { $0.size > $1.size }
            let note = limited || inaccessible > 0
                ? " Partial scan: macOS limited folder access or a folder exceeded its time budget. Allow Files and Folders access for a complete result, then retry."
                : " Checked local user folders and user caches."
            DispatchQueue.main.async {
                self.analyzer.largeFiles = Array(sorted.prefix(150))
                completion(AssistantExecutionResult(
                    text: "Found \(sorted.count) file\(sorted.count == 1 ? "" : "s") at least \(displaySize); showing \(min(20, sorted.count)). System files, application data and dependency folders excluded. Review before deleting." + note,
                    rows: sorted.prefix(20).map {
                        .init(id: $0.url.path, title: $0.name,
                            detail: ($0.url.path.contains("/Library/Caches/") ? "Cache · " : "User file · ") + $0.url.deletingLastPathComponent().path,
                            value: MemoryInfo.formatted($0.size), iconPath: $0.url.path)
                    },
                    actionTitle: sorted.isEmpty ? nil : "Review files",
                    destination: sorted.isEmpty ? nil : "storage-large"
                ))
            }
        }
    }

    struct BoundedCommandResult {
        let data: Data
        let succeeded: Bool
        let timedOut: Bool
    }

    nonisolated static func runBoundedCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> BoundedCommandResult {
        let process = Process()
        let pipe = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        let output = AssistantDataBuffer()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            output.append(chunk)
        }
        process.terminationHandler = { _ in semaphore.signal() }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return .init(data: Data(), succeeded: false, timedOut: false)
        }

        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        if timedOut, process.isRunning {
            process.terminate()
            if semaphore.wait(timeout: .now() + 0.25) == .timedOut, process.isRunning {
                process.interrupt()
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        if !timedOut {
            let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
            output.append(remainder)
        }
        let data = output.snapshot()
        return .init(data: data, succeeded: !timedOut && process.terminationStatus == 0, timedOut: timedOut)
    }

    nonisolated static func lines(in data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    nonisolated static func nullSeparatedStrings(in data: Data) -> [String] {
        data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    nonisolated private static func fileCategory(for url: URL) -> FSNodeCategory {
        switch url.pathExtension.lowercased() {
        case "mov", "mp4", "mkv", "avi", "m4v": return .video
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return .image
        case "pdf", "doc", "docx", "txt", "md", "pages": return .document
        case "zip", "rar", "7z", "tar", "gz", "dmg", "pkg": return .archive
        case "app": return .app
        default: return .unknown
        }
    }

    nonisolated static func processRow(_ node: ProcessNode) -> AssistantCardRow {
        let countDetail = node.instanceCount > 1 ? " · \(node.instanceCount) processes" : ""
        let isProtected = ProcessTreeService.isProtected(node)
        return AssistantCardRow(
            id: String(node.id),
            title: node.name,
            detail: "\(MemoryInfo.formatted(node.memoryBytes)) memory\(countDetail)",
            value: String(format: "%.1f%% capacity", min(100, max(0, node.cpuUsage / Double(max(1, ProcessInfo.processInfo.activeProcessorCount))))),
            iconPath: processIconPath(node),
            fallbackIcon: isProtected ? "lock.shield" : "app",
            action: isProtected ? nil : .quitProcess(
                pid: node.id,
                name: node.name,
                instanceCount: max(node.instanceCount, 1)
            ),
            loadFraction: min(1, max(0, node.cpuUsage / Double(max(1, ProcessInfo.processInfo.activeProcessorCount)) / 100))
        )
    }

    nonisolated static func rankedProcessGroups(_ nodes: [ProcessNode]) -> [ProcessNode] {
        ProcessAggregator.aggregate(nodes)
            .sorted {
                if $0.cpuUsage == $1.cpuUsage { return $0.memoryBytes > $1.memoryBytes }
                return $0.cpuUsage > $1.cpuUsage
            }
    }

    func executeRowAction(
        _ action: AssistantRowAction,
        completion: @escaping (AssistantRowActionOutcome) -> Void
    ) {
        switch action {
        case .organizeFiles(let items):
            DispatchQueue.global(qos: .utility).async {
                let outcome = Self.applyOrganization(items)
                DispatchQueue.main.async { completion(outcome) }
            }
        case .disableStartup(let id):
            guard let item = startup.items.first(where: { $0.id == id }), item.canDisable,
                  !startup.isScanning, !startup.isMutating else {
                completion(.init(succeeded: false, message: "The item changed or is not available for disabling."))
                return
            }
            startup.selectedItemIDs = [id]
            startup.disableSelected()
            waitWhile({ self.startup.isMutating }, timeoutResult: AssistantRowActionOutcome(succeeded: false, message: "Still processing; check Startup Items before retrying."), completion: completion) {
                let disabled = self.startup.items.contains { $0.label == item.label && $0.canRestore }
                return .init(succeeded: disabled, message: self.startup.resultMessage ?? "Check Startup Items for the result.")
            }
        case .quitProcess(let pid, let name, _):
            guard let node = Self.rankedProcessGroups(monitor.processNodes)
                .first(where: { $0.id == pid }) else {
                completion(.init(succeeded: false, message: "The process is no longer running."))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let result = ProcessTreeService.killProcessGroup(node)
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completion(.init(succeeded: true, message: "\(name) quit"))
                    case .protected(let reason), .failed(let reason):
                        completion(.init(succeeded: false, message: reason))
                    }
                }
            }
        case .uninstallApplication(let bundleIdentifier, let name):
            guard let app = uninstaller.apps.first(where: {
                $0.bundleIdentifier == bundleIdentifier
                    || $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else {
                completion(.init(succeeded: false, message: "The application is no longer available."))
                return
            }
            uninstaller.uninstall(apps: [app]) { succeeded in
                completion(.init(
                    succeeded: succeeded,
                    message: succeeded ? "Moved to Trash" : "Could not move the application to Trash"
                ))
            }
        }
    }

    nonisolated private static func globalStartupRows() -> [AssistantCardRow] {
        let fm = FileManager.default
        return ["/Library/LaunchAgents", "/Library/LaunchDaemons"].flatMap { path -> [AssistantCardRow] in
            let root = URL(fileURLWithPath: path)
            return ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "plist" }.prefix(100).compactMap { url in
                    guard let data = try? Data(contentsOf: url),
                          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                          let label = plist["Label"] as? String, !label.hasPrefix("com.apple.") else { return nil }
                    let executable = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
                    let icon = applicationIconPath(executable)
                    return .init(id: url.path, title: label,
                        detail: (path.hasSuffix("LaunchAgents") ? "Global LaunchAgent" : "Global daemon") + " · installed definition, runtime not verified",
                        value: "Managed by macOS", iconPath: icon, fallbackIcon: "gearshape.2")
                }
        }
    }

    private func prepareOrganization(_ target: String, completion: @escaping (AssistantExecutionResult) -> Void) {
        let name: String
        switch target.lowercased() {
        case "downloads", "загрузки": name = "Downloads"
        case "desktop", "рабочий стол": name = "Desktop"
        default:
            completion(.init(text: "Choose Desktop or Downloads before organizing.", failed: true))
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
                var groups: [String: [AssistantMoveItem]] = [:]
                for url in urls.prefix(1000) {
                    guard let value = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                          value.isRegularFile == true, value.isSymbolicLink != true,
                          let modified = value.contentModificationDate else { continue }
                    let category = DesktopFileCategory.classify(url).rawValue
                    groups[category, default: []].append(.init(source: url,
                        destination: root.appendingPathComponent(category).appendingPathComponent(url.lastPathComponent),
                        size: value.fileSize ?? 0, modified: modified))
                }
                let rows: [AssistantCardRow] = groups.keys.sorted().map { category in
                    let items = groups[category] ?? []
                    return .init(id: category, title: category,
                        detail: items.prefix(4).map { $0.source.lastPathComponent }.joined(separator: ", ") + (items.count > 4 ? "…" : ""),
                        value: "\(items.count) files", fallbackIcon: "folder.fill", action: .organizeFiles(items))
                }
                DispatchQueue.main.async {
                    completion(.init(text: "Organization preview for \(name). Nothing moved yet. Review each group and confirm Move files. Existing folders are left untouched." + (urls.count > 1000 ? " Limited to the first 1,000 entries." : ""), rows: rows))
                }
            } catch {
                DispatchQueue.main.async { completion(.init(text: "Cannot read \(name): \(error.localizedDescription)", failed: true)) }
            }
        }
    }

    nonisolated static func applyOrganization(_ items: [AssistantMoveItem], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AssistantRowActionOutcome {
        let fm = FileManager.default
        let allowed = ["Desktop", "Downloads"].map { home.appendingPathComponent($0).standardizedFileURL.path }
        var moved = 0
        for item in items {
            let parent = item.source.deletingLastPathComponent().standardizedFileURL
            guard allowed.contains(parent.path), item.source.resolvingSymlinksInPath().path == item.source.standardizedFileURL.path,
                  !SafeDeletionService.isApplicationOwnedPath(item.source, policy: SafeDeletionService.currentProtectionPolicy()),
                  item.destination.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == parent.path,
                  item.destination.lastPathComponent == item.source.lastPathComponent,
                  DesktopFileCategory.allCases.map(\.rawValue).contains(item.destination.deletingLastPathComponent().lastPathComponent),
                  item.destination.deletingLastPathComponent().resolvingSymlinksInPath().path == item.destination.deletingLastPathComponent().standardizedFileURL.path,
                  let value = try? item.source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                  value.isRegularFile == true, value.isSymbolicLink != true,
                  value.fileSize == item.size, value.contentModificationDate == item.modified,
                  !fm.fileExists(atPath: item.destination.path) else { continue }
            do {
                try fm.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: false)
            } catch {
                var directory: ObjCBool = false
                guard fm.fileExists(atPath: item.destination.deletingLastPathComponent().path, isDirectory: &directory), directory.boolValue else { continue }
            }
            do { try fm.moveItem(at: item.source, to: item.destination); moved += 1 } catch { continue }
        }
        return .init(succeeded: moved == items.count && !items.isEmpty,
            message: "Moved \(moved) of \(items.count). \(items.count - moved) skipped (changed, conflicting, protected or inaccessible).")
    }

    private static func healthRows(_ monitor: SystemMonitor) -> [AssistantCardRow] {
        var rows: [AssistantCardRow] = [
            .init(id: "cpu", title: "CPU", detail: "\(monitor.cpu.processorCount) logical cores", value: percent(monitor.cpu.totalUsage)),
            .init(id: "memory", title: "Memory", detail: "\(MemoryInfo.formatted(monitor.memory.used)) of \(MemoryInfo.formatted(monitor.memory.total))", value: percent(monitor.memory.usedPercent)),
            .init(id: "gpu", title: "GPU", detail: "Latest graphics reading", value: percent(monitor.gpuUsage)),
            .init(id: "compressed", title: "Compressed memory", detail: "In RAM, not free disk space", value: MemoryInfo.formatted(monitor.memory.compressed)),
            .init(id: "cpu-temp", title: "CPU temperature", detail: "Latest sensor reading", value: monitor.thermal.cpuTemp > 0 ? String(format: "%.1f °C", monitor.thermal.cpuTemp) : "Unavailable"),
            .init(id: "gpu-temp", title: "GPU temperature", detail: "Latest sensor reading", value: monitor.thermal.gpuTemp > 0 ? String(format: "%.1f °C", monitor.thermal.gpuTemp) : "Unavailable")
        ]
        if let disk = monitor.disks.first(where: { $0.mountPoint == "/" || $0.mountPoint == "/System/Volumes/Data" }) {
            rows.append(.init(id: "disk", title: "Free storage", detail: disk.volumeName, value: MemoryInfo.formatted(disk.free)))
        }
        if monitor.battery.designCapacity > 0 {
            rows.append(.init(id: "battery", title: "Battery health", detail: "\(monitor.battery.cycleCount) cycles · \(monitor.battery.chargePercent)% charged", value: String(format: "%.0f%%", monitor.battery.healthPercent)))
        }
        return rows
    }

    private static func loadSummary(_ monitor: SystemMonitor) -> String {
        "System: CPU \(percent(monitor.cpu.totalUsage)) · memory \(percent(monitor.memory.usedPercent)) · GPU \(percent(monitor.gpuUsage)) · CPU temperature \(monitor.thermal.cpuTemp > 0 ? String(format: "%.1f °C", monitor.thermal.cpuTemp) : "unavailable")."
    }

    nonisolated static func applicationIconPath(_ executable: String?) -> String? {
        guard let executable else { return nil }
        if let range = executable.range(of: ".app", options: .caseInsensitive) {
            return String(executable[..<range.upperBound])
        }
        return executable
    }

    nonisolated static func sensorGroup(_ name: String) -> String {
        let value = name.lowercased()
        if value.contains("battery") { return "Battery" }
        if value.contains("cpu") { return "CPU" }
        if value.contains("gpu") { return "GPU" }
        if value.contains("ssd") || value.contains("nand") { return "Storage" }
        if value.contains("air") || value.contains("fan") { return "Airflow / wireless" }
        if value.contains("trackpad") { return "Trackpad" }
        return "Power / system"
    }

    nonisolated static func readableSensorName(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("gas gauge") || lowered.contains("battery") { return "Battery" }
        if lowered.contains("soc") || lowered.contains("pmu") { return "Apple silicon" }
        if lowered.contains("gpu") { return "Graphics" }
        if lowered.contains("nand") || lowered.contains("ssd") { return "Storage" }
        if let range = name.range(of: #"CPU Die Sensor\s*([0-9]+)"#, options: [.regularExpression, .caseInsensitive]) {
            let number = name[range].split(whereSeparator: { !$0.isNumber }).last.map(String.init) ?? ""
            return number.isEmpty ? "Processor" : "Processor sensor \(number)"
        }
        return name
            .replacingOccurrences(of: "Sensor", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func temperatureAssessment(_ value: Double) -> String {
        if value >= 90 { return "Very hot — reduce the load" }
        if value >= 75 { return "Warm — keep an eye on it" }
        return "Normal temperature"
    }

    nonisolated private static func processIconPath(_ node: ProcessNode) -> String? {
        let command = (node.groupedInstances.first?.commandLine ?? node.commandLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let appRange = command.range(of: ".app", options: .caseInsensitive) {
            let appPath = String(command[..<appRange.upperBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if appPath.hasPrefix("/") { return appPath }
        }
        let executable = command.split(whereSeparator: \.isWhitespace).first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard let executable, executable.hasPrefix("/") else { return nil }
        return executable
    }

    private func finishAfterRefresh<Result>(
        _ completion: @escaping (Result) -> Void,
        result: @escaping () -> Result
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { completion(result()) }
    }

    private func waitWhile<Result>(
        _ isRunning: @escaping () -> Bool,
        timeout: TimeInterval = 45,
        timeoutResult: Result? = nil,
        completion: @escaping (Result) -> Void,
        result: @escaping () -> Result
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        Task { @MainActor in
            while isRunning(), Date() < deadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if isRunning() {
                if let timeoutResult {
                    completion(timeoutResult)
                } else if Result.self == AssistantExecutionResult.self {
                    completion(AssistantExecutionResult(
                        text: "The operation is still running. You can continue monitoring it in the corresponding section."
                    ) as! Result)
                } else if Result.self == String.self {
                    completion("The operation is still running. You can continue monitoring it in the corresponding section." as! Result)
                }
            } else {
                completion(result())
            }
        }
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}

enum ApplicationSuggestionService {
    private struct Descriptor {
        let name: String
        let bundleIdentifier: String
        let url: URL
    }

    static func loadApplications(completion: @escaping ([AssistantApplication]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let descriptors = findApplications()

            DispatchQueue.main.async {
                let workspace = NSWorkspace.shared
                let applications = descriptors.map { descriptor in
                    AssistantApplication(
                        id: descriptor.url.standardizedFileURL.path,
                        name: descriptor.name,
                        bundleIdentifier: descriptor.bundleIdentifier,
                        url: descriptor.url,
                        icon: workspace.icon(forFile: descriptor.url.path)
                    )
                }
                completion(applications)
            }
        }
    }

    private static func findApplications() -> [Descriptor] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        var results: [Descriptor] = []
        var seenPaths = Set<String>()

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }

            let rootDepth = root.standardizedFileURL.pathComponents.count
            for case let url as URL in enumerator {
                if url.standardizedFileURL.pathComponents.count - rootDepth > 4 {
                    enumerator.skipDescendants()
                    continue
                }

                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
                      !url.path.hasPrefix("/System"),
                      !url.path.hasPrefix("/Applications/Utilities"),
                      seenPaths.insert(url.standardizedFileURL.path).inserted,
                      let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier,
                      !bundleIdentifier.hasPrefix("com.apple.") else { continue }

                results.append(
                    Descriptor(
                        name: url.deletingPathExtension().lastPathComponent,
                        bundleIdentifier: bundleIdentifier,
                        url: url
                    )
                )
            }
        }

        return results
    }
}
