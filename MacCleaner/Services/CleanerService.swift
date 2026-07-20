import Foundation
import Darwin
import AppKit
import SwiftUI

// MARK: - RAM Analysis Types

enum RAMSourceKind: String {
    case inactiveCache  = "Inactive Cache"
    case compressed     = "Compressed Memory"
    case topProcess     = "App"
    case wired          = "Wired (kernel)"
}

enum RAMSafety {
    case safe       // can free without any impact
    case review     // freeable, app may reload data
    case locked     // cannot free without reboot
}

struct RAMSource: Identifiable {
    let id = UUID()
    let name: String
    let kind: RAMSourceKind
    let bytes: UInt64
    let safety: RAMSafety
    let detail: String
    var isSelected: Bool = false
    var pid: Int32? = nil
}

struct RAMCleanResult {
    let requestedCount: Int
    let closedCount: Int
    let refusedCount: Int
    let estimatedReleasedBytes: UInt64

    var closedAny: Bool { closedCount > 0 }
    var allClosed: Bool { requestedCount > 0 && refusedCount == 0 && closedCount == requestedCount }
}

struct RAMAnalysisResult {
    let sources: [RAMSource]
    let totalFreeable: UInt64   // inactive cache + reclaimable
    let inactiveBytes: UInt64
    let compressedBytes: UInt64
    let wiredBytes: UInt64
    let pressure: String        // "Normal" / "Warn" / "Critical"
}

// MARK: - RAM Cleaner

final class RAMCleaner {
    static let allowsForceTermination = false

    // Analyse current RAM layout, returns sources grouped by reclaim-ability
    static func analyze(memory: MemoryInfo, processes: [ProcessNode],
                        progress: @escaping (String) -> Void = { _ in },
                        completion: @escaping (RAMAnalysisResult) -> Void) {
        let userApplications = aggregateUserApplications(processes: processes)
        DispatchQueue.global(qos: .utility).async {
            var sources: [RAMSource] = []

            // 1. Inactive cache is informational. macOS already reclaims it under
            // pressure, so MacCleaner does not install a root helper just to call purge.
            let inactive = memory.cached  // inactive + speculative pages
            if inactive > 50 * 1024 * 1024 {
                progress("Scanning inactive page cache")
                sources.append(RAMSource(
                    name: "Inactive Page Cache",
                    kind: .inactiveCache,
                    bytes: inactive,
                    safety: .locked,
                    detail: "Managed automatically by macOS and reclaimed under pressure.",
                    isSelected: false
                ))
            }

            // 2. Compressed memory block
            if memory.compressed > 50 * 1024 * 1024 {
                progress("Scanning compressed memory")
                sources.append(RAMSource(
                    name: "Compressed Memory",
                    kind: .compressed,
                    bytes: memory.compressed,
                    safety: .locked,
                    detail: "Managed by macOS. Closing a source app releases it safely.",
                    isSelected: false
                ))
            }

            // 3. User-facing applications ranked by their complete process-tree
            // footprint. Selection is always explicit and quitting remains graceful.
            let adaptiveThreshold = max(100 * 1_048_576, memory.total / 100)
            let topProcs = userApplications
                .filter { $0.memoryBytes >= adaptiveThreshold }
                .prefix(10)
            for proc in topProcs {
                progress("Scanning process \(proc.name)")
                sources.append(RAMSource(
                    name: proc.name,
                    kind: .topProcess,
                    bytes: proc.memoryBytes,
                    safety: .review,
                    detail: "User app · graceful Quit only · review unsaved work.",
                    isSelected: false,
                    pid: proc.id
                ))
            }

            // 4. Wired kernel memory (informational only)
            if memory.wired > 200 * 1024 * 1024 {
                progress("Scanning wired kernel memory")
                sources.append(RAMSource(
                    name: "Wired Kernel Memory",
                    kind: .wired,
                    bytes: memory.wired,
                    safety: .locked,
                    detail: "Allocated by macOS kernel. Cannot be freed without restart.",
                    isSelected: false
                ))
            }

            let freeable = sources
                .filter { $0.kind == .topProcess && $0.safety == .review }
                .reduce(UInt64(0)) { $0 + $1.bytes }
            let pressure: String
            let pct = memory.usedPercent
            if pct > 0.9      { pressure = "Critical" }
            else if pct > 0.75 { pressure = "High" }
            else if pct > 0.6  { pressure = "Moderate" }
            else               { pressure = "Normal" }

            let result = RAMAnalysisResult(
                sources: sources,
                totalFreeable: freeable,
                inactiveBytes: inactive,
                compressedBytes: memory.compressed,
                wiredBytes: memory.wired,
                pressure: pressure
            )
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func closeSelectedApplications(
        items: [RAMSource],
        completion: @escaping (RAMCleanResult) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let selected = items.filter {
                $0.isSelected && $0.kind == .topProcess && $0.safety == .review && $0.pid != nil
            }
            var pending: [(source: RAMSource, application: NSRunningApplication)] = []
            var refusedCount = 0

            for item in selected {
                guard let pid = item.pid,
                      let application = NSRunningApplication(processIdentifier: pid),
                      isSafeUserApplication(application, fallbackName: item.name),
                      application.terminate() else {
                    refusedCount += 1
                    continue
                }
                pending.append((item, application))
            }

            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline, pending.contains(where: { !$0.application.isTerminated }) {
                Thread.sleep(forTimeInterval: 0.1)
            }

            let closed = pending.filter { $0.application.isTerminated }
            refusedCount += pending.count - closed.count
            let result = RAMCleanResult(
                requestedCount: selected.count,
                closedCount: closed.count,
                refusedCount: refusedCount,
                estimatedReleasedBytes: closed.reduce(0) { $0 &+ $1.source.bytes }
            )
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Authorization-based purge

    /// Kept for call-site compatibility. macOS manages inactive/compressed memory;
    /// MacCleaner deliberately performs no privileged purge operation.
    @discardableResult
    static func runPurgeWithAuth() -> Bool {
        return false
    }


    private static func inactiveBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        return (UInt64(stats.inactive_count) + UInt64(stats.speculative_count)) * page
    }

    static func isProtectedApplicationName(_ name: String) -> Bool {
        protectedProcessNames.contains { protected in
            name.localizedCaseInsensitiveCompare(protected) == .orderedSame
        }
    }

    private static func isSafeUserApplication(
        _ application: NSRunningApplication,
        fallbackName: String
    ) -> Bool {
        guard application.processIdentifier != Foundation.ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated,
              application.activationPolicy != .prohibited else {
            return false
        }
        let name = application.localizedName ?? fallbackName
        guard !isProtectedApplicationName(name) else { return false }
        if application.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        return true
    }

    private static func aggregateUserApplications(processes: [ProcessNode]) -> [AppProcessInfo] {
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated
                && $0.activationPolicy != .prohibited
                && $0.processIdentifier != Foundation.ProcessInfo.processInfo.processIdentifier
                && !isProtectedApplicationName($0.localizedName ?? "")
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        let applicationsByPID = Dictionary(uniqueKeysWithValues: running.map { ($0.processIdentifier, $0) })
        let applicationPIDs = Set(applicationsByPID.keys)
        let parentByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.id, $0.parentPID) })

