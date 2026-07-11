import Darwin
import Foundation
import ImageIO
import Vision

enum SimilarPhotoScanMode: String, CaseIterable, Sendable {
    case efficient = "Efficient"
    case thorough = "Thorough"

    var maximumPhotos: Int { self == .efficient ? 500 : 2_000 }
    var maximumFilesystemEntries: Int { self == .efficient ? 100_000 : 500_000 }
    var discoveryTimeLimit: TimeInterval { self == .efficient ? 12 : 60 }
    var totalTimeLimit: TimeInterval { self == .efficient ? 60 : 300 }
    var maximumComparisons: Int { self == .efficient ? 75_000 : 1_000_000 }
    var minimumFileBytes: UInt64 { self == .efficient ? 16 * 1_024 : 4 * 1_024 }

    var detail: String {
        switch self {
        case .efficient:
            return "Up to 500 photos · 75,000 comparisons · 60-second budget"
        case .thorough:
            return "Up to 2,000 photos · 1,000,000 comparisons · 5-minute budget"
        }
    }
}

enum SimilarPhotoScanPhase: String, Sendable {
    case idle = "Ready"
    case indexing = "Finding local images"
    case analyzing = "Building private visual fingerprints"
    case grouping = "Grouping conservative matches"
    case finished = "Finished"
}

struct SimilarPhotoScanStatus: Sendable {
    let phase: SimilarPhotoScanPhase
    let discoveredPhotos: Int
    let analyzedPhotos: Int
    let comparisons: Int
    let currentPath: String

    static let idle = SimilarPhotoScanStatus(
        phase: .idle,
        discoveredPhotos: 0,
        analyzedPhotos: 0,
        comparisons: 0,
        currentPath: ""
    )
}

struct SimilarPhotoItem: Identifiable, Hashable, Sendable {
    var id: String { url.standardizedFileURL.path }
    let url: URL
    let logicalBytes: UInt64
    let allocatedBytes: UInt64
    let modifiedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int

    var displayName: String { url.lastPathComponent }
    var pixelCount: Int64 { Int64(pixelWidth) * Int64(pixelHeight) }
    var resolution: String { "\(pixelWidth)×\(pixelHeight)" }
}

struct SimilarPhotoGroup: Identifiable, Sendable {
    let id: String
    let photos: [SimilarPhotoItem]
    let keeperID: String
    let maximumDistance: Float

    var potentialReclaimBytes: UInt64 {
        photos.filter { $0.id != keeperID }.reduce(0) { $0 &+ $1.allocatedBytes }
    }

    var confidenceLabel: String {
        maximumDistance <= SimilarPhotoService.verySimilarDistance ? "Very similar" : "Similar"
    }

    static func sortedPhotos(_ photos: [SimilarPhotoItem]) -> [SimilarPhotoItem] {
        photos.sorted { lhs, rhs in
            if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount > rhs.pixelCount }
            if lhs.logicalBytes != rhs.logicalBytes { return lhs.logicalBytes > rhs.logicalBytes }
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }

    func replacingPhotos(_ remaining: [SimilarPhotoItem]) -> SimilarPhotoGroup? {
        // Distances were verified against the original keeper. If the user
        // removes that reference image, require a rescan instead of presenting
        // the remaining photos as a still-verified group.
        guard remaining.count > 1, remaining.contains(where: { $0.id == keeperID }) else { return nil }
        let sorted = Self.sortedPhotos(remaining)
        return SimilarPhotoGroup(
            id: id,
            photos: sorted,
            keeperID: keeperID,
            maximumDistance: maximumDistance
        )
    }
}

struct SimilarPhotoScanResult: Sendable {
    let groups: [SimilarPhotoGroup]
    let discoveredPhotos: Int
    let analyzedPhotos: Int
    let comparisons: Int
    let skippedCloudFiles: Int
    let wasLimited: Bool
    let duration: TimeInterval
}

@MainActor
final class SimilarPhotoService: ObservableObject {
    // Vision feature-print distance is not a percentage. This conservative
    // threshold was calibrated against re-encoded local fixtures; cleanup also
    // regenerates both prints and applies the same threshold immediately before Trash.
    nonisolated static let maximumSimilarDistance: Float = 0.55
    nonisolated static let verySimilarDistance: Float = 0.35

