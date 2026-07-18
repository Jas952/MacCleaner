import Foundation
import SwiftUI
import CoreGraphics
import AppKit

// MARK: - Junk Models

struct JunkEntry: Identifiable {
    let id: String
    let url: URL
    let name: String
    let path: String
    let size: UInt64
    let itemCount: Int
    let isDirectory: Bool
    let isAggregate: Bool
    let safety: JunkSafety
}

struct JunkCategory: Identifiable {
    var id: String { "\(String(describing: type)):\(ownerID)" }
    let type: JunkType
    var ownerID: String = "system"
    var ownerName: String? = nil
    var ownerDescription: String? = nil
    var safety: JunkSafety = .review
    var blockedReason: String? = nil
    var projectRoot: URL? = nil
    var size: UInt64
    var files: [URL]
    var cleanupRoots: [URL] = []
    var fileCount: Int? = nil
    var entries: [JunkEntry] = []

    var name: String { type.name }
    var icon: String { type.icon }
    var color: Color { type.color }
    var itemCount: Int { fileCount ?? files.count }
    var isSelectedByDefault: Bool {
        type.isSelectedByDefault || safety == .safe || safety == .rebuild || safety == .redownload
    }
    var displayName: String { ownerName ?? name }
    var explanation: String { ownerDescription ?? type.detail }
}

enum JunkSafety: String, Sendable {
    case safe, rebuild, redownload, review, protected

    var label: String {
        switch self {
        case .safe: return "Safe to clean"
        case .rebuild: return "Rebuilds later"
        case .redownload: return "Downloads again"
        case .review: return "Review first"
        case .protected: return "Protected"
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .rebuild: return "hammer.fill"
        case .redownload: return "arrow.down.circle.fill"
        case .review: return "exclamationmark.triangle.fill"
        case .protected: return "lock.fill"
        }
    }
}

enum JunkType: CaseIterable, Hashable {
    case userCache, systemCache, xcodeJunk, systemLogs, browserCache, userLogs, unusedDMG, trash, downloads, screenCaptures, developerOwner

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
        case .developerOwner: return "Developer Tool"
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
        case .developerOwner: return "wrench.and.screwdriver.fill"
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
        case .unusedDMG:      return .teal
        case .trash:          return .gray
        case .downloads:      return .blue
        case .screenCaptures: return .purple
        case .developerOwner: return .accentPurple
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
        case .developerOwner:
            return "Generated files belonging to one developer tool or project."
        }
    }

    var isSelectedByDefault: Bool {
        switch self {
        case .userCache, .browserCache:
            return true
        case .systemCache, .xcodeJunk, .systemLogs, .userLogs, .unusedDMG, .trash, .downloads, .screenCaptures, .developerOwner:
            return false
        }
    }
}

struct JunkCleanResult {
    let success: Bool
    let removedCount: Int
    let alreadyAbsentCount: Int
    let skippedCount: Int
    let failedCount: Int
    let message: String?

    var hasFailures: Bool { failedCount > 0 }
}

struct DeveloperOwnerCandidate {
    let id: String
    let name: String
    let url: URL
    let description: String
    let safety: JunkSafety
    let projectRoot: URL?

    init(id: String, name: String, url: URL, description: String, safety: JunkSafety, projectRoot: URL? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.description = description
        self.safety = safety
        self.projectRoot = projectRoot
    }
}