        var memoryByApplication: [Int32: UInt64] = [:]
        var cpuByApplication: [Int32: Double] = [:]
        for process in processes {
            var currentPID = process.id
            var visited: Set<Int32> = []
            while currentPID > 0, visited.insert(currentPID).inserted {
                if applicationPIDs.contains(currentPID) {
                    memoryByApplication[currentPID, default: 0] &+= process.memoryBytes
                    cpuByApplication[currentPID, default: 0] += process.cpuUsage
                    break
                }
                guard let parentPID = parentByPID[currentPID], parentPID != currentPID else { break }
                currentPID = parentPID
            }
        }

        return applicationsByPID.compactMap { pid, application in
            guard let bytes = memoryByApplication[pid], bytes > 0 else { return nil }
            return AppProcessInfo(
                id: pid,
                name: application.localizedName ?? "Application",
                cpuUsage: cpuByApplication[pid] ?? 0,
                memoryBytes: bytes
            )
        }
        .sorted { $0.memoryBytes > $1.memoryBytes }
    }
}

// MARK: - SSD / Cache Cleaner

struct CleanableItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let category: CleanCategory
    var sizeBytes: Int64
    var isSelected: Bool

    init(name: String, path: String, category: CleanCategory, sizeBytes: Int64 = 0, isSelected: Bool? = nil) {
        self.name = name
        self.path = path
        self.category = category
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected ?? category.isSelectedByDefault
    }
}

struct DiskCleanScanResult {
    let items: [CleanableItem]
    let wasLimited: Bool
    let scannedEntryCount: Int
}

enum DiskCleanScanMode: String, Sendable {
    case efficient = "Efficient"
    case thorough = "Thorough"

    var maximumEntries: Int { self == .efficient ? 80_000 : 500_000 }
    var maximumDuration: TimeInterval { self == .efficient ? 12 : 60 }
    var maximumEntriesPerRoot: Int { self == .efficient ? 5_000 : 50_000 }
    var maximumDurationPerRoot: TimeInterval { self == .efficient ? 0.45 : 3 }
}

enum DiskScanRoot: String, CaseIterable, Identifiable, Hashable, Sendable {
    case browser
    case developer
    case ai
    case applications
    case logs
    case savedState
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browser: return "Browser caches"
        case .developer: return "Developer tools"
        case .ai: return "AI tools"
        case .applications: return "Application caches"
        case .logs: return "Logs and reports"
        case .savedState: return "Saved application state"
        case .trash: return "Trash"
        }
    }

    var detail: String {
        switch self {
        case .browser: return "Chrome, Safari, Firefox and other browser cache data"
        case .developer: return "Xcode, npm, pip, Gradle, Docker build and tool caches"
        case .ai: return "Temporary AI-tool caches and old agent artifacts"
        case .applications: return "Caches created by installed applications"
        case .logs: return "Xcode, simulator and crash reports"
        case .savedState: return "Restorable window and application state"
        case .trash: return "Items already in the user Trash"
        }
    }
}

