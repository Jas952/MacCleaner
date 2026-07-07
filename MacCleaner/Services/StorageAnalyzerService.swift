import Foundation
import SwiftUI
import CoreGraphics

// MARK: - Junk Models

struct JunkCategory: Identifiable {
    let id = UUID()
    let type: JunkType
    var size: UInt64
    var files: [URL]
    var cleanupRoots: [URL] = []
    var fileCount: Int? = nil

    var name: String { type.name }
    var icon: String { type.icon }
    var color: Color { type.color }
    var itemCount: Int { fileCount ?? files.count }
    var isSelectedByDefault: Bool { type.isSelectedByDefault }
}

enum JunkType: CaseIterable, Hashable {
    case userCache, systemCache, xcodeJunk, systemLogs, browserCache, userLogs, unusedDMG, trash, downloads, screenCaptures

    var name: String {
        switch self {
        case .userCache:      return "User Cache"
        case .systemCache:    return "System Cache"
        case .xcodeJunk:      return "Xcode Developer Cache"
        case .systemLogs:     return "System Logs"
        case .browserCache:   return "Browser Cache"
        case .userLogs:       return "User Logs"
        case .unusedDMG:      return "Unused DMGs"
        case .trash:          return "Trash"
        case .downloads:      return "Downloads"
        case .screenCaptures: return "Screen Captures"
        }
    }

    var icon: String {
        switch self {
        case .userCache:      return "person.crop.circle.badge.clock"
        case .systemCache:    return "gearshape.fill"
        case .xcodeJunk:      return "hammer.fill"
        case .systemLogs:     return "doc.text.magnifyingglass"
        case .browserCache:   return "safari.fill"
        case .userLogs:       return "doc.text"
        case .unusedDMG:      return "externaldrive.fill"
        case .trash:          return "trash.fill"
        case .downloads:      return "arrow.down.circle.fill"
        case .screenCaptures: return "camera.viewfinder"
        }
    }

    var color: Color {
        switch self {
        case .userCache:      return .yellow
        case .systemCache:    return .orange
        case .xcodeJunk:      return .blue
        case .systemLogs:     return .gray
        case .browserCache:   return .cyan
        case .userLogs:       return .gray
        case .unusedDMG:      return .secondary
        case .trash:          return .gray
        case .downloads:      return .blue
        case .screenCaptures: return .purple
        }
    }

    var detail: String {
        switch self {
        case .xcodeJunk:
            return "Rebuildable Xcode data. Safe to remove, but Xcode will recreate it and the next build may be slower."
        case .userCache:
            return "App cache in your user Library. Protected Apple caches are skipped."
        case .systemCache:
            return "System cache. Protected locations are skipped."
        case .systemLogs, .userLogs:
            return "Logs that can usually be regenerated."
        case .browserCache:
            return "Browser cache that will be recreated while browsing."
        case .trash:
            return "Items already moved to Trash."
        case .downloads:
            return "Downloaded files. Review before cleaning."
        case .unusedDMG:
            return "Disk images that are usually safe after installation."
        case .screenCaptures:
            return "Screen captures from common save locations."
        }
    }

    var isSelectedByDefault: Bool {
        switch self {
        case .xcodeJunk, .downloads:
            return false
        default:
            return true
        }
    }
}

struct JunkCleanResult {
    let success: Bool
    let removedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let message: String?

    var hasFailures: Bool { failedCount > 0 }
}

// MARK: - Cleanup Statistics

enum CleanupStatsCategory: String, Codable, CaseIterable, Hashable {
    case systemCache = "System Cache"
    case userCache = "User Cache"
    case browserCache = "Browser Cache"
    case developerCache = "Developer Cache"
    case logs = "Logs"
    case appSupport = "App Support"
    case trash = "Trash"
    case downloads = "Downloads"
    case largeFiles = "Large Files"
    case uninstall = "Uninstall"
    case other = "Other"

    var shortName: String {
        switch self {
        case .systemCache: return "System"
        case .userCache: return "Cache"
        case .browserCache: return "Browser"
        case .developerCache: return "Dev"
        case .logs: return "Logs"
        case .appSupport: return "Support"
        case .trash: return "Trash"
        case .downloads: return "Downloads"
        case .largeFiles: return "Large"
        case .uninstall: return "Apps"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .systemCache: return .accentAmber
        case .userCache, .browserCache: return .accentBlue
        case .developerCache: return .accentPurple
        case .logs, .appSupport: return .textTertiary
        case .trash, .downloads, .largeFiles: return .accentGreen
        case .uninstall: return .accentRed
        case .other: return .textSecondary
        }
    }

    var isSystemOrCache: Bool {
        switch self {
        case .systemCache, .userCache, .browserCache, .developerCache, .logs:
            return true
        case .appSupport, .trash, .downloads, .largeFiles, .uninstall, .other:
            return false
        }
    }
}

