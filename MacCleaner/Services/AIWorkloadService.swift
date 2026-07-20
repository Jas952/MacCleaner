import Foundation

struct CodexUsageWindow: Identifiable {
    let id: String
    let title: String
    let remainingPercent: Int
    let resetsAt: Date?
    let windowDurationMinutes: Int?
}

struct CodexUsageSnapshot {
    let planType: String?
    let windows: [CodexUsageWindow]
    let fetchedAt: Date

    var hasData: Bool { !windows.isEmpty }
}

/// Read-only bridge to Codex's local app-server protocol.
/// It never changes auth, config, sessions, or usage state.
enum CodexUsageService {
    private static let lock = NSLock()
    private static var cached: (date: Date, value: CodexUsageSnapshot)?
    private static let cacheTTL: TimeInterval = 60

    static func fetch() -> CodexUsageSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        if let cached, Date().timeIntervalSince(cached.date) < cacheTTL { return cached.value }

        guard let executable = codexExecutable() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        func send(_ message: [String: Any]) {
            guard JSONSerialization.isValidJSONObject(message),
                  let data = try? JSONSerialization.data(withJSONObject: message) else { return }
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([10]))
        }
        send(["method": "initialize", "id": 1, "params": [
            "clientInfo": ["name": "maccleaner", "title": "MacCleaner", "version": "1.0.4"],
            "capabilities": [:]
        ]])

        let responseReady = DispatchSemaphore(value: 0)
        var buffer = Data()
        var response: [String: Any]?
        var didCompleteHandshake = false
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: newline)
                    buffer.removeSubrange(...newline)
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    if (object["id"] as? NSNumber)?.intValue == 1 && !didCompleteHandshake {
                        didCompleteHandshake = true
                        send(["method": "initialized", "params": [:]])
                        send(["method": "account/rateLimits/read", "id": 2, "params": [:]])
                    }
                    if (object["id"] as? NSNumber)?.intValue == 2 {
                        response = object
                        responseReady.signal()
                        return
                    }
                }
            }
        }
        _ = responseReady.wait(timeout: .now() + 5)
        output.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }
        guard let result = response?["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else { return nil }

        var windows: [CodexUsageWindow] = []
        for (key, title) in [("secondary", "5-hour"), ("primary", "Weekly")] {
            guard let raw = limits[key] as? [String: Any],
                  let used = raw["usedPercent"] as? NSNumber else { continue }
            let duration = (raw["windowDurationMins"] as? NSNumber)?.intValue
            let reset = (raw["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let label = duration == 5 * 60 ? "5-hour" : (duration == 7 * 24 * 60 ? "Weekly" : title)
            windows.append(CodexUsageWindow(
                id: key,
                title: label,
                remainingPercent: max(0, min(100, 100 - used.intValue)),
                resetsAt: reset,
                windowDurationMinutes: duration
            ))
        }
        let account = (limits["planType"] as? String)?.capitalized
        let snapshot = CodexUsageSnapshot(planType: account, windows: windows, fetchedAt: Date())
        cached = (Date(), snapshot)
        return snapshot
    }

    private static func codexExecutable() -> String? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

final class AIWorkloadService {
    private static let inventoryCacheTTL: TimeInterval = 10
    private static var componentCache: [String: (date: Date, value: [AIAgentComponent])] = [:]
    private static var sourceCache: [String: (date: Date, value: Bool)] = [:]

    static func snapshot(from processes: [ProcessNode], memory: MemoryInfo) -> AIWorkloadSnapshot {
        let classified = processes
            .map(classify)
            .sorted { lhs, rhs in
                if lhs.cpuUsage == rhs.cpuUsage { return lhs.memoryBytes > rhs.memoryBytes }
                return lhs.cpuUsage > rhs.cpuUsage
            }

        let buckets = AIWorkloadKind.allCases.compactMap { kind -> AIWorkloadBucket? in
            let rows = classified.filter { $0.kind == kind }
            return rows.isEmpty ? nil : AIWorkloadBucket(kind: kind, processes: rows)
        }.sorted { $0.cpuTotal > $1.cpuTotal }
        let agents = buildAgentProfiles(from: classified)

        return AIWorkloadSnapshot(
            date: Date(),
            buckets: buckets,
            recommendations: recommendations(for: buckets, memory: memory),
            agents: agents,
            systemBucket: buckets.first { $0.kind == .system },
            totalMemoryBytes: memory.total,
            usedMemoryBytes: memory.used
        )
    }

    static func classify(_ process: ProcessNode) -> AIWorkloadProcess {
        let name = process.name.lowercased()

        let result: (AIWorkloadKind, String)
        if isSystem(name) {
            result = (.system, "macOS service or protected background process")
        } else if containsAny(name, ["ollama", "llama", "llama-server", "lm studio", "mlx", "ggml", "vllm", "kobold", "text-generation"]) {
            result = (.modelRuntime, "local model runtime or inference server")
        } else if containsAny(name, ["mcp", "modelcontextprotocol"]) {
            result = (.orchestration, "MCP server or bridge used by agents")
        } else if containsAny(name, ["codex", "claude", "cursor", "copilot", "continue", "aider", "goose", "hermes", "antigravity", "devin", "agent"]) {
            result = (.agent, "AI agent or assistant runtime")
        } else if containsAny(name, ["qdrant", "chroma", "lancedb", "weaviate", "milvus", "pgvector", "postgres", "sqlite", "duckdb", "embedding"]) {
            result = (.vectorIndex, "vector database, embedding, or indexing workload")
        } else if containsAny(name, ["docker", "containerd", "colima", "lima", "kubectl", "kube", "podman", "orbstack"]) {
            result = (.orchestration, "container or orchestration layer")
        } else if containsAny(name, ["node", "npm", "pnpm", "bun", "python", "go"]) {
            result = (.buildTool, "runtime that can support agent tools, MCP servers, or local scripts")
        } else if containsAny(name, ["xcodebuild", "swiftc", "clang", "tsserver", "cargo", "rustc", "make"]) {
            result = (.system, "developer tooling outside the agent category")
        } else if process.isBackgroundAgent {
            result = (.system, "background service detected by process heuristics")
        } else {
            result = (.userApp, "regular user application")
        }

        return AIWorkloadProcess(
            id: process.id,
            name: process.name,
            kind: result.0,
            cpuUsage: process.cpuUsage,
            memoryBytes: process.memoryBytes,
            diskRead: process.diskRead,
            diskWritten: process.diskWritten,
            parentPID: process.parentPID,
            reason: result.1,
            commandLine: process.commandLine
        )
    }

    private static func buildAgentProfiles(from processes: [AIWorkloadProcess]) -> [AIAgentProfile] {
        var profiles: [AIAgentProfile] = []

        let codexInstallComponents = codexComponents()
        let codexProcesses = agentProcesses(
            in: processes,
            keywords: ["codex"],
            components: codexInstallComponents
        )
        let codexPIDs = Set(codexProcesses.map(\.id))
        let codexHelpers = descendantProcesses(of: codexPIDs, in: processes)
        let codexMCPProcesses = codexHelpers.filter(isMCPProcess)
        let codexNonMCPHelpers = codexHelpers.filter { !isMCPProcess($0) }

        if codexInstallDetected() {
            let codexMCP = codexMCPServers()
            let codexSkillItems = codexSkills()
            let codexRuntimeProcesses = codexProcesses + codexHelpers
            let codexTerminals = terminalChildren(for: codexRuntimeProcesses, in: processes)
            profiles.append(.init(
                id: "codex",
                name: "Codex",
                description: "Local OpenAI Codex agent runtime, workspace state, skills, plugins, and tool bridges.",
                rootPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex",
                processes: codexProcesses,
                mcpProcesses: codexMCPProcesses,
                helperProcesses: codexNonMCPHelpers,
                components: codexComponents() + mcpConfigComponents(),
                mcpComponents: codexMCP,
                skillComponents: codexSkillItems,
                mcpSourceFound: codexMCPSourceFound(),
                skillSourceFound: codexSkillSourceFound(),
                activityState: activityState(processes: codexRuntimeProcesses, terminalProcesses: codexTerminals),
                terminalProcesses: codexTerminals
            ))
        }

        let knownAgents: [(String, String, [String], [AIAgentComponent], [AIAgentComponent], [AIAgentComponent], Bool, Bool)] = [
            ("Hermes", "hermes", ["hermes"], agentComponents(.hermes), hermesMCPServers(), hermesSkills(), hermesMCPSourceFound(), hermesSkillSourceFound()),
            ("Antigravity", "antigravity", ["antigravity"], agentComponents(.antigravity), antigravityMCPServers(), antigravitySkills(), antigravityMCPSourceFound(), antigravitySkillSourceFound()),
            ("Devin", "devin", ["devin"], agentComponents(.devin), devinMCPServers(), devinSkills(), devinMCPSourceFound(), devinSkillSourceFound()),
            ("Claude Code", "claude", ["claude"], genericComponents(id: "claude", appNames: ["Claude"]), claudeMCPServers(), claudeSkills(), claudeMCPSourceFound(), claudeSkillSourceFound()),
            ("Cursor", "cursor", ["cursor"], genericComponents(id: "cursor", appNames: ["Cursor"]), cursorMCPServers(), cursorSkills(), cursorMCPSourceFound(), cursorSkillSourceFound()),
            ("Aider", "aider", ["aider"], genericComponents(id: "aider", appNames: ["Aider"]), [], [], false, false),
            ("Goose", "goose", ["goose"], genericComponents(id: "goose", appNames: ["Goose"]), [], [], false, false),
            ("Continue", "continue", ["continue"], genericComponents(id: "continue", appNames: ["Continue"]), [], [], false, false)
        ]

        for agent in knownAgents {
            if hasInstallAnchor(agent.3) {
                let rows = agentProcesses(in: processes, keywords: agent.2, components: agent.3)
                let helpers = descendantProcesses(of: Set(rows.map(\.id)), in: processes)
                let agentMCPProcesses = helpers.filter(isMCPProcess)
                let nonMCPHelpers = helpers.filter { !isMCPProcess($0) }
                let runtimeProcesses = rows + helpers
                let terminals = terminalChildren(for: runtimeProcesses, in: processes)
                profiles.append(.init(
                    id: agent.1,
                    name: agent.0,
                    description: "Detected active AI assistant runtime.",
                    rootPath: rootPath(from: agent.3),
                    processes: rows,
                    mcpProcesses: agentMCPProcesses,
                    helperProcesses: nonMCPHelpers,
                    components: agent.3,
                    mcpComponents: agent.4,
                    skillComponents: agent.5,
                    mcpSourceFound: agent.6,
                    skillSourceFound: agent.7,
                    activityState: activityState(processes: runtimeProcesses, terminalProcesses: terminals),
                    terminalProcesses: terminals
                ))
            }
        }

        return profiles.sorted { $0.memoryTotal > $1.memoryTotal }
    }

    private static func isMCPProcess(_ process: AIWorkloadProcess) -> Bool {
        let evidence = "\(process.name) \(process.commandLine) \(process.reason)".lowercased()
        return evidence.contains("mcp") || evidence.contains("modelcontextprotocol")
    }

    private static func agentProcesses(
        in processes: [AIWorkloadProcess],
        keywords: [String],
        components: [AIAgentComponent]
    ) -> [AIWorkloadProcess] {
        let normalizedKeywords = keywords.map { $0.lowercased() }
        let pathFragments = components
            .filter(\.exists)
            .flatMap { component -> [String] in
                let path = component.path.lowercased()
                let appExecutable = path.hasSuffix(".app") ? "\(path)/contents/macos" : path
                return [path, appExecutable]
            }

        return processes.filter { process in
            let name = process.name.lowercased()
            let commandLine = process.commandLine.lowercased()
            if normalizedKeywords.contains(where: { name.contains($0) || commandLine.contains($0) }) {
                return true
            }
            return pathFragments.contains { fragment in
                !fragment.isEmpty && commandLine.contains(fragment)
            }
        }
    }

    private static func descendantProcesses(of rootPIDs: Set<Int32>, in processes: [AIWorkloadProcess]) -> [AIWorkloadProcess] {
        guard !rootPIDs.isEmpty else { return [] }

        var knownPIDs = rootPIDs
        var descendants: [AIWorkloadProcess] = []
        var changed = true

        while changed {
            changed = false
            for process in processes where !knownPIDs.contains(process.id) && knownPIDs.contains(process.parentPID) {
                knownPIDs.insert(process.id)
                descendants.append(process)
                changed = true
            }
        }

        return descendants.sorted {
            if $0.memoryBytes == $1.memoryBytes { return $0.cpuUsage > $1.cpuUsage }
            return $0.memoryBytes > $1.memoryBytes
        }
    }

    private static func activityState(processes: [AIWorkloadProcess], terminalProcesses: [AIWorkloadProcess]) -> AIAgentActivityState {
        if !terminalProcesses.isEmpty { return .terminalActive }
        if processes.contains(where: { $0.cpuUsage >= 1.0 }) { return .active }
        return .idle
    }

    private static func terminalChildren(for agentProcesses: [AIWorkloadProcess], in allProcesses: [AIWorkloadProcess]) -> [AIWorkloadProcess] {
        guard !agentProcesses.isEmpty else { return [] }
        let agentPIDs = Set(agentProcesses.map(\.id))
        return allProcesses
            .filter { agentPIDs.contains($0.parentPID) && isTerminalToolProcess($0) }
            .sorted { lhs, rhs in
                if lhs.cpuUsage == rhs.cpuUsage { return lhs.memoryBytes > rhs.memoryBytes }
                return lhs.cpuUsage > rhs.cpuUsage
            }
    }

    private static func isTerminalToolProcess(_ process: AIWorkloadProcess) -> Bool {
        guard process.cpuUsage >= 0.5 else { return false }

        let executableNames = commandExecutableNames(for: process)
        let exactToolNames: Set<String> = [
            "bash", "zsh", "sh", "fish",
            "node", "npm", "pnpm", "bun", "npx",
            "python", "python3",
            "go", "cargo", "rustc",
            "swift", "swiftc", "xcodebuild",
            "make", "cmake", "git", "curl",
            "uv", "uvx"
        ]

        return executableNames.contains { name in
            exactToolNames.contains(name) ||
            name.hasPrefix("python") ||
            name.hasPrefix("node")
        }
    }

    private static func commandExecutableNames(for process: AIWorkloadProcess) -> [String] {
        let candidates = [process.name, process.commandLine.split(separator: " ").first.map(String.init)]
            .compactMap { $0 }

        return candidates.map { value in
            value
                .components(separatedBy: "/")
                .last?
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                ?? value.lowercased()
        }
    }

    private static func codexInstallDetected() -> Bool {
        codexComponents().contains { $0.exists }
    }

    private static func codexComponents() -> [AIAgentComponent] {
        cachedComponents("codex.components") {
            uncachedCodexComponents()
        }
    }

    private static func uncachedCodexComponents() -> [AIAgentComponent] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [(String, String, String)] = [
            ("Codex home", "\(home)/.codex", "config/cache"),
            ("Skills", "\(home)/.codex/skills", "agent library"),
            ("Plugin cache", "\(home)/.codex/plugins/cache", "plugins"),
            ("Codex config", "\(home)/.codex/config.toml", "settings"),
            ("Codex auth", "\(home)/.codex/auth.json", "credentials")
        ]

        return components(from: candidates)
    }

    private static func mcpConfigComponents() -> [AIAgentComponent] {
        cachedComponents("global.mcpConfigComponents") {
            uncachedMCPConfigComponents()
        }
    }

    private static func uncachedMCPConfigComponents() -> [AIAgentComponent] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates: [(String, String, String)] = [
            ("Codex MCP config", "\(home)/.codex/config.toml", "mcp config"),
            ("Claude MCP config", "\(home)/Library/Application Support/Claude/claude_desktop_config.json", "mcp config"),
            ("Cursor MCP config", "\(home)/.cursor/mcp.json", "mcp config"),
            ("Workspace MCP", "\(home)/.mcp.json", "mcp config"),
            ("MCP cache", "\(home)/.cache/modelcontextprotocol", "cache")
        ]

        return components(from: candidates)
    }

    private static func codexMCPServers() -> [AIAgentComponent] {
        cachedComponents("codex.mcpServers") {
            uncachedCodexMCPServers()
        }
    }

    private static func uncachedCodexMCPServers() -> [AIAgentComponent] {
        let configPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex/config.toml"
        guard let text = try? String(contentsOfFile: configPath) else { return [] }
        let pattern = #"^\[mcp_servers\.([^\].]+)\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.enumerated().compactMap { index, match in
            guard let nameRange = Range(match.range(at: 1), in: text) else { return nil }
            let name = String(text[nameRange])
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : range.length
            let blockRange = NSRange(location: start, length: max(0, end - start))
            let block = (text as NSString).substring(with: blockRange)
            let command = firstConfigValue(named: "command", in: block)
            let args = firstConfigValue(named: "args", in: block)
            let details = [command, args].compactMap { $0 }.joined(separator: " ")
            return AIAgentComponent(
                title: name,
                path: details.isEmpty ? configPath : details,
                kind: "mcp server",
                exists: true
            )
        }
    }

    private static func firstConfigValue(named key: String, in block: String) -> String? {
        let pattern = #"(?m)^"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(block.startIndex..<block.endIndex, in: block)
        guard let match = regex.firstMatch(in: block, range: range),
              let valueRange = Range(match.range(at: 1), in: block) else { return nil }
        return String(block[valueRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
    }

    private static func codexSkills() -> [AIAgentComponent] {
        cachedComponents("codex.skills") {
            skillFiles(in: codexSkillRoots())
        }
    }

    private static func codexMCPSourceFound() -> Bool {
        cachedSource("codex.mcpSource") {
            FileManager.default.fileExists(atPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex/config.toml")
        }
    }

    private static func codexSkillSourceFound() -> Bool {
        cachedSource("codex.skillSource") {
            anyPathExists(codexSkillRoots())
        }
    }

    private static func codexSkillRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.codex/skills",
            "\(home)/.codex/plugins/cache"
        ]
    }

    private static func hermesMCPServers() -> [AIAgentComponent] {
        cachedComponents("hermes.mcpServers") {
            let configPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.hermes/config.yaml"
            return yamlNamedCommandBlocks(in: configPath, rootKey: "mcp_servers", kind: "mcp server")
        }
    }

    private static func hermesSkills() -> [AIAgentComponent] {
        cachedComponents("hermes.skills") {
            skillFiles(in: hermesSkillRoots())
        }
    }

    private static func hermesMCPSourceFound() -> Bool {
        cachedSource("hermes.mcpSource") {
            FileManager.default.fileExists(atPath: "\(FileManager.default.homeDirectoryForCurrentUser.path)/.hermes/config.yaml")
        }
    }

    private static func hermesSkillSourceFound() -> Bool {
        cachedSource("hermes.skillSource") {
            anyPathExists(hermesSkillRoots())
        }
    }

    private static func hermesSkillRoots() -> [String] {
        ["\(FileManager.default.homeDirectoryForCurrentUser.path)/.hermes/skills"]
    }

    private static func antigravityMCPServers() -> [AIAgentComponent] {
        cachedComponents("antigravity.mcpServers") {
            jsonMCPServers(in: antigravityMCPPaths())
        }
    }

    private static func antigravityMCPSourceFound() -> Bool {
        cachedSource("antigravity.mcpSource") {
            anyPathExists(antigravityMCPPaths())
        }
    }

    private static func antigravityMCPPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.antigravity/mcp.json",
            "\(home)/.antigravity/config.json",
            "\(home)/.antigravity/settings.json",
            "\(home)/Library/Application Support/Antigravity/User/settings.json",
            "\(home)/Library/Application Support/Antigravity/app_storage.json"
        ]
    }

    private static func antigravitySkills() -> [AIAgentComponent] {
        cachedComponents("antigravity.skills") {
            var items = extensionComponents(in: antigravityExtensionRoot())
            items.append(contentsOf: workspaceRuleComponents())
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private static func antigravitySkillSourceFound() -> Bool {
        cachedSource("antigravity.skillSource") {
            FileManager.default.fileExists(atPath: antigravityExtensionRoot()) || !workspaceRuleComponents().isEmpty
        }
    }

    private static func antigravityExtensionRoot() -> String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.antigravity/extensions"
    }

    private static func cursorMCPServers() -> [AIAgentComponent] {
        cachedComponents("cursor.mcpServers") {
            jsonMCPServers(in: cursorMCPPaths())
        }
    }

    private static func cursorSkills() -> [AIAgentComponent] {
        cachedComponents("cursor.skills") {
            skillFiles(in: cursorSkillRoots()) + workspaceRuleComponents()
        }
    }

    private static func cursorMCPSourceFound() -> Bool {
        cachedSource("cursor.mcpSource") {
            anyPathExists(cursorMCPPaths())
        }
    }

    private static func cursorSkillSourceFound() -> Bool {
        cachedSource("cursor.skillSource") {
            anyPathExists(cursorSkillRoots()) || !workspaceRuleComponents().isEmpty
        }
    }

    private static func cursorMCPPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.cursor/mcp.json",
            "\(home)/.cursor/settings.json"
        ]
    }

    private static func cursorSkillRoots() -> [String] {
        ["\(FileManager.default.homeDirectoryForCurrentUser.path)/.cursor/skills-cursor"]
    }

    private static func devinMCPServers() -> [AIAgentComponent] {
        cachedComponents("devin.mcpServers") {
            jsonMCPServers(in: devinMCPPaths())
        }
    }

    private static func devinSkills() -> [AIAgentComponent] {
        cachedComponents("devin.skills") {
            var items = extensionComponents(in: devinExtensionRoot())
            items.append(contentsOf: skillFiles(in: devinSkillRoots()))
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private static func devinMCPSourceFound() -> Bool {
        cachedSource("devin.mcpSource") {
            anyPathExists(devinMCPPaths())
        }
    }

    private static func devinSkillSourceFound() -> Bool {
        cachedSource("devin.skillSource") {
            FileManager.default.fileExists(atPath: devinExtensionRoot()) || anyPathExists(devinSkillRoots())
        }
    }

    private static func devinMCPPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.devin/mcp.json",
            "\(home)/.devin/settings.json",
            "\(home)/.devin/config.json",
            "\(home)/.config/devin/config.json",
            "\(home)/.windsurf/config.json",
            "\(home)/.windsurf/mcp.json",
            "\(home)/.windsurf/settings.json",
            "\(home)/Library/Application Support/Devin/User/settings.json"
        ]
    }

    private static func devinExtensionRoot() -> String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.devin/extensions"
    }

    private static func devinSkillRoots() -> [String] {
        ["\(FileManager.default.homeDirectoryForCurrentUser.path)/.devin/skills"]
    }

    private static func claudeMCPServers() -> [AIAgentComponent] {
        cachedComponents("claude.mcpServers") {
            jsonMCPServers(in: claudeMCPPaths())
        }
    }

    private static func claudeSkills() -> [AIAgentComponent] {
        cachedComponents("claude.skills") {
            var items = skillFiles(in: claudeSkillRoots())
            items.append(contentsOf: claudePluginManifests())
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private static func claudeMCPSourceFound() -> Bool {
        cachedSource("claude.mcpSource") {
            anyPathExists(claudeMCPPaths())
        }
    }

    private static func claudeSkillSourceFound() -> Bool {
        cachedSource("claude.skillSource") {
            anyPathExists(claudeSkillRoots())
        }
    }

    private static func claudeMCPPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.claude/.mcp.json",
            "\(home)/.claude/mcp.json",
            "\(home)/.claude/settings.json",
            "\(home)/Library/Application Support/Claude/claude_desktop_config.json"
        ]
    }

    private static func claudeSkillRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.claude/skills",
            "\(home)/.claude/plugins"
        ]
    }

    private static func skillFiles(in roots: [String]) -> [AIAgentComponent] {
        var items: [AIAgentComponent] = []
        var budget = ScanResourceBudget(maximumEntries: 20_000, maximumDuration: 2)
        for root in roots {
            guard budget.beginRoot(),
                  let enumerator = FileManager.default.enumerator(
                    at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }
            let rootDepth = URL(fileURLWithPath: root).pathComponents.count
            while let url = enumerator.nextObject() as? URL {
                guard budget.consumeEntry(), items.count < 500 else {
                    budget.markLimited()
                    break
                }
                if url.pathComponents.count - rootDepth > 8 {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.lastPathComponent == "SKILL.md" else { continue }
                let relative = String(url.path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let path = "\(root)/\(relative)"
                let title = relative
                    .replacingOccurrences(of: "/SKILL.md", with: "")
                    .replacingOccurrences(of: "SKILL.md", with: root.components(separatedBy: "/").last ?? "skill")
                items.append(AIAgentComponent(title: title, path: path, kind: "skill", exists: true))
            }
        }
        return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func yamlNamedCommandBlocks(in path: String, rootKey: String, kind: String) -> [AIAgentComponent] {
        guard let text = try? String(contentsOfFile: path),
              let rootRange = text.range(of: "\n\(rootKey):") ?? text.range(of: "\(rootKey):") else {
            return []
        }

        let tail = String(text[rootRange.upperBound...])
        let lines = tail.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [(name: String, lines: [String])] = []
        var currentName: String?
        var currentLines: [String] = []

        for line in lines {
            if !line.hasPrefix(" ") && !line.isEmpty { break }
            if line.hasPrefix("  "), !line.hasPrefix("    "), line.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
                if let currentName {
                    blocks.append((currentName, currentLines))
                }
                currentName = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ":", with: "")
                currentLines = []
            } else if currentName != nil {
                currentLines.append(line)
            }
        }
        if let currentName {
            blocks.append((currentName, currentLines))
        }

        return blocks.compactMap { block in
            let command = yamlScalar("command", in: block.lines)
            let args = yamlArray("args", in: block.lines).joined(separator: " ")
            let enabled = yamlScalar("enabled", in: block.lines) ?? "true"
            guard enabled != "false" else { return nil }
            let details = [command, args].compactMap { $0 }.joined(separator: " ")
            return AIAgentComponent(title: block.name, path: details.isEmpty ? path : details, kind: kind, exists: true)
        }
    }

    private static func yamlScalar(_ key: String, in lines: [String]) -> String? {
        let prefix = "\(key):"
        guard let line = lines.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func yamlArray(_ key: String, in lines: [String]) -> [String] {
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "\(key):" }) else {
            return []
        }
        var values: [String] = []
        for line in lines.dropFirst(start + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                values.append(String(trimmed.dropFirst(2)))
            } else if !trimmed.isEmpty && !line.hasPrefix("    ") {
                break
            }
        }
        return values
    }

    private static func jsonMCPServers(in paths: [String]) -> [AIAgentComponent] {
        var seen = Set<String>()
        return paths.flatMap { path -> [AIAgentComponent] in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }
            let servers = (object["mcpServers"] ?? object["mcp_servers"] ?? object["servers"]) as? [String: Any] ?? [:]
            return servers.keys.sorted().compactMap { name in
                let key = "\(path)::\(name)"
                guard !seen.contains(key) else { return nil }
                seen.insert(key)
                return AIAgentComponent(title: name, path: path, kind: "mcp server", exists: true)
            }
        }
    }

    private static func extensionComponents(in root: String) -> [AIAgentComponent] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        return entries
            .filter { !$0.hasPrefix(".") && $0 != "extensions.json" }
            .map { entry in
                AIAgentComponent(title: entry, path: "\(root)/\(entry)", kind: "extension", exists: true)
            }
    }

    private static func claudePluginManifests() -> [AIAgentComponent] {
        let root = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude/plugins"
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var items: [AIAgentComponent] = []
        var budget = ScanResourceBudget(maximumEntries: 10_000, maximumDuration: 1)
        let rootDepth = URL(fileURLWithPath: root).pathComponents.count
        while let url = enumerator.nextObject() as? URL {
            guard budget.consumeEntry(), items.count < 250 else { break }
            if url.pathComponents.count - rootDepth > 8 {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent == "plugin.json" || url.lastPathComponent == "PLUGIN.md" else { continue }
            let relative = String(url.path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let path = "\(root)/\(relative)"
            let title = relative
                .replacingOccurrences(of: "/plugin.json", with: "")
                .replacingOccurrences(of: "/PLUGIN.md", with: "")
            items.append(AIAgentComponent(title: title, path: path, kind: "plugin", exists: true))
        }
        return items
    }

    private static func workspaceRuleComponents() -> [AIAgentComponent] {
        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            ("Cursor rules", "\(cwd)/.cursorrules", "workspace rules"),
            ("Cursor rule directory", "\(cwd)/.cursor/rules", "workspace rules"),
            ("Antigravity project config", "\(cwd)/.antigravity", "workspace config")
        ]
        return components(from: candidates).filter(\.exists)
    }

    private static func genericComponents(id: String, appNames: [String]) -> [AIAgentComponent] {
        cachedComponents("generic.\(id).components") {
            uncachedGenericComponents(id: id, appNames: appNames)
        }
    }

    private static func uncachedGenericComponents(id: String, appNames: [String]) -> [AIAgentComponent] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [(String, String, String)] = [
            ("Home config", "\(home)/.\(id)", "config/cache"),
            ("Application support", "\(home)/Library/Application Support/\(appNames[0])", "app support"),
            ("Caches", "\(home)/Library/Caches/\(appNames[0])", "cache")
        ]
        candidates.append(contentsOf: appNames.map { appName in
            ("Application", "/Applications/\(appName).app", "app bundle")
        })
        return components(from: candidates)
    }

    private enum KnownAgentInstall {
        case hermes
        case antigravity
        case devin
    }

    private static func agentComponents(_ agent: KnownAgentInstall) -> [AIAgentComponent] {
        cachedComponents("known.\(agent).components") {
            uncachedAgentComponents(agent)
        }
    }

    private static func uncachedAgentComponents(_ agent: KnownAgentInstall) -> [AIAgentComponent] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch agent {
        case .hermes:
            return components(from: [
                ("Application", "/Applications/Hermes.app", "app bundle"),
                ("Hermes Agent app", "\(home)/hermes-desktop/dist/mac-arm64/Hermes Agent.app", "app bundle"),
                ("Hermes home", "\(home)/.hermes", "config/cache"),
                ("Hermes agent", "\(home)/.hermes/hermes-agent", "agent runtime"),
                ("Hermes CLI", "\(home)/.local/bin/hermes", "cli"),
                ("Hermes state", "\(home)/.local/state/hermes", "state"),
                ("Hermes LaunchAgent", "\(home)/Library/LaunchAgents/ai.hermes.gateway.plist", "launch agent"),
                ("Application support", "\(home)/Library/Application Support/Hermes", "app support"),
                ("Desktop support", "\(home)/Library/Application Support/hermes-desktop", "app support")
            ])
        case .antigravity:
            return components(from: [
                ("Application", "/Applications/Antigravity.app", "app bundle"),
                ("Tools app", "/Applications/Antigravity Tools.app", "app bundle"),
                ("Desktop copy", "\(home)/Desktop/Antigravity.app", "app bundle"),
                ("Gemini Antigravity", "\(home)/.gemini/antigravity", "state"),
                ("Antigravity IDE", "\(home)/.gemini/antigravity-ide", "ide state"),
                ("Antigravity backup", "\(home)/.gemini/antigravity-backup", "backup"),
                ("Home config", "\(home)/.antigravity", "config/cache"),
                ("IDE config", "\(home)/.antigravity-ide", "config/cache"),
                ("Tools config", "\(home)/.antigravity_tools", "config/cache"),
                ("Application support", "\(home)/Library/Application Support/Antigravity", "app support"),
                ("Tools support", "\(home)/Library/Application Support/com.lbjlaq.antigravity-tools", "app support")
            ])
        case .devin:
            return components(from: [
                ("Application", "/Applications/Devin.app", "app bundle"),
                ("Home config", "\(home)/.devin", "config/cache"),
                ("Project config", "\(FileManager.default.currentDirectoryPath)/.devin", "workspace config"),
                ("XDG config", "\(home)/.config/devin", "config"),
                ("Local share", "\(home)/.local/share/devin", "state"),
                ("Cache", "\(home)/.cache/devin", "cache"),
                ("Application support", "\(home)/Library/Application Support/Devin", "app support")
            ])
        }
    }

    private static func components(from candidates: [(String, String, String)]) -> [AIAgentComponent] {
        candidates.map { item in
            AIAgentComponent(
                title: item.0,
                path: item.1,
                kind: item.2,
                exists: FileManager.default.fileExists(atPath: item.1)
            )
        }
    }

    private static func anyPathExists(_ paths: [String]) -> Bool {
        paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func hasInstallAnchor(_ components: [AIAgentComponent]) -> Bool {
        components.contains { component in
            component.exists && ["app bundle", "cli", "agent runtime"].contains(component.kind)
        }
    }

    private static func rootPath(from components: [AIAgentComponent]) -> String {
        let preferred = ["agent runtime", "config/cache", "app support", "app bundle", "cli"]
        for kind in preferred {
            if let component = components.first(where: { $0.exists && $0.kind == kind }) {
                return component.path
            }
        }
        return components.first(where: \.exists)?.path ?? ""
    }

    private static func recommendations(for buckets: [AIWorkloadBucket], memory: MemoryInfo) -> [AIAdvisorRecommendation] {
        var items: [AIAdvisorRecommendation] = []
        let byKind = Dictionary(uniqueKeysWithValues: buckets.map { ($0.kind, $0) })

        if let models = byKind[.modelRuntime], models.cpuTotal > 40 {
            items.append(.init(
                severity: .warning,
                title: "Local model runtime is the dominant load",
                detail: "Reduce context size, use a smaller quantization, pause generation, or move this request to an external provider."
            ))
        }

        if let vectors = byKind[.vectorIndex], vectors.cpuTotal > 25 || vectors.diskTotal > 500_000_000 {
            items.append(.init(
                severity: .warning,
                title: "Indexing or vector storage is active",
                detail: "Batch embeddings in smaller chunks and avoid running vector rebuilds while agents are generating code."
            ))
        }

        if let agents = byKind[.agent], agents.cpuTotal > 20 {
            items.append(.init(
                severity: .info,
                title: "Agent orchestration is visible",
                detail: "Check whether the agent spawned file watchers, MCP tools, or background indexing processes."
            ))
        }

        if memory.usedPercent > 0.85 {
            items.append(.init(
                severity: .critical,
                title: "Memory pressure is high",
                detail: "Close idle model runtimes, reduce parallel agents, or offload large-model tasks to a provider."
            ))
        }

        if items.isEmpty {
            items.append(.init(
                severity: .info,
                title: "No AI-specific pressure detected",
                detail: "Current load appears balanced. Open Agents for process-level attribution if the machine still feels hot."
            ))
        }

        return items
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func isSystem(_ name: String) -> Bool {
        protectedProcessNames.contains { name == $0.lowercased() } ||
        name.hasPrefix("com.apple.") ||
        containsAny(name, ["kernel", "launchd", "windowserver", "mds", "mdworker", "coreaudiod", "cfprefsd", "trustd", "sysmond"])
    }

    private static func cachedComponents(_ key: String, build: () -> [AIAgentComponent]) -> [AIAgentComponent] {
        let now = Date()
        if let cached = componentCache[key], now.timeIntervalSince(cached.date) < inventoryCacheTTL {
            return cached.value
        }

        let value = build()
        componentCache[key] = (now, value)
        return value
    }

    private static func cachedSource(_ key: String, build: () -> Bool) -> Bool {
        let now = Date()
        if let cached = sourceCache[key], now.timeIntervalSince(cached.date) < inventoryCacheTTL {
            return cached.value
        }

        let value = build()
        sourceCache[key] = (now, value)
        return value
    }
}