enum CleanCategory: String, CaseIterable {
    case browserCache  = "Browser Caches"
    case devCache      = "Developer Caches"
    case aiTools       = "AI Tools"
    case userCache     = "App Caches"
    case miscCache     = "Misc Caches"
    case systemCache   = "System Caches"
    case logs          = "User Logs"
    case savedState    = "Saved App State"
    case trash         = "Trash"
    case downloads     = "Large Downloads"

    var scanRoot: DiskScanRoot {
        switch self {
        case .browserCache: return .browser
        case .devCache: return .developer
        case .aiTools: return .ai
        case .userCache, .miscCache, .systemCache: return .applications
        case .logs: return .logs
        case .savedState: return .savedState
        case .trash: return .trash
        case .downloads: return .applications
        }
    }

    var isSelectedByDefault: Bool {
        switch self {
        case .browserCache, .userCache, .miscCache:
            return true
        case .devCache, .aiTools, .systemCache, .logs, .savedState, .trash, .downloads:
            return false
        }
    }

    var icon: String {
        switch self {
        case .browserCache: return "globe"
        case .devCache:     return "hammer"
        case .aiTools:      return "cpu"
        case .userCache:    return "archivebox"
        case .miscCache:    return "tray.full"
        case .systemCache:  return "gearshape.2"
        case .logs:         return "doc.text"
        case .savedState:   return "clock.arrow.circlepath"
        case .trash:        return "trash"
        case .downloads:    return "arrow.down.circle"
        }
    }

    var safetyLabel: String {
        switch self {
        case .browserCache: return "Safe"
        case .devCache:     return "Review"
        case .aiTools:      return "Review"
        case .userCache:    return "Safe"
        case .miscCache:    return "Safe"
        case .systemCache:  return "Review"
        case .logs:         return "Review"
        case .savedState:   return "Review"
        case .trash:        return "Review"
        case .downloads:    return "Review"
        }
    }

    var safetyColor: String {
        switch self {
        case .devCache, .aiTools, .systemCache, .logs, .savedState, .trash, .downloads: return "amber"
        default:         return "green"
        }
    }

    var color: Color {
        switch self {
        case .browserCache: return Color(red: 0.25, green: 0.65, blue: 1.0)
        case .devCache:     return Color(red: 0.55, green: 0.45, blue: 0.9)
        case .aiTools:      return Color(red: 0.45, green: 0.7,  blue: 0.95)
        case .userCache:    return Color(red: 0.3,  green: 0.75, blue: 0.55)
        case .miscCache:    return Color(red: 0.5,  green: 0.6,  blue: 0.7)
        case .systemCache:  return Color(red: 0.45, green: 0.5,  blue: 0.6)
        case .logs:         return Color(red: 0.6,  green: 0.6,  blue: 0.65)
        case .savedState:   return Color(red: 0.9,  green: 0.65, blue: 0.3)
        case .trash:        return Color(red: 0.65, green: 0.65, blue: 0.7)
        case .downloads:    return Color(red: 0.95, green: 0.55, blue: 0.3)
        }
    }
}

final class DiskCleaner {