struct CleanupStatsEntry: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    var displayName: String
    var category: CleanupStatsCategory
    var cleanCount: Int
    var totalBytes: UInt64
    var lastBytes: UInt64
    var firstCleanedAt: Date
    var lastCleanedAt: Date
    var source: String

    var isSystemOrCache: Bool { category.isSystemOrCache || path.hasPrefix("/Library/") || path.hasPrefix("/System/") }
    var isRebuildable: Bool { CleanupStatsStore.isRebuildablePath(path: path, category: category) }
}

struct CleanupStatsEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let path: String
    let displayName: String
    let category: CleanupStatsCategory
    let bytes: UInt64
    let cleanedAt: Date
    let source: String

    var isRebuildable: Bool { CleanupStatsStore.isRebuildablePath(path: path, category: category) }
}

struct CleanupStatsPayload: Codable {
    var entries: [CleanupStatsEntry]
    var events: [CleanupStatsEvent]
}

struct CleanupStatsRecordInput {
    let path: String
    let displayName: String
    let category: CleanupStatsCategory
    let bytes: UInt64
    let source: String
}

@MainActor
final class CleanupStatsStore: ObservableObject {
    static let shared = CleanupStatsStore()

    @Published private(set) var entries: [CleanupStatsEntry] = []
    @Published private(set) var events: [CleanupStatsEvent] = []
    @Published private(set) var isLoaded = false

    private let maxEntries = 800
    private let maxEvents = 600
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {
        loadAsync()
    }

    var totalBytes: UInt64 {
        stableEntries.reduce(0) { $0 + $1.lastBytes }
    }

    var rebuildableBytes: UInt64 {
        rebuildableEntries.reduce(0) { $0 + $1.lastBytes }
    }

    var lifetimeThroughputBytes: UInt64 {
        entries.reduce(0) { $0 + $1.totalBytes }
    }

    var totalCleanCount: Int {
        stableEntries.reduce(0) { $0 + $1.cleanCount }
    }

    var cleanedLast30DaysBytes: UInt64 {
        uniqueBytesSince(days: 30, includeRebuildable: false)
    }

    var systemOrCacheCleanCount: Int {
        stableEntries.filter(\.isSystemOrCache).reduce(0) { $0 + $1.cleanCount }
    }

    var rebuildableCleanCount: Int {
        rebuildableEntries.reduce(0) { $0 + $1.cleanCount }
    }

    var trackedTargetCount: Int {
        entries.count
    }

    private var stableEntries: [CleanupStatsEntry] {
        entries.filter { !$0.isRebuildable }
    }

    private var rebuildableEntries: [CleanupStatsEntry] {
        entries.filter(\.isRebuildable)
    }

    var topRecurringEntries: [CleanupStatsEntry] {
        entries
            .sorted {
                if $0.cleanCount == $1.cleanCount { return $0.lastBytes > $1.lastBytes }
                return $0.cleanCount > $1.cleanCount
            }
            .prefix(5)
            .map { $0 }
    }

    var categoryTotals: [(category: CleanupStatsCategory, bytes: UInt64, count: Int)] {
        CleanupStatsCategory.allCases.compactMap { category in
            let matching = stableEntries.filter { $0.category == category }
            let bytes = matching.reduce(0) { $0 + $1.lastBytes }
            let count = matching.reduce(0) { $0 + $1.cleanCount }
            return bytes > 0 || count > 0 ? (category, bytes, count) : nil
        }
        .sorted { $0.bytes > $1.bytes }
    }

    func uniqueBytesSince(days: Int, includeRebuildable: Bool = true) -> UInt64 {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        var latestByPath: [String: CleanupStatsEvent] = [:]
        for event in events where event.cleanedAt >= cutoff {
            if !includeRebuildable && event.isRebuildable { continue }
            if let existing = latestByPath[event.path], existing.cleanedAt > event.cleanedAt {
                continue
            }
            latestByPath[event.path] = event
        }
        return latestByPath.values.reduce(0) { $0 + $1.bytes }
    }

    func record(_ inputs: [CleanupStatsRecordInput]) {
        guard !inputs.isEmpty else { return }

        var byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        let now = Date()

        for input in inputs {
            let normalizedPath = NSString(string: input.path).standardizingPath
            let displayName = input.displayName.isEmpty
                ? URL(fileURLWithPath: normalizedPath).lastPathComponent
                : input.displayName

            if var existing = byPath[normalizedPath] {
                existing.displayName = displayName
                existing.category = input.category
                existing.cleanCount += 1
                existing.totalBytes += input.bytes
                existing.lastBytes = input.bytes
                existing.lastCleanedAt = now
                existing.source = input.source
                byPath[normalizedPath] = existing
            } else {
                byPath[normalizedPath] = CleanupStatsEntry(
                    path: normalizedPath,
                    displayName: displayName,
                    category: input.category,
                    cleanCount: 1,
                    totalBytes: input.bytes,
                    lastBytes: input.bytes,
                    firstCleanedAt: now,
                    lastCleanedAt: now,
                    source: input.source
                )
            }

            events.append(CleanupStatsEvent(
                id: UUID(),
                path: normalizedPath,
                displayName: displayName,
                category: input.category,
                bytes: input.bytes,
                cleanedAt: now,
                source: input.source
            ))
        }

        entries = Self.compactEntries(Array(byPath.values), limit: maxEntries)
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        saveAsync()
    }

