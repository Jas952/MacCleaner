import AppKit
import Combine
import XCTest
@testable import MacCleaner

final class SafetyPolicyTests: XCTestCase {
    func testPathBoundaryDoesNotAcceptSiblingPrefix() {
        XCTAssertTrue(SafeDeletionService.isPath("/Users/test/Library/Caches/App", inside: "/Users/test/Library/Caches"))
        XCTAssertFalse(SafeDeletionService.isPath("/Users/test/Library/CachesBackup/App", inside: "/Users/test/Library/Caches"))
    }

    func testMacCleanerProtectionCoversWorkingDataBundleAndAncestors() {
        let home = URL(fileURLWithPath: "/tmp/MacCleanerProtectionHome", isDirectory: true)
        let bundle = home.appendingPathComponent("Applications/MacCleaner.app", isDirectory: true)
        let policy = SafeDeletionService.currentProtectionPolicy(
            home: home,
            bundleURL: bundle,
            bundleIdentifier: "com.maccleaner.app"
        )

        XCTAssertTrue(SafeDeletionService.isProtectedApplicationPath(bundle, policy: policy))
        XCTAssertTrue(SafeDeletionService.isProtectedApplicationPath(bundle.deletingLastPathComponent(), policy: policy))
        XCTAssertTrue(SafeDeletionService.isProtectedApplicationPath(
            home.appendingPathComponent("Library/Application Support/MacCleaner/cleanup-stats.json"),
            policy: policy
        ))
        XCTAssertTrue(SafeDeletionService.isApplicationOwnedPath(
            home.appendingPathComponent("Library/Caches/com.maccleaner.app/cache.bin"),
            policy: policy
        ))
        XCTAssertFalse(SafeDeletionService.isApplicationOwnedPath(
            home.appendingPathComponent("Library/Caches", isDirectory: true),
            policy: policy
        ))
        XCTAssertFalse(SafeDeletionService.isProtectedApplicationPath(
            home.appendingPathComponent("Library/Caches/com.example.editor/cache.bin"),
            policy: policy
        ))
    }

