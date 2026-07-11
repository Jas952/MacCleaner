import Foundation

enum CleanupRecommendationRisk: Int, CaseIterable, Sendable {
    case low
    case review

    var label: String {
        switch self {
        case .low: return "Low risk"
        case .review: return "Review"
        }
    }
}

enum CleanupRebuildCost: Int, CaseIterable, Sendable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return "Fast rebuild"
        case .medium: return "May download again"
        case .high: return "Hard to replace"
        }
    }
}

enum CleanupRecommendationCategory: String, Sendable {
    case developer = "Developer"
    case installer = "Installers"
    case backup = "Backups"
}

struct CleanupRecommendation: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let why: String
    let solution: String
    let paths: [URL]
    let bytes: UInt64
    let itemCount: Int
    let estimateIsLimited: Bool
    let ageDays: Int
    let risk: CleanupRecommendationRisk
    let rebuildCost: CleanupRebuildCost
    let category: CleanupRecommendationCategory

    var isSelectedByDefault: Bool {
        risk == .low && rebuildCost == .low
    }

    var priorityScore: Int {
        Self.priorityScore(bytes: bytes, risk: risk, rebuildCost: rebuildCost, ageDays: ageDays)
    }

    static func priorityScore(
        bytes: UInt64,
        risk: CleanupRecommendationRisk,
        rebuildCost: CleanupRebuildCost,
        ageDays: Int
    ) -> Int {
        let megabytes = Double(bytes) / 1_048_576
        let sizeScore = min(55.0, log2(megabytes + 1) * 5.5)
        let ageScore = min(25.0, Double(max(ageDays, 0)) / 180.0 * 25.0)
        let safetyBonus = risk == .low ? 20.0 : 5.0
        let rebuildPenalty: Double
        switch rebuildCost {
        case .low: rebuildPenalty = 0
        case .medium: rebuildPenalty = 8
        case .high: rebuildPenalty = 18
        }
        return Int(max(0, min(100, (sizeScore + ageScore + safetyBonus - rebuildPenalty).rounded())))
    }
}

@MainActor
final class CleanupAdvisorService: ObservableObject {
    @Published private(set) var recommendations: [CleanupRecommendation] = []
    @Published var selectedIDs: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var lastScanAt: Date?
    @Published private(set) var resultMessage: String?

    private var scanWorker: Task<[CleanupRecommendation], Never>?
    private var scanCompletion: Task<Void, Never>?
    private var cleanupWorker: Task<[CleanupMoveOutcome], Never>?
    private var cleanupCompletion: Task<Void, Never>?

    var selectedBytes: UInt64 {
        recommendations
            .filter { selectedIDs.contains($0.id) }
            .reduce(0) { $0 &+ $1.bytes }
    }

    var totalBytes: UInt64 {
        recommendations.reduce(0) { $0 &+ $1.bytes }
    }

    func scan() {
        guard !isScanning, !isCleaning else { return }
        resultMessage = nil
        isScanning = true

        let home = FileManager.default.homeDirectoryForCurrentUser
        let worker = Task.detached(priority: .utility) {
            Self.performScan(home: home)
        }
        scanWorker = worker
        scanCompletion = Task { [weak self] in
            let found = await worker.value
            guard let self, !Task.isCancelled else { return }
            self.recommendations = found.sorted {
                if $0.priorityScore == $1.priorityScore { return $0.bytes > $1.bytes }
                return $0.priorityScore > $1.priorityScore
            }
            self.selectedIDs = Set(found.filter(\.isSelectedByDefault).map(\.id))
            self.lastScanAt = Date()
            self.isScanning = false
            self.scanWorker = nil
            self.scanCompletion = nil
        }
    }

    func cancelScan() {
        scanWorker?.cancel()
        scanCompletion?.cancel()
        scanWorker = nil
        scanCompletion = nil
        isScanning = false
        resultMessage = "Scan cancelled. No files were changed."
    }

    func toggleSelection(_ recommendation: CleanupRecommendation) {
        if selectedIDs.contains(recommendation.id) {
            selectedIDs.remove(recommendation.id)
        } else {
            selectedIDs.insert(recommendation.id)
        }
    }

