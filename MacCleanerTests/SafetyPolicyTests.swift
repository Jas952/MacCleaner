import AppKit
import Combine
import UniformTypeIdentifiers
import XCTest
@testable import MacCleaner

final class SafetyPolicyTests: XCTestCase {
    func testEveryVisibleAssistantPromptHasDeterministicRouting() {
        for prompt in AssistantPrompt.all {
            let result = AssistantModelBridge.deterministicDecision(for: prompt.text)
            if prompt.tool == "uninstall_app" {
                guard case .clarification = result else { return XCTFail("An application name must be requested") }
            } else {
                guard case .command(let call) = result else { return XCTFail("No route for \(prompt.text)") }
                XCTAssertEqual(call.name, prompt.tool, prompt.text)
            }
        }
    }
    func testAssistantLargeFileDefaultAndLessThanAreDistinct() {
        XCTAssertEqual(AssistantModelBridge.deterministicDecision(for: "Find large files"),
            .command(.init(name: "scan_large_files", arguments: ["minimum_size": "100 MB"])))
        guard case .clarification = AssistantModelBridge.deterministicDecision(for: "files under 1 GB") else {
            return XCTFail("Must not turn an upper bound into a lower bound")
        }
    }

    func testAssistantDiscoveryExcludesDependenciesAndSystemData() {
        let home = URL(fileURLWithPath: "/Users/test")
        for path in ["Documents/report.pdf", "Downloads/movie.mp4", "Docs/project/model.bin"] {
            XCTAssertTrue(AssistantFileScope.includes(home.appendingPathComponent(path), home: home), path)
        }
        for path in ["Library/Application Support/app/weights.bin", "Docs/project/vendor/tables.go", "Docs/project/venv/data", "go/pkg/mod/tables.go", "Documents/.git/config"] {
            XCTAssertFalse(AssistantFileScope.includes(home.appendingPathComponent(path), home: home), path)
        }
        XCTAssertTrue(AssistantFileScope.includes(home.appendingPathComponent("Library/Caches/app/blob"), home: home, allowCaches: true))
        XCTAssertFalse(AssistantFileScope.includes(home.appendingPathComponent("Library/Caches/app/blob"), home: home))
    }