    func testSafeDeletionRefusesProtectedMacCleanerDataBeforeTrash() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerProtectedDeleteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("Library/Application Support/MacCleaner/state.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("state".utf8).write(to: file)
        let policy = SafeDeletionService.currentProtectionPolicy(
            home: home,
            bundleURL: home.appendingPathComponent("Applications/MacCleaner.app"),
            bundleIdentifier: "com.maccleaner.app"
        )

        XCTAssertThrowsError(try SafeDeletionService.moveToTrash(file, policy: policy)) { error in
            XCTAssertTrue(error is SafeDeletionError)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testSharedScanBudgetStopsAtGlobalEntryAndTimeLimits() {
        var entryBudget = ScanResourceBudget(maximumEntries: 2, maximumDuration: 60)
        XCTAssertTrue(entryBudget.consumeEntry())
        XCTAssertTrue(entryBudget.consumeEntry())
        XCTAssertFalse(entryBudget.consumeEntry())
        XCTAssertEqual(entryBudget.consumedEntries, 2)
        XCTAssertTrue(entryBudget.wasLimited)

        var expiredBudget = ScanResourceBudget(
            maximumEntries: 100,
            maximumDuration: 1,
            startedAt: Date(timeIntervalSinceNow: -2)
        )
        XCTAssertFalse(expiredBudget.beginRoot())
        XCTAssertTrue(expiredBudget.wasLimited)
    }

    func testSystemMonitorCutsWakeupCadenceWhenNoScreenConsumesData() {
        let active = SystemMonitor.recommendedRefreshInterval(hasActiveConsumers: true)
        let idle = SystemMonitor.recommendedRefreshInterval(hasActiveConsumers: false)
        XCTAssertEqual(active, 15)
        XCTAssertGreaterThanOrEqual(idle, active * 2)
    }

    func testReviewCategoriesAreNotSelectedByDefault() {
        XCTAssertFalse(CleanCategory.devCache.isSelectedByDefault)
        XCTAssertFalse(CleanCategory.aiTools.isSelectedByDefault)
        XCTAssertFalse(CleanCategory.trash.isSelectedByDefault)
        XCTAssertFalse(CleanCategory.downloads.isSelectedByDefault)
    }

    func testNormalUserCachesRemainSelectedByDefault() {
        XCTAssertTrue(CleanCategory.browserCache.isSelectedByDefault)
        XCTAssertTrue(CleanCategory.userCache.isSelectedByDefault)
    }

    func testMacCleanerProcessIsProtected() {
        let node = ProcessNode(
            id: 42,
            name: "MacCleaner",
            commandLine: "/Applications/MacCleaner.app/Contents/MacOS/MacCleaner",
            cpuUsage: 0,
            cpuTime: "0:00",
            memoryBytes: 0,
            parentPID: 1,
            isBackgroundAgent: false
        )
        XCTAssertTrue(ProcessTreeService.isProtected(node))
    }

    func testProcessAggregationKeepsUniqueInstancesAndSumsMetrics() throws {
        func node(_ id: Int32, cpu: Double, time: String, memory: UInt64, read: UInt64, written: UInt64) -> ProcessNode {
            ProcessNode(
                id: id,
                name: "Example App",
                commandLine: "/Applications/Example App.app/Contents/MacOS/Example --pid \(id)",
                cpuUsage: cpu,
                cpuTime: time,
                memoryBytes: memory,
                diskRead: read,
                diskWritten: written,
                parentPID: 1,
                isBackgroundAgent: false
            )
        }

        let first = node(100, cpu: 2.5, time: "0:10", memory: 100, read: 10, written: 20)
        let second = node(101, cpu: 7.5, time: "1:05", memory: 250, read: 30, written: 40)
        let groups = ProcessAggregator.aggregate([first, second, first])
        let group = try XCTUnwrap(groups.first)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(group.instanceCount, 2)
        XCTAssertEqual(group.groupedInstances.map(\.id), [100, 101])
        XCTAssertEqual(group.cpuUsage, 10, accuracy: 0.001)
        XCTAssertEqual(group.cpuTime, "1:15")
        XCTAssertEqual(group.memoryBytes, 350)
        XCTAssertEqual(group.diskRead, 40)
        XCTAssertEqual(group.diskWritten, 60)
    }

    func testProcessAggregationDoesNotExposeSingleProcessAsGroup() throws {
        let process = ProcessNode(
            id: 200,
            name: "Solo",
            commandLine: "/tmp/solo",
            cpuUsage: 1,
            cpuTime: "2:03",
            memoryBytes: 42,
            parentPID: 1,
            isBackgroundAgent: false
        )
        let result = try XCTUnwrap(ProcessAggregator.aggregate([process]).first)
        XCTAssertEqual(result.instanceCount, 1)
        XCTAssertTrue(result.groupedInstances.isEmpty)
        XCTAssertEqual(result.cpuTime, "2:03")
    }

    func testProcessAggregationDoesNotMergeGenericNamesFromDifferentExecutables() {
        let first = ProcessNode(
            id: 301, name: "com", commandLine: "/usr/libexec/com.apple.alpha",
            cpuUsage: 1, cpuTime: "0:01", memoryBytes: 10, parentPID: 1, isBackgroundAgent: true
        )
        let second = ProcessNode(
            id: 302, name: "com", commandLine: "/usr/libexec/com.apple.beta",
            cpuUsage: 2, cpuTime: "0:02", memoryBytes: 20, parentPID: 1, isBackgroundAgent: true
        )
        let groups = ProcessAggregator.aggregate([first, second])
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.instanceCount == 1 })
    }

    func testCleanupAdvisorRanksMoreBytesHigherAtEqualRisk() {
        let small = CleanupRecommendation.priorityScore(
            bytes: 50 * 1_048_576,
            risk: .low,
            rebuildCost: .low,
            ageDays: 30
        )
        let large = CleanupRecommendation.priorityScore(
            bytes: 5 * 1_073_741_824,
            risk: .low,
            rebuildCost: .low,
            ageDays: 30
        )
        XCTAssertGreaterThan(large, small)
    }

