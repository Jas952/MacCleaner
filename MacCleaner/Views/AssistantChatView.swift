import AppKit
import SwiftUI

final class AssistantChatViewModel: ObservableObject {
    @Published var draft = "" {
        didSet {
            selectedSuggestionIndex = 0
            if draft != acceptedSuggestionDraft {
                acceptedSuggestionDraft = nil
            }
        }
    }
    @Published private(set) var messages: [AssistantMessage] = []
    @Published private(set) var applications: [AssistantApplication] = []
    @Published private(set) var isLoadingApplications = true
    @Published var selectedSuggestionIndex = 0
    private var acceptedSuggestionDraft: String?
    @Published var previewToolID = "scan_large_files"
    @Published var showsPreview = false
    @Published var focusRequest = 0
    @Published private(set) var isProcessing = false
    @Published private(set) var pendingCommand: AssistantPendingCommand?
    var executeCommand: ((AssistantToolCall, @escaping (AssistantExecutionResult) -> Void) -> Void)?
    var openDestination: ((String) -> Void)?
    var executeRowAction: ((AssistantRowAction, @escaping (AssistantRowActionOutcome) -> Void) -> Void)?

    var commandSuggestions: [AssistantPrompt] {
        guard acceptedSuggestionDraft != draft, suggestions.isEmpty else { return [] }
        return Array(AssistantPrompt.completions(for: draft).prefix(6))
    }
    var hasSuggestions: Bool { !suggestions.isEmpty || !commandSuggestions.isEmpty }
    func dismissSuggestions() { acceptedSuggestionDraft = draft }
    func acceptPrompt(_ prompt: AssistantPrompt) {
        draft = prompt.text
        acceptedSuggestionDraft = draft
    }

    init() {
        ApplicationSuggestionService.loadApplications { [weak self] applications in
            self?.applications = applications
            self?.isLoadingApplications = false
        }
    }

    var suggestions: [AssistantApplication] {
        guard acceptedSuggestionDraft != draft else { return [] }
        return AssistantSuggestionEngine.matchingApplications(for: draft, in: applications)
    }

    var selectedSuggestion: AssistantApplication? {
        let items = suggestions
        guard !items.isEmpty else { return nil }
        return items[min(selectedSuggestionIndex, items.count - 1)]
    }

    func acceptSelectedSuggestion() {
        if let application = selectedSuggestion { accept(application) }
        else if !commandSuggestions.isEmpty {
            acceptPrompt(commandSuggestions[min(selectedSuggestionIndex, commandSuggestions.count - 1)])
        }
    }

    func accept(_ application: AssistantApplication) {
        draft = AssistantSuggestionEngine.completedDraft(from: draft, applicationName: application.name)
        acceptedSuggestionDraft = draft
    }

    func moveSuggestion(by delta: Int) {
        let count = suggestions.isEmpty ? commandSuggestions.count : suggestions.count
        guard count > 0 else { return }
        selectedSuggestionIndex = (selectedSuggestionIndex + delta + count) % count
    }

    func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep one command in the confirmation gate at a time. A second request
        // must never replace the exact tool call the user is reviewing.
        guard !text.isEmpty, !isProcessing, pendingCommand == nil else { return }