    nonisolated static func category(for cleanCategory: CleanCategory) -> CleanupStatsCategory {
        switch cleanCategory {
        case .browserCache: return .browserCache
        case .devCache, .aiTools: return .developerCache
        case .userCache, .miscCache, .savedState: return .userCache
        case .systemCache: return .systemCache
        case .logs: return .logs
        case .trash: return .trash
        case .downloads: return .downloads
        }
    }

    nonisolated static func category(for junkType: JunkType) -> CleanupStatsCategory {
        switch junkType {
        case .userCache: return .userCache
        case .systemCache: return .systemCache
        case .xcodeJunk: return .developerCache
        case .systemLogs, .userLogs: return .logs
        case .browserCache: return .browserCache
        case .trash: return .trash
        case .downloads, .unusedDMG, .screenCaptures: return .downloads
        }
    }

    nonisolated static func inferCategory(path: String, fallback: CleanupStatsCategory = .other) -> CleanupStatsCategory {
        let lower = path.lowercased()
        if lower.contains("/library/caches/") { return path.hasPrefix("/Library/") ? .systemCache : .userCache }
        if lower.contains("/system/library/caches") { return .systemCache }
        if lower.contains("/developer/xcode/deriveddata") { return .developerCache }
        if lower.contains("/library/logs") || lower.contains("/var/log") { return .logs }
        if lower.contains("/httpstorages/") { return .browserCache }
        if lower.contains("/application support/") { return .appSupport }
        if lower.contains("/.trash") { return .trash }
        if lower.contains("/downloads/") { return .downloads }
        return fallback
    }

    nonisolated static func isRebuildablePath(path: String, category: CleanupStatsCategory) -> Bool {
        let lower = path.lowercased()
        if category == .developerCache { return true }

        let rebuildableMarkers = [
            "/developer/xcode/deriveddata",
            "/developer/xcode/index.noindex",
            "/developer/xcode/modulecache",
            "/developer/xcode/xcuserdata",
            "/coresimulator/caches",
            "/modulecache.noindex",
            "/index.noindex",
            "/deriveddata",
            "/swiftpm",
            "/.build/",
            "/node_modules/.cache",
            "/v8.",
            "/v8-",
            "/gpucache",
            "/code cache",
            "/shadercache"
        ]

        return rebuildableMarkers.contains { lower.contains($0) }
    }

    private var storageURL: URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support
            .appendingPathComponent("MacCleaner", isDirectory: true)
            .appendingPathComponent("cleanup-stats.json")
    }

    private func loadAsync() {
        guard let storageURL else {
            isLoaded = true
            return
        }
        let maxEntries = maxEntries
        let maxEvents = maxEvents

        Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            guard let data = try? Data(contentsOf: storageURL),
                  let payload = try? decoder.decode(CleanupStatsPayload.self, from: data)
            else {
                await MainActor.run {
                    self.isLoaded = true
                }
                return
            }

            let compactEntries = Self.compactEntries(payload.entries, limit: maxEntries)
            let compactEvents = payload.events
                .sorted { $0.cleanedAt < $1.cleanedAt }
                .suffix(maxEvents)

            await MainActor.run {
                self.entries = compactEntries
                self.events = Array(compactEvents)
                self.isLoaded = true
                self.saveAsync()
            }
        }
    }

    private func saveAsync() {
        guard let storageURL else { return }
        let payload = CleanupStatsPayload(entries: entries, events: events)

        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]

            do {
                try FileManager.default.createDirectory(
                    at: storageURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try encoder.encode(payload)
                try data.write(to: storageURL, options: .atomic)
            } catch {
                print("Failed to save cleanup stats: \(error)")
            }
        }
    }

    nonisolated private static func compactEntries(_ entries: [CleanupStatsEntry], limit: Int) -> [CleanupStatsEntry] {
        Array(
            entries
                .sorted {
                    if $0.lastCleanedAt == $1.lastCleanedAt {
                        if $0.cleanCount == $1.cleanCount { return $0.lastBytes > $1.lastBytes }
                        return $0.cleanCount > $1.cleanCount
                    }
                    return $0.lastCleanedAt > $1.lastCleanedAt
                }
                .prefix(limit)
        )
    }
}

// MARK: - FS Models

enum FSNodeCategory: String {
    case folder = "Folder"
    case app = "Application"
    case video = "Video"
    case image = "Image"
    case document = "Document"
    case archive = "Archive"
    case unknown = "File"

    var color: Color {
        switch self {
        case .folder:   return Color.indigo.opacity(0.8)
        case .app:      return Color.pink.opacity(0.8)
        case .video:    return Color.red.opacity(0.8)
        case .image:    return Color.cyan.opacity(0.8)
        case .document: return Color.blue.opacity(0.8)
        case .archive:  return Color.orange.opacity(0.8)
        case .unknown:  return Color.gray.opacity(0.8)
        }
    }
}

