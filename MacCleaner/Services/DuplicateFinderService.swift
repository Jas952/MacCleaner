import CryptoKit
import Foundation

enum DuplicateScanMode: String, CaseIterable, Sendable {
    case efficient = "Efficient"
    case thorough = "Thorough"

    var minimumFileBytes: UInt64 {
        switch self {
        case .efficient: return 1_048_576
        case .thorough: return 128 * 1_024
        }
    }

    var maximumEntries: Int {
        switch self {
        case .efficient: return 200_000
        case .thorough: return 1_000_000
        }
    }

    var discoveryTimeLimit: TimeInterval {
        switch self {
        case .efficient: return 12
        case .thorough: return 90
        }
    }

    var hashReadBudget: UInt64 {
        switch self {
        case .efficient: return 40 * 1_073_741_824
        case .thorough: return 500 * 1_073_741_824
        }
    }

    var detail: String {
        switch self {
        case .efficient: return "Files ≥ 1 MB · up to 40 GB of verification I/O"
        case .thorough: return "Files ≥ 128 KB · up to 500 GB of verification I/O"
        }
    }
}

enum DuplicateScanPhase: String, Sendable {
    case idle = "Ready"
    case indexing = "Indexing file metadata"
    case sampling = "Comparing quick fingerprints"
    case verifying = "Verifying full SHA-256 hashes"
    case finished = "Finished"
}

struct DuplicateScanStatus: Sendable {
    let phase: DuplicateScanPhase
    let scannedFiles: Int
    let hashedFiles: Int
    let currentPath: String

    static let idle = DuplicateScanStatus(phase: .idle, scannedFiles: 0, hashedFiles: 0, currentPath: "")
}

struct DuplicateFileItem: Identifiable, Hashable, Sendable {
    var id: String { url.standardizedFileURL.path }
    let url: URL
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
    let modifiedAt: Date

    var displayName: String { url.lastPathComponent }
}

struct DuplicateFileGroup: Identifiable, Sendable {
    let id: String
    let files: [DuplicateFileItem]
    let keeperID: String

    var logicalBytes: UInt64 { files.first?.logicalBytes ?? 0 }
    var potentialReclaimBytes: UInt64 {
        files.filter { $0.id != keeperID }.reduce(0) { $0 &+ $1.allocatedBytes }
    }

    static func make(id: String, files: [DuplicateFileItem], root: URL) -> DuplicateFileGroup {
        let sorted = files.sorted { lhs, rhs in
            let lhsPenalty = keeperPenalty(for: lhs, root: root)
            let rhsPenalty = keeperPenalty(for: rhs, root: root)
            if lhsPenalty != rhsPenalty { return lhsPenalty < rhsPenalty }
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
            if lhs.url.path.count != rhs.url.path.count { return lhs.url.path.count < rhs.url.path.count }
            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
        return DuplicateFileGroup(id: id, files: sorted, keeperID: sorted[0].id)
    }

    private static func keeperPenalty(for item: DuplicateFileItem, root: URL) -> Int {
        let path = item.url.standardizedFileURL.path.lowercased()
        let name = item.url.deletingPathExtension().lastPathComponent.lowercased()
        var penalty = 0
        if path.contains("/downloads/") { penalty += 120 }
        if path.contains("/desktop/") { penalty += 30 }
        if name.contains(" copy") || name.hasSuffix("-copy") || name.range(of: #"\([0-9]+\)$"#, options: .regularExpression) != nil {
            penalty += 80
        }
        if !SafeDeletionService.isPath(item.url.path, inside: root.path) { penalty += 1_000 }
        return penalty
    }
}

struct DuplicateScanResult: Sendable {
    let groups: [DuplicateFileGroup]
    let scannedFiles: Int
    let hashedFiles: Int
    let skippedCloudFiles: Int
    let wasLimited: Bool
    let duration: TimeInterval
}

@MainActor
final class DuplicateFinderService: ObservableObject {
    @Published private(set) var groups: [DuplicateFileGroup] = []
    @Published var selectedFileIDs: Set<String> = []
    @Published var scanRoot = FileManager.default.homeDirectoryForCurrentUser
    @Published var mode: DuplicateScanMode = .efficient
    @Published private(set) var status: DuplicateScanStatus = .idle
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var scanWasLimited = false
    @Published private(set) var skippedCloudFiles = 0
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var resultMessage: String?

