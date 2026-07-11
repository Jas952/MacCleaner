import Foundation
import AppKit

// MARK: - Protected system processes (never kill these)
let protectedProcessNames: Set<String> = [
    "kernel_task", "launchd", "sysmond", "logd", "notifyd", "cfprefsd",
    "opendirectoryd", "diskarbitrationd", "diskmanagementd", "configd",
    "WindowServer", "loginwindow", "Dock", "Finder", "SystemUIServer",
    "ControlCenter", "NotificationCenter", "Spotlight", "UserEventAgent",
    "coreaudiod", "bluetoothd", "wirelessproxd", "wifi",
    "trustd", "securityd", "authd", "tccd", "amfid",
    "mds", "mds_stores", "mdworker", "mdworker_shared",
    "powerd", "thermalmonitord", "thermald", "SMC",
    "hidd", "IOHIDSystem", "CoreServicesUIAgent",
    "com.apple.WebKit.Networking", "XPC", "xpcproxy",
    "com.apple.appstoreagent", "storedownloadd", "storeassetd",
    "MacCleaner"
]

enum KillResult {
    case success
    case protected(reason: String)
    case failed(reason: String)
}

// MARK: - Models

struct ProcessNode: Identifiable {
    let id: Int32
    let name: String
    let commandLine: String
    let cpuUsage: Double
    let cpuTime: String
    var memoryBytes: UInt64
    var diskRead: UInt64 = 0
    var diskWritten: UInt64 = 0
    let parentPID: Int32
    let isBackgroundAgent: Bool
    var children: [ProcessNode] = []
    var windows: [WindowInfo] = []
}

struct WindowInfo: Identifiable {
    let id: Int
    let name: String
    let ownerName: String
    let ownerPID: Int32
    let memoryBytes: UInt64
    let isOnScreen: Bool
}

final class ProcessTreeService {

    static func fetchProcessTree() -> [ProcessNode] {
        let raw = fetchRawProcesses()
        let windows = fetchWindows()

        var map: [Int32: ProcessNode] = [:]
        for p in raw {
            var node = p
            node.windows = windows.filter { $0.ownerPID == p.id }
            let windowMem = node.windows.reduce(0) { $0 + $1.memoryBytes }
            node.memoryBytes += windowMem
            map[p.id] = node
        }

        var roots: [ProcessNode] = []
        for pid in map.keys.sorted() {
            guard let node = map[pid] else { continue }
            let ppid = node.parentPID
            if ppid != pid && map[ppid] != nil {
                map[ppid]!.children.append(node)
            } else {
                roots.append(node)
            }
        }

        return roots.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    static func fetchFlatProcesses(cachedWindows: [WindowInfo]? = nil) -> [ProcessNode] {
        let raw = fetchRawProcesses()
        let windows = cachedWindows ?? fetchWindows()

        return raw.map { p in
            var node = p
            node.windows = windows.filter { $0.ownerPID == p.id }
            let windowMem = node.windows.reduce(0) { $0 + $1.memoryBytes }
            node.memoryBytes += windowMem
            return node
        }.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    static func fetchWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }

        var result: [WindowInfo] = []
        for dict in list {
            guard
                let pid = dict[kCGWindowOwnerPID] as? Int32,
                let wid = dict[kCGWindowNumber]   as? Int
            else { continue }

            let name      = dict[kCGWindowName]      as? String ?? ""
            let ownerName = dict[kCGWindowOwnerName] as? String ?? "Unknown"
            let memBytes  = (dict[kCGWindowMemoryUsage] as? UInt64) ?? 0
            let onScreen  = (dict[kCGWindowIsOnscreen] as? Bool) ?? false

            result.append(WindowInfo(
                id: wid,
                name: name,
                ownerName: ownerName,
                ownerPID: pid,
                memoryBytes: memBytes,
                isOnScreen: onScreen
            ))
        }
        return result
    }