extension StorageAnalyzerService {
    static func developerOwnerRoots(home: URL) -> [DeveloperOwnerCandidate] {
        var candidates = [
            DeveloperOwnerCandidate(id: "xcode-archives", name: "Xcode · Archives", url: home.appendingPathComponent("Library/Developer/Xcode/Archives"), description: "Saved distribution builds and debug symbols. Keep archives needed for crash symbolication or release history.", safety: .review),
            DeveloperOwnerCandidate(id: "xcode-device-support", name: "Xcode · Device Support", url: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"), description: "Debug symbols for iPhone/iPad versions connected to this Mac. Old versions can be downloaded again, but review the devices you still support.", safety: .review),
            DeveloperOwnerCandidate(id: "xcode-simulator-devices", name: "Xcode · Simulator data", url: home.appendingPathComponent("Library/Developer/CoreSimulator/Devices"), description: "Virtual device data, installed test apps and simulator state. Use Simulator or simctl to erase individual devices when possible.", safety: .review),
            DeveloperOwnerCandidate(id: "xcode-simulator-runtimes", name: "Xcode · Simulator runtimes", url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Profiles/Runtimes"), description: "Installed iOS/watchOS/tvOS simulator operating systems. A runtime can occupy several GB and should be removed only when its version is no longer needed.", safety: .review),
            DeveloperOwnerCandidate(id: "swiftpm", name: "Swift Package Manager", url: home.appendingPathComponent("Library/Caches/org.swift.swiftpm"), description: "Downloaded Swift packages and metadata. SwiftPM resolves them again when a project needs them.", safety: .redownload),
            DeveloperOwnerCandidate(id: "cocoapods", name: "CocoaPods", url: home.appendingPathComponent("Library/Caches/CocoaPods"), description: "Downloaded iOS/macOS pod specifications and archives. Active projects remain intact; missing downloads are restored by CocoaPods.", safety: .redownload),
            DeveloperOwnerCandidate(id: "carthage", name: "Carthage", url: home.appendingPathComponent("Library/Caches/org.carthage.CarthageKit"), description: "Carthage download and build cache. Dependencies may be downloaded and rebuilt again.", safety: .redownload),
            DeveloperOwnerCandidate(id: "homebrew", name: "Homebrew", url: home.appendingPathComponent("Library/Caches/Homebrew"), description: "Downloaded installers and bottles. Installed Homebrew packages are not removed; a future install may download them again.", safety: .redownload),
            DeveloperOwnerCandidate(id: "npm", name: "npm", url: home.appendingPathComponent(".npm/_cacache"), description: "npm's content-addressed download cache. It is not the source code of a project.", safety: .redownload),
            DeveloperOwnerCandidate(id: "yarn", name: "Yarn", url: home.appendingPathComponent("Library/Caches/Yarn"), description: "Downloaded JavaScript packages kept by Yarn.", safety: .redownload),
            DeveloperOwnerCandidate(id: "pnpm", name: "pnpm", url: home.appendingPathComponent("Library/pnpm/store"), description: "Shared content-addressed JavaScript package store used by pnpm.", safety: .redownload),
            DeveloperOwnerCandidate(id: "pip", name: "Python / pip", url: home.appendingPathComponent("Library/Caches/pip"), description: "Downloaded Python wheels and source archives. Installed virtual environments are not targeted.", safety: .redownload),
            DeveloperOwnerCandidate(id: "uv", name: "Python / uv", url: home.appendingPathComponent("Library/Caches/uv"), description: "uv's downloaded Python package and interpreter cache.", safety: .redownload),
            DeveloperOwnerCandidate(id: "gradle", name: "Gradle / Android", url: home.appendingPathComponent(".gradle/caches"), description: "Downloaded Android/Java dependencies and build metadata. The next build may download them again.", safety: .redownload),
            DeveloperOwnerCandidate(id: "android-studio-cache", name: "Android Studio cache", url: home.appendingPathComponent("Library/Caches/Google/AndroidStudio"), description: "Android Studio indexes and temporary IDE data. The exact versioned cache may differ between Android Studio releases.", safety: .rebuild),
            DeveloperOwnerCandidate(id: "android-emulators", name: "Android emulators", url: home.appendingPathComponent(".android/avd"), description: "Virtual Android device images. They can contain installed apps and test data, so review individual emulators before removing them.", safety: .review),
            DeveloperOwnerCandidate(id: "maven", name: "Maven", url: home.appendingPathComponent(".m2/repository"), description: "Local Java/Kotlin dependency repository. Review before cleaning because offline builds may depend on it.", safety: .review),
            DeveloperOwnerCandidate(id: "cargo", name: "Rust / Cargo", url: home.appendingPathComponent(".cargo/registry/cache"), description: "Downloaded Rust crates. Cargo can fetch them again, but offline builds may fail until it does.", safety: .redownload),
            DeveloperOwnerCandidate(id: "go-build", name: "Go", url: home.appendingPathComponent("Library/Caches/go-build"), description: "Compiled Go build cache. It is recreated by the Go toolchain.", safety: .rebuild),
            DeveloperOwnerCandidate(id: "jetbrains", name: "JetBrains IDEs", url: home.appendingPathComponent("Library/Caches/JetBrains"), description: "Indexes and temporary IDE data. JetBrains recreates indexes, but the next opening may be slower.", safety: .rebuild),
            DeveloperOwnerCandidate(id: "blender-cache", name: "Blender cache", url: home.appendingPathComponent("Library/Caches/org.blenderfoundation.blender"), description: "Blender shader and temporary cache. Blender recreates it, but the first render may compile shaders again.", safety: .rebuild),
            DeveloperOwnerCandidate(id: "claude-cache", name: "Claude cache", url: home.appendingPathComponent("Library/Application Support/Claude/Cache"), description: "Temporary web/UI cache used by the Claude desktop app. Conversation history and workspace data are outside this path.", safety: .rebuild),
            DeveloperOwnerCandidate(id: "cursor-cache", name: "Cursor cache", url: home.appendingPathComponent("Library/Application Support/Cursor/Cache"), description: "Temporary editor cache. Cursor recreates it; settings and project source are outside this path.", safety: .rebuild),
            DeveloperOwnerCandidate(id: "vscode-cache", name: "Visual Studio Code cache", url: home.appendingPathComponent("Library/Application Support/Code/Cache"), description: "Temporary editor cache. Extensions, settings and project source are outside this path.", safety: .rebuild),
            DeveloperOwnerCandidate(id: "huggingface", name: "Hugging Face models", url: home.appendingPathComponent(".cache/huggingface"), description: "Downloaded AI datasets and model files. These are potentially valuable and are protected from bulk cleanup.", safety: .protected),
            DeveloperOwnerCandidate(id: "ollama", name: "Ollama models", url: home.appendingPathComponent(".ollama/models"), description: "Local AI model weights. These are not ordinary caches and are protected from bulk cleanup.", safety: .protected),
            DeveloperOwnerCandidate(id: "docker", name: "Docker Desktop data", url: home.appendingPathComponent("Library/Containers/com.docker.docker"), description: "Docker images, build cache, containers and volumes. Volumes may contain databases or source data; use Docker's own prune commands after review.", safety: .protected)
        ]
        let googleCache = home.appendingPathComponent("Library/Caches/Google", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: googleCache, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries where entry.lastPathComponent.hasPrefix("AndroidStudio") {
                candidates.append(DeveloperOwnerCandidate(
                    id: "android-studio-\(entry.lastPathComponent.lowercased())",
                    name: "Android Studio · \(entry.lastPathComponent)",
                    url: entry,
                    description: "Android Studio indexes and temporary IDE data. The cache is recreated; project source and SDKs are outside this path.",
                    safety: .rebuild
                ))
            }
        }
        return candidates
    }

    static func browserDisplayName(for root: URL) -> String {
        switch root.lastPathComponent.lowercased() {
        case "chrome": return "Google Chrome"
        case "com.apple.safari": return "Safari"
        case "com.mozilla.firefox": return "Firefox"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "com.brave.browser": return "Brave"
        default: return root.lastPathComponent
        }
    }

    static func projectArtifactCandidates(home: URL) -> [DeveloperOwnerCandidate] {
        let roots = ["Projects", "Developer", "Code", "src", "Documents"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
        let artifactNames: [(String, String, JunkSafety)] = [
            ("node_modules", "JavaScript dependencies copied for this project.", .redownload),
            (".next", "Next.js build output that is recreated by the next build.", .rebuild),
            ("dist", "Compiled web output. It can be regenerated from the source project.", .rebuild),
            ("build", "Generated build output. It can be regenerated from the source project.", .rebuild),
            ("Pods", "CocoaPods dependencies stored inside this project.", .redownload),
            (".build", "Swift Package Manager build output.", .rebuild),
            ("target", "Rust compiled artifacts for this project.", .rebuild),
            (".venv", "Python virtual environment. It is rebuildable, but may contain custom packages.", .review),
            ("__pycache__", "Python bytecode cache.", .rebuild),
            ("Library", "Unity imported assets and generated cache. Rebuilding can take a long time.", .review),
            ("Intermediate", "Unreal Engine intermediate build data.", .rebuild),
            (".godot", "Godot editor import cache and generated metadata.", .rebuild)
        ]
        var result: [DeveloperOwnerCandidate] = []
        let fm = FileManager.default
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for project in projects.prefix(80) {
                guard (try? project.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let hasProjectMarker = fm.fileExists(atPath: project.appendingPathComponent(".git").path)
                    || fm.fileExists(atPath: project.appendingPathComponent("Package.swift").path)
                    || fm.fileExists(atPath: project.appendingPathComponent("package.json").path)
                    || fm.fileExists(atPath: project.appendingPathComponent("pubspec.yaml").path)
                guard hasProjectMarker else { continue }
                let dirty = Self.projectHasUncommittedChanges(project)
                for (artifact, detail, safety) in artifactNames {
                    let artifactURL = project.appendingPathComponent(artifact, isDirectory: true)
                    guard fm.fileExists(atPath: artifactURL.path) else { continue }
                    let bytes = Self.boundedDirectorySize(artifactURL)
                    guard bytes >= 10 * 1_048_576 else { continue }
                    result.append(DeveloperOwnerCandidate(
                        id: "project-\(project.path.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_"))-\(artifact)",
                        name: "\(project.lastPathComponent) · \(artifact)",
                        url: artifactURL,
                        description: dirty ? "\(detail) Git reports uncommitted changes in this project; review before cleaning." : detail,
                        safety: dirty ? .review : safety,
                        projectRoot: project
                    ))
                }
            }
        }
        return result
    }

    static func projectHasUncommittedChanges(_ project: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: project.appendingPathComponent(".git").path) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", project.path, "status", "--porcelain", "--untracked-files=normal"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return !pipe.fileHandleForReading.readDataToEndOfFile().isEmpty
        } catch {
            return false
        }
    }

    static func boundedDirectorySize(_ root: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        var total: UInt64 = 0
        var count = 0
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return 0 }
        while let url = enumerator.nextObject() as? URL, count < 8_000 {
            count += 1
            guard (try? url.resourceValues(forKeys: keys).isRegularFile) == true else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            total &+= UInt64(max(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0, 0))
        }
        return total
    }

    /// Builds a compact, user-facing preview of a cleanup root. Individual
    /// large children are shown by path; the tail is represented by one folder
    /// row so thousands of tiny files do not turn the result into noise.
    static func previewEntries(at root: URL, safety: JunkSafety, limit: Int = 12) -> [JunkEntry] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: []) else {
            return []
        }
        let rows: [(url: URL, size: UInt64, isDirectory: Bool)] = children.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else { return nil }
            let directory = values.isDirectory == true
            let size: UInt64 = directory
                ? boundedDirectorySize(url)
                : UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0, 0))
            return (url, size, directory)
        }.sorted { $0.size > $1.size }
        guard !rows.isEmpty else { return [] }

        let visibleCount = min(limit, rows.count)
        var result = rows.prefix(visibleCount).map { row in
            JunkEntry(id: row.url.path, url: row.url, name: row.url.lastPathComponent,
                      path: row.url.path, size: row.size, itemCount: 1,
                      isDirectory: row.isDirectory, isAggregate: false, safety: safety)
        }
        if rows.count > visibleCount {
            let rest = rows.dropFirst(visibleCount)
            let restSize = rest.reduce(UInt64(0)) { $0 &+ $1.size }
            result.append(JunkEntry(
                id: "aggregate:\(root.path)", url: root,
                name: "Остальные файлы в \(root.lastPathComponent)", path: root.path,
                size: restSize, itemCount: rest.count, isDirectory: true,
                isAggregate: true, safety: safety
            ))
        }
        return result
    }
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
    case duplicates = "Duplicates"
    case similarPhotos = "Similar Photos"
    case cloud = "Cloud Reclaim"
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
        case .duplicates: return "Duplicates"
        case .similarPhotos: return "Photos"
        case .cloud: return "Cloud"
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
        case .duplicates: return .accentPurple
        case .similarPhotos: return .pink
        case .cloud: return .accentBlue
        case .uninstall: return .accentRed
        case .other: return .textSecondary
        }
    }

    var isSystemOrCache: Bool {
        switch self {
        case .systemCache, .userCache, .browserCache, .developerCache, .logs:
            return true
        case .appSupport, .trash, .downloads, .largeFiles, .duplicates, .similarPhotos, .cloud, .uninstall, .other:
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

private struct CleanupStatsDerivedState {
    var stableBytes: UInt64 = 0
    var rebuildableBytes: UInt64 = 0
    var stableCleanCount = 0
    var systemOrCacheCleanCount = 0
    var rebuildableCleanCount = 0
    var cleanedLast30DaysBytes: UInt64 = 0
    var categoryTotals: [(category: CleanupStatsCategory, bytes: UInt64, count: Int)] = []
    var topRecurringEntries: [CleanupStatsEntry] = []
}

@MainActor
final class CleanupStatsStore: ObservableObject {
    static let shared = CleanupStatsStore()

    @Published private(set) var entries: [CleanupStatsEntry] = []
    @Published private(set) var events: [CleanupStatsEvent] = []
    @Published private(set) var isLoaded = false

    private let maxEntries = 800
    private let maxEvents = 600
    private var derived = CleanupStatsDerivedState()
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
        derived.stableBytes
    }

    var rebuildableBytes: UInt64 {
        derived.rebuildableBytes
    }

    var lifetimeThroughputBytes: UInt64 {
        entries.reduce(0) { $0 + $1.totalBytes }
    }

    var totalCleanCount: Int {
        derived.stableCleanCount
    }

    var cleanedLast30DaysBytes: UInt64 {
        derived.cleanedLast30DaysBytes
    }

    var systemOrCacheCleanCount: Int {
        derived.systemOrCacheCleanCount
    }

    var rebuildableCleanCount: Int {
        derived.rebuildableCleanCount
    }

    var trackedTargetCount: Int {
        entries.count
    }

    var topRecurringEntries: [CleanupStatsEntry] {
        derived.topRecurringEntries
    }

    var categoryTotals: [(category: CleanupStatsCategory, bytes: UInt64, count: Int)] {
        derived.categoryTotals
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
        rebuildDerivedState()
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
        case .developerOwner: return .developerCache
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
                self.rebuildDerivedState()
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

    private func rebuildDerivedState() {
        var next = CleanupStatsDerivedState()
        var categories: [CleanupStatsCategory: (bytes: UInt64, count: Int)] = [:]

        for entry in entries {
            if entry.isRebuildable {
                next.rebuildableBytes &+= entry.lastBytes
                next.rebuildableCleanCount += entry.cleanCount
            } else {
                next.stableBytes &+= entry.lastBytes
                next.stableCleanCount += entry.cleanCount
                if entry.isSystemOrCache { next.systemOrCacheCleanCount += entry.cleanCount }
                let previous = categories[entry.category] ?? (0, 0)
                categories[entry.category] = (
                    previous.bytes &+ entry.lastBytes,
                    previous.count + entry.cleanCount
                )
            }
        }

        next.categoryTotals = categories.map { category, totals in
            (category: category, bytes: totals.bytes, count: totals.count)
        }
        .sorted { $0.bytes > $1.bytes }
        next.topRecurringEntries = Array(entries.sorted {
            if $0.cleanCount == $1.cleanCount { return $0.lastBytes > $1.lastBytes }
            return $0.cleanCount > $1.cleanCount
        }.prefix(5))
        next.cleanedLast30DaysBytes = uniqueBytesSince(days: 30, includeRebuildable: false)
        derived = next
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
    if safeDeletablePrefixes.contains(where: { SafeDeletionService.isPath(path, inside: $0) }) { return true }
    if lockedPrefixes.contains(where: { SafeDeletionService.isPath(path, inside: $0) }) { return false }
    return SafeDeletionService.isPath(path, inside: NSHomeDirectory())
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
    case junkFiles   = "Junk Files"
    case uninstaller = "Uninstaller"
    case largeFiles  = "Large Files"
    case analyzer    = "Disk Map"
    case advisor     = "Cleanup Advisor"
    case duplicates  = "Exact Duplicates"
    case similarPhotos = "Similar Photos"
    case cloud       = "Cloud Reclaim"
    case specialized = "Complete Analysis"

    static let coreTools: [InternalStorageTool] = [.junkFiles, .uninstaller, .largeFiles, .analyzer]
    static let smartTools: [InternalStorageTool] = [.specialized]

    var icon: String {
        switch self {
        case .advisor:     return "sparkle.magnifyingglass"
        case .duplicates:  return "doc.on.doc.fill"
        case .similarPhotos: return "photo.stack.fill"
        case .cloud:       return "icloud.and.arrow.down.fill"
        case .specialized: return "scope"
        case .uninstaller: return "trash.fill"
        case .analyzer:    return "network"
        case .largeFiles:  return "doc.text.magnifyingglass"
        case .junkFiles:   return "archivebox.fill"
        }
    }

    var description: String {
        switch self {
        case .advisor: return "Rank reclaim opportunities by size, safety, age, and rebuild cost."
        case .duplicates: return "Verify byte-for-byte copies and safely keep at least one."
        case .similarPhotos: return "Find visually similar exported photos privately on this Mac."
        case .cloud: return "Free local iCloud space while preserving cloud originals."
        case .specialized: return "Run Cleanup Advisor, duplicate, photo, and cloud analysis in one report."
        case .uninstaller: return "Completely remove apps and their hidden library files."
        case .analyzer:    return "Visualize your disk usage with an interactive network graph."
        case .largeFiles:  return "Find and delete the largest files taking up space."
        case .junkFiles:   return "Clean user-space caches, logs, and temporary files."
        }
    }

    var color: Color {
        switch self {
        case .advisor:     return .green
        case .duplicates:  return .purple
        case .similarPhotos: return .pink
        case .cloud:       return .cyan
        case .specialized: return .accentBlue
        case .uninstaller: return .pink
        case .analyzer:    return .indigo
        case .largeFiles:  return .orange
        case .junkFiles:   return .blue
        }
    }

    var shortName: String {
        switch self {
        case .advisor: return "Advisor"
        case .duplicates: return "Duplicates"
        case .similarPhotos: return "Photos"
        case .cloud: return "Cloud"
        case .specialized: return "Analysis"
        case .uninstaller: return "Remove"
        case .analyzer:    return "Disk Map"
        case .largeFiles:  return "Large"
        case .junkFiles:   return "Junk"
        }
    }
}

enum JunkScanMode: String, Sendable {
    case efficient = "Efficient"
    case thorough = "Thorough"

    var maximumEntries: Int { self == .efficient ? 100_000 : 500_000 }
    var maximumDuration: TimeInterval { self == .efficient ? 8 : 45 }
    var maximumEntriesPerRoot: Int { self == .efficient ? 20_000 : 100_000 }
    var maximumDurationPerRoot: TimeInterval { self == .efficient ? 1.2 : 6 }
    var maximumCollectedFiles: Int { self == .efficient ? 2_000 : 10_000 }
}

enum LargeFileScanMode: String, Sendable {
    case efficient = "Efficient"
    case thorough = "Thorough"

    var maximumEntries: Int { self == .efficient ? 200_000 : 1_000_000 }
    var maximumDuration: TimeInterval { self == .efficient ? 12 : 90 }
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
    @Published var scanWasLimited = false
    @Published var scannedEntryCount = 0
    @Published var largeFileScanWasLimited = false
    @Published var largeFileScannedEntryCount = 0
    @Published var largeFileScanMode: LargeFileScanMode = .efficient
    @Published var junkScanWasLimited = false
    @Published var junkScannedEntryCount = 0
    @Published var junkScanMode: JunkScanMode = .efficient

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
    private let scanStateLock = NSLock()

    func cancel() {
        scanStateLock.lock()
        isCancelled = true
        scanStateLock.unlock()
    }

    @MainActor
    func resetForNavigation() {
        guard !isScanning, !isScanningJunk else { return }
        rootNode = nil
        currentNode = nil
        navigationStack = []
        largeFiles = []
        packedCircles = []
        junkCategories = []
        scanProgress = 0
        currentPath = ""
        scanWasLimited = false
        scannedEntryCount = 0
        largeFileScanWasLimited = false
        largeFileScannedEntryCount = 0
        junkScanWasLimited = false
        junkScannedEntryCount = 0
        selectedDiskNodes = []
    }

    func scan(url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        guard !isScanning else { return }
        let requestedRoot = url.standardizedFileURL
        scanStateLock.lock()
        isCancelled = false
        diskMapScanStartedAt = Date()
        diskMapScannedEntries = 0
        diskMapLimitReached = false
        scanStateLock.unlock()
        DispatchQueue.main.async {
            self.isScanning = true
            self.scanProgress = 0.0
            self.scanWasLimited = false
            self.scannedEntryCount = 0
            self.packedCircles = []
            self.largeFiles = []
            self.rootNode = nil
            self.currentNode = nil
            self.navigationStack = []
            self.selectedDiskNodes = []
        }

        DispatchQueue.global(qos: .utility).async {
            var allFiles: [FSNode] = []
            var lastPathUpdate = Date.distantPast
            func reportPath(_ value: String) {
                let now = Date()
                guard now.timeIntervalSince(lastPathUpdate) > 0.25 else { return }
                lastPathUpdate = now
                let progress = self.diskMapProgressSnapshot()
                DispatchQueue.main.async {
                    self.currentPath = value
                    self.scanProgress = progress.progress
                    self.scannedEntryCount = progress.entries
                }
            }

            reportPath(requestedRoot.lastPathComponent)
            let root = self.scanDirectory(url: requestedRoot, allFiles: &allFiles, depth: 0, progress: reportPath)

            let finalState = self.diskMapProgressSnapshot()
            if finalState.cancelled && !finalState.limited {
                DispatchQueue.main.async { self.isScanning = false }
                return
            }

            let large = allFiles.filter { !$0.isDirectory }.sorted { $0.size > $1.size }
            let topLarge = Array(large.prefix(150))

            DispatchQueue.main.async {
                self.rootNode = root
                self.largeFiles = topLarge
                self.isScanning = false
                self.scanProgress = 1.0
                self.scanWasLimited = finalState.limited
                self.scannedEntryCount = finalState.entries
                self.navigateTo(node: root)
            }
        }
    }

    func scanLargeFiles(
        url: URL = FileManager.default.homeDirectoryForCurrentUser,
        mode: LargeFileScanMode = .efficient
    ) {
        guard !isScanning else { return }
        let root = url.standardizedFileURL
        scanStateLock.lock()
        isCancelled = false
        scanStateLock.unlock()

        DispatchQueue.main.async {
            self.isScanning = true
            self.scanProgress = 0
            self.currentPath = root.path
            self.largeFiles = []
            self.largeFileScanWasLimited = false
            self.largeFileScannedEntryCount = 0
            self.largeFileScanMode = mode
        }

        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let keys: Set<URLResourceKey> = [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
                .creationDateKey, .contentAccessDateKey, .isPackageKey
            ]
            var budget = ScanResourceBudget(
                maximumEntries: mode.maximumEntries,
                maximumDuration: mode.maximumDuration
            )
            let protectionPolicy = SafeDeletionService.currentProtectionPolicy()
            var candidates: [FSNode] = []
            var lastProgressAt = Date.distantPast

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                DispatchQueue.main.async { self.isScanning = false }
                return
            }

            while let fileURL = enumerator.nextObject() as? URL {
                if budget.consumedEntries.isMultiple(of: 64), self.diskScanIsCancelled() {
                    budget.markLimited()
                    break
                }
                guard budget.consumeEntry() else { break }
                let now = Date()
                if now.timeIntervalSince(lastProgressAt) >= 0.05 {
                    lastProgressAt = now
                    let entries = budget.consumedEntries
                    let progress = min(0.99, Double(entries) / Double(mode.maximumEntries))
                    DispatchQueue.main.async {
                        self.currentPath = fileURL.path
                        self.largeFileScannedEntryCount = entries
                        self.scanProgress = progress
                    }
                }
                guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
                if SafeDeletionService.isApplicationOwnedPath(fileURL, policy: protectionPolicy) {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }

                let size = UInt64(max(
                    values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0,
                    0
                ))
                guard size >= 10 * 1_048_576 else { continue }
                candidates.append(FSNode(
                    url: fileURL,
                    name: fileURL.lastPathComponent,
                    isDirectory: false,
                    size: size,
                    creationDate: values.creationDate,
                    lastAccessDate: values.contentAccessDate,
                    category: self.determineCategory(url: fileURL, isDir: false, isPackage: false),
                    isDeletable: isDeletablePath(fileURL.path),
                    children: nil
                ))

                if candidates.count > 300 {
                    candidates = Array(candidates.sorted { $0.size > $1.size }.prefix(150))
                }

            }

            let result = Array(candidates.sorted { $0.size > $1.size }.prefix(150))
            let wasLimited = budget.wasLimited
            let entries = budget.consumedEntries
            DispatchQueue.main.async {
                self.largeFiles = result
                self.largeFileScanWasLimited = wasLimited
                self.largeFileScannedEntryCount = entries
                self.scanProgress = 1
                self.isScanning = false
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
        scanStateLock.lock()
        defer { scanStateLock.unlock() }
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

    private func diskScanIsCancelled() -> Bool {
        scanStateLock.lock()
        defer { scanStateLock.unlock() }
        return isCancelled
    }

    private func diskMapProgressSnapshot() -> (progress: Double, entries: Int, cancelled: Bool, limited: Bool) {
        scanStateLock.lock()
        defer { scanStateLock.unlock() }
        let entryProgress = Double(diskMapScannedEntries) / Double(maxDiskMapEntries)
        let timeProgress = Date().timeIntervalSince(diskMapScanStartedAt) / maxDiskMapDuration
        return (
            min(0.99, max(entryProgress, timeProgress)),
            diskMapScannedEntries,
            isCancelled,
            diskMapLimitReached
        )
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

    func scanJunk(mode: JunkScanMode = .efficient) {
        guard !isScanningJunk else { return }
        DispatchQueue.main.async {
            self.isScanningJunk = true
            self.junkScanMode = mode
            self.junkCategories = []
            self.junkScanWasLimited = false
            self.junkScannedEntryCount = 0
            self.currentPath = ""
        }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            var categories: [JunkCategory] = []
            var budget = ScanResourceBudget(
                maximumEntries: mode.maximumEntries,
                maximumDuration: mode.maximumDuration
            )
            var lastPathUpdate = Date.distantPast

            func reportPath(_ url: URL) {
                let now = Date()
                guard now.timeIntervalSince(lastPathUpdate) >= 0.05 else { return }
                lastPathUpdate = now
                let entries = budget.consumedEntries
                let progress = min(0.99, Double(entries) / Double(mode.maximumEntries))
                DispatchQueue.main.async {
                    self.currentPath = url.path
                    self.junkScannedEntryCount = entries
                    self.scanProgress = progress
                }
            }
            let protectionPolicy = SafeDeletionService.currentProtectionPolicy(home: home)
            let userCacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
            let browserRoots = [
                home.appendingPathComponent("Library/Caches/Google/Chrome"),
                home.appendingPathComponent("Library/Caches/com.apple.Safari"),
                home.appendingPathComponent("Library/Caches/com.mozilla.firefox"),
                home.appendingPathComponent("Library/Caches/com.microsoft.edgemac"),
                home.appendingPathComponent("Library/Caches/com.brave.Browser")
            ]
            let ownerRoots = Self.developerOwnerRoots(home: home)
            let userCacheExclusions: [URL] = (browserRoots + ownerRoots.map(\.url)).compactMap { root in
                let relative = root.path.dropFirst(userCacheRoot.path.count)
                    .split(separator: "/", omittingEmptySubsequences: true)
                guard let first = relative.first else { return nil }
                return userCacheRoot.appendingPathComponent(String(first), isDirectory: true)
            }

            func scanPath(
                _ url: URL,
                collectFiles: Bool = true,
                excludedRoots: [URL] = [],
                minimumCollectedBytes: UInt64 = 0
            ) -> (UInt64, [URL], Int) {
                guard budget.beginRoot() else { return (0, [], 0) }
                var size: UInt64 = 0
                var files: [URL] = []
                var fileCount = 0
                let keys: Set<URLResourceKey> = [
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey
                ]
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                ) else { return (0, [], 0) }
                let rootDeadline = Date().addingTimeInterval(mode.maximumDurationPerRoot)
                var rootEntries = 0
                while let fileURL = enumerator.nextObject() as? URL {
                    if rootEntries >= mode.maximumEntriesPerRoot
                        || (rootEntries.isMultiple(of: 64) && Date() >= rootDeadline) {
                        budget.markLimited()
                        break
                    }
                    guard budget.consumeEntry() else { break }
                    rootEntries += 1
                    reportPath(fileURL)
                    let values = try? fileURL.resourceValues(forKeys: keys)
                    let isExcluded = excludedRoots.contains {
                        SafeDeletionService.isPath(fileURL.path, inside: $0.path)
                    }
                    if isExcluded
                        || SafeDeletionService.isApplicationOwnedPath(fileURL, policy: protectionPolicy) {
                        if values?.isDirectory == true { enumerator.skipDescendants() }
                        continue
                    }
                    guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
                    let allocated = values?.totalFileAllocatedSize
                        ?? values?.fileAllocatedSize
                        ?? values?.fileSize
                        ?? 0
                    if collectFiles && UInt64(max(allocated, 0)) < minimumCollectedBytes { continue }
                    if collectFiles && files.count >= mode.maximumCollectedFiles {
                        budget.markLimited()
                        break
                    }
                    size &+= UInt64(max(allocated, 0))
                    fileCount += 1
                    if collectFiles { files.append(fileURL) }
                }
                return (size, files, fileCount)
            }

            func scanMatchingFiles(_ roots: [URL], predicate: (URL) -> Bool) -> (UInt64, [URL], Int) {
                var size: UInt64 = 0
                var files: [URL] = []
                for root in roots {
                    guard budget.beginRoot() else { break }
                    guard let contents = try? fm.contentsOfDirectory(
                        at: root,
                        includingPropertiesForKeys: [
                            .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
                            .isRegularFileKey, .isSymbolicLinkKey
                        ],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for url in contents {
                        guard budget.consumeEntry(), files.count < mode.maximumCollectedFiles else {
                            budget.markLimited()
                            break
                        }
                        reportPath(url)
                        guard predicate(url) else { continue }
                        let values = try? url.resourceValues(forKeys: [
                            .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
                            .isRegularFileKey, .isSymbolicLinkKey
                        ])
                        guard values?.isRegularFile == true,
                              values?.isSymbolicLink != true,
                              !SafeDeletionService.isApplicationOwnedPath(url, policy: protectionPolicy) else { continue }
                        let allocated = values?.totalFileAllocatedSize
                            ?? values?.fileAllocatedSize
                            ?? values?.fileSize
                            ?? 0
                        size &+= UInt64(max(allocated, 0))
                        files.append(url)
                    }
                }
                return (size, files, files.count)
            }

            // Prioritize user-actionable roots. Browser containers are excluded
            // from the broad cache walk and measured exactly once below.
            let (userCacheSize, userCacheFiles, userCacheCount) = scanPath(
                userCacheRoot,
                collectFiles: false,
                excludedRoots: Array(Set(userCacheExclusions))
            )
            if userCacheSize > 0 { categories.append(JunkCategory(type: .userCache, size: userCacheSize, files: userCacheFiles, cleanupRoots: [userCacheRoot], fileCount: userCacheCount)) }

            for root in browserRoots where fm.fileExists(atPath: root.path) {
                let result = scanPath(root, collectFiles: false)
                if result.0 > 0 {
                    let browserName = Self.browserDisplayName(for: root)
                    categories.append(JunkCategory(
                        type: .browserCache,
                        ownerID: "browser-\(browserName.lowercased().replacingOccurrences(of: " ", with: "-"))",
                        ownerName: "\(browserName) cache",
                        ownerDescription: "Temporary pages, images and scripts kept by \(browserName). They are recreated while browsing; open \(browserName) must be closed before cleaning.",
                        safety: .rebuild,
                        size: result.0,
                        files: [],
                        cleanupRoots: [root],
                        fileCount: result.2
                    ))
                }
            }

            let xcodeRoot = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            let (xcodeSize, xcodeFiles, xcodeCount) = scanPath(xcodeRoot, collectFiles: false)
            if xcodeSize > 0 {
                categories.append(JunkCategory(
                    type: .xcodeJunk,
                    ownerID: "xcode-derived-data",
                    ownerName: "Xcode · DerivedData",
                    ownerDescription: "Build intermediates, indexes and logs generated by Xcode. The source project is not deleted; Xcode rebuilds this data on the next build.",
                    safety: .rebuild,
                    size: xcodeSize,
                    files: xcodeFiles,
                    cleanupRoots: [xcodeRoot],
                    fileCount: xcodeCount
                ))
            }

            // Developer caches are kept as separate owner rows. This avoids
            // making a developer choose between one opaque "User Cache" total
            // and a dangerous all-or-nothing delete.
            for candidate in ownerRoots {
                guard candidate.id != "xcode-derived-data",
                      fm.fileExists(atPath: candidate.url.path) else { continue }
                let result = scanPath(candidate.url, collectFiles: false)
                let measuredBytes = result.0 > 0 ? result.0 : Self.boundedDirectorySize(candidate.url)
                guard measuredBytes > 0 else { continue }
                categories.append(JunkCategory(
                    type: .developerOwner,
                    ownerID: candidate.id,
                    ownerName: candidate.name,
                    ownerDescription: candidate.description,
                    safety: candidate.safety,
                    size: measuredBytes,
                    files: [],
                    cleanupRoots: [candidate.url],
                    fileCount: result.2
                ))
            }

            for candidate in Self.projectArtifactCandidates(home: home) {
                guard fm.fileExists(atPath: candidate.url.path) else { continue }
                let bytes = Self.boundedDirectorySize(candidate.url)
                guard bytes > 0 else { continue }
                let dirty = candidate.projectRoot.map(Self.projectHasUncommittedChanges) ?? false
                categories.append(JunkCategory(
                    type: .developerOwner,
                    ownerID: candidate.id,
                    ownerName: candidate.name,
                    ownerDescription: candidate.description,
                    safety: dirty ? .review : candidate.safety,
                    blockedReason: dirty ? "Project has uncommitted Git changes" : nil,
                    projectRoot: candidate.projectRoot,
                    size: bytes,
                    files: [],
                    cleanupRoots: [candidate.url],
                    fileCount: nil
                ))
            }

            let userLogsRoot = home.appendingPathComponent("Library/Logs")
            let (userLogsSize, userLogsFiles, userLogsCount) = scanPath(userLogsRoot, collectFiles: false)
            if userLogsSize > 0 { categories.append(JunkCategory(type: .userLogs, size: userLogsSize, files: userLogsFiles, cleanupRoots: [userLogsRoot], fileCount: userLogsCount)) }

            let trashRoot = home.appendingPathComponent(".Trash")
            let (trashSize, trashFiles, trashCount) = scanPath(trashRoot, collectFiles: false)
            if trashSize > 0 { categories.append(JunkCategory(type: .trash, size: trashSize, files: trashFiles, cleanupRoots: [trashRoot], fileCount: trashCount)) }

            let downloadsRoot = home.appendingPathComponent("Downloads")
            let (_, downloadsFiles, _) = scanPath(
                downloadsRoot,
                minimumCollectedBytes: 50 * 1_048_576
            )

            let (dmgSize, dmgFiles, dmgCount) = scanMatchingFiles(
                [downloadsRoot],
                predicate: { $0.pathExtension.lowercased() == "dmg" }
            )
            if dmgSize > 0 { categories.append(JunkCategory(type: .unusedDMG, size: dmgSize, files: dmgFiles, fileCount: dmgCount)) }

            let screenshotNames = ["screenshot", "screen shot", "снимок экрана", "capture"]
            let (captureSize, captureFiles, captureCount) = scanMatchingFiles(
                [home.appendingPathComponent("Desktop"), home.appendingPathComponent("Downloads")],
                predicate: { url in
                    let name = url.deletingPathExtension().lastPathComponent.lowercased()
                    return screenshotNames.contains { name.contains($0) }
                }
            )
            if captureSize > 0 { categories.append(JunkCategory(type: .screenCaptures, size: captureSize, files: captureFiles, fileCount: captureCount)) }

            let specializedPaths = Set((dmgFiles + captureFiles).map { $0.standardizedFileURL.path })
            let largeDownloads = downloadsFiles.filter { url in
                guard !specializedPaths.contains(url.standardizedFileURL.path) else { return false }
                let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
                ])
                let allocated = values?.totalFileAllocatedSize
                    ?? values?.fileAllocatedSize
                    ?? values?.fileSize
                    ?? 0
                return allocated >= 50 * 1_048_576
            }
            let largeDownloadSize = largeDownloads.reduce(UInt64(0)) { total, url in
                let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
                ])
                let allocated = values?.totalFileAllocatedSize
                    ?? values?.fileAllocatedSize
                    ?? values?.fileSize
                    ?? 0
                return total &+ UInt64(max(allocated, 0))
            }
            if largeDownloadSize > 0 {
                categories.append(JunkCategory(
                    type: .downloads,
                    size: largeDownloadSize,
                    files: largeDownloads,
                    fileCount: largeDownloads.count
                ))
            }

            // System-wide roots are review-only and scanned last so they cannot
            // starve useful user-space results within the global budget.
            let systemCacheRoot = URL(fileURLWithPath: "/Library/Caches")
            let (systemCacheSize, systemCacheFiles, systemCacheCount) = scanPath(systemCacheRoot, collectFiles: false)
            if systemCacheSize > 0 { categories.append(JunkCategory(type: .systemCache, size: systemCacheSize, files: systemCacheFiles, cleanupRoots: [systemCacheRoot], fileCount: systemCacheCount)) }

            let systemLogsRoot = URL(fileURLWithPath: "/Library/Logs")
            let (systemLogsSize, systemLogsFiles, systemLogsCount) = scanPath(systemLogsRoot, collectFiles: false)
            if systemLogsSize > 0 { categories.append(JunkCategory(type: .systemLogs, size: systemLogsSize, files: systemLogsFiles, cleanupRoots: [systemLogsRoot], fileCount: systemLogsCount)) }

            let detailedCategories = categories.map { category -> JunkCategory in
                var detailed = category
                if detailed.entries.isEmpty {
                    if let root = detailed.cleanupRoots.first {
                        detailed.entries = Self.previewEntries(at: root, safety: detailed.safety)
                    } else {
                        detailed.entries = detailed.files.prefix(12).map { url in
                            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                            let isDirectory = values?.isDirectory == true
                            let size = isDirectory ? Self.boundedDirectorySize(url) : UInt64(max(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0, 0))
                            return JunkEntry(id: url.path, url: url, name: url.lastPathComponent, path: url.path, size: size, itemCount: 1, isDirectory: isDirectory, isAggregate: false, safety: detailed.safety)
                        }
                    }
                }
                return detailed
            }
            DispatchQueue.main.async {
                self.junkCategories = detailedCategories.sorted { $0.size > $1.size }
                self.junkScanWasLimited = budget.wasLimited
                self.junkScannedEntryCount = budget.consumedEntries
                self.isScanningJunk = false
            }
        }
    }

    func trashItem(url: URL, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var measurementBudget = ScanResourceBudget(maximumEntries: 20_000, maximumDuration: 1)
            let sizeBefore = self.itemSize(at: url, budget: &measurementBudget)
            let statsInput = CleanupStatsRecordInput(
                path: url.path,
                displayName: url.lastPathComponent,
                category: CleanupStatsStore.inferCategory(path: url.path, fallback: .largeFiles),
                bytes: sizeBefore,
                source: "Storage"
            )
            do {
                _ = try SafeDeletionService.moveToTrash(url)
                Task { @MainActor in
                    CleanupStatsStore.shared.record([statsInput])
                }
                DispatchQueue.main.async { completion(true, nil) }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "Could not move the item to Trash: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Retries one already-selected Large Files item through macOS's native
    /// administrator prompt. The app passes only the exact source path and
    /// the current user's Trash path; it never asks for or stores a password.
    func trashItemAsAdministrator(url: URL, completion: @escaping (Bool, String?) -> Void) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        let command = "/bin/mv -n -- \(Self.shellQuote(url.path)) \(Self.shellQuote(trash.path))"
        let script = "do shell script \"\(Self.appleScriptEscaped(command))\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    completion(task.terminationStatus == 0, task.terminationStatus == 0 ? nil : (output?.isEmpty == false ? output : "Administrator authorization was cancelled or the file could not be moved."))
                }
            } catch {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func cleanJunkCategory(
        _ category: JunkCategory,
        allowUncommittedProject: Bool = false,
        completion: @escaping (JunkCleanResult) -> Void
    ) {
        // Protected developer-owner roots may be scanned and displayed, but
        // they are never eligible for a bulk Trash operation—even if a stale
        // selection state or a future caller passes them directly here.
        if category.safety == .protected {
            completion(JunkCleanResult(
                success: true,
                removedCount: 0,
                alreadyAbsentCount: 0,
                skippedCount: category.itemCount,
                failedCount: 0,
                message: "Protected data was not removed. Use the owning tool to manage it."
            ))
            return
        }
        if category.type == .trash {
            completion(JunkCleanResult(
                success: false,
                removedCount: 0,
                alreadyAbsentCount: 0,
                skippedCount: category.itemCount,
                failedCount: 0,
                message: "Use Finder's Empty Trash command to permanently remove Trash contents."
            ))
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            var statsByPath: [String: CleanupStatsRecordInput] = [:]
            var firstError: String?
            var failedCount = 0
            var skippedCount = 0
            var removedCount = 0
            var alreadyAbsentCount = 0
            let statsCategory = CleanupStatsStore.category(for: category.type)
            let protectionPolicy = SafeDeletionService.currentProtectionPolicy()
            let browserRoots = self.userBrowserCacheRoots()
            var measurementBudget = ScanResourceBudget(maximumEntries: 50_000, maximumDuration: 5)

            if !category.cleanupRoots.isEmpty {
                for root in category.cleanupRoots {
                    autoreleasepool {
                        guard fm.fileExists(atPath: root.path) else {
                            alreadyAbsentCount += 1
                            return
                        }

                        do {
                            let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])
	                            var removedChildren = 0
	                            var removedBytes: UInt64 = 0
	                            for child in children {
	                                if self.shouldSkipJunkURL(
                                        child,
                                        category: category,
                                        protectionPolicy: protectionPolicy,
                                        browserRoots: browserRoots,
                                        allowUncommittedProject: allowUncommittedProject
                                    ) {
	                                    skippedCount += 1
	                                    continue
	                                }
	                                let childSize = self.itemSize(at: child, budget: &measurementBudget)
	                                do {
                                            _ = try SafeDeletionService.moveToTrash(child)
                                    removedChildren += 1
                                    removedBytes += childSize
	                                } catch {
	                                    if self.isFileMissing(error) {
	                                        alreadyAbsentCount += 1
	                                    } else if self.isPermissionDenied(error) {
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
                                    source: "Junk Files · moved to Trash"
                                )
                            }
                        } catch {
                            if self.isFileMissing(error) {
                                alreadyAbsentCount += 1
                            } else {
                                failedCount += 1
                                if firstError == nil {
                                    firstError = error.localizedDescription
                                }
                            }
                        }
                    }
                }
            } else {
                for url in category.files {
                    autoreleasepool {
	                        guard fm.fileExists(atPath: url.path) else {
	                            alreadyAbsentCount += 1
	                            return
	                        }
	                        if self.shouldSkipJunkURL(
                                url,
                                category: category,
                                protectionPolicy: protectionPolicy,
                                browserRoots: browserRoots,
                                allowUncommittedProject: allowUncommittedProject
                            ) {
	                            skippedCount += 1
	                            return
	                        }

	                        let sizeBefore = self.itemSize(at: url, budget: &measurementBudget)
                        do {
                            _ = try SafeDeletionService.moveToTrash(url)
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
	                            if self.isFileMissing(error) {
	                                alreadyAbsentCount += 1
	                            } else if self.isPermissionDenied(error) {
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
	                    alreadyAbsentCount: alreadyAbsentCount,
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
        case .userCache, .systemCache, .browserCache, .xcodeJunk, .systemLogs, .userLogs, .developerOwner:
            return parent
        case .trash, .downloads, .unusedDMG, .screenCaptures:
            return path
        }
    }

    private func shouldSkipJunkURL(
        _ url: URL,
        category: JunkCategory,
        protectionPolicy: SafeDeletionService.ProtectionPolicy,
        browserRoots: [URL],
        allowUncommittedProject: Bool = false
    ) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()

        if SafeDeletionService.isProtectedApplicationPath(url, policy: protectionPolicy) { return true }

        if category.type == .browserCache,
           let owner = category.ownerName?.replacingOccurrences(of: " cache", with: ""),
           NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == owner && !$0.isTerminated }) {
            return true
        }
        if !allowUncommittedProject && category.projectRoot.map(Self.projectHasUncommittedChanges) == true {
            return true
        }

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
            if category.type == .userCache {
                if browserRoots.contains(where: {
                    SafeDeletionService.isPath($0.path, inside: url.path)
                        || SafeDeletionService.isPath(url.path, inside: $0.path)
                }) {
                    return true
                }
            }
            return path.contains("/library/containers/com.apple.")
                || path.contains("/library/group containers/group.com.apple.")
        case .xcodeJunk:
            let keepNames: Set<String> = ["archives", "devicesupport"]
            return keepNames.contains(name)
        case .developerOwner:
            // Docker and model stores are intentionally review-only. They can
            // be measured in Junk Files, but this layer never guesses how to
            // destroy a container volume or a model selected by an agent.
            return category.safety == .protected
        default:
            return false
        }
    }

    private func userBrowserCacheRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Caches/Google/Chrome"),
            home.appendingPathComponent("Library/Caches/com.apple.Safari"),
            home.appendingPathComponent("Library/Caches/com.mozilla.firefox"),
            home.appendingPathComponent("Library/Caches/com.microsoft.edgemac"),
            home.appendingPathComponent("Library/Caches/com.brave.Browser")
        ]
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && (
            nsError.code == NSFileWriteNoPermissionError ||
            nsError.code == NSFileReadNoPermissionError ||
            nsError.code == NSFileWriteVolumeReadOnlyError
        )
    }

    private func isFileMissing(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError {
                return true
            }
        } else if nsError.domain == NSPOSIXErrorDomain && nsError.code == 2 { // ENOENT
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isFileMissing(underlying)
        }
        return false
    }

    private func itemSize(at url: URL, budget: inout ScanResourceBudget) -> UInt64 {
        let fm = FileManager.default
        guard !SafeDeletionService.isProtectedApplicationPath(url) else { return 0 }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            guard budget.consumeEntry() else { return 0 }
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
            ])
            let allocated = values?.totalFileAllocatedSize
                ?? values?.fileAllocatedSize
                ?? values?.fileSize
                ?? 0
            return UInt64(max(allocated, 0))
        }

        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey
        ]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        let protectionPolicy = SafeDeletionService.currentProtectionPolicy()
        var total: UInt64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard budget.consumeEntry() else { break }
            let values = try? fileURL.resourceValues(forKeys: keys)
            if SafeDeletionService.isApplicationOwnedPath(fileURL, policy: protectionPolicy) {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isDirectory == false {
                let allocated = values?.totalFileAllocatedSize
                    ?? values?.fileAllocatedSize
                    ?? values?.fileSize
                    ?? 0
                total &+= UInt64(max(allocated, 0))
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