    private var scanWorker: Task<DuplicateScanResult, Never>?
    private var scanProgressTask: Task<Void, Never>?
    private var scanCompletion: Task<Void, Never>?
    private var cleanupWorker: Task<[DuplicateMoveOutcome], Never>?
    private var cleanupCompletion: Task<Void, Never>?

    var potentialReclaimBytes: UInt64 {
        groups.reduce(0) { $0 &+ $1.potentialReclaimBytes }
    }

    var selectedBytes: UInt64 {
        let items = groups.flatMap(\.files)
        return items
            .filter { selectedFileIDs.contains($0.id) }
            .reduce(0) { $0 &+ $1.allocatedBytes }
    }

    var selectedCount: Int { selectedFileIDs.count }

    func startScan() {
        guard !isScanning, !isCleaning else { return }
        let root = scanRoot.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            resultMessage = "Choose a readable folder before scanning."
            return
        }

        groups = []
        selectedFileIDs = []
        scanWasLimited = false
        skippedCloudFiles = 0
        resultMessage = nil
        status = DuplicateScanStatus(phase: .indexing, scannedFiles: 0, hashedFiles: 0, currentPath: root.path)
        isScanning = true
        let selectedMode = mode

        let (progressStream, progressContinuation) = AsyncStream<DuplicateScanStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let worker = Task.detached(priority: .utility) {
            Self.performScan(root: root, mode: selectedMode) { update in
                progressContinuation.yield(update)
            }
        }
        scanWorker = worker
        scanProgressTask = Task { [weak self] in
            for await update in progressStream {
                guard let self, self.isScanning else { return }
                self.status = update
            }
        }
        scanCompletion = Task { [weak self] in
            let result = await worker.value
            progressContinuation.finish()
            guard let self, !Task.isCancelled else { return }
            self.groups = result.groups
            self.selectedFileIDs = []
            self.scanWasLimited = result.wasLimited
            self.skippedCloudFiles = result.skippedCloudFiles
            self.lastScanDuration = result.duration
            self.status = DuplicateScanStatus(
                phase: .finished,
                scannedFiles: result.scannedFiles,
                hashedFiles: result.hashedFiles,
                currentPath: root.path
            )
            self.isScanning = false
            self.scanWorker = nil
            self.scanProgressTask = nil
            self.scanCompletion = nil
            if result.groups.isEmpty {
                self.resultMessage = result.wasLimited
                    ? "No exact duplicates were verified within the selected scan limits."
                    : "No exact duplicates were found."
            }
        }
    }

    func cancelScan() {
        scanWorker?.cancel()
        scanProgressTask?.cancel()
        scanCompletion?.cancel()
        scanWorker = nil
        scanProgressTask = nil
        scanCompletion = nil
        isScanning = false
        status = .idle
        resultMessage = "Scan cancelled. No files were changed."
    }

    func setScanRoot(_ url: URL) {
        guard !isScanning, !isCleaning else { return }
        scanRoot = url.standardizedFileURL
        groups = []
        selectedFileIDs = []
        status = .idle
        resultMessage = nil
    }

    func toggleSelection(_ item: DuplicateFileItem, in group: DuplicateFileGroup) {
        if selectedFileIDs.contains(item.id) {
            selectedFileIDs.remove(item.id)
            return
        }
        let selectedInGroup = group.files.filter { selectedFileIDs.contains($0.id) }.count
        guard selectedInGroup < group.files.count - 1 else {
            resultMessage = "At least one verified copy must remain in every group."
            return
        }
        selectedFileIDs.insert(item.id)
    }

    func selectSuggestedCopies() {
        selectedFileIDs = Set(groups.flatMap { group in
            group.files.filter { $0.id != group.keeperID }.map(\.id)
        })
        resultMessage = "Suggested copies selected. Review every path before moving files to Trash."
    }