    func testCleanupAdvisorPenalizesRiskAndRebuildCost() {
        let safe = CleanupRecommendation.priorityScore(
            bytes: 1_073_741_824,
            risk: .low,
            rebuildCost: .low,
            ageDays: 90
        )
        let sensitive = CleanupRecommendation.priorityScore(
            bytes: 1_073_741_824,
            risk: .review,
            rebuildCost: .high,
            ageDays: 90
        )
        XCTAssertGreaterThan(safe, sensitive)
    }

    func testCleanupAdvisorNeverPreselectsSensitiveData() {
        let recommendation = CleanupRecommendation(
            id: "backup",
            title: "Backup",
            detail: "",
            why: "",
            solution: "",
            paths: [URL(fileURLWithPath: "/tmp/backup")],
            bytes: 1_073_741_824,
            itemCount: 1,
            estimateIsLimited: false,
            ageDays: 365,
            risk: .review,
            rebuildCost: .high,
            category: .backup
        )
        XCTAssertFalse(recommendation.isSelectedByDefault)
    }

    func testCleanupAdvisorRequiresOptInWhenCacheMustRedownload() {
        let recommendation = CleanupRecommendation(
            id: "package-cache",
            title: "Package cache",
            detail: "",
            why: "",
            solution: "",
            paths: [URL(fileURLWithPath: "/tmp/cache")],
            bytes: 500 * 1_048_576,
            itemCount: 1,
            estimateIsLimited: false,
            ageDays: 30,
            risk: .low,
            rebuildCost: .medium,
            category: .developer
        )
        XCTAssertFalse(recommendation.isSelectedByDefault)
    }

