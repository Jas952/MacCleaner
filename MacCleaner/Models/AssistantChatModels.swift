import AppKit
import Foundation

struct AssistantApplication: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let url: URL
    let icon: NSImage
}

enum AssistantMessageRole {
    case user
    case assistant
}

struct AssistantMessage: Identifiable {
    let id = UUID()
    let role: AssistantMessageRole
    var text: String
    var isProcessing = false
    var previewTool: String? = nil
    var previewPhase: AssistantPreviewPhase = .running
    var resultRows: [AssistantCardRow] = []
    var resultActionTitle: String? = nil
    var resultDestination: String? = nil
}

enum AssistantRowAction: Equatable {
    case quitProcess(pid: Int32, name: String, instanceCount: Int)
    case uninstallApplication(bundleIdentifier: String, name: String)
    case disableStartup(id: String)
    case organizeFiles([AssistantMoveItem])
}

struct AssistantMoveItem: Equatable {
    let source: URL
    let destination: URL
    let size: Int
    let modified: Date
}

enum AssistantRowActionState: Equatable {
    case idle
    case running
    case succeeded(String)
    case failed(String)
}

struct AssistantCardRow: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let value: String
    var iconPath: String? = nil
    var fallbackIcon: String = "doc"
    var action: AssistantRowAction? = nil
    var actionState: AssistantRowActionState = .idle
    var loadFraction: Double? = nil
}

struct AssistantRowActionOutcome: Equatable {
    let succeeded: Bool
    let message: String
}

struct AssistantExecutionResult: Equatable {
    let text: String
    var rows: [AssistantCardRow] = []
    var actionTitle: String? = nil
    var destination: String? = nil
    var failed = false
    var stillRunning = false
}

struct AssistantToolCall: Equatable {
    let name: String
    let arguments: [String: String]

    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ")
    }

    var presentationTitle: String {
        AssistantToolPresentation.all.first(where: { $0.id == name })?.title ?? displayName
    }

    var argumentSummary: String {
        arguments.keys.sorted().map { "\($0): \(arguments[$0] ?? "")" }.joined(separator: " · ")
    }

    /// Only commands that can change or remove data stop at the confirmation gate.
    /// Discovery commands (including an uninstall preview) are safe to run immediately.
    var requiresConfirmation: Bool {
        switch name {
        case "clean_selected_items", "move_items_to_trash", "disable_startup_item",
             "restore_startup_item", "run_maintenance", "flush_dns":
            return true
        default:
            return false
        }
    }
}

struct AssistantPendingCommand: Identifiable, Equatable {
    let id = UUID()
    let query: String
    let call: AssistantToolCall
}

enum AssistantModelDecision: Equatable {
    case command(AssistantToolCall)
    case clarification(String)
    case rejected(String)
    case failed(String)
}

enum AssistantSuggestionEngine {
    private static let applicationCommands = [
        "удали", "удалить", "деинсталлируй", "очисти",
        "remove", "uninstall", "delete", "clean"
    ]

    static func applicationQuery(in draft: String) -> String? {
        guard let parts = applicationParts(in: draft) else { return nil }
        return parts.query.foldedForAssistantSearch
    }

    private static func applicationParts(in draft: String) -> (prefix: String, query: String)? {
        let words = draft.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let index = words.firstIndex(where: { applicationCommands.contains($0.foldedForAssistantSearch) }),
              index <= 4 else { return nil }
        var end = index + 1
        if end < words.count, ["приложение", "программу", "app", "application"].contains(words[end].lowercased()) { end += 1 }
        return (words.prefix(end).joined(separator: " "), words.dropFirst(end).joined(separator: " "))
    }

    static func matchingApplications(
        for draft: String,
        in applications: [AssistantApplication],
        limit: Int = 6
    ) -> [AssistantApplication] {
        guard let query = applicationQuery(in: draft) else { return [] }
        let sorted = applications.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return Array(sorted.prefix(limit)) }

        let prefixMatches = sorted.filter { $0.name.foldedForAssistantSearch.hasPrefix(query) }
        if !prefixMatches.isEmpty {
            return Array(prefixMatches.prefix(limit))
        }
        let containsMatches = sorted.filter {
            $0.name.foldedForAssistantSearch.contains(query)
        }
        return Array(containsMatches.prefix(limit))
    }

    static func completedDraft(from draft: String, applicationName: String) -> String {
        guard let parts = applicationParts(in: draft) else { return applicationName }
        return "\(parts.prefix) \(applicationName)"
    }
}

private extension String {
    var foldedForAssistantSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