    static func scan(mode: DiskCleanScanMode = .efficient,
                     roots: Set<DiskScanRoot> = Set(DiskScanRoot.allCases),
                     excludingPaths: Set<String> = [],
                     progress: @escaping (String) -> Void = { _ in },
                     completion: @escaping (DiskCleanScanResult) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var items: [CleanableItem] = []
            let fm = FileManager.default
            let home = NSHomeDirectory()
            var resourceBudget = ScanResourceBudget(
                maximumEntries: mode.maximumEntries,
                maximumDuration: mode.maximumDuration
            )
            let protectionPolicy = SafeDeletionService.currentProtectionPolicy()
            var lastProgressAt = Date.distantPast

            func emitProgress(_ message: String) {
                let now = Date()
                guard now.timeIntervalSince(lastProgressAt) >= 0.08 else { return }
                lastProgressAt = now
                progress(message)
            }

            func estimateSize(_ path: String) -> Int64 {
                guard !excludingPaths.contains(path) else { return 0 }
                let url = URL(fileURLWithPath: path)
                guard resourceBudget.beginRoot(),
                      !SafeDeletionService.isApplicationOwnedPath(url, policy: protectionPolicy) else { return 0 }
                return dirSize(
                    path: path,
                    budget: &resourceBudget,
                    protectionPolicy: protectionPolicy,
                    maximumEntriesPerRoot: mode.maximumEntriesPerRoot,
                    maximumDurationPerRoot: mode.maximumDurationPerRoot
                )
            }

            let targets: [(String, String, CleanCategory)] = [
                // ── Browser caches (user-space, fully safe) ──
                ("\(home)/Library/Caches/Google/Chrome", "Chrome Cache", .browserCache),
                ("\(home)/Library/Application Support/Google/Chrome/Default/Cache", "Chrome Network Cache", .browserCache),
                ("\(home)/Library/Application Support/Google/Chrome/Default/Code Cache", "Chrome Code Cache", .browserCache),
                ("\(home)/Library/Caches/com.apple.Safari", "Safari Cache", .browserCache),
                ("\(home)/Library/Caches/com.mozilla.firefox", "Firefox Cache", .browserCache),
                ("\(home)/Library/Caches/com.microsoft.edgemac", "Edge Cache", .browserCache),
                ("\(home)/Library/Application Support/Arc/User Data/Default/Cache", "Arc Cache", .browserCache),
                ("\(home)/Library/Application Support/Arc/User Data/Default/Code Cache", "Arc Code Cache", .browserCache),
                ("\(home)/Library/Caches/com.brave.Browser", "Brave Cache", .browserCache),
                ("\(home)/.cache/puppeteer", "Puppeteer Cache", .browserCache),

                // ── Developer caches (safe to remove, rebuilt automatically) ──
                ("\(home)/Library/Developer/Xcode/DerivedData", "Xcode DerivedData", .devCache),
                ("\(home)/Library/Developer/CoreSimulator/Caches", "Simulator Caches", .devCache),
                ("\(home)/Library/Caches/com.apple.dt.Xcode", "Xcode Index Cache", .devCache),
                ("\(home)/.npm/_cacache", "npm Cache", .devCache),
                ("\(home)/.npm/_prebuilds", "npm Prebuilds", .devCache),
                ("\(home)/.npm/_logs", "npm Logs", .devCache),
                ("\(home)/.cache/yarn", "Yarn Cache", .devCache),
                ("\(home)/Library/Caches/pip", "pip Cache", .devCache),
                ("\(home)/.gradle/caches", "Gradle Cache", .devCache),
                ("\(home)/.cache/node/corepack", "Corepack Cache", .devCache),
                ("\(home)/.docker/buildx", "Docker BuildX Cache", .devCache),

                // ── AI Tools (temporary caches, old versions — local models are kept) ──
                ("\(home)/.gemini/antigravity-browser-profile/Default/Cache", "Gemini Browser Cache", .aiTools),
                ("\(home)/.gemini/antigravity-browser-profile/Default/Code Cache", "Gemini Code Cache", .aiTools),
                ("\(home)/.gemini/antigravity-browser-profile/Default/GPUCache", "Gemini GPU Cache", .aiTools),
                ("\(home)/.gemini/tmp", "Gemini Temp", .aiTools),
                ("\(home)/.continue/cache", "Continue Cache", .aiTools),
                ("\(home)/.aider/cache", "Aider Cache", .aiTools),

                // ── App caches (user ~/Library/Caches subdirs, not the parent) ──
                ("\(home)/Library/Caches/com.spotify.client", "Spotify Cache", .userCache),
                ("\(home)/Library/Caches/com.apple.Music", "Music Cache", .userCache),
                ("\(home)/Library/Caches/com.apple.podcasts", "Podcasts Cache", .userCache),
                ("\(home)/Library/Caches/com.tinyspeck.slackmacgap", "Slack Cache", .userCache),
                ("\(home)/Library/Caches/com.microsoft.VSCode", "VS Code Cache", .userCache),
                ("\(home)/Library/Caches/com.figma.desktop", "Figma Cache", .userCache),

                // ── Misc caches ──
                ("\(home)/Library/Caches/Steam", "Steam Cache", .miscCache),
                ("\(home)/Library/Caches/com.mitchellh.ghostty", "Ghostty Cache", .miscCache),
                ("\(home)/Library/Application Support/Spotify/PersistentCache", "Spotify Persistent Cache", .miscCache),
                ("\(home)/Library/Application Support/Steam/appcache", "Steam App Cache", .miscCache),
                ("\(home)/Library/Application Support/Steam/logs", "Steam Logs", .miscCache),
                ("\(home)/Library/Application Support/Steam/depotcache", "Steam Depot Cache", .miscCache),

                // ── User logs (~/Library/Logs only — not /Library/Logs) ──
                ("\(home)/Library/Logs/Xcode", "Xcode Logs", .logs),
                ("\(home)/Library/Logs/DiagnosticReports", "Crash Reports", .logs),
                ("\(home)/Library/Logs/CoreSimulator", "Simulator Logs", .logs),
                ("\(home)/Library/Application Support/CrashReporter", "App Crash Reports", .logs),

                // ── Saved Application State (restored windows — safe to clear) ──
                ("\(home)/Library/Saved Application State", "Saved App State", .savedState),

                // ── Trash ──
                ("\(home)/.Trash", "Trash", .trash),
            ]

            // ── Dynamic AI tool scans ──
            // Cursor Agent old versions
            let cursorVersionsDir = "\(home)/.local/share/cursor-agent/versions"
            if fm.fileExists(atPath: cursorVersionsDir),
               roots.contains(.ai),
               let contents = try? fm.contentsOfDirectory(atPath: cursorVersionsDir) {
                // Keep the newest version, mark older ones for cleanup
                let sorted = contents.sorted().reversed()
                for (i, version) in sorted.enumerated() {
                    guard i > 0 else { continue } // skip newest
                    let versionPath = (cursorVersionsDir as NSString).appendingPathComponent(version)
                    let size = estimateSize(versionPath)
                    guard size > 1024 * 1024 else { continue }
                    items.append(CleanableItem(name: "Cursor Agent Old Version \(version)", path: versionPath, category: .aiTools, sizeBytes: size))
                }
            }

            // Obsolete VS Code / Cursor extensions
            for (dir, label) in [
                ("\(home)/.vscode/extensions", "Obsolete VS Code Extension"),
                ("\(home)/.cursor/extensions", "Obsolete Cursor Extension"),
            ] {
                guard roots.contains(.developer) else { continue }
                if fm.fileExists(atPath: dir),
                   let contents = try? fm.contentsOfDirectory(atPath: dir) {
                    for ext in contents {
                        let extPath = (dir as NSString).appendingPathComponent(ext)
                        let size = estimateSize(extPath)
                        guard size > 5 * 1024 * 1024 else { continue }
                        items.append(CleanableItem(name: "\(label) \(ext)", path: extPath, category: .devCache, sizeBytes: size, isSelected: false))
                    }
                }
            }

            for (path, name, category) in targets {
                guard roots.contains(category.scanRoot) else { continue }
                guard fm.fileExists(atPath: path) else { continue }
                emitProgress("Scanning \(name)")
                let size = estimateSize(path)
                guard size > 1024 * 1024 else { continue }
                items.append(CleanableItem(name: name, path: path, category: category, sizeBytes: size))
            }

            // Collect already-added paths so dynamic scan doesn't duplicate
            let knownPaths = Set(items.map(\.path))

            // ── Dynamic: all ~/Library/Caches/* subdirs (App Caches) ──
            let cachesDir = "\(home)/Library/Caches"
            if roots.contains(.applications), let subdirs = try? fm.contentsOfDirectory(atPath: cachesDir) {
                for sub in subdirs {
                    let fullPath = (cachesDir as NSString).appendingPathComponent(sub)
                    guard !knownPaths.contains(fullPath) else { continue }
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
                    emitProgress("Scanning \(sub) cache")
                    let size = estimateSize(fullPath)
                    guard size > 512 * 1024 else { continue } // 512 KB min
                    items.append(CleanableItem(name: sub, path: fullPath, category: .userCache, sizeBytes: size))
                }
            }

            // ── Dynamic: ~/Library/Application Support/*/CachedData|GPUCache|Cache|Code Cache|Dawn* ──
            let appSupportDir = "\(home)/Library/Application Support"
            let appSupportSubdirNames = ["CachedData", "GPUCache", "Cache", "Code Cache",
                                         "DawnGraphiteCache", "DawnWebGPUCache", "GraphiteDawnCache",
                                         "DawnCache", "ShaderCache", "Service Worker/CacheStorage", "Service Worker/ScriptCache"]
            if roots.contains(.applications), let apps = try? fm.contentsOfDirectory(atPath: appSupportDir) {
                for app in apps {
                    let appDir = (appSupportDir as NSString).appendingPathComponent(app)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: appDir, isDirectory: &isDir), isDir.boolValue else { continue }
                    for subName in appSupportSubdirNames {
                        let subPath = (appDir as NSString).appendingPathComponent(subName)
                        guard !knownPaths.contains(subPath) else { continue }
                        guard fm.fileExists(atPath: subPath) else { continue }
                        emitProgress("Scanning \(app) \(subName)")
                        let size = estimateSize(subPath)
                        guard size > 512 * 1024 else { continue }
                        let label = "\(app) \(subName)"
                        items.append(CleanableItem(name: label, path: subPath, category: .userCache, sizeBytes: size))
                    }
                }
            }