    func testCleanupAdvisorFindsSupportedCacheUsingAllocatedBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerAdvisorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = root.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: 11 * 1_048_576)
            .write(to: cache.appendingPathComponent("bottle.tar.gz"), options: .atomic)

        let results = CleanupAdvisorService.performScan(home: root)
        let homebrew = try XCTUnwrap(results.first { $0.id == "homebrew-cache" })
        XCTAssertGreaterThanOrEqual(homebrew.bytes, 10 * 1_048_576)
        XCTAssertEqual(homebrew.risk, .low)
        XCTAssertFalse(homebrew.isSelectedByDefault)
    }

    func testDuplicateFinderRequiresFullContentMatch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerDuplicateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let matching = Data(repeating: 0x5A, count: 1_100_000)
        let different = Data(repeating: 0xA5, count: 1_100_000)
        try matching.write(to: root.appendingPathComponent("original.bin"))
        try matching.write(to: root.appendingPathComponent("copy.bin"))
        try different.write(to: root.appendingPathComponent("same-size-different.bin"))

        let result = DuplicateFinderService.performScan(root: root, mode: .efficient)
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].files.count, 2)
        XCTAssertEqual(Set(result.groups[0].files.map(\.displayName)), Set(["original.bin", "copy.bin"]))
    }

    func testDuplicateFinderDoesNotTreatHardLinksAsReclaimableCopies() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerHardLinkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let original = root.appendingPathComponent("original.bin")
        let linked = root.appendingPathComponent("hard-link.bin")
        try Data(repeating: 0x42, count: 1_100_000).write(to: original)
        try FileManager.default.linkItem(at: original, to: linked)

        let result = DuplicateFinderService.performScan(root: root, mode: .efficient)
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testDuplicateFingerprintDetectsChangesAfterScan() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerChangedDuplicateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let original = root.appendingPathComponent("original.bin")
        let copy = root.appendingPathComponent("copy.bin")
        let initial = Data(repeating: 0x11, count: 1_100_000)
        try initial.write(to: original)
        try initial.write(to: copy)
        let result = DuplicateFinderService.performScan(root: root, mode: .efficient)
        let expectedDigest = try XCTUnwrap(result.groups.first?.id)

        try Data(repeating: 0x22, count: 1_100_000).write(to: copy)
        let changedDigest = try XCTUnwrap(DuplicateFinderService.fullFingerprint(url: copy)?.digest)
        XCTAssertNotEqual(changedDigest, expectedDigest)
    }

    func testDuplicateRescanDoesNotReturnRemovedPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerDuplicateRescanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.bin")
        let copy = root.appendingPathComponent("copy.bin")
        let data = Data(repeating: 0x42, count: 1_200_000)
        try data.write(to: original)
        try data.write(to: copy)

        XCTAssertEqual(DuplicateFinderService.performScan(root: root, mode: .efficient).groups.count, 1)
        try FileManager.default.removeItem(at: copy)
        let rescanned = DuplicateFinderService.performScan(root: root, mode: .efficient)
        XCTAssertTrue(rescanned.groups.isEmpty)
        XCTAssertFalse(rescanned.groups.flatMap(\.files).contains { $0.url == copy })
    }

    @MainActor
    func testCleanerNavigationResetRestoresInitialState() {
        let state = CleanerViewState()
        state.hasScan = true
        state.showResult = true
        state.scanProgress = 1
        state.resultFreed = 512
        state.dnsFlow = .done
        state.dnsSuccess = true
        state.optimizationPhase = .success
        state.optimizationFoundDisk = 1_024
        state.optimizationLogs = [OptimizationLog(message: "Finished", status: .success)]

        state.resetForNavigation()

        XCTAssertFalse(state.hasScan)
        XCTAssertFalse(state.showResult)
        XCTAssertEqual(state.scanProgress, 0)
        XCTAssertNil(state.resultFreed)
        if case .idle = state.dnsFlow {} else { XCTFail("DNS flow was not reset") }
        if case .ready = state.optimizationPhase {} else { XCTFail("Optimization phase was not reset") }
        XCTAssertTrue(state.optimizationLogs.isEmpty)
        XCTAssertEqual(state.optimizationFoundDisk, 0)
    }

    @MainActor
    func testDuplicateSelectionAlwaysKeepsOneCopy() {
        let root = URL(fileURLWithPath: "/tmp/duplicates", isDirectory: true)
        let first = DuplicateFileItem(
            url: root.appendingPathComponent("a.bin"),
            logicalBytes: 10,
            allocatedBytes: 10,
            modifiedAt: .distantPast
        )
        let second = DuplicateFileItem(
            url: root.appendingPathComponent("b.bin"),
            logicalBytes: 10,
            allocatedBytes: 10,
            modifiedAt: .distantFuture
        )
        let group = DuplicateFileGroup.make(id: "hash", files: [first, second], root: root)
        let service = DuplicateFinderService()

        service.toggleSelection(first, in: group)
        service.toggleSelection(second, in: group)

        XCTAssertEqual(service.selectedFileIDs.count, 1)
        XCTAssertTrue(service.selectionKeepsOneFilePerGroup)
    }

    func testCloudReclaimRequiresCurrentUploadedConflictFreeItem() {
        let eligible = CloudItemMetadata(
            isUbiquitous: true,
            downloadStatus: URLUbiquitousItemDownloadingStatus.current.rawValue,
            isUploaded: true,
            isUploading: false,
            hasUnresolvedConflicts: false,
            allocatedBytes: 10 * 1_048_576
        )
        XCTAssertTrue(eligible.isEligibleForLocalEviction)
    }

    func testCloudReclaimRejectsUnprovenCloudState() {
        let base = CloudItemMetadata(
            isUbiquitous: true,
            downloadStatus: URLUbiquitousItemDownloadingStatus.current.rawValue,
            isUploaded: true,
            isUploading: false,
            hasUnresolvedConflicts: false,
            allocatedBytes: 10 * 1_048_576
        )
        XCTAssertTrue(base.isEligibleForLocalEviction)

        XCTAssertFalse(CloudItemMetadata(
            isUbiquitous: false,
            downloadStatus: base.downloadStatus,
            isUploaded: true,
            isUploading: false,
            hasUnresolvedConflicts: false,
            allocatedBytes: base.allocatedBytes
        ).isEligibleForLocalEviction)
        XCTAssertFalse(CloudItemMetadata(
            isUbiquitous: true,
            downloadStatus: URLUbiquitousItemDownloadingStatus.notDownloaded.rawValue,
            isUploaded: true,
            isUploading: false,
            hasUnresolvedConflicts: false,
            allocatedBytes: base.allocatedBytes
        ).isEligibleForLocalEviction)
        XCTAssertFalse(CloudItemMetadata(
            isUbiquitous: true,
            downloadStatus: base.downloadStatus,
            isUploaded: nil,
            isUploading: false,
            hasUnresolvedConflicts: false,
            allocatedBytes: base.allocatedBytes
        ).isEligibleForLocalEviction)
        XCTAssertFalse(CloudItemMetadata(
            isUbiquitous: true,
            downloadStatus: base.downloadStatus,
            isUploaded: true,
            isUploading: true,
            hasUnresolvedConflicts: false,
            allocatedBytes: base.allocatedBytes
        ).isEligibleForLocalEviction)
        XCTAssertFalse(CloudItemMetadata(
            isUbiquitous: true,
            downloadStatus: base.downloadStatus,
            isUploaded: true,
            isUploading: false,
            hasUnresolvedConflicts: true,
            allocatedBytes: base.allocatedBytes
        ).isEligibleForLocalEviction)
    }

    func testCloudReclaimIgnoresOrdinaryLocalFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerCloudTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x77, count: 2 * 1_048_576)
            .write(to: root.appendingPathComponent("local-only.bin"))

        let result = CloudReclaimService.performScan(root: root)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.scannedFiles, 1)
    }

    func testSimilarPhotoVisionThresholdSeparatesReencodeFromDifferentScreen() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let icon = projectRoot.appendingPathComponent("MacCleaner/Assets.xcassets/AppIcon.appiconset/icon_512x512.png")
        let different = projectRoot.appendingPathComponent("docs/readme-media/hero-v2.png")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerSimilarDistanceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let reencoded = root.appendingPathComponent("reencoded.jpg")
        try jpegData(from: icon, compression: 0.75).write(to: reencoded)

        let similarDistance = try XCTUnwrap(SimilarPhotoService.featureDistance(first: icon, second: reencoded))
        let differentDistance = try XCTUnwrap(SimilarPhotoService.featureDistance(first: icon, second: different))

        XCTAssertLessThanOrEqual(similarDistance, SimilarPhotoService.maximumSimilarDistance)
        XCTAssertGreaterThan(differentDistance, SimilarPhotoService.maximumSimilarDistance)
        XCTAssertLessThan(similarDistance, differentDistance)
    }

    func testSimilarPhotoScanGroupsReencodedImageWithoutSelectingAnything() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = projectRoot.appendingPathComponent("MacCleaner/Assets.xcassets/AppIcon.appiconset/icon_512x512.png")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerSimilarScanTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent("original.png"))
        try jpegData(from: source, compression: 0.9).write(to: root.appendingPathComponent("variant.jpg"))

        let result = SimilarPhotoService.performScan(root: root, mode: .efficient)

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].photos.count, 2)
        XCTAssertLessThanOrEqual(result.groups[0].maximumDistance, SimilarPhotoService.maximumSimilarDistance)
    }

    @MainActor
    func testSimilarPhotoSelectionAlwaysKeepsOnePhoto() {
        let root = URL(fileURLWithPath: "/tmp/similar-photos", isDirectory: true)
        let first = SimilarPhotoItem(
            url: root.appendingPathComponent("a.jpg"),
            logicalBytes: 100,
            allocatedBytes: 100,
            modifiedAt: .distantPast,
            pixelWidth: 4_000,
            pixelHeight: 3_000
        )
        let second = SimilarPhotoItem(
            url: root.appendingPathComponent("b.jpg"),
            logicalBytes: 80,
            allocatedBytes: 80,
            modifiedAt: .distantFuture,
            pixelWidth: 2_000,
            pixelHeight: 1_500
        )
        let group = SimilarPhotoGroup(
            id: first.id,
            photos: [first, second],
            keeperID: first.id,
            maximumDistance: 0.2
        )
        let service = SimilarPhotoService()

        service.toggleSelection(first, in: group)
        service.toggleSelection(second, in: group)

        XCTAssertEqual(service.selectedPhotoIDs.count, 1)
        XCTAssertTrue(service.selectedPhotoIDs.contains(first.id))
        XCTAssertTrue(service.selectionKeepsOnePhotoPerGroup)
    }

    func testSimilarPhotoSnapshotRejectsFileChangedAfterScan() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerSimilarSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("photo.jpg")
        try Data(repeating: 0x11, count: 20_000).write(to: url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let item = SimilarPhotoItem(
            url: url,
            logicalBytes: UInt64(try XCTUnwrap(values.fileSize)),
            allocatedBytes: UInt64(try XCTUnwrap(values.fileSize)),
            modifiedAt: try XCTUnwrap(values.contentModificationDate),
            pixelWidth: 100,
            pixelHeight: 100
        )
        XCTAssertTrue(SimilarPhotoService.snapshotMatches(item))

        try Data(repeating: 0x22, count: 21_000).write(to: url)
        XCTAssertFalse(SimilarPhotoService.snapshotMatches(item))
    }

    func testStartupOptimizerParsesMeasuredHighImpactAgent() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerStartupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let launchAgents = StartupOptimizerService.enabledRoot(home: home)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        let plist = launchAgents.appendingPathComponent("com.example.sync.plist")
        try writePlist([
            "Label": "com.example.sync",
            "ProgramArguments": ["/tmp/example-sync", "--background"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StartInterval": 300
        ], to: plist)
        let process = ProcessNode(
            id: 9_001,
            name: "example-sync",
            commandLine: "/tmp/example-sync --background",
            cpuUsage: 5,
            cpuTime: "0:10",
            memoryBytes: 100 * 1_048_576,
            parentPID: 1,
            isBackgroundAgent: true
        )

        let result = StartupOptimizerService.performScan(home: home, processes: [process])
        let item = try XCTUnwrap(result.items.first)

        XCTAssertTrue(item.canDisable)
        XCTAssertTrue(item.isRunning)
        XCTAssertEqual(item.currentMemoryBytes, 100 * 1_048_576)
        XCTAssertEqual(item.impact, .high)
        XCTAssertGreaterThanOrEqual(item.impactScore, 80)
        XCTAssertEqual(result.measuredMemoryBytes, item.currentMemoryBytes)
    }

    func testStartupOptimizerProtectsAppleAndMacCleanerLabels() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerStartupProtectedTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for label in ["com.apple.example", "com.maccleaner.app"] {
            let url = root.appendingPathComponent("\(UUID().uuidString).plist")
            try writePlist(["Label": label, "Program": "/tmp/example"], to: url)
            let item = try XCTUnwrap(StartupOptimizerService.parseItem(at: url, location: .enabled, processes: []))
            XCTAssertTrue(item.isProtected)
            XCTAssertFalse(item.canDisable)
        }
    }

    func testStartupOptimizerRejectsChangedOrSymlinkedPlist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerStartupSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("agent.plist")
        try writePlist(["Label": "com.example.agent", "Program": "/tmp/agent"], to: original)
        let item = try XCTUnwrap(StartupOptimizerService.parseItem(at: original, location: .enabled, processes: []))
        XCTAssertTrue(StartupOptimizerService.snapshotMatches(item))

        try writePlist(["Label": "com.example.changed", "Program": "/tmp/agent"], to: original)
        XCTAssertFalse(StartupOptimizerService.snapshotMatches(item))

        let symlink = root.appendingPathComponent("linked.plist")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
        XCTAssertNil(StartupOptimizerService.parseItem(at: symlink, location: .enabled, processes: []))
    }

    @MainActor
    func testStartupOptimizerNeverPreselectsAgents() {
        let service = StartupOptimizerService()
        XCTAssertTrue(service.selectedItemIDs.isEmpty)
    }

    func testStartupImpactScoreUsesMeasuredRuntimeSignals() {
        let dormant = StartupOptimizerService.impactScore(
            memoryBytes: 0,
            cpuPercent: 0,
            isRunning: false,
            runAtLoad: true,
            keepAlive: false,
            startInterval: nil
        )
        let active = StartupOptimizerService.impactScore(
            memoryBytes: 200 * 1_048_576,
            cpuPercent: 8,
            isRunning: true,
            runAtLoad: true,
            keepAlive: true,
            startInterval: 300
        )
        XCTAssertEqual(dormant, 10)
        XCTAssertGreaterThanOrEqual(active, 90)
    }

    @MainActor
    func testThumbnailCacheSeparatesRequestedPixelSizes() async throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iconURL = projectRoot
            .appendingPathComponent("MacCleaner/Assets.xcassets/AppIcon.appiconset/icon_512x512.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))

        ThumbnailCache.shared.removeAll()
        defer { ThumbnailCache.shared.removeAll() }
        let small = await DesktopThumbnailLoader.load(
            url: iconURL,
            maxPixelSize: 64,
            preferredSize: CGSize(width: 64, height: 64)
        )
        let large = await DesktopThumbnailLoader.load(
            url: iconURL,
            maxPixelSize: 256,
            preferredSize: CGSize(width: 256, height: 256)
        )

        XCTAssertEqual(try XCTUnwrap(small).size.width, 64)
        XCTAssertEqual(try XCTUnwrap(large).size.width, 256)
        XCTAssertEqual(ThumbnailCache.maximumCostBytes, 64 * 1024 * 1024)
    }

    func testRAMAdvisorNeverPreselectsApplications() {
        let source = RAMSource(
            name: "Editor",
            kind: .topProcess,
            bytes: 2 * 1_073_741_824,
            safety: .review,
            detail: "Review",
            pid: 42
        )
        XCTAssertFalse(source.isSelected)
    }

    func testRAMCleanerForbidsForceTermination() {
        XCTAssertFalse(RAMCleaner.allowsForceTermination)
        XCTAssertTrue(RAMCleaner.isProtectedApplicationName("Finder"))
        XCTAssertTrue(RAMCleaner.isProtectedApplicationName("MacCleaner"))
        XCTAssertFalse(RAMCleaner.isProtectedApplicationName("Example Editor"))
    }

    func testThoroughModesExpandScanCoverageWithoutChangingLowLoadDefaults() {
        XCTAssertGreaterThan(DiskCleanScanMode.thorough.maximumEntries, DiskCleanScanMode.efficient.maximumEntries)
        XCTAssertGreaterThan(JunkScanMode.thorough.maximumEntries, JunkScanMode.efficient.maximumEntries)
        XCTAssertGreaterThan(LargeFileScanMode.thorough.maximumEntries, LargeFileScanMode.efficient.maximumEntries)
        XCTAssertGreaterThan(CloudReclaimScanMode.thorough.maximumEntries, CloudReclaimScanMode.efficient.maximumEntries)
        XCTAssertEqual(JunkScanMode.efficient.maximumDuration, 8)
        XCTAssertEqual(LargeFileScanMode.efficient.maximumDuration, 12)
    }

    func testLargeFileScanFindsDeeplyNestedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerLargeFileTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("one/two/three/four/five", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = nested.appendingPathComponent("deep-large-file.bin")
        try Data(repeating: 0xA5, count: 11 * 1_048_576).write(to: file)

        let service = StorageAnalyzerService()
        let finished = expectation(description: "Large file scan finished")
        var sawScanStart = false
        var cancellable: AnyCancellable?
        cancellable = service.$isScanning.sink { isScanning in
            if isScanning { sawScanStart = true }
            if sawScanStart && !isScanning { finished.fulfill() }
        }

        service.scanLargeFiles(url: root)
        wait(for: [finished], timeout: 5)
        XCTAssertTrue(service.largeFiles.contains { $0.url.standardizedFileURL == file.standardizedFileURL })
        XCTAssertFalse(service.largeFileScanWasLimited)
        withExtendedLifetime(cancellable) {}
    }

    private func jpegData(from url: URL, compression: Double) throws -> Data {
        let image = try XCTUnwrap(NSImage(contentsOf: url))
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compression]
        ))
    }

    private func writePlist(_ dictionary: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }
}