    struct ProcessInfoPayload: Codable {
        let pid: Int32
        let footprint: UInt64
        let diskRead: UInt64
        let diskWritten: UInt64
    }

    private static func fetchRawProcesses() -> [ProcessNode] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-wwwwaxo", "pid=,ppid=,pcpu=,rss=,time=,args="]
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        var outputData = Data()
        let outputLock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            outputData.append(chunk)
            outputLock.unlock()
        }
        let semaphore = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in semaphore.signal() }
        guard (try? task.run()) != nil else { return [] }
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            task.terminate()
            pipe.fileHandleForReading.readabilityHandler = nil
            return []
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
        outputLock.lock()
        outputData.append(remainingData)
        let data = outputData
        outputLock.unlock()
        guard let out = String(data: data, encoding: .utf8) else { return [] }

        var results: [ProcessNode] = []
        let lines = out.components(separatedBy: "\n")
        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces)
                            .components(separatedBy: .whitespaces)
                            .filter { !$0.isEmpty }
            guard parts.count >= 6,
                  let pid   = Int32(parts[0]),
                  let ppid  = Int32(parts[1]),
                  let cpu   = Double(parts[2]),
                  let rssKB = UInt64(parts[3]) else { continue }

            let timeStr = parts[4]
            let commandLine = parts[5...].joined(separator: " ")
            let name = displayName(from: commandLine)
            let isAgent = isBackgroundAgent(name: name, fullPath: commandLine)

            let memBytes = rssKB * 1024

            results.append(ProcessNode(
                id: pid,
                name: name,
                commandLine: commandLine,
                cpuUsage: cpu,
                cpuTime: timeStr,
                memoryBytes: memBytes,
                diskRead: 0,
                diskWritten: 0,
                parentPID: ppid,
                isBackgroundAgent: isAgent
            ))
        }
        return results
    }

    private static func displayName(from commandLine: String) -> String {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }

        if let appRange = trimmed.range(of: ".app", options: .caseInsensitive) {
            let appPath = String(trimmed[..<appRange.upperBound])
            let appName = URL(fileURLWithPath: appPath).lastPathComponent
            if !appName.isEmpty {
                return appName.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            }
        }

        let executable = String(trimmed.split(separator: " ").first ?? Substring(trimmed))
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return name.isEmpty ? executable : name
    }

    static func isProtected(_ node: ProcessNode) -> Bool {
        if node.id <= 1 { return true }
        if node.id == ProcessInfo.processInfo.processIdentifier { return true }
        if protectedProcessNames.contains(node.name) { return true }
        let lowered = node.name.lowercased()
        let protectedPrefixes = ["com.apple.security", "com.apple.system", "com.maccleaner.", "kernel"]
        return protectedPrefixes.contains { lowered.hasPrefix($0) }
    }

    @discardableResult
    static func killProcess(_ node: ProcessNode) -> KillResult {
        sendSignal(SIGTERM, to: node)
    }

    @discardableResult
    static func forceKillProcess(_ node: ProcessNode) -> KillResult {
        sendSignal(SIGKILL, to: node)
    }

    private static func sendSignal(_ signal: Int32, to node: ProcessNode) -> KillResult {
        if isProtected(node) {
            return .protected(reason: "\"\(node.name)\" is protected and cannot be terminated by MacCleaner.")
        }

        let result = Darwin.kill(node.id, signal)
        if result == 0 { return .success }
        return .failed(reason: String(cString: strerror(errno)))
    }

    private static func isBackgroundAgent(name: String, fullPath: String) -> Bool {
        let agentKeywords = [
            "agent", "daemon", "helper", "service", "extension",
            "XPCService", "crashpad", "updater", "com.apple.",
            "launchd", "mdworker", "mds", "nsurlsession", "warmd",
            "symptomsd", "syslogd", "logd", "notifyd", "cfprefsd"
        ]
        let lower = (name + fullPath).lowercased()
        return agentKeywords.contains { lower.contains($0) }
    }
}