    func testAssistantFolderSearchCanBeStoppedWithoutBlockingTheApp() {
        let started = Date()
        let result = AssistantCommandExecutor.runBoundedCommand(
            executable: "/bin/sleep",
            arguments: ["2"],
            timeout: 0.05
        )
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8)
    }

    func testAssistantFolderSearchPreservesPathsContainingSpaces() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleaner Search \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large sample.bin")
        try Data(repeating: 0xA5, count: 2_048).write(to: file)

        let result = AssistantCommandExecutor.runBoundedCommand(
            executable: "/usr/bin/find",
            arguments: [root.path, "-type", "f", "-size", "+1024c", "-print0"],
            timeout: 1
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(AssistantCommandExecutor.nullSeparatedStrings(in: result.data), [file.path])
    }

    func testAssistantOrganizationNeverOverwrites() throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let downloads = home.appendingPathComponent("Downloads")
        let destination = downloads.appendingPathComponent("Documents/report.txt")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let source = downloads.appendingPathComponent("report.txt")
        try Data("new".utf8).write(to: source)
        try Data("keep".utf8).write(to: destination)
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let result = AssistantCommandExecutor.applyOrganization([
            .init(source: source, destination: destination, size: values.fileSize!, modified: values.contentModificationDate!)
        ], home: home)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testAssistantOrganizationMovesOnlyConfirmedSnapshot() throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let source = root.appendingPathComponent("example.txt")
        let destination = root.appendingPathComponent("Documents/example.txt")
        try Data("sample".utf8).write(to: source)
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let plan = AssistantMoveItem(source: source, destination: destination, size: values.fileSize!, modified: values.contentModificationDate!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Preview cannot move anything")
        XCTAssertTrue(AssistantCommandExecutor.applyOrganization([plan], home: home).succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("sample".utf8))
        XCTAssertFalse(AssistantCommandExecutor.applyOrganization([plan], home: home).succeeded, "Stale plans must not be replayed")
    }

    func testAssistantModelBridgeRoutesRussianLargeFilePhrase() {
        let routed = expectation(description: "The bundled local router returns a large-file command")
        AssistantModelBridge.propose(to: "найди файлы тяжелее 5 гб") { decision in
            XCTAssertEqual(
                decision,
                .command(AssistantToolCall(name: "scan_large_files", arguments: ["minimum_size": "5 GB"]))
            )
            routed.fulfill()
        }
        wait(for: [routed], timeout: 10)
    }

    func testAssistantModelBridgeDoesNotClaimExecution() {
        let text = AssistantModelBridge.displayText(["ok": true, "tool_call": ["name": "uninstall_app", "arguments": ["app_name": "Spotify"]]])
        XCTAssertTrue(text.contains("Spotify"))
        XCTAssertTrue(text.contains("calculate what would be removed"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("executed"))
        let failure = AssistantModelBridge.displayText(["ok": false])
        XCTAssertTrue(failure.contains("No action was performed"))
        let rejected = AssistantModelBridge.displayText(["reason": "out_of_scope_guard", "response": ["text": "Outside scope"]])
        XCTAssertEqual(rejected, "Outside scope")
    }

    func testAssistantModelBridgeRejectsUnknownToolsAndMissingRequiredArguments() {
        let unknown = AssistantModelBridge.decision(from: [
            "ok": true,
            "tool_call": ["name": "invented_tool", "arguments": [:]]
        ])
        XCTAssertEqual(unknown, .failed("The model proposed an unsupported action. Nothing was performed."))

        let missingTarget = AssistantModelBridge.decision(from: [
            "ok": true,
            "tool_call": ["name": "uninstall_app", "arguments": [:]]
        ])
        XCTAssertEqual(missingTarget, .clarification("Which application should I prepare for removal?"))

        let valid = AssistantModelBridge.decision(from: [
            "ok": true,
            "tool_call": ["name": "uninstall_app", "arguments": ["app_name": "Spotify"]]
        ])
        XCTAssertEqual(valid, .command(AssistantToolCall(name: "uninstall_app", arguments: ["app_name": "Spotify"])))
    }

    func testAssistantConfirmationExecutesOnlyAfterYes() {
        let model = AssistantChatViewModel()
        let call = AssistantToolCall(name: "check_battery_health", arguments: [:])
        var executions = 0
        let executionFinished = expectation(description: "Assistant execution updates its live card")
        model.executeCommand = { received, completion in
            XCTAssertEqual(received, call)
            executions += 1
            completion(AssistantExecutionResult(text: "Done"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { executionFinished.fulfill() }
        }
        model.prepareForConfirmation(call, query: "Check battery health")

        XCTAssertEqual(executions, 0)
        model.confirmPendingCommand()
        XCTAssertEqual(executions, 1)
        wait(for: [executionFinished], timeout: 4)
        XCTAssertNil(model.pendingCommand)
        XCTAssertEqual(model.messages.last?.previewTool, "check_battery_health")
        XCTAssertEqual(model.messages.last?.previewPhase, .result)
        XCTAssertFalse(model.messages.last?.isProcessing ?? true)
    }

    func testAssistantConfirmationIsLimitedToStateChangingCommands() {
        XCTAssertFalse(AssistantToolCall(name: "check_battery_health", arguments: [:]).requiresConfirmation)
        XCTAssertFalse(AssistantToolCall(name: "list_processes", arguments: [:]).requiresConfirmation)
        XCTAssertFalse(AssistantToolCall(name: "scan_large_files", arguments: ["minimum_size": "1 GB"]).requiresConfirmation)
        XCTAssertFalse(AssistantToolCall(name: "uninstall_app", arguments: ["app_name": "Spotify"]).requiresConfirmation)

        XCTAssertTrue(AssistantToolCall(name: "move_items_to_trash", arguments: ["items": "selected"]).requiresConfirmation)
        XCTAssertTrue(AssistantToolCall(name: "clean_selected_items", arguments: ["items": "selected"]).requiresConfirmation)
        XCTAssertTrue(AssistantToolCall(name: "flush_dns", arguments: [:]).requiresConfirmation)
    }

    func testAssistantUsesReadableTemperatureLabelsAndAssessments() {
        XCTAssertEqual(AssistantCommandExecutor.readableSensorName("CPU Die Sensor 10"), "Processor sensor 10")
        XCTAssertEqual(AssistantCommandExecutor.readableSensorName("SoC Sensor PMU tcal"), "Apple silicon")
        XCTAssertEqual(AssistantCommandExecutor.readableSensorName("gas gauge battery"), "Battery")
        XCTAssertEqual(AssistantCommandExecutor.temperatureAssessment(52), "Normal temperature")
        XCTAssertEqual(AssistantCommandExecutor.temperatureAssessment(78), "Warm — keep an eye on it")
        XCTAssertEqual(AssistantCommandExecutor.temperatureAssessment(94), "Very hot — reduce the load")
    }

    func testLongRunningCommandStaysVisibleAsContinuing() {
        let model = AssistantChatViewModel()
        let finished = expectation(description: "Long-running result is reflected in the card")
        model.executeCommand = { _, completion in
            completion(AssistantExecutionResult(
                text: "The scan is still running.",
                actionTitle: "Open Current Scan…",
                destination: "storage-large",
                stillRunning: true
            ))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { finished.fulfill() }
        }
        model.prepareForConfirmation(
            AssistantToolCall(name: "scan_large_files", arguments: ["minimum_size": "1 GB"]),
            query: "Find files larger than 1 GB"
        )

        model.confirmPendingCommand()
        wait(for: [finished], timeout: 4)

        XCTAssertEqual(model.messages.last?.previewPhase, .deferred)
        XCTAssertEqual(model.messages.last?.resultDestination, "storage-large")
    }

    func testAssistantConfirmationNoDoesNotExecute() {
        let model = AssistantChatViewModel()
        var executions = 0
        model.executeCommand = { _, _ in executions += 1 }
        model.prepareForConfirmation(AssistantToolCall(name: "flush_dns", arguments: [:]), query: "Clear DNS")

        model.declinePendingCommand()

        XCTAssertEqual(executions, 0)
        XCTAssertNil(model.pendingCommand)
        XCTAssertTrue(model.messages.last?.text.contains("not executed") == true)
    }

    func testAssistantConfirmationRequestErrorDoesNotExecute() {
        let model = AssistantChatViewModel()
        var executions = 0
        model.executeCommand = { _, _ in executions += 1 }
        model.prepareForConfirmation(AssistantToolCall(name: "list_processes", arguments: [:]), query: "Check battery")

        model.reportPendingCommandError()

        XCTAssertEqual(executions, 0)
        XCTAssertNil(model.pendingCommand)
        XCTAssertTrue(model.messages.last?.text.contains("incorrect interpretation") == true)
    }

    func testAssistantPendingConfirmationCannotBeReplacedByAnotherSubmission() {
        let model = AssistantChatViewModel()
        let original = AssistantToolCall(name: "check_battery_health", arguments: [:])
        model.prepareForConfirmation(original, query: "Check battery health")
        let messageCount = model.messages.count
        model.draft = "Check temperature"

        model.submit()

        XCTAssertEqual(model.pendingCommand?.call, original)
        XCTAssertEqual(model.messages.count, messageCount)
        XCTAssertEqual(model.draft, "Check temperature")
    }

    func testAssistantNaturalPrefixAndCompletion() {
        let apps = assistantTestApplications()
        XCTAssertEqual(AssistantSuggestionEngine.matchingApplications(for: "я хочу удалить приложение sp", in: apps).map(\.name), ["Spotify"])
        XCTAssertEqual(AssistantSuggestionEngine.completedDraft(from: "я хочу удалить приложение sp", applicationName: "Spotify"), "я хочу удалить приложение Spotify")
        XCTAssertEqual(AssistantSuggestionEngine.matchingApplications(for: "я хочу удалить", in: apps).count, 4)
        XCTAssertTrue(AssistantSuggestionEngine.matchingApplications(for: "расскажи про Spotify", in: apps).isEmpty)
    }

    func testAssistantCommandContinuationAndDismissal() {
        XCTAssertTrue(AssistantPrompt.completions(for: "").isEmpty)
        XCTAssertEqual(AssistantPrompt.completions(for: "organize").map(\.text), ["Organize Downloads", "Organize Desktop"])
        XCTAssertTrue(AssistantPrompt.completions(for: "Check").contains { $0.tool == "check_battery_health" })
        let model = AssistantChatViewModel()
        model.draft = "Check"
        XCTAssertTrue(model.hasSuggestions)
        model.dismissSuggestions()
        XCTAssertFalse(model.hasSuggestions)
        model.draft = "Check b"
        model.acceptSelectedSuggestion()
        XCTAssertEqual(model.draft, "Check battery health")
        XCTAssertFalse(model.hasSuggestions)
    }

    func testAssistantPreviewCatalogHasUniqueCommands() {
        XCTAssertEqual(AssistantToolPresentation.all.count, 39)
        XCTAssertEqual(Set(AssistantToolPresentation.all.map(\.id)).count, 39)
        let model = AssistantChatViewModel()
        model.addPreview(tool: AssistantToolPresentation.all[0], phase: .failed)
        XCTAssertEqual(model.messages.last?.previewPhase, .failed)
        XCTAssertEqual(model.messages.last?.previewTool, "request_clarification")
    }

    func testAssistantSuggestionsRequireSupportedCommand() {
        let applications = assistantTestApplications()
        XCTAssertTrue(AssistantSuggestionEngine.matchingApplications(for: "spotify", in: applications).isEmpty)
        XCTAssertEqual(
            AssistantSuggestionEngine.matchingApplications(for: "удали", in: applications).map(\.name),
            ["DisplayLink Manager", "Notion", "Spotify", "Telegram"]
        )
    }

    func testAssistantSuggestionsPreferApplicationNamePrefix() {
        let applications = assistantTestApplications()
        XCTAssertEqual(
            AssistantSuggestionEngine.matchingApplications(for: "удали sp", in: applications).map(\.name),
            ["Spotify"]
        )
        XCTAssertEqual(
            AssistantSuggestionEngine.matchingApplications(for: "uninstall tel", in: applications).map(\.name),
            ["Telegram"]
        )
    }

    func testAssistantTabCompletionPreservesCommand() {
        XCTAssertEqual(
            AssistantSuggestionEngine.completedDraft(from: "очисти spot", applicationName: "Spotify"),
            "очисти Spotify"
        )
    }

    func testAssistantProcessRowsExposeOnlySafeQuitActions() {
        let protected = ProcessNode(
            id: 44,
            name: "WindowServer",
            commandLine: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer",
            cpuUsage: 20,
            cpuTime: "00:10",
            memoryBytes: 80_000_000,
            parentPID: 1,
            isBackgroundAgent: true
        )
        let application = ProcessNode(
            id: 1234,
            name: "Spotify",
            commandLine: "/Applications/Spotify.app/Contents/MacOS/Spotify",
            cpuUsage: 4,
            cpuTime: "00:01",
            memoryBytes: 240_000_000,
            parentPID: 1,
            isBackgroundAgent: false
        )

        let protectedRow = AssistantCommandExecutor.processRow(protected)
        let applicationRow = AssistantCommandExecutor.processRow(application)

        XCTAssertNil(protectedRow.action)
        XCTAssertEqual(protectedRow.fallbackIcon, "lock.shield")
        XCTAssertEqual(applicationRow.iconPath, "/Applications/Spotify.app")
        XCTAssertEqual(
            applicationRow.action,
            .quitProcess(pid: 1234, name: "Spotify", instanceCount: 1)
        )
    }

    func testAssistantProcessRowsGroupApplicationInstancesIntoOneQuitAction() throws {
        let first = ProcessNode(
            id: 1234,
            name: "Spotify",
            commandLine: "/Applications/Spotify.app/Contents/MacOS/Spotify",
            cpuUsage: 4,
            cpuTime: "00:01",
            memoryBytes: 240_000_000,
            parentPID: 1,
            isBackgroundAgent: false
        )
        let helper = ProcessNode(
            id: 1235,
            name: "Spotify",
            commandLine: "/Applications/Spotify.app/Contents/MacOS/Spotify --type=helper",
            cpuUsage: 2,
            cpuTime: "00:01",
            memoryBytes: 120_000_000,
            parentPID: 1234,
            isBackgroundAgent: false
        )

        let group = try XCTUnwrap(AssistantCommandExecutor.rankedProcessGroups([first, helper]).first)
        let row = AssistantCommandExecutor.processRow(group)

        XCTAssertEqual(group.instanceCount, 2)
        XCTAssertTrue(row.detail.contains("2 processes"))
        XCTAssertEqual(
            row.action,
            .quitProcess(pid: 1234, name: "Spotify", instanceCount: 2)
        )
    }

    private func assistantTestApplications() -> [AssistantApplication] {
        ["Telegram", "Spotify", "Notion", "DisplayLink Manager"].map { name in
            AssistantApplication(
                id: name,
                name: name,
                bundleIdentifier: "test.\(name.lowercased())",
                url: URL(fileURLWithPath: "/Applications/\(name).app"),
                icon: NSImage(size: NSSize(width: 16, height: 16))
            )
        }
    }

    func testThermalSurfaceDoesNotFabricateMissingSensors() {
        var thermal = ThermalInfo()
        thermal.cpuTemp = 80
        thermal.gpuTemp = 80
        let empty = MacBookThermalField(thermal: thermal, fans: [], modelIdentifier: "Mac15,6")
        XCTAssertTrue(empty.zones.isEmpty, "Summary values are not independent sensor readings")
        thermal.sensors = [SensorReading.hid(name: "tdie1", temperature: 80)]
        let field = MacBookThermalField(thermal: thermal, fans: [], modelIdentifier: "Mac15,6")
        XCTAssertEqual(field.zones.count, 1)
        XCTAssertTrue(field.readings(for: "battery-pack").isEmpty)
        XCTAssertTrue(field.readings(for: "fan-left").isEmpty)
        XCTAssertEqual(field.zones.first?.reading.sourceID, "tdie1")
        XCTAssertFalse(field.hasFanTelemetry)
    }

    func testHIDChannelsKeepIdentityWithoutInventedGPUOrAirflow() {
        let first = SensorReading.hid(name: "tdev7", temperature: 45)
        let second = SensorReading.hid(name: "tdev7", temperature: 46)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.category, .soc)
        XCTAssertEqual(first.sourceID, "tdev7")
        XCTAssertEqual(first.source, "HID")
        XCTAssertFalse(first.name.contains("GPU"))
        XCTAssertFalse(first.name.contains("Airflow"))
        XCTAssertEqual(SensorReading.hid(name: "left unknown", temperature: 40).category, .other)
    }

    func testThermalSpatialInterpolationPreservesAnchorsAndMeasuredBounds() {
        var thermal = ThermalInfo()
        thermal.sensors = [SensorReading.hid(name: "tdie1", temperature: 80),
                           SensorReading.hid(name: "gas gauge", temperature: 35)]
        let field = MacBookThermalField(thermal: thermal, fans: [], modelIdentifier: "Mac15,6")
        for zone in field.zones {
            XCTAssertEqual(field.temperature(x: zone.center.x, y: zone.center.y), zone.reading.value, accuracy: 0.0001)
        }
        for row in 0...20 {
            for column in 0...20 {
                let value = field.temperature(x: Double(column) / 20, y: Double(row) / 20)
                XCTAssertTrue(value.isFinite && value >= 35 && value <= 80)
            }
        }
        let nearCPU = field.temperature(x: 0.40, y: 0.18)
        let farCPU = field.temperature(x: 0.10, y: 0.18)
        XCTAssertGreaterThan(nearCPU, farCPU)
    }

    func testThermalAnimationDoesNotChangeLiveHoverReadingsOrLayout() {
        var initial = ThermalInfo()
        initial.sensors = [SensorReading.hid(name: "tdie1", temperature: 50)]
        let first = MacBookThermalField(thermal: initial, fans: [], modelIdentifier: "Mac15,6")
        initial.sensors = [SensorReading.hid(name: "tdie1", temperature: 80),
                           SensorReading.hid(name: "tdie2", temperature: 60)]
        let next = MacBookThermalField(thermal: initial, fans: [], modelIdentifier: "Mac15,6")
        let midway = first.interpolated(to: next, progress: 0.5)
        let zone = midway.zones.first { $0.reading.sourceID == "tdie1" }!
        XCTAssertEqual(zone.temperature, 65)
        XCTAssertEqual(zone.reading.value, 80)
        XCTAssertEqual(zone.center, first.zones[0].center)
        XCTAssertEqual(first.components.map(\.frame), next.components.map(\.frame))
        XCTAssertEqual(first.components.map(\.id), next.components.map(\.id))
    }

    func testThermalInvalidAndDuplicateReadingsAreExcluded() {
        var thermal = ThermalInfo()
        thermal.sensors = [SensorReading.hid(name: "tdie1", temperature: 50),
                           SensorReading.hid(name: "tdie1", temperature: 51),
                           SensorReading.hid(name: "tdie2", temperature: .nan),
                           SensorReading.hid(name: "tdie3", temperature: .infinity),
                           SensorReading.hid(name: "tdie4", temperature: 0)]
        let field = MacBookThermalField(thermal: thermal, fans: [], modelIdentifier: "Mac15,6")
        XCTAssertEqual(field.activeSensorCount, 1)
        XCTAssertEqual(field.zones.count, 1)
        XCTAssertEqual(field.zones[0].temperature, 50)
    }

    func testThermalAxisDoesNotClipMeasuredHighTemperatures() {
        var thermal = ThermalInfo()
        thermal.sensors = [SensorReading.hid(name: "tdie1", temperature: 108)]
        let field = MacBookThermalField(thermal: thermal, fans: [], modelIdentifier: "Mac15,6")
        XCTAssertEqual(field.temperatureCeiling, 110)
        XCTAssertGreaterThan(field.height(for: 108), field.height(for: 95))
        XCTAssertLessThan(field.height(for: 108), 1)
    }

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
        XCTAssertTrue(SafeDeletionService.isApplicationOwnedPath(
            home.appendingPathComponent(
                "Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/archive/Mac/mod/example.archive"
            ),
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

    func testProcessHistoryMergesDuplicateIdentitiesInsteadOfCrashingChart() {
        let first = ProcessGraphPoint(
            id: "Cyberpunk2077|/Applications/Cyberpunk2077.app",
            pid: 101,
            name: "Cyberpunk2077",
            executablePath: "/Applications/Cyberpunk2077.app",
            cpu: 82.5,
            memoryBytes: 700_000_000,
            instanceCount: 1
        )
        let duplicate = ProcessGraphPoint(
            id: first.id,
            pid: 202,
            name: first.name,
            executablePath: first.executablePath,
            cpu: 117.5,
            memoryBytes: 500_000_000,
            instanceCount: 1
        )

        let indexed = ProcessGraphSample.indexedProcesses([first, duplicate])

        XCTAssertEqual(indexed.count, 1)
        XCTAssertEqual(indexed[first.id]?.cpu ?? -1, 200, accuracy: 0.001)
        XCTAssertEqual(indexed[first.id]?.memoryBytes, 1_200_000_000)
        XCTAssertEqual(indexed[first.id]?.instanceCount, 2)
    }

    func testProcessGraphMetricsUseWholeMacCapacity() {
        let processorCount = Double(max(1, Foundation.ProcessInfo.processInfo.processorCount))
        let process = ProcessGraphPoint(
            id: "load|/Applications/Load.app",
            pid: 303,
            name: "Load",
            executablePath: "/Applications/Load.app",
            cpu: processorCount * 25,
            memoryBytes: 2 * 1_073_741_824,
            instanceCount: 1
        )

        XCTAssertEqual(ProcessGraphMetric.cpu.value(for: process), 25, accuracy: 0.001)
        XCTAssertEqual(ProcessGraphMetric.memory.value(for: process), 2, accuracy: 0.001)
        XCTAssertEqual(
            ProcessGraphMetric.memory.systemCapacity,
            Double(Foundation.ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
            accuracy: 0.001
        )
        XCTAssertTrue(ProcessGraphMetric.cpu.isMinor(0.5))
        XCTAssertFalse(ProcessGraphMetric.cpu.isMinor(1.5))
    }

    func testProcessGraphLogScaleExpandsSmallLoadsAndRemainsReversible() {
        let linear = ProcessGraphScaleMode.linear.normalized(1, upperBound: 100, softening: 0.25)
        let logarithmic = ProcessGraphScaleMode.logarithmic.normalized(1, upperBound: 100, softening: 0.25)
        let restored = ProcessGraphScaleMode.logarithmic.value(
            atNormalizedPosition: logarithmic,
            upperBound: 100,
            softening: 0.25
        )

        XCTAssertGreaterThan(logarithmic, linear)
        XCTAssertEqual(restored, 1, accuracy: 0.001)
    }

    func testFourHourProcessGraphBucketsSamplesWithoutArtificialZeroDrops() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let samples = (0..<240).map { index in
            let cpu = index.isMultiple(of: 7) ? 220.0 : 55.0
            let process = ProcessGraphPoint(
                id: "game|/Applications/Game.app",
                pid: 404,
                name: "Game",
                executablePath: "/Applications/Game.app",
                cpu: cpu,
                memoryBytes: 2 * 1_073_741_824,
                instanceCount: 1
            )
            return ProcessGraphSample(
                date: now.addingTimeInterval(-ProcessGraphInterval.fourHours.duration + Double(index * 60)),
                processes: [process]
            )
        }

        let chart = ProcessHistoryChartData(
            samples: samples,
            metric: .cpu,
            interval: .fourHours,
            hidesMinorProcesses: false,
            now: now
        )
        let process = try XCTUnwrap(chart.series.first)
        let points = chart.segmentsByProcessID[process.id, default: []].flatMap { $0 }

        XCTAssertFalse(points.isEmpty)
        XCTAssertLessThanOrEqual(points.count, 72)
        XCTAssertTrue(points.allSatisfy { $0.value > 0 })
    }

    func testShortProcessHistoryGapCreatesAnExplicitBridge() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let offsets: [TimeInterval] = [-600, -580, -560, -240, -220, -200]
        let samples = offsets.map { offset in
            ProcessGraphSample(
                date: now.addingTimeInterval(offset),
                processes: [
                    ProcessGraphPoint(
                        id: "browser|/Applications/Browser.app",
                        pid: 505,
                        name: "Browser",
                        executablePath: "/Applications/Browser.app",
                        cpu: 55,
                        memoryBytes: 1_073_741_824,
                        instanceCount: 1
                    )
                ]
            )
        }

        let chart = ProcessHistoryChartData(
            samples: samples,
            metric: .cpu,
            interval: .thirtyMinutes,
            hidesMinorProcesses: false,
            now: now
        )
        let process = try XCTUnwrap(chart.series.first)

        XCTAssertEqual(chart.segmentsByProcessID[process.id]?.count, 2)
        XCTAssertEqual(chart.bridgesByProcessID[process.id]?.count, 1)
    }

    func testElevenMinuteCollectorOutageCreatesAnExplicitBridge() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let offsets: [TimeInterval] = [-1_000, -980, -960, -300, -280, -260]
        let samples = offsets.map { offset in
            ProcessGraphSample(
                date: now.addingTimeInterval(offset),
                processes: [
                    ProcessGraphPoint(
                        id: "browser|/Applications/Browser.app",
                        pid: 505,
                        name: "Browser",
                        executablePath: "/Applications/Browser.app",
                        cpu: 55,
                        memoryBytes: 1_073_741_824,
                        instanceCount: 1
                    )
                ]
            )
        }

        let chart = ProcessHistoryChartData(
            samples: samples,
            metric: .cpu,
            interval: .thirtyMinutes,
            hidesMinorProcesses: false,
            now: now
        )
        let process = try XCTUnwrap(chart.series.first)

        XCTAssertEqual(chart.segmentsByProcessID[process.id]?.count, 2)
        XCTAssertEqual(chart.bridgesByProcessID[process.id]?.count, 1)
    }

    func testProcessAbsenceDuringHealthyCollectionRemainsABreak() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tracked = ProcessGraphPoint(
            id: "browser|/Applications/Browser.app",
            pid: 505,
            name: "Browser",
            executablePath: "/Applications/Browser.app",
            cpu: 55,
            memoryBytes: 1_073_741_824,
            instanceCount: 1
        )
        let other = ProcessGraphPoint(
            id: "helper|/usr/bin/helper",
            pid: 506,
            name: "Helper",
            executablePath: "/usr/bin/helper",
            cpu: 3,
            memoryBytes: 20_000_000,
            instanceCount: 1
        )
        let offsets = [-1_000, -980, -960, -760, -560, -360, -300, -280, -260]
        let samples = offsets.map { offset in
            ProcessGraphSample(
                date: now.addingTimeInterval(TimeInterval(offset)),
                processes: offset > -900 && offset < -320 ? [other] : [tracked, other]
            )
        }

        let chart = ProcessHistoryChartData(
            samples: samples,
            metric: .cpu,
            interval: .thirtyMinutes,
            hidesMinorProcesses: false,
            now: now
        )
        let process = try XCTUnwrap(chart.series.first(where: { $0.id == tracked.id }))

        XCTAssertEqual(chart.segmentsByProcessID[process.id]?.count, 2)
        XCTAssertTrue(chart.bridgesByProcessID[process.id, default: []].isEmpty)
    }

    func testLatestProcessAppearsBeforeStabilityThreshold() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var samples = (1...10).map { index in
            ProcessGraphSample(
                date: now.addingTimeInterval(Double(-index * 60)),
                processes: [
                    ProcessGraphPoint(
                        id: "older|/Applications/Older.app",
                        pid: 606,
                        name: "Older",
                        executablePath: "/Applications/Older.app",
                        cpu: 44,
                        memoryBytes: 900_000_000,
                        instanceCount: 1
                    )
                ]
            )
        }
        samples.append(
            ProcessGraphSample(
                date: now,
                processes: [
                    ProcessGraphPoint(
                        id: "current|/Applications/Current.app",
                        pid: 607,
                        name: "Current",
                        executablePath: "/Applications/Current.app",
                        cpu: 110,
                        memoryBytes: 2 * 1_073_741_824,
                        instanceCount: 1
                    )
                ]
            )
        )

        let chart = ProcessHistoryChartData(
            samples: samples,
            metric: .cpu,
            interval: .thirtyMinutes,
            hidesMinorProcesses: true,
            now: now
        )
        let current = try XCTUnwrap(chart.series.first(where: { $0.name == "Current" }))

        XCTAssertEqual(chart.segmentsByProcessID[current.id]?.flatMap { $0 }.count, 1)
    }

    func testMac156PowerControllerOrderMatchesVerifiedPortLayout() {
        XCTAssertEqual(MacBookPowerPort.resolved(modelIdentifier: "Mac15,6", controllerIndex: 0), .leftUSBCTop)
        XCTAssertEqual(MacBookPowerPort.resolved(modelIdentifier: "Mac15,6", controllerIndex: 1), .leftUSBCBottom)
        XCTAssertEqual(MacBookPowerPort.resolved(modelIdentifier: "Mac15,6", controllerIndex: 2), .magSafe)
        XCTAssertEqual(MacBookPowerPort.resolved(modelIdentifier: "Mac15,6", controllerIndex: 3), .rightUSBC)
    }

    func testAppleSiliconFanRPMDecodesLittleEndianFloat() {
        let expected = Float(4_766)
        let bits = expected.bitPattern
        let bytes = [
            UInt8(bits & 0xff),
            UInt8((bits >> 8) & 0xff),
            UInt8((bits >> 16) & 0xff),
            UInt8((bits >> 24) & 0xff)
        ]

        XCTAssertEqual(SMCNumericDecoder.decode(dataType: "flt ", bytes: bytes), expected, accuracy: 0.1)
        XCTAssertEqual(SMCService.protocolDataStride, 80)
    }

    func testIntelFanRPMStillDecodesFPE2() {
        let expected = 2_317
        let raw = UInt16(expected * 4)
        let bytes = [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]

        XCTAssertEqual(SMCNumericDecoder.decode(dataType: "fpe2", bytes: bytes), Float(expected), accuracy: 0.1)
    }

    func testUnknownMacNeverClaimsPhysicalPowerPortFromControllerIndex() {
        XCTAssertEqual(MacBookPowerPort.resolved(modelIdentifier: "Mac99,1", controllerIndex: 2), .usbCUnknown)
        XCTAssertEqual(MacBookPowerPort.resolved(modelIdentifier: "Mac15,6", controllerIndex: 99), .usbCUnknown)
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
        state.optimizationScannedRoots = [.browser]

        state.resetForNavigation()

        XCTAssertFalse(state.hasScan)
        XCTAssertFalse(state.showResult)
        XCTAssertEqual(state.scanProgress, 0)
        XCTAssertNil(state.resultFreed)
        if case .idle = state.dnsFlow {} else { XCTFail("DNS flow was not reset") }
        if case .ready = state.optimizationPhase {} else { XCTFail("Optimization phase was not reset") }
        XCTAssertTrue(state.optimizationLogs.isEmpty)
        XCTAssertEqual(state.optimizationFoundDisk, 0)
        XCTAssertEqual(state.optimizationScannedRoots, [.browser])
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

    @MainActor
    func testMediaCompressorNeverKeepsALargerCandidate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerCompressorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("sample.png")
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 32, height: 32)).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: source, options: .atomic)

        let result = try MediaCompressorService.compressFile(source, quality: 0.72, removeMetadata: true)
        if let output = result.output {
            XCTAssertLessThan(result.candidateBytes, result.originalBytes)
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(output.lastPathComponent.contains("-compressed"))
        } else {
            XCTAssertGreaterThanOrEqual(result.candidateBytes, result.originalBytes)
            XCTAssertEqual(result.savedBytes, 0)
        }
    }

    func testBetaUtilitiesStayOutOfTheToolsWorkspace() {
        let betaTools: Set<UtilityToolID> = [.fileReader, .mediaCompressor, .audioMixer, .chargeLimit]
        let gatedBetaTools = betaTools.subtracting([.fileReader])

        XCTAssertEqual(Set(UtilityToolID.configurableCases.filter(\.isBeta)), betaTools)
        XCTAssertTrue(gatedBetaTools.isDisjoint(with: Set(UtilityToolID.availableCases)))
        XCTAssertTrue(UtilityToolID.availableCases.contains(.fileReader))
        XCTAssertTrue(UtilityToolID.availableCases.allSatisfy(\.isAvailableInTools))
    }

    func testEveryMenuBarGaugeHasTwoCompactValueFormats() {
        for gauge in MenuBarGauge.allCases {
            XCTAssertEqual(gauge.valueFormats.count, 2)
            XCTAssertTrue(gauge.valueFormats.allSatisfy { $0.compactTitle.count == 1 })
        }
    }

    func testMenuBarOffersBatteryAndDirectValueDisplayStyles() {
        XCTAssertEqual(MenuBarGaugeDisplayStyle.allCases, [.battery, .value])
        XCTAssertEqual(MenuBarGaugeDisplayStyle.battery.title, "Battery")
        XCTAssertEqual(MenuBarGaugeDisplayStyle.value.title, "Values")
    }

    func testMenuBarDisplayStyleMigratesAndPersistsPerGauge() throws {
        let suiteName = "MacCleanerMenuBarStyleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MenuBarGaugeDisplayStyle.value.rawValue, forKey: "menuBarGaugeDisplayStyle")

        let first = SettingsManager(defaults: defaults)
        XCTAssertTrue(MenuBarGauge.allCases.allSatisfy { first.displayStyle(for: $0) == .value })

        first.setDisplayStyle(.battery, for: .cpu)

        let reloaded = SettingsManager(defaults: defaults)
        XCTAssertEqual(reloaded.displayStyle(for: .cpu), .battery)
        XCTAssertEqual(reloaded.displayStyle(for: .ram), .value)
        XCTAssertEqual(reloaded.displayStyle(for: .gpu), .value)
    }

    func testMenuBarGaugeDragOrderPersists() throws {
        let suiteName = "MacCleanerMenuBarOrderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        settings.setGaugeEnabled(true, gauge: .gpu)
        XCTAssertEqual(settings.menuBarGaugeIDs, ["cpu", "ram", "gpu"])

        settings.moveGauge("cpu", to: "gpu")
        XCTAssertEqual(settings.menuBarGaugeIDs, ["ram", "gpu", "cpu"])

        let reloaded = SettingsManager(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarGaugeIDs, ["ram", "gpu", "cpu"])
    }

    func testMenuBarDashboardCardsCanBeReorderedRemovedAndRestored() throws {
        let suiteName = "MacCleanerMenuBarDashboardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        XCTAssertEqual(
            settings.menuBarDashboardModuleIDs,
            MenuBarDashboardModule.allCases.map(\.rawValue)
        )

        settings.moveMenuBarDashboardModule("cpu", to: "disk")
        settings.removeMenuBarDashboardModule(.network)
        XCTAssertEqual(settings.menuBarDashboardModuleIDs, ["memory", "disk", "cpu", "graphics", "battery"])

        settings.restoreMenuBarDashboardModule(.network)
        let reloaded = SettingsManager(defaults: defaults)
        XCTAssertEqual(reloaded.menuBarDashboardModuleIDs, ["memory", "disk", "cpu", "graphics", "battery", "network"])
    }

    func testMenuBarDashboardDirectDragOrderPersistsAndRejectsInvalidSets() throws {
        let suiteName = "MacCleanerMenuBarDirectDragTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        let order: [MenuBarDashboardModule] = [.battery, .cpu, .memory, .disk, .network, .graphics]
        settings.setMenuBarDashboardModuleOrder(order)
        XCTAssertEqual(settings.menuBarDashboardModuleIDs, order.map(\.rawValue))

        settings.setMenuBarDashboardModuleOrder([.cpu, .memory])
        XCTAssertEqual(settings.menuBarDashboardModuleIDs, order.map(\.rawValue))
        XCTAssertEqual(SettingsManager(defaults: defaults).menuBarDashboardModuleIDs, order.map(\.rawValue))
    }

    @MainActor
    func testPasteboardPayloadPreservesEveryRepresentation() throws {
        let source = NSPasteboard(name: NSPasteboard.Name("MacCleanerTests.source.\(UUID().uuidString)"))
        let destination = NSPasteboard(name: NSPasteboard.Name("MacCleanerTests.destination.\(UUID().uuidString)"))
        let item = NSPasteboardItem()
        let plainText = "Styled clipboard text"
        let rtf = Data("{\\rtf1\\ansi Styled clipboard text}".utf8)
        let html = Data("<strong>Styled clipboard text</strong>".utf8)
        let fileURL = URL(fileURLWithPath: "/tmp/MacCleaner Clipboard Test.txt").absoluteString

        XCTAssertTrue(item.setString(plainText, forType: .string))
        XCTAssertTrue(item.setData(rtf, forType: .rtf))
        XCTAssertTrue(item.setData(html, forType: .html))
        XCTAssertTrue(item.setString(fileURL, forType: .fileURL))
        source.clearContents()
        XCTAssertTrue(source.writeObjects([item]))

        let payload = PasteboardPayload(pasteboard: source)
        XCTAssertTrue(payload.write(to: destination))
        XCTAssertEqual(destination.string(forType: .string), plainText)
        XCTAssertEqual(destination.data(forType: .rtf), rtf)
        XCTAssertEqual(destination.data(forType: .html), html)
        XCTAssertEqual(destination.string(forType: .fileURL), fileURL)

        let providers = payload.makeItemProviders()
        XCTAssertEqual(providers.count, 1)
        XCTAssertTrue(Set(item.types.map(\.rawValue))
            .isSubset(of: Set(try XCTUnwrap(providers.first).registeredTypeIdentifiers)))
    }

    func testDeveloperOwnerCatalogSeparatesToolOwnersAndProtectsModels() {
        let home = URL(fileURLWithPath: "/Users/test")
        let owners = StorageAnalyzerService.developerOwnerRoots(home: home)
        let ids = Set(owners.map(\.id))
        XCTAssertTrue(ids.contains("swiftpm"))
        XCTAssertTrue(ids.contains("cocoapods"))
        XCTAssertTrue(ids.contains("carthage"))
        XCTAssertTrue(ids.contains("xcode-simulator-runtimes"))
        XCTAssertEqual(ids.count, owners.count)
        XCTAssertEqual(owners.first(where: { $0.id == "ollama" })?.safety, .protected)
        XCTAssertEqual(owners.first(where: { $0.id == "docker" })?.safety, .protected)
    }

    func testJunkOwnerSelectionIdentityDoesNotCollapseBrowserRows() {
        let chrome = JunkCategory(
            type: .browserCache,
            ownerID: "browser-chrome",
            ownerName: "Google Chrome cache",
            size: 10,
            files: []
        )
        let safari = JunkCategory(
            type: .browserCache,
            ownerID: "browser-safari",
            ownerName: "Safari cache",
            size: 10,
            files: []
        )
        XCTAssertNotEqual(chrome.id, safari.id)
    }

    func testJunkCategoryAutoSelectsRebuildableEntriesOnly() {
        let rebuildable = JunkCategory(type: .developerOwner, ownerID: "cache", safety: .rebuild, size: 1, files: [])
        let protected = JunkCategory(type: .developerOwner, ownerID: "models", safety: .protected, size: 1, files: [])
        let review = JunkCategory(type: .developerOwner, ownerID: "archives", safety: .review, size: 1, files: [])

        XCTAssertTrue(rebuildable.isSelectedByDefault)
        XCTAssertFalse(protected.isSelectedByDefault)
        XCTAssertFalse(review.isSelectedByDefault)
    }

    @MainActor
    func testDiagnosticLogStoreExportsAndClearsLocalEntries() throws {
        let store = DiagnosticLogStore.shared
        store.clear()
        store.append(category: "test", message: "sample", metadata: ["cpu": "0.5"])
        XCTAssertEqual(store.count, 1)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let jsonURL = directory.appendingPathComponent("logs.json")
        let csvURL = directory.appendingPathComponent("logs.csv")
        try store.exportJSON(to: jsonURL)
        try store.exportCSV(to: csvURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: csvURL.path))
        XCTAssertTrue(String(data: try Data(contentsOf: csvURL), encoding: .utf8)?.contains("sample") == true)

        store.clear()
        XCTAssertEqual(store.count, 0)
    }

    @MainActor
    func testDropShelfKeepsSourceFileAndStoresSessionCopy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleaner-Shelf-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("notes.txt")
        let contents = "Shelf must preserve this exact text\nwith a second line."
        try contents.data(using: .utf8)!.write(to: source)

        let store = ShelfStore.shared
        store.clear()
        XCTAssertTrue(store.accept([NSItemProvider(object: source as NSURL)]))

        let deadline = Date().addingTimeInterval(2)
        while store.items.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(item.storage, .sessionCopy)
        let storedURL = try XCTUnwrap(item.storedURL)
        XCTAssertNotEqual(storedURL, source)
        XCTAssertEqual(String(data: try Data(contentsOf: storedURL), encoding: .utf8), contents)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        let exportExpectation = expectation(description: "Drop Shelf exports a disposable file copy")
        item.provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { value, error in
            XCTAssertNil(error)
            let exportedURL: URL? = {
                if let url = value as? URL { return url }
                if let url = value as? NSURL { return url as URL }
                if let data = value as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                return nil
            }()
            XCTAssertNotNil(exportedURL)
            if let exportedURL {
                XCTAssertNotEqual(exportedURL, source)
                XCTAssertEqual(try? String(contentsOf: exportedURL, encoding: .utf8), contents)
            }
            exportExpectation.fulfill()
        }
        wait(for: [exportExpectation], timeout: 2)

        let dataExpectation = expectation(description: "Drop Shelf publishes a file URL data representation")
        item.provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
            XCTAssertNil(error)
            let exportedURL = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            XCTAssertNotNil(exportedURL)
            if let exportedURL {
                XCTAssertNotEqual(exportedURL, source)
                XCTAssertEqual(try? String(contentsOf: exportedURL, encoding: .utf8), contents)
            }
            dataExpectation.fulfill()
        }
        wait(for: [dataExpectation], timeout: 2)

        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
    }

    @MainActor
    func testOptimizeUsesSelectableRootsAndKeepsARepeatScanCached() {
        let state = CleanerViewState()
        XCTAssertEqual(state.optimizationSelectedRoots, Set(DiskScanRoot.allCases))
        XCTAssertFalse(CleanerTool.allCases.contains { $0.title == "Startup" })
        XCTAssertEqual(CleanCategory.browserCache.scanRoot, .browser)
        XCTAssertEqual(CleanCategory.devCache.scanRoot, .developer)
        XCTAssertEqual(CleanCategory.logs.scanRoot, .logs)

        state.optimizationScannedRoots = [.browser, .developer]
        let selected = Set([DiskScanRoot.browser, .developer, .logs])
        let rootsNeedingScan = selected.subtracting(state.optimizationScannedRoots)
        XCTAssertEqual(rootsNeedingScan, [.logs])

        state.clearOptimizationScanCache()
        XCTAssertTrue(state.optimizationScannedRoots.isEmpty)
    }

    func testJunkCleanupTreatsAlreadyMissingFileAsResolved() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleaner-missing-\(UUID().uuidString)")
        let category = JunkCategory(
            type: .systemCache,
            ownerID: "missing-race",
            size: 1,
            files: [missingURL]
        )
        let finished = expectation(description: "Missing cache item resolved")

        StorageAnalyzerService().cleanJunkCategory(category) { result in
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.removedCount, 0)
            XCTAssertEqual(result.alreadyAbsentCount, 1)
            XCTAssertEqual(result.failedCount, 0)
            finished.fulfill()
        }

        wait(for: [finished], timeout: 2)
    }

    @MainActor
    func testProcessHistoryPersistsOnlyTheLatestFourHours() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleaner-ProcessHistory-\(UUID().uuidString)", isDirectory: true)
        let storageURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let point = ProcessGraphPoint(
            id: "editor|/Applications/Editor.app/Contents/MacOS/Editor",
            pid: 42,
            name: "Editor",
            executablePath: "/Applications/Editor.app/Contents/MacOS/Editor",
            cpu: 18,
            memoryBytes: 512 * 1_024 * 1_024,
            instanceCount: 1
        )
        let store = ProcessHistoryStore(storageURL: storageURL, now: now)
        store.append(
            ProcessGraphSample(date: now.addingTimeInterval(-(ProcessHistoryStore.retentionInterval + 1)), processes: [point]),
            now: now
        )
        store.append(ProcessGraphSample(date: now.addingTimeInterval(-60), processes: [point]), now: now)
        store.flushPersistenceForTesting()

        let restored = ProcessHistoryStore(storageURL: storageURL, now: now)
        XCTAssertEqual(restored.samples.count, 1)
        XCTAssertEqual(restored.samples.first?.date, now.addingTimeInterval(-60))
        XCTAssertEqual(restored.samples.first?.processes.first?.executablePath, point.executablePath)
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