struct FSNode: Identifiable, Equatable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: UInt64
    let creationDate: Date?
    let lastAccessDate: Date?
    let category: FSNodeCategory
    let isDeletable: Bool
    var children: [FSNode]?

    static func == (lhs: FSNode, rhs: FSNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PackedCircle: Identifiable {
    let id = UUID()
    let node: FSNode
    var center: CGPoint
    var radius: CGFloat
}

// MARK: - Path helpers

private let safeDeletablePrefixes: [String] = [
    NSHomeDirectory() + "/Library/Caches",
    NSHomeDirectory() + "/Library/Logs",
    NSHomeDirectory() + "/Library/Developer/CoreSimulator/Devices",
    NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData",
    NSHomeDirectory() + "/Library/Application Support/Steam",
    NSHomeDirectory() + "/Library/Application Support/Google/Chrome",
    NSHomeDirectory() + "/Library/Application Support/Telegram Desktop",
    NSHomeDirectory() + "/Library/Application Support/Spotify",
    NSHomeDirectory() + "/Library/Application Support/Caches",
    NSHomeDirectory() + "/Library/Application Support/adspower_global",
    NSHomeDirectory() + "/Library/Application Support/CD Projekt Red",
    NSHomeDirectory() + "/Downloads",
    NSHomeDirectory() + "/Desktop",
    NSHomeDirectory() + "/Documents",
    NSHomeDirectory() + "/Movies",
    NSHomeDirectory() + "/Music",
    NSHomeDirectory() + "/Pictures",
    NSHomeDirectory() + "/.Trash",
    NSHomeDirectory() + "/Docs",
    NSHomeDirectory() + "/astrid",
    NSHomeDirectory() + "/hermes-desktop",
    NSHomeDirectory() + "/Screen Studio Projects",
    NSHomeDirectory() + "/go",
    NSHomeDirectory() + "/insforge",
    NSHomeDirectory() + "/langgraph",
    NSHomeDirectory() + "/mobai",
    NSHomeDirectory() + "/skillz-macos",
    NSHomeDirectory() + "/PycharmProjects",
]

private let lockedPrefixes: [String] = [
    "/System", "/usr", "/bin", "/sbin",
    "/private/var", "/private/etc",
    "/Library",
    "/Applications",
    NSHomeDirectory() + "/Library/Containers",
    NSHomeDirectory() + "/Library/Group Containers",
    NSHomeDirectory() + "/Library/Application Support",
    NSHomeDirectory() + "/Library/Preferences",
    NSHomeDirectory() + "/Library/Keychains",
    NSHomeDirectory() + "/Library"
]

func isDeletablePath(_ path: String) -> Bool {
    if safeDeletablePrefixes.contains(where: { path.hasPrefix($0) }) { return true }
    if lockedPrefixes.contains(where: { path.hasPrefix($0) }) { return false }
    return path.hasPrefix(NSHomeDirectory())
}

func relativePath(_ url: URL) -> String {
    let home = NSHomeDirectory()
    let p = url.path
    let relative = p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    let parts = relative.split(separator: "/", omittingEmptySubsequences: true)
    if parts.count > 3 {
        return "~/…/" + parts.suffix(2).joined(separator: "/")
    }
    return relative
}

// MARK: - InternalStorageTool

enum InternalStorageTool: String, CaseIterable {
    case uninstaller = "Uninstaller"
    case analyzer    = "Disk Map"
    case largeFiles  = "Large Files"
    case junkFiles   = "Junk Files"

    var icon: String {
        switch self {
        case .uninstaller: return "trash.fill"
        case .analyzer:    return "network"
        case .largeFiles:  return "doc.text.magnifyingglass"
        case .junkFiles:   return "archivebox.fill"
        }
    }

    var description: String {
        switch self {
        case .uninstaller: return "Completely remove apps and their hidden library files."
        case .analyzer:    return "Visualize your disk usage with an interactive network graph."
        case .largeFiles:  return "Find and delete the largest files taking up space."
        case .junkFiles:   return "Clean user-space caches, logs, and temporary files."
        }
    }

    var color: Color {
        switch self {
        case .uninstaller: return .pink
        case .analyzer:    return .indigo
        case .largeFiles:  return .orange
        case .junkFiles:   return .blue
        }
    }

    var shortName: String {
        switch self {
        case .uninstaller: return "Remove"
        case .analyzer:    return "Disk Map"
        case .largeFiles:  return "Large"
        case .junkFiles:   return "Junk"
        }
    }
}

// MARK: - StorageAnalyzerService

class StorageAnalyzerService: ObservableObject {
    @Published var rootNode: FSNode?
    @Published var currentNode: FSNode?
    @Published var navigationStack: [FSNode] = []

    @Published var largeFiles: [FSNode] = []
    @Published var packedCircles: [PackedCircle] = []
    @Published var junkCategories: [JunkCategory] = []
    @Published var isScanning = false
    @Published var isScanningJunk = false
    @Published var scanProgress: Double = 0.0
    @Published var currentPath: String = ""

    @Published var selectedDiskNodes: Set<FSNode> = []

    var selectedTotalSize: UInt64 {
        selectedDiskNodes.reduce(0) { $0 + $1.size }
    }

    private var isCancelled = false
    private let maxDiskMapEntries = 30_000
    private let maxDiskMapDuration: TimeInterval = 12
    private var diskMapScanStartedAt = Date.distantPast
    private var diskMapScannedEntries = 0
    private var diskMapLimitReached = false

    func cancel() { isCancelled = true }

    func scan(url: URL = URL(fileURLWithPath: "/")) {
        guard !isScanning else { return }
        isCancelled = false
        diskMapScanStartedAt = Date()
        diskMapScannedEntries = 0
        diskMapLimitReached = false
        DispatchQueue.main.async {
            self.isScanning = true
            self.scanProgress = 0.0
            self.packedCircles = []
            self.largeFiles = []
            self.rootNode = nil
            self.currentNode = nil
            self.navigationStack = []
            self.selectedDiskNodes = []
        }

        DispatchQueue.global(qos: .utility).async {
            var allFiles: [FSNode] = []
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            var lastPathUpdate = Date.distantPast
            func reportPath(_ value: String) {
                let now = Date()
                guard now.timeIntervalSince(lastPathUpdate) > 0.25 else { return }
                lastPathUpdate = now
                DispatchQueue.main.async { self.currentPath = value }
            }

            reportPath(home.lastPathComponent)
            var root = self.scanDirectory(url: home, allFiles: &allFiles, depth: 0, progress: reportPath)

            let libraryURL = home.appendingPathComponent("Library")
            if fm.fileExists(atPath: libraryURL.path),
               !(root.children?.contains(where: { $0.url == libraryURL }) ?? false) {
                reportPath("Library")
                let libNode = self.scanDirectory(url: libraryURL, allFiles: &allFiles, depth: 1, progress: reportPath)
                if libNode.size > 0 {
                    var children = root.children ?? []
                    children.append(libNode)
                    children.sort { $0.size > $1.size }
                    root = FSNode(url: root.url, name: root.name, isDirectory: true,
                                 size: root.size + libNode.size,
                                 creationDate: root.creationDate, lastAccessDate: root.lastAccessDate,
                                 category: root.category, isDeletable: root.isDeletable, children: children)
                }
            }

            if self.isCancelled && !self.diskMapLimitReached {
                DispatchQueue.main.async { self.isScanning = false }
                return
            }

            let large = allFiles.filter { !$0.isDirectory }.sorted { $0.size > $1.size }
            let topLarge = Array(large.prefix(150))

            DispatchQueue.main.async {
                self.rootNode = root
                self.largeFiles = topLarge
                self.isScanning = false
                self.navigateTo(node: root)
            }
        }
    }

    func navigateTo(node: FSNode) {
        if let current = currentNode {
            if !navigationStack.contains(where: { $0.id == current.id }) {
                navigationStack.append(current)
            }
        }
        currentNode = node
        repackCurrentNode()
    }

    func navigateBack() {
        guard !navigationStack.isEmpty else { return }
        let previous = navigationStack.removeLast()
        currentNode = previous
        repackCurrentNode()
    }

    private func repackCurrentNode() {
        guard let current = currentNode, let children = current.children, !children.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let sortedChildren = children.sorted { $0.size > $1.size }
            let topNodes = Array(sortedChildren.prefix(80))
            let packed = self.layoutOrganicGraph(nodes: topNodes)
            DispatchQueue.main.async { self.packedCircles = packed }
        }
    }

    private func determineCategory(url: URL, isDir: Bool, isPackage: Bool) -> FSNodeCategory {
        if isDir && !isPackage { return .folder }
        if isPackage && url.pathExtension == "app" { return .app }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "mkv", "avi", "webm": return .video
        case "jpg", "jpeg", "png", "heic", "gif", "svg", "webp": return .image
        case "pdf", "doc", "docx", "xls", "xlsx", "txt", "rtf", "pages", "numbers", "key": return .document
        case "zip", "rar", "7z", "tar", "gz", "dmg": return .archive
        default: return .unknown
        }
    }

    private func scanDirectory(
        url: URL,
        allFiles: inout [FSNode],
        depth: Int = 0,
        progress: ((String) -> Void)? = nil
    ) -> FSNode {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentAccessDateKey,
            .isPackageKey
        ]

        guard !shouldStopDiskMapScan() else {
            return FSNode(url: url, name: url.lastPathComponent, isDirectory: true, size: 0,
                         creationDate: nil, lastAccessDate: nil, category: .folder, isDeletable: false, children: nil)
        }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return FSNode(url: url, name: url.lastPathComponent, isDirectory: false, size: 0,
                         creationDate: nil, lastAccessDate: nil, category: .unknown, isDeletable: false, children: nil)
        }

        let resourceValues = try? url.resourceValues(forKeys: Set(keys))
        let creationDate = resourceValues?.creationDate
        let lastAccessDate = resourceValues?.contentAccessDate
        let isPackage = resourceValues?.isPackage ?? false
        let category = determineCategory(url: url, isDir: isDir.boolValue, isPackage: isPackage)

        if !isDir.boolValue || isPackage {
            let size = UInt64(resourceValues?.totalFileAllocatedSize ?? resourceValues?.fileAllocatedSize ?? resourceValues?.fileSize ?? 0)
            let deletable = isDeletablePath(url.path)
            let node = FSNode(url: url, name: url.lastPathComponent, isDirectory: false, size: size,
                             creationDate: creationDate, lastAccessDate: lastAccessDate,
                             category: category, isDeletable: deletable, children: nil)
            if size > 10 * 1024 * 1024 { allFiles.append(node) }
            return node
        }

        var childrenNodes: [FSNode] = []
        var totalSize: UInt64 = 0

        if depth < 3 {
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]) {
                for case let childURL as URL in enumerator {
                    if shouldStopDiskMapScan() { break }
                    if depth <= 1 { progress?(childURL.lastPathComponent) }
                    let childNode = scanDirectory(url: childURL, allFiles: &allFiles, depth: depth + 1, progress: progress)
                    let minSize: UInt64 = childNode.isDirectory ? 0 : 1_000_000
                    if childNode.size > minSize { childrenNodes.append(childNode) }
                    totalSize += childNode.size
                }
            }
        } else {
            totalSize = UInt64(
                resourceValues?.totalFileAllocatedSize ??
                resourceValues?.fileAllocatedSize ??
                resourceValues?.fileSize ??
                0
            )
        }

        childrenNodes.sort { $0.size > $1.size }
        let deletable = isDeletablePath(url.path)
        return FSNode(url: url, name: url.lastPathComponent, isDirectory: true, size: totalSize,
                     creationDate: creationDate, lastAccessDate: lastAccessDate,
                     category: .folder, isDeletable: deletable, children: childrenNodes)
    }

    private func shouldStopDiskMapScan() -> Bool {
        if isCancelled { return true }

        diskMapScannedEntries += 1
        let timedOut = Date().timeIntervalSince(diskMapScanStartedAt) > maxDiskMapDuration
        let hitEntryLimit = diskMapScannedEntries > maxDiskMapEntries
        if timedOut || hitEntryLimit {
            diskMapLimitReached = true
            isCancelled = true
            return true
        }

        return false
    }

    // MARK: - Organic Radial Layout

    private func layoutOrganicGraph(nodes: [FSNode]) -> [PackedCircle] {
        guard !nodes.isEmpty else { return [] }
        let maxSize = CGFloat(nodes.first!.size)
        var packed: [PackedCircle] = []
        for node in nodes {
            let areaRatio = CGFloat(node.size) / maxSize
            let radius = max(15.0, sqrt(areaRatio) * 75.0)
            var x: CGFloat = 0
            var y: CGFloat = 0
            var angle = CGFloat.random(in: 0...2 * .pi)
            var distance: CGFloat = 30
            for _ in 0..<1500 {
                x = cos(angle) * distance
                y = sin(angle) * distance
                var collided = false
                for other in packed {
                    let dx = x - other.center.x
                    let dy = y - other.center.y
                    let dist = sqrt(dx*dx + dy*dy)
                    if dist < (radius + other.radius + 6) { collided = true; break }
                }
                if !collided { break }
                angle += 0.5
                distance += 2
            }
            packed.append(PackedCircle(node: node, center: CGPoint(x: x, y: y), radius: radius))
        }
        return packed
    }

    func scanJunk() {
        guard !isScanningJunk else { return }
        DispatchQueue.main.async {
            self.isScanningJunk = true
            self.junkCategories = []
        }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            var categories: [JunkCategory] = []

            func scanPath(_ url: URL, collectFiles: Bool = true) -> (UInt64, [URL], Int) {
                var size: UInt64 = 0
                var files: [URL] = []
                var fileCount = 0
                let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                               options: [.skipsHiddenFiles])
                while let fileUrl = enumerator?.nextObject() as? URL {
                    let rv = try? fileUrl.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    if rv?.isDirectory == false {
                        size += UInt64(rv?.fileSize ?? 0)
                        fileCount += 1
                        if collectFiles { files.append(fileUrl) }
                    }
                }
                return (size, files, fileCount)
            }

            let userCacheRoot = home.appendingPathComponent("Library/Caches")
            let (userCacheSize, userCacheFiles, userCacheCount) = scanPath(userCacheRoot, collectFiles: false)
            if userCacheSize > 0 { categories.append(JunkCategory(type: .userCache, size: userCacheSize, files: userCacheFiles, cleanupRoots: [userCacheRoot], fileCount: userCacheCount)) }

            let xcodeRoot = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            let (xcodeSize, xcodeFiles, xcodeCount) = scanPath(xcodeRoot, collectFiles: false)
            if xcodeSize > 0 { categories.append(JunkCategory(type: .xcodeJunk, size: xcodeSize, files: xcodeFiles, cleanupRoots: [xcodeRoot], fileCount: xcodeCount)) }

            let userLogsRoot = home.appendingPathComponent("Library/Logs")
            let (userLogsSize, userLogsFiles, userLogsCount) = scanPath(userLogsRoot, collectFiles: false)
            if userLogsSize > 0 { categories.append(JunkCategory(type: .userLogs, size: userLogsSize, files: userLogsFiles, cleanupRoots: [userLogsRoot], fileCount: userLogsCount)) }

            let trashRoot = home.appendingPathComponent(".Trash")
            let (trashSize, trashFiles, trashCount) = scanPath(trashRoot, collectFiles: false)
            if trashSize > 0 { categories.append(JunkCategory(type: .trash, size: trashSize, files: trashFiles, cleanupRoots: [trashRoot], fileCount: trashCount)) }

            let (downloadsSize, downloadsFiles, _) = scanPath(home.appendingPathComponent("Downloads"))
            if downloadsSize > 0 { categories.append(JunkCategory(type: .downloads, size: downloadsSize, files: downloadsFiles)) }

            DispatchQueue.main.async {
                self.junkCategories = categories.sorted { $0.size > $1.size }
                self.isScanningJunk = false
            }
        }
    }

    func trashItem(url: URL, completion: @escaping (Bool, String?) -> Void) {
        let sizeBefore = itemSize(at: url)
        let statsInput = CleanupStatsRecordInput(
            path: url.path,
            displayName: url.lastPathComponent,
            category: CleanupStatsStore.inferCategory(path: url.path, fallback: .largeFiles),
            bytes: sizeBefore,
            source: "Storage"
        )

        func complete(_ success: Bool, _ errorMessage: String?) {
            if success {
                Task { @MainActor in
                    CleanupStatsStore.shared.record([statsInput])
                }
            }
            DispatchQueue.main.async { completion(success, errorMessage) }
        }

        NSWorkspace.shared.recycle([url]) { _, error in
            DispatchQueue.global(qos: .utility).async {
                if let error = error {
                    print("Failed to recycle via NSWorkspace: \(error)")
                    _ = try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
                    do {
                        var outUrl: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &outUrl)
                        complete(true, nil)
                    } catch {
                        print("Failed to recycle via FileManager: \(error)")
                        do {
                            try FileManager.default.removeItem(at: url)
                            complete(true, nil)
                        } catch let hardError {
                            print("Failed to hard delete: \(hardError)")
                            let scriptSource = """
                            tell application "Finder"
                                delete POSIX file "\(url.path)"
                            end tell
                            """
                            if let script = NSAppleScript(source: scriptSource) {
                                var scriptError: NSDictionary?
                                script.executeAndReturnError(&scriptError)
                                if scriptError == nil {
                                    complete(true, nil)
                                    return
                                }
                            }
                            complete(false, hardError.localizedDescription)
                        }
                    }
                } else {
                    complete(true, nil)
                }
            }
        }
    }

    func cleanJunkCategory(_ category: JunkCategory, completion: @escaping (JunkCleanResult) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            var statsByPath: [String: CleanupStatsRecordInput] = [:]
            var firstError: String?
            var failedCount = 0
            var skippedCount = 0
            var removedCount = 0
            let statsCategory = CleanupStatsStore.category(for: category.type)

            if !category.cleanupRoots.isEmpty {
                for root in category.cleanupRoots {
                    autoreleasepool {
                        guard fm.fileExists(atPath: root.path) else { return }

                        do {
                            let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])
	                            var removedChildren = 0
	                            var removedBytes: UInt64 = 0
	                            for child in children {
	                                if self.shouldSkipJunkURL(child, category: category) {
	                                    skippedCount += 1
	                                    continue
	                                }
	                                let childSize = self.itemSize(at: child)
	                                do {
	                                    try fm.removeItem(at: child)
                                    removedChildren += 1
                                    removedBytes += childSize
	                                } catch {
	                                    if self.isPermissionDenied(error) {
	                                        skippedCount += 1
	                                    } else {
	                                        failedCount += 1
	                                        if firstError == nil {
	                                            firstError = error.localizedDescription
	                                        }
	                                    }
	                                }
	                            }
                            if removedChildren > 0 {
                                removedCount += removedChildren
                                statsByPath[root.path] = CleanupStatsRecordInput(
                                    path: root.path,
                                    displayName: root.lastPathComponent.isEmpty ? category.name : root.lastPathComponent,
                                    category: statsCategory,
                                    bytes: removedBytes,
                                    source: "Junk Files"
                                )
                            }
                        } catch {
                            failedCount += 1
                            if firstError == nil {
                                firstError = error.localizedDescription
                            }
                        }
                    }
                }
            } else {
                for url in category.files {
                    autoreleasepool {
	                        guard fm.fileExists(atPath: url.path) else { return }
	                        if self.shouldSkipJunkURL(url, category: category) {
	                            skippedCount += 1
	                            return
	                        }

	                        let sizeBefore = self.itemSize(at: url)
                        do {
                            try fm.removeItem(at: url)
                            removedCount += 1
                            let statsPath = self.statsPath(forJunkURL: url, category: category)
                            let displayName = URL(fileURLWithPath: statsPath).lastPathComponent
                            if let existing = statsByPath[statsPath] {
                                statsByPath[statsPath] = CleanupStatsRecordInput(
                                    path: existing.path,
                                    displayName: existing.displayName,
                                    category: existing.category,
                                    bytes: existing.bytes + sizeBefore,
                                    source: existing.source
                                )
                            } else {
                                statsByPath[statsPath] = CleanupStatsRecordInput(
                                    path: statsPath,
                                    displayName: displayName.isEmpty ? category.name : displayName,
                                    category: statsCategory,
                                    bytes: sizeBefore,
                                    source: "Junk Files"
                                )
                            }
	                        } catch {
	                            if self.isPermissionDenied(error) {
	                                skippedCount += 1
	                            } else {
	                                failedCount += 1
	                                if firstError == nil {
	                                    firstError = error.localizedDescription
	                                }
	                            }
	                        }
	                    }
	                }
	            }

            let statsInputs = Array(statsByPath.values)

	            DispatchQueue.main.async {
	                let message: String?
	                if failedCount > 0 {
	                    message = "\(failedCount) items could not be removed. \(firstError ?? "")"
	                } else if skippedCount > 0 {
	                    message = "\(skippedCount) protected items skipped"
	                } else {
	                    message = nil
	                }
	                completion(JunkCleanResult(
	                    success: removedCount > 0 || failedCount == 0,
	                    removedCount: removedCount,
	                    skippedCount: skippedCount,
	                    failedCount: failedCount,
	                    message: message
	                ))
	            }

            if !statsInputs.isEmpty {
                Task { @MainActor in
                    CleanupStatsStore.shared.record(statsInputs)
                }
            }
        }
    }

    private func statsPath(forJunkURL url: URL, category: JunkCategory) -> String {
        let path = url.path
        let parent = url.deletingLastPathComponent().path

        switch category.type {
        case .userCache, .systemCache, .browserCache, .xcodeJunk, .systemLogs, .userLogs:
            return parent
        case .trash, .downloads, .unusedDMG, .screenCaptures:
            return path
        }
    }

    private func shouldSkipJunkURL(_ url: URL, category: JunkCategory) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()

        switch category.type {
        case .userCache, .systemCache:
            let protectedNames = [
                "com.apple.homekit",
                "com.apple.cloudkit",
                "com.apple.containermanagerd",
                "com.apple.security",
                "com.apple.tcc",
                "com.apple.trustd",
                "com.apple.akd",
                "com.apple.identityservicesd"
            ]
            if protectedNames.contains(where: { name == $0 || path.contains("/\($0)") }) {
                return true
            }
            return path.contains("/library/containers/com.apple.")
                || path.contains("/library/group containers/group.com.apple.")
        case .xcodeJunk:
            let keepNames: Set<String> = ["archives", "devicesupport"]
            return keepNames.contains(name)
        default:
            return false
        }
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && (
            nsError.code == NSFileWriteNoPermissionError ||
            nsError.code == NSFileReadNoPermissionError ||
            nsError.code == NSFileWriteVolumeReadOnlyError
        )
    }

    private func itemSize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return UInt64(values?.fileSize ?? 0)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == false {
                total += UInt64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    func deleteSingleNode(_ node: FSNode) {
        guard node.isDeletable else { return }
        trashItem(url: node.url) { success, _ in
            if success {
                if let current = self.currentNode {
                    if let index = self.navigationStack.firstIndex(where: { $0.id == current.id }) {
                        self.navigationStack[index].children?.removeAll { $0.id == node.id }
                    }
                    self.currentNode?.children?.removeAll { $0.id == node.id }
                }
                self.selectedDiskNodes.remove(node)
                self.repackCurrentNode()
            }
        }
    }

    func deleteSelectedDiskNodes(completion: @escaping (Bool) -> Void) {
        let filesToDelete = selectedDiskNodes.filter { $0.isDeletable }
        guard !filesToDelete.isEmpty else { completion(false); return }

        let dispatchGroup = DispatchGroup()
        var successCount = 0
        var successfullyDeletedIds: Set<UUID> = []

        for file in filesToDelete {
            dispatchGroup.enter()
            trashItem(url: file.url) { success, _ in
                if success { successCount += 1; successfullyDeletedIds.insert(file.id) }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            let fullySuccessful = successCount == filesToDelete.count
            if let current = self.currentNode {
                if let index = self.navigationStack.firstIndex(where: { $0.id == current.id }) {
                    self.navigationStack[index].children?.removeAll { successfullyDeletedIds.contains($0.id) }
                }
                self.currentNode?.children?.removeAll { successfullyDeletedIds.contains($0.id) }
            }
            self.selectedDiskNodes = self.selectedDiskNodes.filter { !successfullyDeletedIds.contains($0.id) }
            self.repackCurrentNode()
            completion(fullySuccessful)
        }
    }
}