    func clearSelection() {
        selectedFileIDs = []
        resultMessage = nil
    }

    func moveSelectedToTrash() {
        guard !isScanning, !isCleaning, !selectedFileIDs.isEmpty else { return }
        guard selectionKeepsOneFilePerGroup else {
            resultMessage = "Cleanup stopped because one group would lose every copy."
            return
        }

        let cleanupGroups = groups.compactMap { group -> DuplicateCleanupGroup? in
            let selectedItems = group.files.filter { selectedFileIDs.contains($0.id) }
            guard !selectedItems.isEmpty,
                  let retainedItem = group.files.first(where: { !selectedFileIDs.contains($0.id) }) else {
                return nil
            }
            return DuplicateCleanupGroup(
                expectedDigest: group.id,
                retainedItem: retainedItem,
                selectedItems: selectedItems
            )
        }
        isCleaning = true
        resultMessage = nil

        let worker = Task.detached(priority: .utility) {
            var outcomes: [DuplicateMoveOutcome] = []
            for group in cleanupGroups {
                guard let retained = Self.fullFingerprint(url: group.retainedItem.url),
                      retained.digest == group.expectedDigest,
                      retained.bytesRead == group.retainedItem.logicalBytes else {
                    outcomes.append(contentsOf: group.selectedItems.map {
                        DuplicateMoveOutcome(item: $0, failure: .contentChanged)
                    })
                    continue
                }

                for item in group.selectedItems {
                    guard let current = Self.fullFingerprint(url: item.url),
                          current.digest == group.expectedDigest,
                          current.bytesRead == item.logicalBytes else {
                        outcomes.append(DuplicateMoveOutcome(item: item, failure: .contentChanged))
                        continue
                    }
                    do {
                        _ = try SafeDeletionService.moveToTrash(item.url)
                        outcomes.append(DuplicateMoveOutcome(item: item, failure: nil))
                    } catch {
                        outcomes.append(DuplicateMoveOutcome(item: item, failure: .moveFailed))
                    }
                }
            }
            return outcomes
        }
        cleanupWorker = worker
        cleanupCompletion = Task { [weak self] in
            let outcomes = await worker.value
            guard let self, !Task.isCancelled else { return }
            let moved = outcomes.filter(\.moved)
            let changed = outcomes.filter { $0.failure == .contentChanged }
            let failed = outcomes.filter { $0.failure == .moveFailed }
            let movedIDs = Set(moved.map(\.item.id))

            let updatedGroups = self.groups.compactMap { group -> DuplicateFileGroup? in
                let remaining = group.files.filter { !movedIDs.contains($0.id) }
                guard remaining.count > 1 else { return nil }
                return DuplicateFileGroup.make(id: group.id, files: remaining, root: self.scanRoot)
            }
            self.groups = updatedGroups
            self.selectedFileIDs.subtract(movedIDs)

            if !moved.isEmpty {
                CleanupStatsStore.shared.record(moved.map { outcome in
                    CleanupStatsRecordInput(
                        path: outcome.item.url.path,
                        displayName: outcome.item.displayName,
                        category: .duplicates,
                        bytes: outcome.item.allocatedBytes,
                        source: "Exact Duplicates"
                    )
                })
            }

            self.isCleaning = false
            self.cleanupWorker = nil
            self.cleanupCompletion = nil
            if failed.isEmpty, changed.isEmpty {
                self.resultMessage = "Moved \(moved.count) verified duplicate\(moved.count == 1 ? "" : "s") to Trash. Empty Trash in Finder to reclaim the space."
            } else {
                var details: [String] = []
                if !changed.isEmpty { details.append("\(changed.count) changed after the scan and were protected") }
                if !failed.isEmpty { details.append("\(failed.count) could not be moved") }
                self.resultMessage = "Moved \(moved.count) duplicate\(moved.count == 1 ? "" : "s") to Trash; " + details.joined(separator: "; ") + "."
            }
        }
    }

    var selectionKeepsOneFilePerGroup: Bool {
        groups.allSatisfy { group in
            group.files.filter { selectedFileIDs.contains($0.id) }.count < group.files.count
        }
    }