    func moveSelectedToTrash() {
        guard !isScanning, !isCleaning else { return }
        let selected = recommendations.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else {
            resultMessage = "Select at least one recommendation first."
            return
        }

        isCleaning = true
        resultMessage = nil
        let worker = Task.detached(priority: .utility) {
            selected.map { recommendation in
                var movedPaths: [String] = []
                var failedPaths: [String] = []
                for url in recommendation.paths {
                    guard !Task.isCancelled else { break }
                    do {
                        _ = try SafeDeletionService.moveToTrash(url)
                        movedPaths.append(url.standardizedFileURL.path)
                    } catch {
                        failedPaths.append(url.standardizedFileURL.path)
                    }
                }
                return CleanupMoveOutcome(
                    recommendationID: recommendation.id,
                    movedPaths: movedPaths,
                    failedPaths: failedPaths
                )
            }
        }
        cleanupWorker = worker
        cleanupCompletion = Task { [weak self] in
            let outcomes = await worker.value
            guard let self, !Task.isCancelled else { return }

            let byID = Dictionary(uniqueKeysWithValues: self.recommendations.map { ($0.id, $0) })
            var stats: [CleanupStatsRecordInput] = []
            var movedCount = 0
            var failedCount = 0
            var completedIDs: Set<String> = []

            for outcome in outcomes {
                guard let recommendation = byID[outcome.recommendationID] else { continue }
                movedCount += outcome.movedPaths.count
                failedCount += outcome.failedPaths.count
                if outcome.failedPaths.isEmpty { completedIDs.insert(outcome.recommendationID) }

                let bytesPerPath = recommendation.paths.isEmpty
                    ? recommendation.bytes
                    : recommendation.bytes / UInt64(recommendation.paths.count)
                for path in outcome.movedPaths {
                    stats.append(CleanupStatsRecordInput(
                        path: path,
                        displayName: URL(fileURLWithPath: path).lastPathComponent,
                        category: recommendation.category == .developer ? .developerCache : .other,
                        bytes: bytesPerPath,
                        source: "Cleanup Advisor"
                    ))
                }
            }

            if !stats.isEmpty { CleanupStatsStore.shared.record(stats) }
            self.recommendations.removeAll { completedIDs.contains($0.id) }
            self.selectedIDs.subtract(completedIDs)
            self.isCleaning = false
            self.cleanupWorker = nil
            self.cleanupCompletion = nil
            if failedCount == 0 {
                self.resultMessage = "Moved \(movedCount) item\(movedCount == 1 ? "" : "s") to Trash. Empty Trash in Finder when you want to reclaim the disk space."
            } else {
                self.resultMessage = "Moved \(movedCount) item\(movedCount == 1 ? "" : "s") to Trash; \(failedCount) could not be moved. Nothing was permanently deleted."
            }
        }
    }

    deinit {
        scanWorker?.cancel()
        scanCompletion?.cancel()
        cleanupWorker?.cancel()
        cleanupCompletion?.cancel()
    }
}

private struct CleanupMoveOutcome: Sendable {
    let recommendationID: String
    let movedPaths: [String]
    let failedPaths: [String]
}

extension CleanupAdvisorService {
    struct DirectoryCandidate {
        let id: String
        let title: String
        let relativePath: String
        let detail: String
        let why: String
        let solution: String
        let risk: CleanupRecommendationRisk
        let rebuildCost: CleanupRebuildCost
    }

    struct SizeEstimate {
        let bytes: UInt64
        let itemCount: Int
        let isLimited: Bool
        let newestModificationDate: Date?
    }

    struct CollectionSizeEstimate {
        let measuredURLs: [URL]
        let bytes: UInt64
        let itemCount: Int
        let isLimited: Bool
    }