        messages.append(AssistantMessage(role: .user, text: text))
        var pending = AssistantMessage(role: .assistant, text: "Reading your request and selecting an action…")
        pending.isProcessing = true
        messages.append(pending)
        let messageID = pending.id
        let startedAt = Date()
        isProcessing = true
        draft = ""
        AssistantModelBridge.propose(to: text) { [weak self] decision in
            // Keep short local requests from flashing the progress indicator for one frame.
            let remaining = max(0, 1.0 - Date().timeIntervalSince(startedAt))
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                guard let self else { return }
                if let index = self.messages.firstIndex(where: { $0.id == messageID }) {
                    self.messages[index].text = AssistantModelBridge.displayText(for: decision)
                    self.messages[index].isProcessing = false
                }
                if case .command(let call) = decision {
                    if call.requiresConfirmation {
                        self.prepareForConfirmation(call, query: text)
                        self.isProcessing = false
                    } else {
                        self.messages.removeAll { $0.id == messageID }
                        self.isProcessing = false
                        self.startExecution(call)
                    }
                } else {
                    self.isProcessing = false
                }
            }
        }
    }

    func prepareForConfirmation(_ call: AssistantToolCall, query: String) {
        pendingCommand = AssistantPendingCommand(query: query, call: call)
    }

    func confirmPendingCommand() {
        guard let pending = pendingCommand, !isProcessing else { return }
        pendingCommand = nil
        startExecution(pending.call)
    }

    private func startExecution(_ call: AssistantToolCall) {
        isProcessing = true
        var message = AssistantMessage(role: .assistant, text: "Executing \(call.displayName)…")
        message.isProcessing = true
        message.previewTool = call.name
        message.previewPhase = .running
        messages.append(message)
        let messageID = message.id
        let startedAt = Date()

        guard let executeCommand else {
            finishExecution(messageID: messageID, result: AssistantExecutionResult(
                text: "This action is recognized, but it is not connected yet. Nothing was changed.",
                failed: true
            ))
            return
        }
        executeCommand(call) { [weak self] result in
            let remaining = max(0, 1.1 - Date().timeIntervalSince(startedAt))
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                self?.finishExecution(messageID: messageID, result: result)
            }
        }
    }

    func declinePendingCommand() {
        guard pendingCommand != nil else { return }
        pendingCommand = nil
        messages.append(AssistantMessage(role: .assistant, text: "Cancelled. The command was not executed."))
    }

    func reportPendingCommandError() {
        guard let pending = pendingCommand else { return }
        pendingCommand = nil
        messages.append(AssistantMessage(
            role: .assistant,
            text: "Marked as an incorrect interpretation: \(pending.call.displayName). Nothing was executed. Please rephrase the request."
        ))
    }

    private func finishExecution(messageID: UUID, result: AssistantExecutionResult) {
        if let index = messages.firstIndex(where: { $0.id == messageID }) {
            messages[index].text = result.text
            messages[index].isProcessing = false
            messages[index].resultRows = result.rows
            messages[index].resultActionTitle = result.actionTitle
            messages[index].resultDestination = result.destination
            messages[index].previewPhase = result.failed ? .failed : (result.stillRunning ? .deferred : .result)
        }
        isProcessing = false
    }

    func performRowAction(messageID: UUID, rowID: String) {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }),
              let rowIndex = messages[messageIndex].resultRows.firstIndex(where: { $0.id == rowID }),
              let action = messages[messageIndex].resultRows[rowIndex].action,
              messages[messageIndex].resultRows[rowIndex].actionState == .idle,
              let executeRowAction else { return }

        messages[messageIndex].resultRows[rowIndex].actionState = .running
        executeRowAction(action) { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self,
                      let messageIndex = self.messages.firstIndex(where: { $0.id == messageID }),
                      let rowIndex = self.messages[messageIndex].resultRows.firstIndex(where: { $0.id == rowID }) else { return }
                self.messages[messageIndex].resultRows[rowIndex].actionState = outcome.succeeded
                    ? .succeeded(outcome.message)
                    : .failed(outcome.message)
                if outcome.succeeded {
                    self.messages[messageIndex].resultRows[rowIndex].action = nil
                }
            }
        }
    }

    func addPreview(tool: AssistantToolPresentation, phase: AssistantPreviewPhase) {
        messages.append(AssistantMessage(role: .assistant, text: "Command preview",
            previewTool: tool.id, previewPhase: phase))
    }
}