    deinit {
        scanWorker?.cancel()
        scanProgressTask?.cancel()
        scanCompletion?.cancel()
        cleanupWorker?.cancel()
        cleanupCompletion?.cancel()
    }
}

private struct DuplicateCleanupGroup: Sendable {
    let expectedDigest: String
    let retainedItem: DuplicateFileItem
    let selectedItems: [DuplicateFileItem]
}

private enum DuplicateMoveFailure: Sendable, Equatable {
    case contentChanged
    case moveFailed
}

private struct DuplicateMoveOutcome: Sendable {
    let item: DuplicateFileItem
    let failure: DuplicateMoveFailure?
    var moved: Bool { failure == nil }
}

extension DuplicateFinderService {
    private struct Candidate: Sendable {
        let url: URL
        let logicalBytes: UInt64
        let allocatedBytes: UInt64
        let modifiedAt: Date
        let resourceID: String
    }

    nonisolated static func performScan(
        root: URL,
        mode: DuplicateScanMode,
        progress: (@Sendable (DuplicateScanStatus) -> Void)? = nil
    ) -> DuplicateScanResult {
        let startedAt = Date()
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return DuplicateScanResult(groups: [], scannedFiles: 0, hashedFiles: 0, skippedCloudFiles: 0, wasLimited: false, duration: 0)
        }