            // ── Dynamic: Chrome / Chromium multi-profile caches ──
            let chromiumApps = [
                ("\(home)/Library/Application Support/Google/Chrome", "Chrome"),
            ]
            let profileSubdirs = ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage",
                                  "Service Worker/ScriptCache", "component_crx_cache"]
            for (appPath, appName) in chromiumApps where roots.contains(.browser) {
                guard fm.fileExists(atPath: appPath),
                      let profiles = try? fm.contentsOfDirectory(atPath: appPath) else { continue }
                for profile in profiles {
                    let profileDir = (appPath as NSString).appendingPathComponent(profile)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: profileDir, isDirectory: &isDir), isDir.boolValue else { continue }
                    guard profile.hasPrefix("Profile") || profile == "Default" else { continue }
                    for sub in profileSubdirs {
                        let subPath = (profileDir as NSString).appendingPathComponent(sub)
                        guard !knownPaths.contains(subPath) else { continue }
                        guard fm.fileExists(atPath: subPath) else { continue }
                        let label = "\(appName) \(profile) \(sub.replacingOccurrences(of: "/", with: " "))"
                        emitProgress("Scanning \(label)")
                        let size = estimateSize(subPath)
                        guard size > 512 * 1024 else { continue }
                        items.append(CleanableItem(name: label, path: subPath, category: .browserCache, sizeBytes: size))
                    }
                }
            }

            // Deduplicate: remove items whose path is a child of another item
            let allPaths = items.map(\.path).sorted { $0.count < $1.count }
            var parentPaths: [String] = []
            for path in allPaths {
                let isChild = parentPaths.contains { parent in
                    path.hasPrefix(parent + "/")
                }
                if !isChild {
                    parentPaths.append(path)
                }
            }
            let parentSet = Set(parentPaths)
            items = items.filter {
                parentSet.contains($0.path)
                    && !SafeDeletionService.isApplicationOwnedPath(
                        URL(fileURLWithPath: $0.path),
                        policy: protectionPolicy
                    )
            }

            items.sort { $0.sizeBytes > $1.sizeBytes }
            let result = DiskCleanScanResult(
                items: items,
                wasLimited: resourceBudget.wasLimited,
                scannedEntryCount: resourceBudget.consumedEntries
            )
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func clean(items: [CleanableItem], completion: @escaping (Int64, [String]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            var freed: Int64 = 0
            var errors: [String] = []
            var statsInputs: [CleanupStatsRecordInput] = []
            var measurementBudget = ScanResourceBudget(maximumEntries: 50_000, maximumDuration: 5)
            let protectionPolicy = SafeDeletionService.currentProtectionPolicy()

            for item in items where item.isSelected {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
                let statsCategory = CleanupStatsStore.category(for: item.category)

                do {
                    if item.category == .trash {
                        errors.append("\(item.name): use Finder's Empty Trash command for permanent deletion")
                        continue
                    }
                    if isDir.boolValue {
                        // Empty the directory but keep the folder itself so apps/OS
                        // are less likely to immediately refill the cache.
                        let contents = try fm.contentsOfDirectory(atPath: item.path)
                        for file in contents {
                            let full = (item.path as NSString).appendingPathComponent(file)
                            let url = URL(fileURLWithPath: full)
                            guard !SafeDeletionService.isProtectedApplicationPath(url, policy: protectionPolicy) else {
                                continue
                            }
                            let sizeBefore = dirSize(
                                path: full,
                                budget: &measurementBudget,
                                protectionPolicy: protectionPolicy
                            )
                            _ = try SafeDeletionService.moveToTrash(url, policy: protectionPolicy)
                            freed += sizeBefore
                            statsInputs.append(CleanupStatsRecordInput(
                                path: full,
                                displayName: file,
                                category: statsCategory,
                                bytes: UInt64(max(0, sizeBefore)),
                                source: "Optimize"
                            ))
                        }
                    } else {
                        // Single file (e.g. large download)
                        let url = URL(fileURLWithPath: item.path)
                        guard !SafeDeletionService.isProtectedApplicationPath(url, policy: protectionPolicy) else {
                            continue
                        }
                        let sizeBefore = dirSize(
                            path: item.path,
                            budget: &measurementBudget,
                            protectionPolicy: protectionPolicy
                        )
                        _ = try SafeDeletionService.moveToTrash(url, policy: protectionPolicy)
                        freed += sizeBefore
                        statsInputs.append(CleanupStatsRecordInput(
                            path: item.path,
                            displayName: item.name,
                            category: statsCategory,
                            bytes: UInt64(max(0, sizeBefore)),
                            source: "Optimize"
                        ))
                    }
                } catch {
                    errors.append("\(item.name): \(error.localizedDescription)")
                }
            }

            if !statsInputs.isEmpty {
                DispatchQueue.main.async {
                    CleanupStatsStore.shared.record(statsInputs)
                }
            }

            DispatchQueue.main.async { completion(freed, errors) }
        }
    }

    private static func dirSize(
        path: String,
        budget: inout ScanResourceBudget,
        protectionPolicy: SafeDeletionService.ProtectionPolicy,
        maximumEntriesPerRoot: Int = 5_000,
        maximumDurationPerRoot: TimeInterval = 0.45
    ) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            guard budget.consumeEntry() else { return 0 }
            let attributes = try? fm.attributesOfItem(atPath: path)
            return attributes?[.size] as? Int64 ?? 0
        }

        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey
        ]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        let rootDeadline = Date().addingTimeInterval(maximumDurationPerRoot)
        var total: Int64 = 0
        var rootEntries = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if rootEntries >= maximumEntriesPerRoot
                || (rootEntries.isMultiple(of: 64) && Date() >= rootDeadline) {
                budget.markLimited()
                break
            }
            guard budget.consumeEntry() else { break }
            rootEntries += 1
            let values = try? fileURL.resourceValues(forKeys: keys)
            if SafeDeletionService.isApplicationOwnedPath(fileURL, policy: protectionPolicy) {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let size = values?.totalFileAllocatedSize
                ?? values?.fileAllocatedSize
                ?? values?.fileSize
                ?? 0
            total += Int64(size)
        }
        return total
    }

    static func formattedSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 0.1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 0.1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}