    @Published private(set) var groups: [SimilarPhotoGroup] = []
    @Published var selectedPhotoIDs: Set<String> = []
    @Published var scanRoot: URL = {
        let pictures = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return FileManager.default.fileExists(atPath: pictures.path)
            ? pictures
            : FileManager.default.homeDirectoryForCurrentUser
    }()
    @Published var mode: SimilarPhotoScanMode = .efficient
    @Published private(set) var status: SimilarPhotoScanStatus = .idle
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var scanWasLimited = false
    @Published private(set) var skippedCloudFiles = 0
    @Published private(set) var lastScanDuration: TimeInterval?
    @Published private(set) var resultMessage: String?

    private var scanWorker: Task<SimilarPhotoScanResult, Never>?
    private var progressTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var cleanupWorker: Task<[SimilarPhotoMoveOutcome], Never>?
    private var cleanupCompletion: Task<Void, Never>?

    var potentialReclaimBytes: UInt64 {
        groups.reduce(0) { $0 &+ $1.potentialReclaimBytes }
    }

    var selectedBytes: UInt64 {
        groups.flatMap(\.photos)
            .filter { selectedPhotoIDs.contains($0.id) }
            .reduce(0) { $0 &+ $1.allocatedBytes }
    }

    var selectedCount: Int { selectedPhotoIDs.count }

    func startScan() {
        guard !isScanning, !isCleaning else { return }
        let root = scanRoot.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            resultMessage = "Choose a readable folder before scanning."
            return
        }

