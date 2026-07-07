import Foundation
import AppKit

struct ProcessDetailInfo {
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryBytes: UInt64
    let user: String
    let parentPID: Int32
    let threads: Int
    let openFiles: Int
    let diskReadBytes: UInt64
    let diskWrittenBytes: UInt64
    let listeningPorts: [String]
    let childCount: Int
    let startedAgo: String
    let workingDirectory: String
    let executablePath: String
    let commandLine: String
    let parentChain: [(name: String, pid: Int32)]
    let appBundlePath: String?

    var likelySource: String? {
        guard let bundle = appBundlePath else { return nil }
        return URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent
    }

    var diskIOFormatted: String {
        let r = MemoryInfo.formatted(diskReadBytes)
        let w = MemoryInfo.formatted(diskWrittenBytes)
        return "\(r) R · \(w) W"
    }

    var memoryFormatted: String {
        MemoryInfo.formatted(memoryBytes)
    }
}

final class ProcessDetailService {

    static func fetchDetail(for node: ProcessNode) -> ProcessDetailInfo {
        let user = fetchUser(pid: node.id)
        let threads = fetchThreadCount(pid: node.id)
        let openFiles = fetchOpenFileCount(pid: node.id)
        let listeningPorts = fetchListeningPorts(pid: node.id)
        let childCount = fetchChildCount(pid: node.id)
        let started = fetchStartedAgo(pid: node.id)
        let cwd = fetchWorkingDirectory(pid: node.id)
        let parentChain = buildParentChain(pid: node.id)
        let bundlePath = detectBundlePath(commandLine: node.commandLine)
        let execDisplay = formatExecutable(commandLine: node.commandLine, name: node.name)

        return ProcessDetailInfo(
            pid: node.id,
            name: node.name,
            cpuUsage: node.cpuUsage,
            memoryBytes: node.memoryBytes,
            user: user,
            parentPID: node.parentPID,
            threads: threads,
            openFiles: openFiles,
            diskReadBytes: node.diskRead,
            diskWrittenBytes: node.diskWritten,
            listeningPorts: listeningPorts,
            childCount: childCount,
            startedAgo: started,
            workingDirectory: cwd,
            executablePath: execDisplay,
            commandLine: node.commandLine,
            parentChain: parentChain,
            appBundlePath: bundlePath
        )
    }

    // MARK: - Shell helpers

    private static func shell(_ args: [String]) -> String {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", args.joined(separator: " ")]
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in semaphore.signal() }
        guard (try? task.run()) != nil else { return "" }
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            task.terminate()
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func fetchUser(pid: Int32) -> String {
        let out = shell(["ps", "-p", "\(pid)", "-o", "user="])
        return out.isEmpty ? "unknown" : out
    }

    private static func fetchThreadCount(pid: Int32) -> Int {
        let out = shell(["ps", "-M", "-p", "\(pid)", "|", "wc", "-l"])
        let count = Int(out.trimmingCharacters(in: .whitespaces)) ?? 1
        return max(0, count - 1) // subtract header
    }

    private static func fetchOpenFileCount(pid: Int32) -> Int {
        let out = shell(["lsof", "-p", "\(pid)", "2>/dev/null", "|", "wc", "-l"])
        let count = Int(out.trimmingCharacters(in: .whitespaces)) ?? 1
        return max(0, count - 1)
    }