    nonisolated static func performScan(home: URL) -> [CleanupRecommendation] {
        let directoryCandidates = [
            DirectoryCandidate(
                id: "xcode-derived-data",
                title: "Xcode DerivedData",
                relativePath: "Library/Developer/Xcode/DerivedData",
                detail: "Build products and indexes generated by Xcode.",
                why: "Old projects can leave gigabytes of rebuildable data behind.",
                solution: "Move it to Trash; Xcode recreates data for projects you build again.",
                risk: .low,
                rebuildCost: .medium
            ),
            DirectoryCandidate(
                id: "xcode-simulator-caches",
                title: "Simulator caches",
                relativePath: "Library/Developer/CoreSimulator/Caches",
                detail: "Rebuildable metadata and caches used by Apple simulators.",
                why: "Simulator updates and testing can accumulate stale cache data.",
                solution: "Move the cache to Trash; Simulator recreates it when needed.",
                risk: .low,
                rebuildCost: .low
            ),
            DirectoryCandidate(
                id: "homebrew-cache",
                title: "Homebrew downloads",
                relativePath: "Library/Caches/Homebrew",
                detail: "Downloaded bottles and source archives retained by Homebrew.",
                why: "Installed packages do not require most cached installers to keep running.",
                solution: "Move the cache to Trash; Homebrew downloads a package again if required.",
                risk: .low,
                rebuildCost: .medium
            ),
            DirectoryCandidate(
                id: "npm-cache",
                title: "npm package cache",
                relativePath: ".npm/_cacache",
                detail: "Content-addressed package data downloaded by npm.",
                why: "Repeated installs can build a large cache independent of active projects.",
                solution: "Move it to Trash; npm fetches missing packages on the next install.",
                risk: .low,
                rebuildCost: .medium
            ),
            DirectoryCandidate(
                id: "gradle-cache",
                title: "Gradle dependency cache",
                relativePath: ".gradle/caches",
                detail: "Downloaded dependencies and build metadata used by Gradle.",
                why: "Old Gradle versions and inactive projects may leave large caches.",
                solution: "Move it to Trash; the next affected build can take longer and redownload dependencies.",
                risk: .low,
                rebuildCost: .medium
            ),
            DirectoryCandidate(
                id: "cocoapods-cache",
                title: "CocoaPods cache",
                relativePath: "Library/Caches/CocoaPods",
                detail: "Downloaded pod specifications and package artifacts.",
                why: "The cache can outlive the projects and pod versions that created it.",
                solution: "Move it to Trash; CocoaPods downloads missing artifacts when needed.",
                risk: .low,
                rebuildCost: .medium
            ),
            DirectoryCandidate(
                id: "pip-cache",
                title: "Python package cache",
                relativePath: "Library/Caches/pip",
                detail: "Python wheels and source packages downloaded by pip.",
                why: "Installed environments continue working without cached installers.",
                solution: "Move it to Trash; pip downloads packages again during a future install.",
                risk: .low,
                rebuildCost: .medium
            ),
            DirectoryCandidate(
                id: "swiftpm-cache",
                title: "Swift Package Manager cache",
                relativePath: "Library/Caches/org.swift.swiftpm",
                detail: "Rebuildable metadata and downloads used by Swift Package Manager.",
                why: "Dependencies from inactive projects can remain after builds finish.",
                solution: "Move it to Trash; SwiftPM resolves and downloads missing data again.",
                risk: .low,
                rebuildCost: .medium
            )
        ]

        var results: [CleanupRecommendation] = []
        for candidate in directoryCandidates {
            guard !Task.isCancelled else { return results }
            let url = home.appendingPathComponent(candidate.relativePath, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let estimate = estimateSize(of: url, entryLimit: 12_000, timeLimit: 0.25)
            guard estimate.bytes >= 10 * 1_048_576 else { continue }
            let age = daysSince(estimate.newestModificationDate)
            results.append(CleanupRecommendation(
                id: candidate.id,
                title: candidate.title,
                detail: candidate.detail,
                why: candidate.why,
                solution: candidate.solution,
                paths: [url],
                bytes: estimate.bytes,
                itemCount: estimate.itemCount,
                estimateIsLimited: estimate.isLimited,
                ageDays: age,
                risk: candidate.risk,
                rebuildCost: candidate.rebuildCost,
                category: .developer
            ))
        }

        if !Task.isCancelled,
           let installers = oldInstallersRecommendation(home: home) {
            results.append(installers)
        }
        if !Task.isCancelled,
           let archives = xcodeArchivesRecommendation(home: home) {
            results.append(archives)
        }
        if !Task.isCancelled,
           let backups = mobileBackupsRecommendation(home: home) {
            results.append(backups)
        }
        return results
    }

    nonisolated static func oldInstallersRecommendation(home: URL) -> CleanupRecommendation? {
        let allowedExtensions = Set(["dmg", "pkg", "zip", "xip", "tar", "gz", "bz2", "xz", "7z", "rar"])
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        var matches: [URL] = []
        var total: UInt64 = 0
        var oldestDays = 0

        for folderName in ["Downloads", "Desktop"] {
            let folder = home.appendingPathComponent(folderName, isDirectory: true)
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { continue }
            for file in files.prefix(2_500) {
                guard !Task.isCancelled, allowedExtensions.contains(file.pathExtension.lowercased()) else { continue }
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                let date = values.contentModificationDate ?? Date()
                guard date < cutoff else { continue }
                matches.append(file)
                total &+= UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0, 0))
                oldestDays = max(oldestDays, daysSince(date))
            }
        }