struct AssistantChatView: View {
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator
    @ObservedObject var model: AssistantChatViewModel
    @State private var showsPromptPicker = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            composer
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Color.surfaceLight)
        .accessibilityIdentifier("assistant-chat-view")
        .animation(.easeInOut(duration: 0.18), value: model.pendingCommand?.id)
        .onChange(of: model.pendingCommand?.id) { _ in
            guard let pending = model.pendingCommand else { return }
            modalCoordinator.present(title: "Confirm action", width: 440, height: 290) {
                AssistantConfirmationPopover(
                    pending: pending,
                    onConfirm: { model.confirmPendingCommand(); modalCoordinator.dismiss() },
                    onDecline: { model.declinePendingCommand(); modalCoordinator.dismiss() },
                    onReportError: { model.reportPendingCommandError(); modalCoordinator.dismiss() }
                )
            }
        }
        .onChange(of: modalCoordinator.presentation?.id) { id in
            if id == nil { model.declinePendingCommand() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Quick Assist")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text("A faster way to take care of your Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondaryLight)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(model.isProcessing ? Color.accentBlue : Color.accentGreen)
                    .frame(width: 7, height: 7)
                Text(model.isProcessing ? "Working locally" : (AssistantModelBridge.available ? "Local · protected actions" : "Model unavailable"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.textSecondaryLight.opacity(0.055))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(model.messages) { message in
                        AssistantMessageRow(message: message) { destination in
                            model.openDestination?(destination)
                        } onRowAction: { rowID in
                            model.performRowAction(messageID: message.id, rowID: rowID)
                        }
                            .frame(
                                maxWidth: .infinity,
                                alignment: message.role == .user ? .trailing : .leading
                            )
                            .id(message.id)
                    }
                    if model.messages.isEmpty {
                        AssistantWelcomePrompts { prompt in
                            model.acceptPrompt(prompt)
                            model.focusRequest += 1
                        }
                        .transition(.opacity)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("assistant-conversation-bottom")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 1240)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                proxy.scrollTo("assistant-conversation-bottom", anchor: .bottom)
            }
            .onChange(of: conversationRevision) { _ in
                scrollToConversationEnd(proxy)
            }
            .onChange(of: model.pendingCommand?.id) { _ in
                scrollToConversationEnd(proxy)
            }
        }
    }

    private func scrollToConversationEnd(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("assistant-conversation-bottom", anchor: .bottom)
            }
        }
    }

    private var conversationRevision: [String] {
        model.messages.map {
            "\($0.id.uuidString)|\($0.text)|\($0.isProcessing)|\($0.previewPhase.rawValue)"
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    showsPromptPicker.toggle()
                } label: {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(width: 28, height: 28)
                        .background(Color.textSecondaryLight.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Example requests")
                .accessibilityLabel("Example requests")
                .popover(isPresented: $showsPromptPicker, arrowEdge: .bottom) {
                    AssistantPromptPopover { prompt in
                        model.acceptPrompt(prompt)
                        model.focusRequest += 1
                        showsPromptPicker = false
                    }
                }

                AssistantCommandField(
                    text: $model.draft,
                    placeholder: model.isLoadingApplications
                        ? "Loading applications…"
                        : "Ask Quick Assist…",
                    canAcceptSuggestion: model.hasSuggestions,
                    onSubmit: model.submit,
                    onAcceptSuggestion: model.acceptSelectedSuggestion,
                    onMoveSuggestion: model.moveSuggestion,
                    onDismissSuggestion: model.dismissSuggestions,
                    focusRequest: model.focusRequest
                )
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)

                if model.hasSuggestions {
                    HStack(spacing: 4) {
                        Text("accept")
                        Text("Tab")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiaryLight)
                }

                Button(action: model.submit) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.35) : Color.accentBlue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(
                    model.isProcessing
                        || model.pendingCommand != nil
                        || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send message (Command-Return)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color.surfaceCardLight)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderLight, lineWidth: 1))
        .shadow(color: Color.shadowMedium, radius: 12, x: 0, y: 4)
        .overlay(alignment: .bottomLeading) {
            if model.hasSuggestions {
                VStack(spacing: 0) {
                    if !model.suggestions.isEmpty {
                        AssistantSuggestionPanel(applications: model.suggestions,
                            selectedIndex: model.selectedSuggestionIndex, onSelect: model.accept)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SUGGESTIONS   ·   ↑↓ select   ·   Tab accept   ·   Esc dismiss")
                                .font(.system(size: 10)).foregroundStyle(.secondary).padding(8)
                            ForEach(Array(model.commandSuggestions.enumerated()), id: \.element.id) { index, prompt in
                                Button { model.acceptPrompt(prompt) } label: {
                                    Label(prompt.text, systemImage: prompt.icon)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                        .background(index == model.selectedSuggestionIndex ? Color.accentBlue.opacity(0.12) : .clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain)
                            }
                        }.padding(6)
                    }
                }
                .background(Color.surfaceCardLight)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderLight))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .frame(maxWidth: 510)
                .padding(.bottom, 66)
            }
        }
        .animation(.easeOut(duration: 0.14), value: model.suggestions.map(\.id))
    }

    private var pendingCommandBinding: Binding<AssistantPendingCommand?> {
        Binding(
            get: { model.pendingCommand },
            set: { value in
                if value == nil, model.pendingCommand != nil {
                    model.declinePendingCommand()
                }
            }
        )
    }
}

private struct AssistantWelcomePrompts: View {
    let onSelect: (AssistantPrompt) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("What can I help with?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text("Describe the problem naturally, or start with one of these examples.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondaryLight)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(AssistantPrompt.starters) { prompt in
                    Button { onSelect(prompt) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: prompt.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textSecondaryLight)
                            Text(prompt.text)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textPrimaryLight)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color.textSecondaryLight.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
        .padding(.top, 12)
    }
}

private struct AssistantPromptPopover: View {
    let onSelect: (AssistantPrompt) -> Void
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Example requests")
                    .font(.system(size: 13, weight: .semibold))
                Text("Choose one, then adjust it in the input field.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(AssistantPrompt.all) { prompt in
                    Button { onSelect(prompt) } label: {
                        Label(prompt.text, systemImage: prompt.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.045))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 430)
    }
}