    private static func fetchListeningPorts(pid: Int32) -> [String] {
        let out = shell(["lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-p", "\(pid)", "2>/dev/null",
                         "|", "awk", "'NR>1{print $9}'"])
        guard !out.isEmpty else { return [] }
        return out.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private static func fetchChildCount(pid: Int32) -> Int {
        let out = shell(["pgrep", "-P", "\(pid)", "|", "wc", "-l"])
        return Int(out.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static func fetchStartedAgo(pid: Int32) -> String {
        let out = shell(["ps", "-p", "\(pid)", "-o", "lstart="])
        guard !out.isEmpty else { return "N/A" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // ps lstart format: "Mon Jan  1 12:00:00 2024"
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        // Also try with double-space padding
        let cleaned = out.replacingOccurrences(of: "  ", with: " ")
        guard let date = formatter.date(from: cleaned) ?? formatter.date(from: out) else { return out }

        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m" }
        if elapsed < 86400 { return "\(elapsed / 3600)h \((elapsed % 3600) / 60)m" }
        return "\(elapsed / 86400)d \((elapsed % 86400) / 3600)h"
    }

    private static func fetchWorkingDirectory(pid: Int32) -> String {
        let out = shell(["lsof", "-p", "\(pid)", "-d", "cwd", "-Fn", "2>/dev/null",
                         "|", "grep", "'^n'", "|", "head", "-1", "|", "cut", "-c2-"])
        return out.isEmpty ? "/" : out
    }

    private static func buildParentChain(pid: Int32) -> [(name: String, pid: Int32)] {
        var chain: [(name: String, pid: Int32)] = []
        var current = pid
        var visited = Set<Int32>()

        while current > 0 && !visited.contains(current) {
            visited.insert(current)
            let out = shell(["ps", "-p", "\(current)", "-o", "ppid=,comm="])
            let parts = out.trimmingCharacters(in: .whitespaces)
                           .components(separatedBy: .whitespaces)
                           .filter { !$0.isEmpty }
            guard parts.count >= 2, let ppid = Int32(parts[0]) else { break }
            let name = parts[1...].joined(separator: " ")
            let displayName = URL(fileURLWithPath: name).lastPathComponent
            chain.insert((name: displayName, pid: current), at: 0)
            if ppid == current || ppid == 0 { break }
            current = ppid
        }

        return chain
    }

    private static func detectBundlePath(commandLine: String) -> String? {
        guard let range = commandLine.range(of: ".app", options: .caseInsensitive) else { return nil }
        let prefix = String(commandLine[..<range.upperBound])
        // Extract just the path part (before any args)
        let path = prefix.components(separatedBy: " ").last(where: { $0.contains(".app") }) ?? prefix
        return path
    }

    private static func formatExecutable(commandLine: String, name: String) -> String {
        if let bundlePath = detectBundlePath(commandLine: commandLine) {
            let appName = URL(fileURLWithPath: bundlePath).lastPathComponent
            let execName = URL(fileURLWithPath: commandLine.components(separatedBy: " ").first ?? "").lastPathComponent
            if execName != appName.replacingOccurrences(of: ".app", with: "") && !execName.isEmpty {
                return "\(appName) / \(execName)"
            }
            return appName
        }
        let exec = commandLine.components(separatedBy: " ").first ?? name
        return URL(fileURLWithPath: exec).lastPathComponent
    }

    private static let iconCache = NSCache<NSString, NSImage>()

    static func appIcon(for commandLine: String) -> NSImage? {
        let key = commandLine as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        guard let bundlePath = detectBundlePath(commandLine: commandLine) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        iconCache.setObject(icon, forKey: key)
        return icon
    }

    static func revealInFinder(commandLine: String) {
        if let bundlePath = detectBundlePath(commandLine: commandLine) {
            NSWorkspace.shared.selectFile(bundlePath, inFileViewerRootedAtPath: "")
        } else if let exec = commandLine.components(separatedBy: " ").first {
            NSWorkspace.shared.selectFile(exec, inFileViewerRootedAtPath: "")
        }
    }

    static func copySummary(_ info: ProcessDetailInfo) -> String {
        var lines: [String] = []
        lines.append("\(info.name) — Process Detail")
        lines.append("PID \(info.pid) · CPU \(String(format: "%.1f%%", info.cpuUsage)) · MEM \(info.memoryFormatted) · \(info.user)")
        lines.append("")
        if let source = info.likelySource { lines.append("Likely Source: \(source)") }
        if let bundle = info.appBundlePath { lines.append("Evidence: \(bundle)") }
        lines.append("Threads: \(info.threads)")
        lines.append("Open Files: \(info.openFiles)")
        lines.append("Disk I/O: \(info.diskIOFormatted)")
        if !info.listeningPorts.isEmpty { lines.append("Listening Ports: \(info.listeningPorts.joined(separator: ", "))") }
        lines.append("Children: \(info.childCount)")
        lines.append("User: \(info.user)")
        lines.append("Started: \(info.startedAgo)")
        lines.append("Working Directory: \(info.workingDirectory)")
        lines.append("Executable: \(info.executablePath)")
        lines.append("")
        lines.append("Command: \(info.commandLine)")
        return lines.joined(separator: "\n")
    }
}