// MARK: - DNS Cache Cleaner

final class DNSCleaner {
    static func flush(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            @discardableResult
            func run(_ exe: String, _ args: [String]) -> Bool {
                let t = Process()
                t.executableURL = URL(fileURLWithPath: exe)
                t.arguments = args
                t.standardOutput = Pipe()
                t.standardError  = Pipe()
                do {
                    let semaphore = DispatchSemaphore(value: 0)
                    t.terminationHandler = { _ in semaphore.signal() }
                    try t.run()
                    if semaphore.wait(timeout: .now() + 5) == .timedOut {
                        t.terminate()
                        return false
                    }
                    return t.terminationStatus == 0
                } catch {
                    return false
                }
            }
            // dscacheutil flushes user-space DNS cache (no sudo needed)
            let ok1 = run("/usr/bin/dscacheutil", ["-flushcache"])
            // notify mDNSResponder to drop its cache (SIGHUP to own process is allowed)
            let ok2 = run("/bin/bash", ["-c", "kill -HUP $(pgrep mDNSResponder) 2>/dev/null || true"])
            let ok = ok1 || ok2
            DispatchQueue.main.async {
                completion(ok, ok ? "DNS cache cleared" : "Partial flush — user cache cleared")
            }
        }
    }
}

// MARK: - System Refresh Service