        guard !matches.isEmpty, total >= 10 * 1_048_576 else { return nil }
        return CleanupRecommendation(
            id: "old-installers",
            title: "Old installers and archives",
            detail: "\(matches.count) archive or installer file\(matches.count == 1 ? "" : "s") older than 30 days in Downloads or Desktop.",
            why: "Install media often remains after an app or package is installed.",
            solution: "Review the list, then move selected files to Trash. Personal archives may be valuable.",
            paths: matches,
            bytes: total,
            itemCount: matches.count,
            estimateIsLimited: false,
            ageDays: oldestDays,
            risk: .review,
            rebuildCost: .high,
            category: .installer
        )
    }

    nonisolated static func xcodeArchivesRecommendation(home: URL) -> CleanupRecommendation? {
        let root = home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var archives: [(url: URL, modified: Date)] = []
        while let url = enumerator.nextObject() as? URL, archives.count < 250 {
            guard !Task.isCancelled else { return nil }
            guard url.pathExtension.lowercased() == "xcarchive" else { continue }
            enumerator.skipDescendants()
            let modified = (try? url.resourceValues(forKeys: keys).contentModificationDate) ?? Date()
            if modified < cutoff { archives.append((url, modified)) }
        }

        guard !archives.isEmpty else { return nil }
        archives.sort { $0.modified < $1.modified }
        let collection = estimateCollection(
            archives.map(\.url),
            entryLimitPerRoot: 10_000,
            totalTimeLimit: 1.0
        )
        guard collection.bytes >= 10 * 1_048_576 else { return nil }
        let oldestDays = daysSince(archives.first?.modified)
        return CleanupRecommendation(
            id: "old-xcode-archives",
            title: "Old Xcode Archives",
            detail: "\(collection.measuredURLs.count) measured app archive\(collection.measuredURLs.count == 1 ? "" : "s") older than 90 days.",
            why: "Archives include symbols and signed builds, so they can be very large.",
            solution: "Review carefully. Keep archives required for crash symbolication or redistribution.",
            paths: collection.measuredURLs,
            bytes: collection.bytes,
            itemCount: collection.itemCount,
            estimateIsLimited: collection.isLimited || archives.count >= 250,
            ageDays: oldestDays,
            risk: .review,
            rebuildCost: .high,
            category: .backup
        )
    }

    nonisolated static func mobileBackupsRecommendation(home: URL) -> CleanupRecommendation? {
        let root = home.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return nil }
        let backups = children.compactMap { url -> (url: URL, modified: Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory == true else { return nil }
            return (url, values.contentModificationDate ?? Date())
        }.sorted { $0.modified < $1.modified }
        guard !backups.isEmpty else { return nil }

        let candidates = Array(backups.prefix(100))
        let collection = estimateCollection(
            candidates.map(\.url),
            entryLimitPerRoot: 15_000,
            totalTimeLimit: 1.0
        )
        guard collection.bytes >= 10 * 1_048_576 else { return nil }
        return CleanupRecommendation(
            id: "mobile-device-backups",
            title: "iPhone and iPad backups",
            detail: "\(collection.measuredURLs.count) measured local device backup\(collection.measuredURLs.count == 1 ? "" : "s") found.",
            why: "Local encrypted or unencrypted backups can occupy tens or hundreds of gigabytes.",
            solution: "Remove only backups you no longer need. A deleted backup cannot be rebuilt without the device and its data.",
            paths: collection.measuredURLs,
            bytes: collection.bytes,
            itemCount: collection.itemCount,
            estimateIsLimited: collection.isLimited || backups.count > 100,
            ageDays: daysSince(candidates.first?.modified),
            risk: .review,
            rebuildCost: .high,
            category: .backup
        )
    }

    nonisolated static func estimateSize(of root: URL, entryLimit: Int, timeLimit: TimeInterval) -> SizeEstimate {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return SizeEstimate(bytes: 0, itemCount: 0, isLimited: false, newestModificationDate: nil)
        }

        let deadline = Date().addingTimeInterval(timeLimit)
        var bytes: UInt64 = 0
        var count = 0
        var newest: Date?
        var limited = false
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled || count >= entryLimit || Date() >= deadline {
                limited = true
                break
            }
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { continue }
            if values.isRegularFile == true {
                bytes &+= UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0, 0))
                count += 1
            }
            if let modified = values.contentModificationDate, newest == nil || modified > newest! {
                newest = modified
            }
        }
        return SizeEstimate(bytes: bytes, itemCount: count, isLimited: limited, newestModificationDate: newest)
    }

    nonisolated static func estimateCollection(
        _ urls: [URL],
        entryLimitPerRoot: Int,
        totalTimeLimit: TimeInterval
    ) -> CollectionSizeEstimate {
        let deadline = Date().addingTimeInterval(totalTimeLimit)
        var measuredURLs: [URL] = []
        var bytes: UInt64 = 0
        var itemCount = 0
        var limited = false

        for url in urls {
            guard !Task.isCancelled else {
                limited = true
                break
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0.02 else {
                limited = true
                break
            }
            let estimate = estimateSize(
                of: url,
                entryLimit: entryLimitPerRoot,
                timeLimit: min(0.35, remaining)
            )
            measuredURLs.append(url)
            bytes &+= estimate.bytes
            itemCount += estimate.itemCount
            limited = limited || estimate.isLimited
        }

        if measuredURLs.count < urls.count { limited = true }
        return CollectionSizeEstimate(
            measuredURLs: measuredURLs,
            bytes: bytes,
            itemCount: itemCount,
            isLimited: limited
        )
    }

    nonisolated static func daysSince(_ date: Date?) -> Int {
        guard let date else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)
    }
}
