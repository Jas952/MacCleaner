import Foundation

struct CloudItemMetadata: Sendable {
    let isUbiquitous: Bool
    let downloadStatus: String?
    let isUploaded: Bool?
    let isUploading: Bool?
    let hasUnresolvedConflicts: Bool?
    let allocatedBytes: UInt64

    var isEligibleForLocalEviction: Bool {
        isUbiquitous
            && downloadStatus == URLUbiquitousItemDownloadingStatus.current.rawValue
            && isUploaded == true
            && isUploading != true
            && hasUnresolvedConflicts != true
            && allocatedBytes >= 1_048_576
    }
}

struct CloudReclaimItem: Identifiable, Hashable, Sendable {
    var id: String { url.standardizedFileURL.path }
    let url: URL
    let allocatedBytes: UInt64
    let logicalBytes: UInt64
    let lastUsedAt: Date

    var displayName: String { url.lastPathComponent }
    var inactiveDays: Int {
        max(0, Calendar.current.dateComponents([.day], from: lastUsedAt, to: Date()).day ?? 0)
    }
}

struct CloudReclaimScanResult: Sendable {
    let items: [CloudReclaimItem]
    let scannedFiles: Int
    let skippedUnverified: Int
    let wasLimited: Bool
    let duration: TimeInterval
}

struct CloudReclaimProgress: Sendable {
    let scannedFiles: Int
    let eligibleFiles: Int
    let currentPath: String
}

enum CloudReclaimScanMode: String, Sendable {
    case efficient = "Efficient"
    case thorough = "Thorough"

    var maximumEntries: Int { self == .efficient ? 200_000 : 1_000_000 }
    var timeLimit: TimeInterval { self == .efficient ? 8 : 60 }
}

protocol CloudItemEvicting: Sendable {
    func isUbiquitousItem(at url: URL) -> Bool
    func evictUbiquitousItem(at url: URL) throws
}

struct SystemCloudItemEvictor: CloudItemEvicting {
    func isUbiquitousItem(at url: URL) -> Bool {
        FileManager.default.isUbiquitousItem(at: url)
    }

    func evictUbiquitousItem(at url: URL) throws {
        try FileManager.default.evictUbiquitousItem(at: url)
    }
}