private struct AssistantConfirmationPopover: View {
    let pending: AssistantPendingCommand
    let onConfirm: () -> Void
    let onDecline: () -> Void
    let onReportError: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm this change")
                        .font(.system(size: 13, weight: .semibold))
                    Text(pending.call.presentationTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondaryLight)
                }
            }

            if !pending.call.argumentSummary.isEmpty {
                Text(pending.call.argumentSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondaryLight)
                    .lineLimit(3)
            }

            Text("This command can change data or system state.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.textTertiaryLight)

            HStack(spacing: 8) {
                Button("Wrong action", action: onReportError)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondaryLight)
                    .accessibilityIdentifier("assistant-confirmation-error")
                Spacer()
                Button("Cancel", action: onDecline)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("assistant-confirmation-no")
                Button("Continue", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("assistant-confirmation-yes")
            }
        }
        .padding(16)
        .frame(width: 340)
        .accessibilityIdentifier("assistant-confirmation-panel")
    }
}

private struct AssistantMessageRow: View {
    let message: AssistantMessage
    let onOpenDestination: (String) -> Void
    let onRowAction: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 180)
            }
            Group {
                if let toolID = message.previewTool,
                   let tool = AssistantToolPresentation.all.first(where: { $0.id == toolID }) {
                    AssistantCommandCard(
                        tool: tool,
                        phase: message.previewPhase,
                        rows: message.previewPhase == .result
                            ? message.resultRows
                            : AssistantCommandCard.liveRows(for: tool, resultText: message.text),
                        summary: message.text,
                        isPreview: false,
                        allowsInteraction: false,
                        resultActionTitle: message.resultActionTitle,
                        onOpenResult: {
                            if let destination = message.resultDestination {
                                onOpenDestination(destination)
                            }
                        },
                        onRowAction: { onRowAction($0.id) }
                    )
                    .frame(maxWidth: 820, alignment: .leading)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topLeading)))
                } else if message.isProcessing {
                    AssistantLoadingIndicator(title: "Understanding your request", subtitle: "Choosing the right action")
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("assistant-model-progress")
                } else {
                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundStyle(message.role == .user ? Color.textPrimaryLight : Color.textPrimaryLight)
                        .textSelection(.enabled)
                        .padding(.horizontal, message.role == .user ? 13 : 0)
                        .padding(.vertical, message.role == .user ? 9 : 3)
                        .background(message.role == .user ? Color.accentBlue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: message.role == .user ? 560 : 760,
                               alignment: message.role == .user ? .trailing : .leading)
                }
            }
            .frame(
                maxWidth: message.role == .user ? nil : .infinity,
                alignment: message.role == .user ? .trailing : .leading
            )
            if message.role != .user {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AssistantSuggestionPanel: View {
    let applications: [AssistantApplication]
    let selectedIndex: Int
    let onSelect: (AssistantApplication) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("APPLICATIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiaryLight)
                Spacer()
                Text("↑↓ select  ·  Tab accept  ·  Esc dismiss")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 3)

            ForEach(Array(applications.enumerated()), id: \.element.id) { index, application in
                Button(action: { onSelect(application) }) {
                    HStack(spacing: 10) {
                        Image(nsImage: application.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(application.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.textPrimaryLight)
                            Text(application.bundleIdentifier)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textTertiaryLight)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(index == selectedIndex ? Color.accentBlue.opacity(0.10) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .background(Color.surfaceCardLight)

        Divider()
    }
}

private struct AssistantCommandField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let canAcceptSuggestion: Bool
    let onSubmit: () -> Void
    let onAcceptSuggestion: () -> Void
    let onMoveSuggestion: (Int) -> Void
    let onDismissSuggestion: () -> Void
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.setAccessibilityIdentifier("assistant-command-field")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AssistantCommandField
        var lastFocusRequest = 0

        init(parent: AssistantCommandField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)) where parent.canAcceptSuggestion:
                parent.onDismissSuggestion()
                return true
            case #selector(NSResponder.insertTab(_:)) where parent.canAcceptSuggestion:
                parent.onAcceptSuggestion()
                return true
            case #selector(NSResponder.moveUp(_:)) where parent.canAcceptSuggestion:
                parent.onMoveSuggestion(-1)
                return true
            case #selector(NSResponder.moveDown(_:)) where parent.canAcceptSuggestion:
                parent.onMoveSuggestion(1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            default:
                return false
            }
        }
    }
}