        groups = []
        selectedPhotoIDs = []
        scanWasLimited = false
        skippedCloudFiles = 0
        resultMessage = nil
        status = SimilarPhotoScanStatus(
            phase: .indexing,
            discoveredPhotos: 0,
            analyzedPhotos: 0,
            comparisons: 0,
            currentPath: root.path
        )
        isScanning = true
        let selectedMode = mode
        let (stream, continuation) = AsyncStream<SimilarPhotoScanStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let worker = Task.detached(priority: .utility) {
            Self.performScan(root: root, mode: selectedMode) { continuation.yield($0) }
        }
        scanWorker = worker
        progressTask = Task { [weak self] in
            for await update in stream {
                guard let self, self.isScanning else { return }
                self.status = update
            }
        }
        completionTask = Task { [weak self] in
            let result = await worker.value
            continuation.finish()
            guard let self, !Task.isCancelled else { return }
            self.groups = result.groups
            self.selectedPhotoIDs = []
            self.scanWasLimited = result.wasLimited
            self.skippedCloudFiles = result.skippedCloudFiles
            self.lastScanDuration = result.duration
            self.status = SimilarPhotoScanStatus(
                phase: .finished,
                discoveredPhotos: result.discoveredPhotos,
                analyzedPhotos: result.analyzedPhotos,
                comparisons: result.comparisons,
                currentPath: root.path
            )
            self.isScanning = false
            self.scanWorker = nil
            self.progressTask = nil
            self.completionTask = nil
            if result.groups.isEmpty {
                self.resultMessage = result.wasLimited
                    ? "No conservative visual matches were found within the selected resource limits."
                    : "No conservative visual matches were found."
            }
        }
    }

    func cancelScan() {
        scanWorker?.cancel()
        progressTask?.cancel()
        completionTask?.cancel()
        scanWorker = nil
        progressTask = nil
        completionTask = nil
        isScanning = false
        status = .idle
        resultMessage = "Scan cancelled. No files were changed."
    }

    func setScanRoot(_ url: URL) {
        guard !isScanning, !isCleaning else { return }
        scanRoot = url.standardizedFileURL
        groups = []
        selectedPhotoIDs = []
        status = .idle
        resultMessage = nil
    }

    func toggleSelection(_ photo: SimilarPhotoItem, in group: SimilarPhotoGroup) {
        if selectedPhotoIDs.contains(photo.id) {
            selectedPhotoIDs.remove(photo.id)
            return
        }
        let selectedInGroup = group.photos.filter { selectedPhotoIDs.contains($0.id) }.count
        guard selectedInGroup < group.photos.count - 1 else {
            resultMessage = "At least one photo must remain in every similar group."
            return
        }
        selectedPhotoIDs.insert(photo.id)
    }

    func selectLowerResolutionVariants() {
        selectedPhotoIDs = Set(groups.flatMap { group -> [String] in
            guard let keeper = group.photos.first(where: { $0.id == group.keeperID }) else { return [] }
            return group.photos
                .filter { $0.id != keeper.id && $0.pixelCount < keeper.pixelCount }
                .map(\.id)
        })
        resultMessage = selectedPhotoIDs.isEmpty
            ? "No strictly lower-resolution variants were found. Nothing was selected."
            : "Only strictly lower-resolution variants were selected. Review the images before moving them to Trash."
    }

    func clearSelection() {
        selectedPhotoIDs = []
        resultMessage = nil
    }

    var selectionKeepsOnePhotoPerGroup: Bool {
        groups.allSatisfy { group in
            group.photos.filter { selectedPhotoIDs.contains($0.id) }.count < group.photos.count
        }
    }

    func moveSelectedToTrash() {
        guard !isScanning, !isCleaning, !selectedPhotoIDs.isEmpty else { return }
        guard selectionKeepsOnePhotoPerGroup else {
            resultMessage = "Cleanup stopped because one group would lose every photo."
            return
        }

        let root = scanRoot.standardizedFileURL
        let cleanupGroups = groups.compactMap { group -> SimilarPhotoCleanupGroup? in
            let selected = group.photos.filter { selectedPhotoIDs.contains($0.id) }
            let retained = SimilarPhotoGroup.sortedPhotos(group.photos.filter { !selectedPhotoIDs.contains($0.id) }).first
            guard !selected.isEmpty, let retained else { return nil }
            return SimilarPhotoCleanupGroup(retained: retained, selected: selected)
        }
        isCleaning = true
        resultMessage = nil

        let worker = Task.detached(priority: .utility) {
            var outcomes: [SimilarPhotoMoveOutcome] = []
            for group in cleanupGroups {
                guard SafeDeletionService.isPath(group.retained.url.path, inside: root.path),
                      Self.snapshotMatches(group.retained),
                      let retainedPrint = Self.featurePrint(url: group.retained.url) else {
                    outcomes.append(contentsOf: group.selected.map {
                        SimilarPhotoMoveOutcome(item: $0, failure: .changedOrUnverified)
                    })
                    continue
                }

                for item in group.selected {
                    guard !Task.isCancelled,
                          SafeDeletionService.isPath(item.url.path, inside: root.path),
                          Self.snapshotMatches(item),
                          let print = Self.featurePrint(url: item.url),
                          let distance = Self.distance(retainedPrint, print),
                          distance <= Self.maximumSimilarDistance else {
                        outcomes.append(SimilarPhotoMoveOutcome(item: item, failure: .changedOrUnverified))
                        continue
                    }
                    do {
                        _ = try SafeDeletionService.moveToTrash(item.url)
                        outcomes.append(SimilarPhotoMoveOutcome(item: item, failure: nil))
                    } catch {
                        outcomes.append(SimilarPhotoMoveOutcome(item: item, failure: .moveFailed))
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
            let protected = outcomes.filter { $0.failure == .changedOrUnverified }
            let failed = outcomes.filter { $0.failure == .moveFailed }
            let movedIDs = Set(moved.map(\.item.id))
            self.groups = self.groups.compactMap { group in
                group.replacingPhotos(group.photos.filter { !movedIDs.contains($0.id) })
            }
            let remainingIDs = Set(self.groups.flatMap { $0.photos.map(\.id) })
            self.selectedPhotoIDs.formIntersection(remainingIDs)

            if !moved.isEmpty {
                CleanupStatsStore.shared.record(moved.map { outcome in
                    CleanupStatsRecordInput(
                        path: outcome.item.url.path,
                        displayName: outcome.item.displayName,
                        category: .similarPhotos,
                        bytes: outcome.item.allocatedBytes,
                        source: "Similar Photos"
                    )
                })
            }

            self.isCleaning = false
            self.cleanupWorker = nil
            self.cleanupCompletion = nil
            var details = ["Moved \(moved.count) photo\(moved.count == 1 ? "" : "s") to Trash"]
            if !protected.isEmpty { details.append("\(protected.count) changed or could not be reverified and were protected") }
            if !failed.isEmpty { details.append("\(failed.count) could not be moved") }
            self.resultMessage = details.joined(separator: "; ") + ". Empty Trash in Finder to reclaim the space."
        }
    }

    deinit {
        scanWorker?.cancel()
        progressTask?.cancel()
        completionTask?.cancel()
        cleanupWorker?.cancel()
        cleanupCompletion?.cancel()
    }
}

private struct SimilarPhotoCleanupGroup: Sendable {
    let retained: SimilarPhotoItem
    let selected: [SimilarPhotoItem]
}

private enum SimilarPhotoMoveFailure: Sendable, Equatable {
    case changedOrUnverified
    case moveFailed
}

private struct SimilarPhotoMoveOutcome: Sendable {
    let item: SimilarPhotoItem
    let failure: SimilarPhotoMoveFailure?
    var moved: Bool { failure == nil }
}

extension SimilarPhotoService {
    private struct Candidate: Sendable {
        let item: SimilarPhotoItem
        let aspectRatio: Double
    }

    private struct FeatureRecord {
        let candidate: Candidate
        let observation: VNFeaturePrintObservation
    }

    nonisolated static func performScan(
        root: URL,
        mode: SimilarPhotoScanMode,
        progress: (@Sendable (SimilarPhotoScanStatus) -> Void)? = nil
    ) -> SimilarPhotoScanResult {
        let startedAt = Date()
        let discoveryDeadline = startedAt.addingTimeInterval(mode.discoveryTimeLimit)
        let totalDeadline = startedAt.addingTimeInterval(mode.totalTimeLimit)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .contentModificationDateKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return SimilarPhotoScanResult(groups: [], discoveredPhotos: 0, analyzedPhotos: 0, comparisons: 0, skippedCloudFiles: 0, wasLimited: false, duration: 0)
        }

        var candidates: [Candidate] = []
        var visitedEntries = 0
        var skippedCloudFiles = 0
        var wasLimited = false
        let protectionPolicy = SafeDeletionService.currentProtectionPolicy()

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled || Date() >= discoveryDeadline || visitedEntries >= mode.maximumFilesystemEntries {
                wasLimited = true
                break
            }
            visitedEntries += 1
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if SafeDeletionService.isApplicationOwnedPath(url, policy: protectionPolicy) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
                skippedCloudFiles += 1
                continue
            }
            let logical = UInt64(max(values.fileSize ?? 0, 0))
            guard logical >= mode.minimumFileBytes,
                  let dimensions = imageDimensions(url: url),
                  dimensions.width >= 64, dimensions.height >= 64 else { continue }
            let allocated = UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0, 0))
            let item = SimilarPhotoItem(
                url: url.standardizedFileURL,
                logicalBytes: logical,
                allocatedBytes: allocated > 0 ? allocated : logical,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                pixelWidth: dimensions.width,
                pixelHeight: dimensions.height
            )
            candidates.append(Candidate(
                item: item,
                aspectRatio: Double(dimensions.width) / Double(dimensions.height)
            ))
            if candidates.count == 1 || candidates.count.isMultiple(of: 25) {
                progress?(SimilarPhotoScanStatus(
                    phase: .indexing,
                    discoveredPhotos: candidates.count,
                    analyzedPhotos: 0,
                    comparisons: 0,
                    currentPath: url.path
                ))
            }
            if candidates.count >= mode.maximumPhotos {
                wasLimited = true
                break
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.item.pixelCount != rhs.item.pixelCount { return lhs.item.pixelCount > rhs.item.pixelCount }
            return lhs.item.url.path.localizedStandardCompare(rhs.item.url.path) == .orderedAscending
        }

        var clusters: [[FeatureRecord]] = []
        var analyzedPhotos = 0
        var comparisons = 0
        outer: for candidate in candidates {
            if Task.isCancelled || Date() >= totalDeadline {
                wasLimited = true
                break
            }
            guard let observation = featurePrint(url: candidate.item.url) else { continue }
            analyzedPhotos += 1
            let record = FeatureRecord(candidate: candidate, observation: observation)
            var bestClusterIndex: Int?
            var bestDistance = Float.greatestFiniteMagnitude

            for index in clusters.indices {
                if comparisons >= mode.maximumComparisons {
                    wasLimited = true
                    break outer
                }
                let representative = clusters[index][0]
                guard aspectRatiosAreComparable(candidate.aspectRatio, representative.candidate.aspectRatio) else { continue }
                comparisons += 1
                guard let value = distance(observation, representative.observation),
                      value <= maximumSimilarDistance,
                      value < bestDistance else { continue }
                bestDistance = value
                bestClusterIndex = index
            }

            if let bestClusterIndex {
                clusters[bestClusterIndex].append(record)
            } else {
                clusters.append([record])
            }
            if analyzedPhotos == 1 || analyzedPhotos.isMultiple(of: 10) {
                progress?(SimilarPhotoScanStatus(
                    phase: .analyzing,
                    discoveredPhotos: candidates.count,
                    analyzedPhotos: analyzedPhotos,
                    comparisons: comparisons,
                    currentPath: candidate.item.url.path
                ))
            }
        }

        progress?(SimilarPhotoScanStatus(
            phase: .grouping,
            discoveredPhotos: candidates.count,
            analyzedPhotos: analyzedPhotos,
            comparisons: comparisons,
            currentPath: root.path
        ))
        let groups = clusters.compactMap(makeGroup).sorted {
            if $0.potentialReclaimBytes != $1.potentialReclaimBytes {
                return $0.potentialReclaimBytes > $1.potentialReclaimBytes
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        return SimilarPhotoScanResult(
            groups: groups,
            discoveredPhotos: candidates.count,
            analyzedPhotos: analyzedPhotos,
            comparisons: comparisons,
            skippedCloudFiles: skippedCloudFiles,
            wasLimited: wasLimited,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    nonisolated static func featureDistance(first: URL, second: URL) -> Float? {
        guard let firstPrint = featurePrint(url: first),
              let secondPrint = featurePrint(url: second) else { return nil }
        return distance(firstPrint, secondPrint)
    }

    nonisolated static func snapshotMatches(_ item: SimilarPhotoItem) -> Bool {
        var information = stat()
        let result = item.url.path.withCString { lstat($0, &information) }
        guard result == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_size >= 0,
              UInt64(information.st_size) == item.logicalBytes else { return false }
        let modifiedAt = Date(
            timeIntervalSince1970: Double(information.st_mtimespec.tv_sec)
                + Double(information.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        return abs(modifiedAt.timeIntervalSince(item.modifiedAt)) < 0.001
    }

    nonisolated private static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp", "bmp", "gif"
    ]

    nonisolated private static func aspectRatiosAreComparable(_ lhs: Double, _ rhs: Double) -> Bool {
        guard lhs > 0, rhs > 0 else { return false }
        return abs(log(lhs / rhs)) <= 0.25
    }

    nonisolated private static func imageDimensions(url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return (width.intValue, height.intValue)
    }

    nonisolated private static func featurePrint(url: URL) -> VNFeaturePrintObservation? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: 512
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .scaleFit
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                return request.results?.first as? VNFeaturePrintObservation
            } catch {
                return nil
            }
        }
    }

    nonisolated private static func distance(
        _ lhs: VNFeaturePrintObservation,
        _ rhs: VNFeaturePrintObservation
    ) -> Float? {
        var value: Float = 0
        do {
            try lhs.computeDistance(&value, to: rhs)
            return value.isFinite ? value : nil
        } catch {
            return nil
        }
    }

    nonisolated private static func makeGroup(_ records: [FeatureRecord]) -> SimilarPhotoGroup? {
        guard records.count > 1 else { return nil }
        let sortedItems = SimilarPhotoGroup.sortedPhotos(records.map(\.candidate.item))
        guard let keeper = sortedItems.first,
              let keeperRecord = records.first(where: { $0.candidate.item.id == keeper.id }) else { return nil }
        let verified = records.compactMap { record -> (SimilarPhotoItem, Float)? in
            guard let value = distance(keeperRecord.observation, record.observation),
                  value <= maximumSimilarDistance else { return nil }
            return (record.candidate.item, value)
        }
        guard verified.count > 1 else { return nil }
        let photos = SimilarPhotoGroup.sortedPhotos(verified.map(\.0))
        return SimilarPhotoGroup(
            id: photos[0].id,
            photos: photos,
            keeperID: photos[0].id,
            maximumDistance: verified.map(\.1).max() ?? 0
        )
    }
}