@MainActor
final class CloudReclaimService: ObservableObject {
    @Published private(set) var items: [CloudReclaimItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isEvicting = false
    @Published private(set) var scanProgress = CloudReclaimProgress(scannedFiles: 0, eligibleFiles: 0, currentPath: "")
    @Published private(set) var scanWasLimited = false
    @Published private(set) var skippedUnverified = 0
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var scanMode: CloudReclaimScanMode = .efficient
    @Published private(set) var resultMessage: String?

    let rootURL: URL
    private let evictor: any CloudItemEvicting
    private var scanWorker: Task<CloudReclaimScanResult, Never>?
    private var scanProgressTask: Task<Void, Never>?
    private var scanCompletion: Task<Void, Never>?
    private var evictionWorker: Task<[CloudEvictionOutcome], Never>?
    private var evictionCompletion: Task<Void, Never>?

    init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true),
        evictor: any CloudItemEvicting = SystemCloudItemEvictor()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.evictor = evictor
    }

    var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var totalEligibleBytes: UInt64 { items.reduce(0) { $0 &+ $1.allocatedBytes } }
    var selectedBytes: UInt64 {
        items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 &+ $1.allocatedBytes }
    }
    var inactiveNinetyDayCount: Int { items.filter { $0.inactiveDays >= 90 }.count }

    func scan(mode: CloudReclaimScanMode = .efficient) {
        guard !isScanning, !isEvicting else { return }
        guard isAvailable else {
            resultMessage = "iCloud Drive is not available at the standard local location."
            return
        }

        items = []
        selectedIDs = []
        scanWasLimited = false
        scanMode = mode
        skippedUnverified = 0
        resultMessage = nil
        scanProgress = CloudReclaimProgress(scannedFiles: 0, eligibleFiles: 0, currentPath: rootURL.path)
        isScanning = true

        let (stream, continuation) = AsyncStream<CloudReclaimProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let root = rootURL
        let worker = Task.detached(priority: .utility) {
            Self.performScan(
                root: root,
                maximumEntries: mode.maximumEntries,
                timeLimit: mode.timeLimit
            ) { continuation.yield($0) }
        }
        scanWorker = worker
        scanProgressTask = Task { [weak self] in
            for await progress in stream {
                guard let self, self.isScanning else { return }
                self.scanProgress = progress
            }
        }
        scanCompletion = Task { [weak self] in
            let result = await worker.value
            continuation.finish()
            guard let self, !Task.isCancelled else { return }
            self.items = result.items.sorted {
                if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
                return $0.lastUsedAt < $1.lastUsedAt
            }
            self.selectedIDs = []
            self.scanWasLimited = result.wasLimited
            self.skippedUnverified = result.skippedUnverified
            self.lastScanDuration = result.duration
            self.scanProgress = CloudReclaimProgress(
                scannedFiles: result.scannedFiles,
                eligibleFiles: result.items.count,
                currentPath: root.path
            )
            self.isScanning = false
            self.scanWorker = nil
            self.scanProgressTask = nil
            self.scanCompletion = nil
            if result.items.isEmpty {
                self.resultMessage = result.wasLimited
                    ? "No eligible local iCloud copies were found within the scan limits."
                    : "No safely evictable local iCloud copies larger than 1 MB were found."
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
        resultMessage = "Scan cancelled. No cloud or local files were changed."
    }

    func toggle(_ item: CloudReclaimItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectInactive(days: Int = 90) {
        selectedIDs = Set(items.filter { $0.inactiveDays >= days }.map(\.id))
        resultMessage = selectedIDs.isEmpty
            ? "No eligible files have been inactive for \(days) days."
            : "Selected \(selectedIDs.count) file\(selectedIDs.count == 1 ? "" : "s") inactive for at least \(days) days."
    }

    func clearSelection() {
        selectedIDs = []
        resultMessage = nil
    }

    func resetForNavigation() {
        guard !isScanning, !isEvicting else { return }
        items = []
        selectedIDs = []
        scanProgress = CloudReclaimProgress(scannedFiles: 0, eligibleFiles: 0, currentPath: "")
        scanWasLimited = false
        skippedUnverified = 0
        lastScanDuration = nil
        resultMessage = nil
    }

    func removeSelectedLocalCopies() {
        guard !isScanning, !isEvicting else { return }
        let selected = items.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        isEvicting = true
        resultMessage = nil
        let evictor = self.evictor
        let worker = Task.detached(priority: .utility) {
            selected.map { item in
                guard evictor.isUbiquitousItem(at: item.url),
                      let metadata = Self.metadata(at: item.url),
                      metadata.isEligibleForLocalEviction else {
                    return CloudEvictionOutcome(item: item, failure: .stateChanged)
                }
                do {
                    try evictor.evictUbiquitousItem(at: item.url)
                    return CloudEvictionOutcome(item: item, failure: nil)
                } catch {
                    return CloudEvictionOutcome(item: item, failure: .evictionFailed)
                }
            }
        }
        evictionWorker = worker
        evictionCompletion = Task { [weak self] in
            let outcomes = await worker.value
            guard let self, !Task.isCancelled else { return }
            let released = outcomes.filter(\.succeeded)
            let changed = outcomes.filter { $0.failure == .stateChanged }
            let failed = outcomes.filter { $0.failure == .evictionFailed }
            let releasedIDs = Set(released.map(\.item.id))

            if !released.isEmpty {
                CleanupStatsStore.shared.record(released.map { outcome in
                    CleanupStatsRecordInput(
                        path: outcome.item.url.path,
                        displayName: outcome.item.displayName,
                        category: .cloud,
                        bytes: outcome.item.allocatedBytes,
                        source: "Cloud Reclaim"
                    )
                })
            }

            self.items.removeAll { releasedIDs.contains($0.id) }
            self.selectedIDs.subtract(releasedIDs)
            self.isEvicting = false
            self.evictionWorker = nil
            self.evictionCompletion = nil

            let bytes = released.reduce(0) { $0 &+ $1.item.allocatedBytes }
            var details = ["Removed \(released.count) local cop\(released.count == 1 ? "y" : "ies") representing up to \(Self.formatBytes(bytes)); iCloud originals remain available"]
            if !changed.isEmpty { details.append("\(changed.count) changed state and were protected") }
            if !failed.isEmpty { details.append("\(failed.count) could not be evicted") }
            self.resultMessage = details.joined(separator: "; ") + "."
        }
    }

    deinit {
        scanWorker?.cancel()
        scanProgressTask?.cancel()
        scanCompletion?.cancel()
        evictionWorker?.cancel()
        evictionCompletion?.cancel()
    }
}

private enum CloudEvictionFailure: Sendable, Equatable {
    case stateChanged
    case evictionFailed
}

private struct CloudEvictionOutcome: Sendable {
    let item: CloudReclaimItem
    let failure: CloudEvictionFailure?
    var succeeded: Bool { failure == nil }
}

extension CloudReclaimService {
    nonisolated static func performScan(
        root: URL,
        maximumEntries: Int = 200_000,
        timeLimit: TimeInterval = 8,
        progress: (@Sendable (CloudReclaimProgress) -> Void)? = nil
    ) -> CloudReclaimScanResult {
        let startedAt = Date()
        let keys = resourceKeys
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return CloudReclaimScanResult(items: [], scannedFiles: 0, skippedUnverified: 0, wasLimited: false, duration: 0)
        }

        let deadline = Date().addingTimeInterval(timeLimit)
        var items: [CloudReclaimItem] = []
        var scannedFiles = 0
        var skippedUnverified = 0
        var wasLimited = false
        let protectionPolicy = SafeDeletionService.currentProtectionPolicy()

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { wasLimited = true; break }
            if scannedFiles >= maximumEntries || Date() >= deadline {
                wasLimited = true
                break
            }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if SafeDeletionService.isApplicationOwnedPath(url, policy: protectionPolicy) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            scannedFiles += 1

            let itemMetadata = metadata(from: values)
            guard itemMetadata.isEligibleForLocalEviction else {
                if itemMetadata.isUbiquitous { skippedUnverified += 1 }
                continue
            }

            items.append(CloudReclaimItem(
                url: url.standardizedFileURL,
                allocatedBytes: itemMetadata.allocatedBytes,
                logicalBytes: UInt64(max(values.fileSize ?? 0, 0)),
                lastUsedAt: values.contentAccessDate ?? values.contentModificationDate ?? Date()
            ))
            if scannedFiles.isMultiple(of: 500) || items.count == 1 {
                progress?(CloudReclaimProgress(scannedFiles: scannedFiles, eligibleFiles: items.count, currentPath: url.path))
            }
        }

        return CloudReclaimScanResult(
            items: items,
            scannedFiles: scannedFiles,
            skippedUnverified: skippedUnverified,
            wasLimited: wasLimited,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    nonisolated static func metadata(at url: URL) -> CloudItemMetadata? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
        return metadata(from: values)
    }

    nonisolated static func metadata(from values: URLResourceValues) -> CloudItemMetadata {
        let allocated = UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0, 0))
        return CloudItemMetadata(
            isUbiquitous: values.isUbiquitousItem == true,
            downloadStatus: values.ubiquitousItemDownloadingStatus?.rawValue,
            isUploaded: values.ubiquitousItemIsUploaded,
            isUploading: values.ubiquitousItemIsUploading,
            hasUnresolvedConflicts: values.ubiquitousItemHasUnresolvedConflicts,
            allocatedBytes: allocated
        )
    }

    private nonisolated static var resourceKeys: Set<URLResourceKey> {
        [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .contentAccessDateKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemHasUnresolvedConflictsKey
        ]
    }

    private nonisolated static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .file)
    }
}