struct RefreshTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    var isSelected: Bool = true
    var state: RefreshTaskState = .pending
}

enum RefreshTaskState {
    case pending, running, done, failed
}

final class SystemRefreshService {

    static func allTasks() -> [RefreshTask] {
        [
            RefreshTask(id: "quicklook_cache", title: "Rebuild QuickLook cache", detail: "qlmanage -r cache"),
            RefreshTask(id: "quicklook_thumbs", title: "Rebuild QuickLook thumbnails", detail: "qlmanage -r"),
            RefreshTask(id: "saved_window_state", title: "Clear stale saved window state", detail: "Moves entries to Trash", isSelected: false),
            RefreshTask(id: "quarantine", title: "Clear quarantine history", detail: "Moves quarantine database to Trash", isSelected: false),
            RefreshTask(id: "font_cache", title: "Rebuild font cache", detail: "atsutil databases -remove", isSelected: false),
            RefreshTask(id: "launch_services", title: "Rebuild Launch Services database", detail: "lsregister -r", isSelected: false),
            RefreshTask(id: "shared_file_list", title: "Clean empty shared file list entries", detail: "~/Library/Application Support/com.apple.sharedfilelist"),
            RefreshTask(id: "broken_launch_agents", title: "Remove broken Launch Agents", detail: "Moves invalid entries to Trash", isSelected: false),
            RefreshTask(id: "notification_db", title: "Prune Notification Center database", detail: "Review: modifies live database sidecars", isSelected: false),
            RefreshTask(id: "orphaned_spotlight", title: "Remove orphaned Spotlight rules", detail: "Spotlight exclusion entries", isSelected: false),
            RefreshTask(id: "login_items", title: "Audit Login Items", detail: "SMAppService / legacy login items", isSelected: false),
            RefreshTask(id: "ds_store_network", title: "Prevent .DS_Store on network drives", detail: "defaults write DSDontWriteNetworkStores"),
            RefreshTask(id: "usage_db", title: "Trim oversized usage database", detail: "Review: modifies live database sidecars", isSelected: false),
            RefreshTask(id: "corrupted_prefs", title: "Recover corrupted preferences", detail: "Moves invalid plists to Trash", isSelected: false),
        ]
    }