        let deadline = Date().addingTimeInterval(mode.discoveryTimeLimit)
        let protectionPolicy = SafeDeletionService.currentProtectionPolicy()
        var bySize: [UInt64: [Candidate]] = [:]
        var scannedFiles = 0
        var skippedCloudFiles = 0
        var wasLimited = false

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { wasLimited = true; break }
            if scannedFiles >= mode.maximumEntries || Date() >= deadline {
                wasLimited = true
                break
            }

            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if SafeDeletionService.isApplicationOwnedPath(url, policy: protectionPolicy) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory == true {
                if shouldSkipDirectory(url, root: root) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            scannedFiles += 1
            if scannedFiles.isMultiple(of: 500) {
                progress?(DuplicateScanStatus(phase: .indexing, scannedFiles: scannedFiles, hashedFiles: 0, currentPath: url.path))
            }

            if values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus != .current {
                skippedCloudFiles += 1
                continue
            }

            let logical = UInt64(max(values.fileSize ?? 0, 0))
            guard logical >= mode.minimumFileBytes else { continue }
            let allocated = UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0, 0))
            let resourceID = values.fileResourceIdentifier.map { String(describing: $0) } ?? url.standardizedFileURL.path
            bySize[logical, default: []].append(Candidate(
                url: url.standardizedFileURL,
                logicalBytes: logical,
                allocatedBytes: allocated > 0 ? allocated : logical,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                resourceID: resourceID
            ))
        }

        let candidateGroups = bySize.values
            .map(uniqueResources)
            .filter { $0.count > 1 }
            .sorted { potentialBytes($0) > potentialBytes($1) }

        var exactGroups: [DuplicateFileGroup] = []
        var hashReadBytes: UInt64 = 0
        var hashedFiles = 0
        var didEmitVerificationProgress = false

        outer: for sizeGroup in candidateGroups {
            if Task.isCancelled { wasLimited = true; break }
            var quickGroups: [String: [Candidate]] = [:]
            for candidate in sizeGroup {
                if Task.isCancelled { wasLimited = true; break outer }
                let projectedQuickRead = min(candidate.logicalBytes, 128 * 1_024)
                if projectedQuickRead > mode.hashReadBudget - min(hashReadBytes, mode.hashReadBudget) {
                    wasLimited = true
                    break outer
                }
                guard let quick = quickFingerprint(candidate) else { continue }
                hashReadBytes &+= projectedQuickRead
                quickGroups[quick, default: []].append(candidate)
                hashedFiles += 1
                if hashedFiles == 1 || hashedFiles.isMultiple(of: 25) {
                    progress?(DuplicateScanStatus(phase: .sampling, scannedFiles: scannedFiles, hashedFiles: hashedFiles, currentPath: candidate.url.path))
                }
            }

            for quickGroup in quickGroups.values where quickGroup.count > 1 {
                let projectedRead = quickGroup.reduce(0) { $0 &+ $1.logicalBytes }
                if projectedRead > mode.hashReadBudget - min(hashReadBytes, mode.hashReadBudget) {
                    wasLimited = true
                    continue
                }

                var fullGroups: [String: [Candidate]] = [:]
                for candidate in quickGroup {
                    if Task.isCancelled { wasLimited = true; break outer }
                    guard let full = fullFingerprint(candidate), full.bytesRead == candidate.logicalBytes else { continue }
                    hashReadBytes &+= full.bytesRead
                    fullGroups[full.digest, default: []].append(candidate)
                    hashedFiles += 1
                    if !didEmitVerificationProgress || hashedFiles.isMultiple(of: 25) {
                        progress?(DuplicateScanStatus(phase: .verifying, scannedFiles: scannedFiles, hashedFiles: hashedFiles, currentPath: candidate.url.path))
                        didEmitVerificationProgress = true
                    }
                }

                for (digest, candidates) in fullGroups where candidates.count > 1 {
                    let files = candidates.map {
                        DuplicateFileItem(
                            url: $0.url,
                            logicalBytes: $0.logicalBytes,
                            allocatedBytes: $0.allocatedBytes,
                            modifiedAt: $0.modifiedAt
                        )
                    }
                    exactGroups.append(DuplicateFileGroup.make(id: digest, files: files, root: root))
                }
            }
        }

        exactGroups.sort { $0.potentialReclaimBytes > $1.potentialReclaimBytes }
        return DuplicateScanResult(
            groups: exactGroups,
            scannedFiles: scannedFiles,
            hashedFiles: hashedFiles,
            skippedCloudFiles: skippedCloudFiles,
            wasLimited: wasLimited,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private nonisolated static func shouldSkipDirectory(_ url: URL, root: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let skippedNames: Set<String> = [
            ".trash", ".git", ".svn", ".hg", ".build", "node_modules",
            "deriveddata", "pods", "carthage", "backups.backupdb"
        ]
        if skippedNames.contains(name) { return true }

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        if root.standardizedFileURL.path == home.path {
            let library = home.appendingPathComponent("Library", isDirectory: true)
            if SafeDeletionService.isPath(url.path, inside: library.path) { return true }
        }
        return false
    }

    private nonisolated static func uniqueResources(_ candidates: [Candidate]) -> [Candidate] {
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.resourceID).inserted }
    }

    private nonisolated static func potentialBytes(_ candidates: [Candidate]) -> UInt64 {
        guard candidates.count > 1 else { return 0 }
        return candidates.dropFirst().reduce(0) { $0 &+ $1.allocatedBytes }
    }

    private nonisolated static func quickFingerprint(_ candidate: Candidate) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: candidate.url)
            defer { try? handle.close() }
            let sampleSize = 64 * 1_024
            let first = try handle.read(upToCount: sampleSize) ?? Data()
            let tailOffset = candidate.logicalBytes > UInt64(sampleSize)
                ? candidate.logicalBytes - UInt64(sampleSize)
                : 0
            try handle.seek(toOffset: tailOffset)
            let last = try handle.read(upToCount: sampleSize) ?? Data()
            var sample = Data()
            withUnsafeBytes(of: candidate.logicalBytes.bigEndian) { sample.append(contentsOf: $0) }
            sample.append(first)
            sample.append(last)
            return SHA256.hash(data: sample).hexString
        } catch {
            return nil
        }
    }

    private nonisolated static func fullFingerprint(_ candidate: Candidate) -> (digest: String, bytesRead: UInt64)? {
        fullFingerprint(url: candidate.url)
    }

    nonisolated static func fullFingerprint(url: URL) -> (digest: String, bytesRead: UInt64)? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            var bytesRead: UInt64 = 0
            while true {
                if Task.isCancelled { return nil }
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
                hasher.update(data: data)
                bytesRead &+= UInt64(data.count)
            }
            return (hasher.finalize().hexString, bytesRead)
        } catch {
            return nil
        }
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