    static func execute(task: RefreshTask, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let ok: Bool
            switch task.id {
            case "quicklook_cache":
                ok = run("/usr/bin/qlmanage", ["-r", "cache"])
            case "quicklook_thumbs":
                ok = run("/usr/bin/qlmanage", ["-r"])
            case "saved_window_state":
                ok = clearDirectory("\(NSHomeDirectory())/Library/Saved Application State")
            case "quarantine":
                ok = clearQuarantineHistory()
            case "font_cache":
                ok = run("/usr/bin/atsutil", ["databases", "-remove"])
            case "launch_services":
                ok = rebuildLaunchServices()
            case "shared_file_list":
                ok = cleanSharedFileLists()
            case "broken_launch_agents":
                ok = removeBrokenLaunchAgents()
            case "notification_db":
                ok = pruneNotificationDB()
            case "orphaned_spotlight":
                ok = removeOrphanedSpotlightRules()
            case "login_items":
                ok = auditLoginItems()
            case "ds_store_network":
                ok = run("/usr/bin/defaults", ["write", "com.apple.desktopservices", "DSDontWriteNetworkStores", "-bool", "true"])
                     && run("/usr/bin/defaults", ["write", "com.apple.desktopservices", "DSDontWriteUSBStores", "-bool", "true"])
            case "usage_db":
                ok = trimUsageDB()
            case "corrupted_prefs":
                ok = recoverCorruptedPrefs()
            default:
                ok = false
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> Bool {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: exe)
        t.arguments = args
        t.standardOutput = Pipe()
        t.standardError  = Pipe()
        do {
            let semaphore = DispatchSemaphore(value: 0)
            t.terminationHandler = { _ in semaphore.signal() }
            try t.run()
            if semaphore.wait(timeout: .now() + 20) == .timedOut {
                t.terminate()
                return false
            }
            return t.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func clearDirectory(_ path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return true }
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return false }
        var ok = true
        for item in contents {
            let full = (path as NSString).appendingPathComponent(item)
            do { _ = try SafeDeletionService.moveToTrash(URL(fileURLWithPath: full)) } catch { ok = false }
        }
        return ok
    }

    private static func clearQuarantineHistory() -> Bool {
        let home = NSHomeDirectory()
        let dbPath = "\(home)/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
        let fm = FileManager.default
        if fm.fileExists(atPath: dbPath) {
            do { _ = try SafeDeletionService.moveToTrash(URL(fileURLWithPath: dbPath)); return true } catch { return false }
        }
        return true
    }

    private static func cleanSharedFileLists() -> Bool {
        let path = "\(NSHomeDirectory())/Library/Application Support/com.apple.sharedfilelist"
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return true }
        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return true }
        for file in files {
            let full = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let size = attrs[.size] as? Int, size == 0 {
                _ = try? SafeDeletionService.moveToTrash(URL(fileURLWithPath: full))
            }
        }
        return true
    }

    private static func removeBrokenLaunchAgents() -> Bool {
        let path = "\(NSHomeDirectory())/Library/LaunchAgents"
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return true }
        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return true }
        for file in files where file.hasSuffix(".plist") {
            let full = (path as NSString).appendingPathComponent(file)
            if let data = fm.contents(atPath: full) {
                let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil)
                guard let dict = parsed as? [String: Any] else { continue }
                if let prog = dict["Program"] as? String, !fm.fileExists(atPath: prog) {
                    _ = try? SafeDeletionService.moveToTrash(URL(fileURLWithPath: full))
                }
                if let args = dict["ProgramArguments"] as? [String],
                   let exe = args.first, !fm.fileExists(atPath: exe) {
                    _ = try? SafeDeletionService.moveToTrash(URL(fileURLWithPath: full))
                }
            }
        }
        return true
    }

    private static func pruneNotificationDB() -> Bool {
        let home = NSHomeDirectory()
        let ncDir = "\(home)/Library/GroupContainers"
        let fm = FileManager.default
        guard fm.fileExists(atPath: ncDir),
              let groups = try? fm.contentsOfDirectory(atPath: ncDir) else { return true }
        for group in groups where group.contains("com.apple.notificationcenterui") {
            let dbDir = (ncDir as NSString).appendingPathComponent(group)
            if let files = try? fm.contentsOfDirectory(atPath: dbDir) {
                for file in files where file.hasSuffix(".db-wal") || file.hasSuffix(".db-shm") {
                    _ = try? SafeDeletionService.moveToTrash(URL(fileURLWithPath: (dbDir as NSString).appendingPathComponent(file)))
                }
            }
        }
        return true
    }

    private static func removeOrphanedSpotlightRules() -> Bool {
        // Reset Spotlight privacy settings for home dir (safe, non-destructive)
        let home = NSHomeDirectory()
        let plistPath = "\(home)/Library/Preferences/com.apple.Spotlight.plist"
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistPath),
              let data = fm.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let exclusions = plist["EXCLUSIONS"] as? [[String: Any]] else { return true }
        // Remove exclusions pointing to non-existent paths
        let cleaned = exclusions.filter { entry in
            guard let path = entry["path"] as? String else { return true }
            return fm.fileExists(atPath: path)
        }
        if cleaned.count < exclusions.count {
            var updated = plist
            updated["EXCLUSIONS"] = cleaned
            if let newData = try? PropertyListSerialization.data(fromPropertyList: updated, format: .xml, options: 0) {
                try? newData.write(to: URL(fileURLWithPath: plistPath))
            }
        }
        return true
    }

    private static func auditLoginItems() -> Bool {
        // Clean up broken LaunchAgents (login items) by checking plist validity
        let laPath = "\(NSHomeDirectory())/Library/LaunchAgents"
        let fm = FileManager.default
        guard fm.fileExists(atPath: laPath),
              let files = try? fm.contentsOfDirectory(atPath: laPath) else { return true }
        for file in files where file.hasSuffix(".plist") {
            let full = (laPath as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: full) else { continue }
            let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil)
            if parsed == nil {
                _ = try? SafeDeletionService.moveToTrash(URL(fileURLWithPath: full))
            }
        }
        return true
    }

    private static func rebuildLaunchServices() -> Bool {
        // Try multiple known paths for lsregister
        let candidates = [
            "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister",
            "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister",
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
        ]
        let fm = FileManager.default
        for path in candidates {
            if fm.fileExists(atPath: path) {
                // -kill was removed in newer macOS; just -r to rebuild
                return run(path, ["-r", "-domain", "local", "-domain", "user"])
            }
        }
        return run("/bin/bash", ["-c", "$(find /System/Library/Frameworks/CoreServices.framework -name lsregister -type f 2>/dev/null | head -1) -r -domain local -domain user"])
    }

    private static func trimUsageDB() -> Bool {
        let home = NSHomeDirectory()
        let knowledgePath = "\(home)/Library/Application Support/Knowledge"
        let fm = FileManager.default
        guard fm.fileExists(atPath: knowledgePath),
              let files = try? fm.contentsOfDirectory(atPath: knowledgePath) else { return true }
        for file in files where file.hasSuffix(".db-wal") || file.hasSuffix(".db-shm") {
            _ = try? SafeDeletionService.moveToTrash(URL(fileURLWithPath: (knowledgePath as NSString).appendingPathComponent(file)))
        }
        return true
    }

    private static func recoverCorruptedPrefs() -> Bool {
        let prefsPath = "\(NSHomeDirectory())/Library/Preferences"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: prefsPath) else { return true }
        for file in files where file.hasSuffix(".plist") {
            let full = (prefsPath as NSString).appendingPathComponent(file)
            if let data = fm.contents(atPath: full) {
                let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil)
                if parsed == nil {
                    // Corrupted — remove so macOS recreates with defaults
                    _ = try? SafeDeletionService.moveToTrash(URL(fileURLWithPath: full))
                }
            }
        }
        return true
    }
}
