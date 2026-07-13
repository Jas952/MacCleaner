import SwiftUI
import AppKit

struct AILoadView: View {
    @ObservedObject var monitor: SystemMonitor

    private var snapshot: AIWorkloadSnapshot {
        AIWorkloadService.snapshot(from: monitor.processNodes, memory: monitor.memory)
    }

    var body: some View {
        let currentSnapshot = snapshot

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                AIHeader(
                    title: "AI Load",
                    subtitle: "Separates macOS load from agents, model runtimes, vector indexes, and orchestration."
                ) {
                    AIRefreshButton {
                        monitor.refresh(forceProcesses: true, forceSensors: true)
                    }
                }

                HStack(spacing: 14) {
                    AILoadHero(snapshot: currentSnapshot)
                    AIRecommendationPanel(items: currentSnapshot.recommendations)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Load Attribution")
                    ForEach(currentSnapshot.buckets) { bucket in
                        AIBucketRow(bucket: bucket)
                    }
                }
                .surfaceCard(padding: 16)
            }
            .padding(24)
        }
        .background(Color.surfaceLight)
        .onAppear {
            monitor.setConsumer(.ai, active: true)
            monitor.refresh(
                forceProcesses: monitor.processNodes.isEmpty,
                forceSensors: monitor.thermal.cpuTemp == 0
            )
        }
        .onDisappear {
            monitor.setConsumer(.ai, active: false)
        }
    }
}

private enum AgentsViewTab: String, CaseIterable {
    case agents = "Agents"
    case indexes = "Indexes"
}

struct AIAgentsView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var selectedTab: AgentsViewTab = .agents
    @State private var inspectorAgentID: String?
    @State private var inspectorKind: AgentInspectorKind = .processes
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator
    @State private var snapshot: AIWorkloadSnapshot?
    @State private var snapshotTask: Task<Void, Never>?
    @State private var stores: [AIIndexStore] = []
    @State private var storesTask: Task<Void, Never>?
    @State private var storesLoading = false

    private var totalMemory: UInt64 {
        Foundation.ProcessInfo.processInfo.physicalMemory
    }

    var body: some View {
        let currentSnapshot = snapshot ?? .empty(memory: monitor.memory)

        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    AIHeader(title: "Agents", subtitle: "Active agents, MCP bridges, helper runtimes, and LLM-related local load.") {
                        AIRefreshButton {
                            monitor.refresh(forceProcesses: true)
                            if selectedTab == .indexes { loadStores(force: true) }
                        }
                    }

                    // Tab picker
                    HStack(spacing: 0) {
                        ForEach(AgentsViewTab.allCases, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(selectedTab == tab ? Color.white : Color.textSecondaryLight)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(selectedTab == tab ? Color.textSecondaryLight : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.borderLight.opacity(0.4))
                    .clipShape(Capsule())

                    if selectedTab == .agents {
                        agentsContent(currentSnapshot)
                    } else {
                        indexesContent()
                    }
                }
                .padding(24)
                .padding(.bottom, 8)
            }

            if selectedTab == .agents {
                AgentMemoryFooter(snapshot: currentSnapshot)
            }
        }
        .background(Color.surfaceLight)
        .onAppear {
            monitor.setConsumer(.ai, active: true)
            if monitor.processNodes.isEmpty {
                monitor.refresh(forceProcesses: true)
            }
            loadSnapshot()
            loadStores()
        }
        .onDisappear {
            monitor.setConsumer(.ai, active: false)
            snapshotTask?.cancel()
            storesTask?.cancel()
        }
        .onReceive(monitor.$processNodes) { _ in
            loadSnapshot(debounce: 0.15)
            loadStores(debounce: 0.15)
        }
    }

    // MARK: - Agents Tab

    @ViewBuilder
    private func agentsContent(_ currentSnapshot: AIWorkloadSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Detected Agents")
            if currentSnapshot.agents.isEmpty {
                Text("No active AI agents detected. System and regular app processes are intentionally not expanded here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondaryLight)
            } else {
                ForEach(currentSnapshot.agents) { agent in
                    AIAgentCard(agent: agent, totalMemory: currentSnapshot.totalMemoryBytes) { agentID, kind in
                        inspectorAgentID = agentID
                        inspectorKind = kind
                        modalCoordinator.present(title: "Agent Inspector", subtitle: "Processes and attributed workloads") {
                            AgentInspectorWindow(
                                agents: currentSnapshot.agents,
                                selectedAgentID: $inspectorAgentID,
                                selectedKind: $inspectorKind
                            )
                        }
                    }
                }
            }
        }
        .surfaceCard(padding: 16)
    }

    // MARK: - Indexes Tab

    @ViewBuilder
    private func indexesContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Detected Vector Stores")
                if storesLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                }
                Spacer()
            }
            ForEach(stores) { store in
                AIIndexStoreCard(store: store, totalMemory: totalMemory)
            }
        }
        .surfaceCard(padding: 16)
    }

    // MARK: - Data Loading

    private func loadSnapshot(debounce: TimeInterval = 0) {
        let processes = monitor.processNodes
        let memory = monitor.memory
        snapshotTask?.cancel()
        snapshotTask = Task.detached(priority: .utility) {
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
                if Task.isCancelled { return }
            }
            let value = AIWorkloadService.snapshot(from: processes, memory: memory)
            if Task.isCancelled { return }
            await MainActor.run {
                snapshot = value
            }
        }
    }

    private func loadStores(force: Bool = false, debounce: TimeInterval = 0) {
        let processes = monitor.processNodes
        storesTask?.cancel()
        storesLoading = stores.isEmpty || force
        storesTask = Task.detached(priority: .utility) {
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
                if Task.isCancelled { return }
            }
            let value = AIIndexStoreService.stores(from: processes, force: force)
            if Task.isCancelled { return }
            await MainActor.run {
                stores = value
                storesLoading = false
            }
        }
    }
}

struct AIAdvisorView: View {
    @ObservedObject var monitor: SystemMonitor

    private var snapshot: AIWorkloadSnapshot {
        AIWorkloadService.snapshot(from: monitor.processNodes, memory: monitor.memory)
    }

    var body: some View {
        let currentSnapshot = snapshot

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                AIHeader(title: "Advisor", subtitle: "A local explanation layer. Go provider client will attach here next.") {
                    AIRefreshButton {
                        monitor.refresh(forceProcesses: true, forceSensors: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("What is loading this Mac?")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(advisorSummary(currentSnapshot))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondaryLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .surfaceCard(padding: 18)

                AIRecommendationPanel(items: currentSnapshot.recommendations)
            }
            .padding(24)
        }
        .background(Color.surfaceLight)
        .onAppear {
            monitor.setConsumer(.ai, active: true)
        }
        .onDisappear {
            monitor.setConsumer(.ai, active: false)
        }
    }

    private func advisorSummary(_ snapshot: AIWorkloadSnapshot) -> String {
        let top = snapshot.buckets.prefix(3).map { "\($0.kind.rawValue): \(String(format: "%.1f", $0.cpuTotal))% CPU" }.joined(separator: ", ")
        let aiPercent = Int(snapshot.aiCPUShare * 100)
        return "AI-related infrastructure accounts for roughly \(aiPercent)% of the observed classified CPU load. Top contributors: \(top.isEmpty ? "no active workload" : top). This local advisor is rule-based now; the planned Go agent should receive the same snapshot and ask the configured provider for richer explanations."
    }
}

struct AILibraryView: View {
    @State private var mode: LLMFitMode = .compatible
    @State private var sort: LLMFitSort = .score
    @State private var limit = 50
    @State private var searchText = ""
    @State private var perfectOnly = false
    @State private var toolUseOnly = false
    @State private var compatibleOnly = false
    @State private var paramFilter: LLMFitParamFilter = .any
    @State private var selectedProviders: Set<String> = []
    @State private var selectedUseCases: Set<String> = []
    @State private var selectedCapabilities: Set<String> = []
    @State private var selectedModel: LLMFitModel?
    @State private var snapshot: LLMFitSnapshot?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var loadTask: Task<Void, Never>?

    private var providers: [String] {
        Array(Set((snapshot?.models ?? []).compactMap(\.provider))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var useCases: [String] {
        Array(Set((snapshot?.models ?? []).compactMap(\.useCase))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var capabilities: [String] {
        Array(Set((snapshot?.models ?? []).flatMap { $0.capabilities ?? [] })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var visibleModels: [LLMFitModel] {
        let models = snapshot?.models ?? []
        let filtered = models.filter { model in
            if compatibleOnly && !modelFitsCurrentDevice(model) { return false }
            if toolUseOnly && !(model.capabilities ?? []).contains("tool_use") { return false }
            if !selectedProviders.isEmpty && !selectedProviders.contains(model.provider ?? "") { return false }
            if !selectedUseCases.isEmpty && !selectedUseCases.contains(model.useCase ?? "") { return false }
            if !selectedCapabilities.isEmpty && selectedCapabilities.isDisjoint(with: Set(model.capabilities ?? [])) { return false }
            if !paramFilter.contains(model.paramsB ?? paramsFromRaw(model.parametersRaw)) { return false }
            if searchText.isEmpty { return true }
            let haystack = [
                model.name,
                model.provider ?? "",
                model.parameterCount ?? "",
                model.useCase ?? "",
                model.runtimeLabel ?? model.runtime ?? "",
                (model.capabilities ?? []).joined(separator: " ")
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
        return Array(filtered.prefix(limit))
    }

    var body: some View {
        Group {
            if let selectedModel {
                LLMFitModelDetailView(model: selectedModel) {
                    self.selectedModel = nil
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        AIHeader(title: "Library", subtitle: "llmfit model catalog projected into MacCleaner for fit, memory, speed, and capability scanning.") {
                            AIRefreshButton {
                                load(force: true)
                            }
                        }

                        LLMLibraryControls(
                            mode: $mode,
                            sort: $sort,
                            limit: $limit,
                            searchText: $searchText,
                            perfectOnly: $perfectOnly,
                            toolUseOnly: $toolUseOnly,
                            compatibleOnly: $compatibleOnly,
                            paramFilter: $paramFilter,
                            selectedProviders: $selectedProviders,
                            selectedUseCases: $selectedUseCases,
                            selectedCapabilities: $selectedCapabilities,
                            providers: providers,
                            useCases: useCases,
                            capabilities: capabilities
                        )
                        .surfaceCard(padding: 14)

                        if let snapshot {
                            LLMFitSystemStrip(snapshot: snapshot)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionLabel(text: mode == .compatible ? "Compatible Models" : "All llmfit Models")
                                if isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.55)
                                        .frame(width: 14, height: 14)
                                }
                                Spacer()
                                if let snapshot {
                                    Text(summaryText(snapshot))
                                        .font(.mono(10, weight: .medium))
                                        .foregroundStyle(Color.textTertiaryLight)
                                }
                            }

                            if let errorText {
                                Text(errorText)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentRed)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 12)
                            } else if visibleModels.isEmpty && isLoading {
                                Text("Loading llmfit model data...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textSecondaryLight)
                                    .padding(.vertical, 12)
                            } else if visibleModels.isEmpty {
                                Text("No models match the current filters.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textSecondaryLight)
                                    .padding(.vertical, 12)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(visibleModels) { model in
                                        LLMFitModelRow(model: model, totalRAMGB: snapshot?.system?.totalRAMGB) {
                                            selectedModel = model
                                        }
                                    }
                                }
                            }
                        }
                        .surfaceCard(padding: 16)
                    }
                    .padding(24)
                }
            }
        }
        .background(Color.surfaceLight)
        .onAppear {
            load()
        }
        .onDisappear {
            loadTask?.cancel()
        }
        .onChange(of: mode) { _ in load() }
        .onChange(of: sort) { _ in load() }
        .onChange(of: limit) { _ in load(debounce: 0.2) }
        .onChange(of: perfectOnly) { _ in load() }
        .onChange(of: toolUseOnly) { _ in load() }
    }

    private func load(force: Bool = false, debounce: TimeInterval = 0) {
        loadTask?.cancel()
        let mode = mode
        let sort = sort
        let limit = limit
        let perfectOnly = perfectOnly
        let toolUseOnly = toolUseOnly
        isLoading = snapshot == nil || force
        errorText = nil

        loadTask = Task.detached(priority: .utility) {
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
                if Task.isCancelled { return }
            }

            do {
                let value = try LLMFitService.load(
                    mode: mode,
                    sort: sort,
                    perfect: perfectOnly,
                    toolUse: toolUseOnly,
                    limit: limit
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    snapshot = value
                    isLoading = false
                    errorText = nil
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    isLoading = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func summaryText(_ snapshot: LLMFitSnapshot) -> String {
        if let total = snapshot.totalKnownModels {
            return "\(visibleModels.count) shown · \(total) in llmfit database · \(snapshot.command)"
        }
        return "\(visibleModels.count) shown · \(snapshot.command)"
    }

    private func modelFitsCurrentDevice(_ model: LLMFitModel) -> Bool {
        let totalRAM = snapshot?.system?.totalRAMGB ?? Foundation.ProcessInfo.processInfo.physicalMemoryGB
        let required = model.memoryRequiredGB ?? model.recommendedRAMGB ?? model.minRAMGB ?? 0
        return required <= totalRAM
    }

    private func modelFamily(_ model: LLMFitModel) -> String {
        let raw = model.name.split(separator: "/").last.map(String.init) ?? model.name
        let cleaned = raw
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let parts = cleaned.split(separator: "-").map(String.init)
        guard let first = parts.first, !first.isEmpty else { return raw }
        if first.lowercased().contains("qwen") { return "Qwen" }
        if first.lowercased().contains("llama") { return "Llama" }
        if first.lowercased().contains("gemma") { return "Gemma" }
        if first.lowercased().contains("mistral") { return "Mistral" }
        if first.lowercased().contains("deepseek") { return "DeepSeek" }
        if first.lowercased().contains("phi") { return "Phi" }
        if first.lowercased().contains("lfm") { return "LFM" }
        return first
    }

    private func paramsFromRaw(_ raw: UInt64?) -> Double? {
        guard let raw else { return nil }
        return Double(raw) / 1_000_000_000
    }
}

struct AIIndexesView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var stores: [AIIndexStore] = []
    @State private var storesTask: Task<Void, Never>?
    @State private var isLoading = false

    private var totalMemory: UInt64 {
        Foundation.ProcessInfo.processInfo.physicalMemory
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                AIHeader(title: "Indexes", subtitle: "Vector stores, embedded retrieval libraries, and local index load used by agents.") {
                    AIRefreshButton {
                        monitor.refresh(forceProcesses: true)
                        loadStores(force: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel(text: "Detected Vector Stores")
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.55)
                                .frame(width: 14, height: 14)
                        }
                        Spacer()
                    }
                    ForEach(stores) { store in
                        AIIndexStoreCard(store: store, totalMemory: totalMemory)
                    }
                }
                .surfaceCard(padding: 16)
            }
            .padding(24)
            .padding(.bottom, 8)
        }
        .background(Color.surfaceLight)
        .onAppear {
            monitor.setConsumer(.ai, active: true)
            if monitor.processNodes.isEmpty {
                monitor.refresh(forceProcesses: true)
            }
            loadStores()
        }
        .onDisappear {
            monitor.setConsumer(.ai, active: false)
            storesTask?.cancel()
        }
        .onReceive(monitor.$processNodes) { _ in
            loadStores(debounce: 0.15)
        }
    }

    private func loadStores(force: Bool = false, debounce: TimeInterval = 0) {
        let processes = monitor.processNodes
        storesTask?.cancel()
        isLoading = stores.isEmpty || force
        storesTask = Task.detached(priority: .utility) {
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
                if Task.isCancelled { return }
            }
            let value = AIIndexStoreService.stores(from: processes, force: force)
            if Task.isCancelled { return }
            await MainActor.run {
                stores = value
                isLoading = false
            }
        }
    }
}

private struct LLMLibraryControls: View {
    @Binding var mode: LLMFitMode
    @Binding var sort: LLMFitSort
    @Binding var limit: Int
    @Binding var searchText: String
    @Binding var perfectOnly: Bool
    @Binding var toolUseOnly: Bool
    @Binding var compatibleOnly: Bool
    @Binding var paramFilter: LLMFitParamFilter
    @Binding var selectedProviders: Set<String>
    @Binding var selectedUseCases: Set<String>
    @Binding var selectedCapabilities: Set<String>
    let providers: [String]
    let useCases: [String]
    let capabilities: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(LLMFitMode.allCases) { item in
                        Button(action: { mode = item }) {
                            Text(item.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(mode == item ? Color.white : Color.textSecondaryLight)
                                .lineLimit(1)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .frame(width: 88, height: 32)
                                .background(mode == item ? Color.accentBlue : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(mode == item ? Color.accentBlue : Color.borderLight))
                        }
                        .buttonStyle(.plain)
                    }
                }

                LLMFilterButton(
                    title: "Sort",
                    value: sort.title,
                    options: [LLMFitSort.score, .tps, .mem, .ctx, .date].map(\.title)
                ) { selected in
                    if let next = LLMFitSort.allCases.first(where: { $0.title == selected }) {
                        sort = next
                    }
                }
                .frame(width: 128)
                .help(sort.hint)

                LLMFilterButton(
                    title: "Model size",
                    value: paramFilter.rawValue,
                    options: LLMFitParamFilter.allCases.map(\.rawValue)
                ) { selected in
                    if let next = LLMFitParamFilter.allCases.first(where: { $0.rawValue == selected }) {
                        paramFilter = next
                    }
                }
                .frame(width: 128)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiaryLight)
                    ZStack(alignment: .leading) {
                        if searchText.isEmpty {
                            Text("Model, provider, use case...")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textTertiaryLight)
                        }
                        TextField("", text: $searchText)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textPrimaryLight)
                            .textFieldStyle(.plain)
                    }
                    .frame(height: 20)
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(Color.surfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight))
                .frame(maxWidth: .infinity)

                LLMLimitStepper(value: $limit)
                    .frame(width: 118)
            }

            HStack(alignment: .bottom, spacing: 8) {
                LabeledLLMFilter(title: "Providers") {
                    LLMSelectionFilterButton(title: "Providers", selected: $selectedProviders, options: providers)
                }
                .frame(width: 150)
                LabeledLLMFilter(title: "Use cases") {
                    LLMSelectionFilterButton(title: "Use cases", selected: $selectedUseCases, options: useCases)
                }
                .frame(width: 170)
                LabeledLLMFilter(title: "Caps") {
                    LLMSelectionFilterButton(title: "Caps", selected: $selectedCapabilities, options: capabilities, display: displayCapability)
                }
                .frame(width: 140)

                LLMCheckbox(title: "Best hardware match", isOn: $perfectOnly)
                    .help("llmfit --perfect: show only models that match recommended specs")
                LLMCheckbox(title: "Function calling", isOn: $toolUseOnly)
                    .help("llmfit --tool-use: models marked with tool/function-call capability")
                LLMCheckbox(title: "Memory fits", isOn: $compatibleOnly)
                    .help("Keep models whose estimated required memory fits this Mac")

                Spacer()
            }
        }
    }

    private func displayCapability(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
    }
}

private struct LLMSortChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.textSecondaryLight)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(isSelected ? Color.accentBlue : Color(red: 0.965, green: 0.975, blue: 0.988))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isSelected ? Color.accentBlue : Color.borderLight))
        }
        .buttonStyle(.plain)
    }
}

private struct LLMCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.accentBlue : Color.white)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isOn ? Color.accentBlue : Color.borderLight, lineWidth: 1)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 15, height: 15)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
            }
            .padding(.horizontal, 2)
            .frame(height: 32)
        }
        .buttonStyle(.plain)
    }
}

private struct LLMLimitStepper: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("Limit \(value)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondaryLight)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                value = max(20, value - 10)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 20)
            }
            .disabled(value <= 20)
            Button {
                value = min(250, value + 10)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 20)
            }
            .disabled(value >= 250)
        }
        .foregroundStyle(Color.textSecondaryLight)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(Color(red: 0.965, green: 0.975, blue: 0.988))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight))
        .buttonStyle(.plain)
    }
}

private struct LLMFitSystemStrip: View {
    let snapshot: LLMFitSnapshot

    var body: some View {
        HStack(spacing: 8) {
            LLMSmallStat(title: "Hardware", value: snapshot.system?.cpuName ?? snapshot.system?.gpuName ?? "This Mac")
            LLMSmallStat(title: "Unified RAM", value: gb(snapshot.system?.totalRAMGB))
            LLMSmallStat(title: "Available Now", value: gb(snapshot.system?.availableRAMGB))
            LLMSmallStat(title: "GPU Memory", value: gb(snapshot.system?.gpuVRAMGB))
            LLMSmallStat(title: "Backend", value: system.backend ?? "Unknown")
            LLMSmallStat(title: "Installed", value: "\(snapshot.models.filter { $0.installed == true }.count)")
            LLMSmallStat(title: "Top Score", value: topScore)
        }
        .surfaceCard(padding: 12)
    }

    private var system: LLMFitSystem {
        snapshot.system ?? LLMFitSystem(
            availableRAMGB: nil,
            backend: nil,
            cpuCores: nil,
            cpuName: nil,
            gpuName: nil,
            gpuVRAMGB: nil,
            totalRAMGB: nil,
            unifiedMemory: nil
        )
    }

    private var topScore: String {
        guard let score = snapshot.models.compactMap(\.score).max() else { return "-" }
        return String(format: "%.0f/100", score)
    }

    private func gb(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f GB", value)
    }
}

private struct LLMFilterButton: View {
    let title: String
    let value: String
    let options: [String]
    let onSelect: (String) -> Void
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator

    var body: some View {
        Button {
            modalCoordinator.present(title: title, subtitle: "Choose one option") {
                VStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            onSelect(option)
                            modalCoordinator.dismiss()
                        } label: {
                            HStack {
                                Text(option).font(.system(size: 12, weight: .medium))
                                Spacer()
                                if option == value { Image(systemName: "checkmark").foregroundStyle(Color.accentBlue) }
                            }
                            .foregroundStyle(Color.textPrimaryLight)
                            .padding(.horizontal, 14).frame(height: 42)
                            .background(option == value ? Color.accentBlue.opacity(0.08) : Color.surfaceCardLight)
                            .overlay(Rectangle().strokeBorder(Color.borderLight))
                        }.buttonStyle(.plain)
                    }
                }
            }
        } label: {
            LLMFilterPickerLabel(title: title, value: value)
        }
        .buttonStyle(.plain)
        .frame(height: 32)
    }
}

private struct LLMSelectionFilterButton: View {
    let title: String
    @Binding var selected: Set<String>
    let options: [String]
    var display: (String) -> String = { $0 }
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator

    private var valueText: String {
        if selected.isEmpty { return "All" }
        if selected.count == 1, let first = selected.first { return display(first) }
        return "\(selected.count) selected"
    }

    var body: some View {
        Button {
            modalCoordinator.present(title: title, subtitle: "Select one or more filters") {
                VStack(spacing: 8) {
                    Button {
                        selected.removeAll()
                    } label: {
                        HStack { Text("All"); Spacer(); if selected.isEmpty { Image(systemName: "checkmark") } }
                            .foregroundStyle(Color.textPrimaryLight)
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(selected.isEmpty ? Color.accentBlue.opacity(0.08) : Color.surfaceCardLight)
                            .overlay(Rectangle().strokeBorder(Color.borderLight))
                    }.buttonStyle(.plain)
                    ForEach(options, id: \.self) { option in
                        Button {
                            if selected.contains(option) { selected.remove(option) } else { selected.insert(option) }
                        } label: {
                            HStack {
                                Text(display(option)); Spacer()
                                Image(systemName: selected.contains(option) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selected.contains(option) ? Color.accentBlue : Color.textTertiaryLight)
                            }
                            .foregroundStyle(Color.textPrimaryLight)
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(Color.surfaceCardLight)
                            .overlay(Rectangle().strokeBorder(Color.borderLight))
                        }.buttonStyle(.plain)
                    }
                }
            }
        } label: {
            LLMValuePickerLabel(value: valueText)
        }
        .buttonStyle(.plain)
        .frame(height: 32)
    }
}

private struct LabeledLLMFilter<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiaryLight)
            content()
        }
    }
}

private struct LLMValuePickerLabel: View {
    let value: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 0.965, green: 0.975, blue: 0.988))
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.borderLight.opacity(0.95), lineWidth: 1)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            .padding(.horizontal, 9)
        }
        .frame(height: 32)
    }
}

private struct LLMFilterPickerLabel: View {
    let title: String
    let value: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 0.965, green: 0.975, blue: 0.988))
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.borderLight.opacity(0.95), lineWidth: 1)
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.textTertiaryLight)
                    Text(value)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            .padding(.horizontal, 9)
        }
        .frame(height: 32)
    }
}

private struct LLMSmallStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight))
    }
}

private struct LLMFitModelRow: View {
    let model: LLMFitModel
    let totalRAMGB: Double?
    let onOpen: () -> Void

    private var requiredGB: Double {
        model.memoryRequiredGB ?? model.recommendedRAMGB ?? model.minRAMGB ?? 0
    }

    private var memoryBaseGB: Double {
        model.memoryAvailableGB ?? totalRAMGB ?? Foundation.ProcessInfo.processInfo.physicalMemoryGB
    }

    private var memoryShare: Double {
        guard memoryBaseGB > 0 else { return 0 }
        return min(requiredGB / memoryBaseGB, 1)
    }

    private var fitColor: Color {
        switch (model.fitLevel ?? "").lowercased() {
        case "excellent", "good": return Color.accentGreen
        case "fair", "okay": return Color.accentAmber
        case "poor": return Color.accentRed
        default: return requiredGB <= memoryBaseGB ? Color.accentGreen : Color.accentRed
        }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(model.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(model.provider ?? "Unknown")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textTertiaryLight)
                            .lineLimit(1)
                        if model.isMoE == true {
                            LLMBadge(text: "MoE", color: Color.accentAmber)
                        }
                        ForEach((model.capabilities ?? []).prefix(2), id: \.self) { capability in
                            LLMBadge(text: capability.replacingOccurrences(of: "_", with: " "), color: Color.accentBlue)
                        }
                    }

                    Text(model.useCase ?? "No use-case metadata")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondaryLight)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(scoreText)
                        .font(.mono(13, weight: .semibold))
                        .foregroundStyle(fitColor)
                    if let score = model.score {
                        Text(model.fitLevel ?? scoreCaption(for: score))
                            .font(.mono(10))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                }
                .frame(width: 88, alignment: .trailing)
            }

            HStack(spacing: 8) {
                InlineMetric(title: "Params", value: model.parameterCount ?? "-")
                InlineMetric(title: "Runtime", value: model.runtimeLabel ?? model.runtime ?? model.format ?? "-")
                InlineMetric(title: "Quant", value: model.bestQuant ?? model.quantization ?? "-")
                InlineMetric(title: "TPS", value: tpsText)
                InlineMetric(title: "CTX", value: contextText)
                InlineMetric(title: "RAM", value: memoryText)
            }

            MiniBar(value: memoryShare, color: fitColor, height: 3)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderLight.opacity(0.9)))
        }
        .buttonStyle(.plain)
    }

    private var scoreText: String {
        guard let score = model.score else { return fitFallback }
        return String(format: "%.0f", score)
    }

    private var fitFallback: String {
        requiredGB <= memoryBaseGB ? "Fits" : "High RAM"
    }

    private func scoreCaption(for score: Double) -> String {
        switch score {
        case 90...: return "Excellent"
        case 75..<90: return "Good"
        case 55..<75: return "Marginal"
        default: return "Risky"
        }
    }

    private var tpsText: String {
        guard let tps = model.estimatedTPS else { return "-" }
        return String(format: "%.1f", tps)
    }

    private var contextText: String {
        let value = model.effectiveContextLength ?? model.contextLength
        guard let value else { return "-" }
        if value >= 1000 { return "\(value / 1000)k" }
        return "\(value)"
    }

    private var memoryText: String {
        guard requiredGB > 0 else { return "-" }
        return String(format: "%.1f/%.1f GB", requiredGB, memoryBaseGB)
    }
}

private struct LLMBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct LLMFitModelDetailView: View {
    let model: LLMFitModel
    let onBack: () -> Void
    @State private var detail: LLMFitModel?
    @State private var system: LLMFitSystem?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?

    private var current: LLMFitModel { detail ?? model }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("llmfit info projection")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentRed)
                        .surfaceCard(padding: 14)
                }

                HStack(spacing: 8) {
                    LLMSmallStat(title: "Provider", value: current.provider ?? "Unknown")
                    LLMSmallStat(title: "Params", value: current.parameterCount ?? "-")
                    LLMSmallStat(title: "Runtime", value: current.runtimeLabel ?? current.runtime ?? current.format ?? "-")
                    LLMSmallStat(title: "Quant", value: current.bestQuant ?? current.quantization ?? "-")
                    LLMSmallStat(title: "Context", value: contextText(current))
                    LLMSmallStat(title: "Released", value: current.releaseDate ?? "Unknown")
                }
                .surfaceCard(padding: 12)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Model")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                        DetailInfoTile(label: "Full name", value: current.name)
                        DetailInfoTile(label: "Use case", value: current.useCase ?? "-")
                        DetailInfoTile(label: "Category", value: current.category ?? "-")
                        DetailInfoTile(label: "License", value: current.license ?? "Unknown")
                        DetailInfoTile(label: "Installed runtime", value: current.installed == true ? "Detected" : "No runtime detected")
                        DetailInfoTile(label: "Format", value: current.format ?? "-")
                        DetailInfoTile(label: "Default quant", value: current.quantization ?? "-")
                        DetailInfoTile(label: "Best quant for this Mac", value: current.bestQuant ?? "-")
                    }
                }
                .surfaceCard(padding: 16)

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Score Breakdown")
                        DetailScoreRow(title: "Overall", value: current.score)
                        DetailScoreRow(title: "Quality", value: current.scoreComponents?.quality)
                        DetailScoreRow(title: "Speed", value: current.scoreComponents?.speed)
                        DetailScoreRow(title: "Fit", value: current.scoreComponents?.fit)
                        DetailScoreRow(title: "Context", value: current.scoreComponents?.context)
                    }
                    .frame(maxWidth: .infinity, minHeight: 178, alignment: .top)
                    .surfaceCard(padding: 16)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "System Fit")
                        DetailKeyValue(label: "Fit level", value: current.fitLevel ?? "Unknown")
                        DetailKeyValue(label: "Run mode", value: current.runMode ?? "-")
                        DetailKeyValue(label: "Estimated speed", value: current.estimatedTPS.map { String(format: "%.1f tok/s", $0) } ?? "-")
                        DetailKeyValue(label: "Required memory", value: current.memoryRequiredGB.map { String(format: "%.1f GB", $0) } ?? "-")
                        DetailKeyValue(label: "Memory use", value: current.utilizationPct.map { String(format: "%.1f%%", $0) } ?? "-")
                        DetailKeyValue(label: "Disk estimate", value: current.diskSizeGB.map { String(format: "%.1f GB", $0) } ?? "-")
                    }
                    .frame(maxWidth: .infinity, minHeight: 178, alignment: .top)
                    .surfaceCard(padding: 16)
                }

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Memory")
                        DetailKeyValue(label: "Min VRAM", value: current.minVRAMGB.map { String(format: "%.1f GB", $0) } ?? "-")
                        DetailKeyValue(label: "Min RAM", value: current.minRAMGB.map { String(format: "%.1f GB", $0) } ?? "-")
                        DetailKeyValue(label: "Recommended RAM", value: current.recommendedRAMGB.map { String(format: "%.1f GB", $0) } ?? "-")
                        DetailKeyValue(label: "Available for estimate", value: current.memoryAvailableGB.map { String(format: "%.1f GB", $0) } ?? "-")
                        DetailKeyValue(label: "Total memory", value: current.totalMemoryGB.map { String(format: "%.1f GB", $0) } ?? "-")
                    }
                    .frame(maxWidth: .infinity, minHeight: 158, alignment: .top)
                    .surfaceCard(padding: 16)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Context")
                        DetailKeyValue(label: "Reported context", value: current.contextLength.map { "\($0) tokens" } ?? "-")
                        DetailKeyValue(label: "Effective context", value: current.effectiveContextLength.map { "\($0) tokens" } ?? "-")
                        DetailKeyValue(label: "Estimated speed", value: current.estimatedTPS.map { String(format: "%.1f tok/s", $0) } ?? "-")
                        DetailKeyValue(label: "Disk / quant", value: current.diskSizeGB.map { String(format: "%.1f GB", $0) } ?? "-")
                    }
                    .frame(maxWidth: .infinity, minHeight: 158, alignment: .top)
                    .surfaceCard(padding: 16)
                }

                if current.isMoE == true || current.moeOffloadedGB != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "MoE Architecture")
                        DetailKeyValue(label: "MoE model", value: current.isMoE == true ? "Yes" : "No")
                        DetailKeyValue(label: "Offloaded / active VRAM", value: current.moeOffloadedGB.map { String(format: "%.1f GB", $0) } ?? "-")
                    }
                    .surfaceCard(padding: 16)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Capabilities")
                    if let caps = current.capabilities, !caps.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(caps, id: \.self) { capability in
                                LLMBadge(text: capability.replacingOccurrences(of: "_", with: " "), color: Color.accentBlue)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        Text("No capabilities returned by llmfit.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                }
                .surfaceCard(padding: 16)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Model Notes")
                    notesView
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(padding: 16)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Runtime Environment")
                    DetailKeyValue(label: "Detected backend", value: system?.backend ?? "-")
                    DetailKeyValue(label: "CPU", value: system?.cpuName ?? "-")
                    DetailKeyValue(label: "CPU cores", value: system?.cpuCores.map(String.init) ?? "-")
                    DetailKeyValue(label: "GPU", value: system?.gpuName ?? "-")
                    DetailKeyValue(label: "GPU memory", value: system?.gpuVRAMGB.map { String(format: "%.1f GB", $0) } ?? "-")
                    DetailKeyValue(label: "Total RAM", value: system?.totalRAMGB.map { String(format: "%.1f GB", $0) } ?? "-")
                    DetailKeyValue(label: "Unified memory", value: system?.unifiedMemory == true ? "Yes" : "No")
                    DetailKeyValue(label: "Available RAM now", value: system?.availableRAMGB.map { String(format: "%.1f GB", $0) } ?? "-")
                }
                .surfaceCard(padding: 16)
            }
            .padding(24)
        }
        .background(Color.surfaceLight)
        .onAppear { load() }
        .onDisappear { task?.cancel() }
    }

    private func load() {
        task?.cancel()
        isLoading = true
        errorText = nil
        let name = model.name
        task = Task.detached(priority: .utility) {
            do {
                let response = try LLMFitService.info(modelName: name)
                if Task.isCancelled { return }
                await MainActor.run {
                    detail = response.models.first
                    system = response.system
                    isLoading = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    errorText = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func contextText(_ model: LLMFitModel) -> String {
        guard let value = model.contextLength else { return "-" }
        return value >= 1000 ? "\(value / 1000)k" : "\(value)"
    }

    @ViewBuilder
    private var notesView: some View {
        if let notes = current.notes, !notes.isEmpty {
            ForEach(notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Color.accentBlue).frame(width: 5, height: 5).padding(.top, 5)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondaryLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No notes returned by llmfit for this model.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondaryLight)
        }
    }
}

private struct DetailInfoTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight))
    }
}

private struct DetailScoreRow: View {
    let title: String
    let value: Double?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondaryLight)
            Spacer()
            Text(value.map { String(format: "%.1f / 100", $0) } ?? "-")
                .font(.mono(12, weight: .semibold))
                .foregroundStyle(Color.accentGreen)
        }
    }
}

private struct DetailKeyValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondaryLight)
            Spacer()
            Text(value)
                .font(.mono(12, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private extension Foundation.ProcessInfo {
    var physicalMemoryGB: Double {
        Double(physicalMemory) / 1_073_741_824
    }
}

private struct AIIndexStoreCard: View {
    let store: AIIndexStore
    let totalMemory: UInt64
    @State private var detailsExpanded = false

    private var memoryShare: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(store.memoryBytes) / Double(totalMemory)
    }

    private var memoryPercentText: String {
        let percent = memoryShare * 100
        return percent > 0 && percent < 1 ? String(format: "%.1f%%", percent) : "\(Int(percent))%"
    }

    private var sourceCount: Int {
        store.components.filter(\.exists).count + store.dependencies.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(store.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        Text(store.status.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(statusColor)
                        Text(store.rootPath)
                            .font(.mono(10))
                            .foregroundStyle(Color.textTertiaryLight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 12) {
                        InlineMetric(title: "Processes", value: "\(store.processes.count)")
                        InlineMetric(title: "Disk", value: MemoryInfo.formatted(store.diskBytes))
                        InlineMetric(title: "Sources", value: "\(sourceCount)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(MemoryInfo.formatted(store.memoryBytes)) (\(memoryPercentText))")
                        .font(.mono(13, weight: .semibold))
                        .foregroundStyle(statusColor)
                    Text("RAM")
                        .font(.mono(11))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                .frame(width: 116, alignment: .trailing)
            }

            CompactDisclosureRow(
                title: "Storage & Dependencies",
                detail: "\(store.components.filter(\.exists).count) paths · \(store.dependencies.count) deps",
                isExpanded: $detailsExpanded
            )

            if detailsExpanded {
                ComponentRows(components: store.components + store.dependencies)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.borderLight.opacity(0.9))
        )
    }

    private var statusColor: Color {
        switch store.status {
        case .active:
            return Color.accentBlue
        case .idle:
            return Color.accentGreen
        case .installed:
            return Color.accentAmber
        case .missing:
            return Color.textTertiaryLight
        }
    }
}

private struct InlineMetric: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.mono(10, weight: .semibold))
                .foregroundStyle(Color.textSecondaryLight)
        }
    }
}

private struct AgentMemoryFooter: View {
    let snapshot: AIWorkloadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memory")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                Spacer()
                Text("\(MemoryInfo.formatted(snapshot.agentMemoryBytes)) agents · \(Int(snapshot.agentMemoryShare * 100))% of total RAM")
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.surfaceLight)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.textTertiaryLight.opacity(0.35))
                        .frame(width: proxy.size.width * min(snapshot.memoryUsedShare, 1))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentBlue)
                        .frame(width: proxy.size.width * min(snapshot.agentMemoryShare, 1))
                }
            }
            .frame(height: 10)

            HStack(spacing: 14) {
                LegendDot(color: Color.accentBlue, title: "Agents", value: MemoryInfo.formatted(snapshot.agentMemoryBytes))
                LegendDot(color: Color.textTertiaryLight.opacity(0.55), title: "System / Other", value: MemoryInfo.formatted(snapshot.systemMemoryBytes))
                Spacer()
                Text("Total used \(Int(snapshot.memoryUsedShare * 100))%")
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(Color.textTertiaryLight)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(Rectangle().fill(Color.borderLight).frame(height: 1), alignment: .top)
    }
}

private struct LegendDot: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textSecondaryLight)
            Text(value)
                .font(.mono(10))
                .foregroundStyle(Color.textTertiaryLight)
        }
    }
}

private struct AIAgentsSummary: View {
    let snapshot: AIWorkloadSnapshot

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Agent Memory")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(snapshot.agentMemoryShare * 100))%")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(MemoryInfo.formatted(snapshot.agentMemoryBytes))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                MiniBar(value: snapshot.agentMemoryShare, color: Color.accentBlue, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .surfaceCard(padding: 18)

            VStack(alignment: .leading, spacing: 8) {
                Text("System")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                Text("Non-agent processes are grouped here and not expanded in this section.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondaryLight)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(snapshot.systemBucket?.processes.count ?? 0) processes")
                    .font(.mono(18, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .surfaceCard(padding: 18)
        }
    }
}

private struct AIAgentCard: View {
    let agent: AIAgentProfile
    let totalMemory: UInt64
    let onInspect: (String, AgentInspectorKind) -> Void
    @State private var componentsExpanded = false

    private var memoryShare: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(agent.memoryTotal) / Double(totalMemory)
    }

    private var memoryPercentText: String {
        let percent = memoryShare * 100
        return percent > 0 && percent < 1 ? String(format: "%.1f%%", percent) : "\(Int(percent))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        AgentActivityIndicator(state: agent.activityState)
                        Text(agent.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        Text(agent.activityState.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(activityLabelColor)
                        if !agent.rootPath.isEmpty {
                            Text(agent.rootPath)
                                .font(.mono(10))
                                .foregroundStyle(Color.textTertiaryLight)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(spacing: 3) {
                        MiniBar(value: memoryShare, color: Color.accentBlue, height: 4)
                        HStack {
                            Text(MemoryInfo.formatted(agent.memoryTotal))
                            Spacer()
                            Text(MemoryInfo.formatted(totalMemory))
                        }
                        .font(.mono(9))
                        .foregroundStyle(Color.textTertiaryLight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    MetricPill(
                        title: "Processes",
                        value: "\(agent.loadProcesses.count)",
                        action: { onInspect(agent.id, .processes) }
                    )
                    MetricPill(
                        title: "MCP",
                        value: agent.mcpSourceFound ? "\(agent.mcpComponents.count)" : "None",
                        action: { onInspect(agent.id, .mcp) }
                    )
                    MetricPill(
                        title: "Skills",
                        value: agent.skillSourceFound ? "\(agent.skillComponents.count)" : "None",
                        action: { onInspect(agent.id, .skills) }
                    )
                }
                .frame(width: 360)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(MemoryInfo.formatted(agent.memoryTotal)) (\(memoryPercentText))")
                        .font(.mono(13, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                    Text("RAM")
                        .font(.mono(11))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                .frame(width: 116, alignment: .trailing)
            }

            if !agent.components.isEmpty {
                CompactDisclosureRow(
                    title: "Components",
                    detail: "\(agent.components.filter(\.exists).count) found",
                    isExpanded: $componentsExpanded
                )
                if componentsExpanded {
                    ComponentRows(components: agent.components)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.borderLight.opacity(0.9))
        )
    }

    private var activityLabelColor: Color {
        switch agent.activityState {
        case .terminalActive, .active:
            return Color.accentBlue
        case .idle:
            return Color.textTertiaryLight
        }
    }
}

private struct AgentActivityIndicator: View {
    let state: AIAgentActivityState

    var body: some View {
        Group {
            switch state {
            case .terminalActive:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.45)
                    .frame(width: 12, height: 12)
                    .help("Agent has active terminal/tool child process")
            case .active:
                Circle()
                    .fill(Color.accentBlue)
                    .frame(width: 7, height: 7)
                    .help("Agent process is active")
            case .idle:
                Circle()
                    .strokeBorder(Color.textTertiaryLight.opacity(0.55), lineWidth: 1)
                    .frame(width: 7, height: 7)
                    .help("Agent is installed but no active process was detected")
            }
        }
        .frame(width: 12, height: 12)
    }
}

private struct CompactDisclosureRow: View {
    let title: String
    let detail: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: { isExpanded.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondaryLight)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiaryLight)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
    }
}

private struct ComponentRows: View {
    let components: [AIAgentComponent]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(components) { component in
                HStack(spacing: 8) {
                    Circle()
                        .fill(component.exists ? Color.accentGreen : Color.textTertiaryLight.opacity(0.4))
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(component.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondaryLight)
                        Text(component.path)
                            .font(.mono(10))
                            .foregroundStyle(Color.textTertiaryLight)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(component.kind)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                .padding(.leading, 18)
            }
        }
    }
}

private enum AgentInspectorKind: String, CaseIterable, Identifiable {
    case processes = "Processes"
    case mcp = "MCP"
    case skills = "Skills"

    var id: String { rawValue }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(value)
                    .font(.mono(12, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
            }
            Spacer(minLength: 4)
            Button(action: action) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 16, height: 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.borderLight))
            }
            .buttonStyle(.plain)
            .help("Open \(title) details")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight))
    }
}

private struct AgentInspectorWindow: View {
    let agents: [AIAgentProfile]
    @Binding var selectedAgentID: String?
    @Binding var selectedKind: AgentInspectorKind
    @Environment(\.dismiss) private var dismiss

    private var selectedAgent: AIAgentProfile? {
        agents.first { $0.id == selectedAgentID } ?? agents.first
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Agents")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiaryLight)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 6)

                ForEach(agents) { agent in
                    Button(action: { selectedAgentID = agent.id }) {
                        HStack {
                            Text(agent.name)
                                .font(.system(size: 12, weight: selectedAgentID == agent.id ? .semibold : .medium))
                                .foregroundStyle(selectedAgentID == agent.id ? Color.textPrimaryLight : Color.textSecondaryLight)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selectedAgentID == agent.id ? Color.white : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .frame(width: 210)
            .background(Color.surfaceLight)

            Rectangle().fill(Color.borderLight).frame(width: 1)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedAgent?.name ?? "Agent")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        if let root = selectedAgent?.rootPath, !root.isEmpty {
                            Text(root)
                                .font(.mono(10))
                                .foregroundStyle(Color.textSecondaryLight)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text(sourceText(for: selectedAgent, kind: selectedKind))
                            .font(.mono(10))
                            .foregroundStyle(Color.textTertiaryLight)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textSecondaryLight)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    ForEach(AgentInspectorKind.allCases) { kind in
                        Button(action: { selectedKind = kind }) {
                            Text(kind.rawValue)
                                .font(.system(size: 12, weight: selectedKind == kind ? .semibold : .medium))
                                .foregroundStyle(selectedKind == kind ? Color.white : Color.textSecondaryLight)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(selectedKind == kind ? Color.accentBlue : Color.surfaceLight)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(selectedKind == kind ? Color.accentBlue : Color.borderLight)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                Divider()

                let rows = items(for: selectedAgent, kind: selectedKind)
                HStack {
                    Text(selectedKind.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondaryLight)
                    Spacer()
                    Text("\(rows.count) items")
                        .font(.mono(11, weight: .medium))
                        .foregroundStyle(Color.textTertiaryLight)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        if rows.isEmpty {
                            Text(emptyText(for: selectedAgent, kind: selectedKind))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textSecondaryLight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 18)
                        } else {
                            ForEach(rows) { item in
                                InspectorItemRow(item: item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(width: 590, height: 500)
            .background(Color.white)
        }
        .frame(width: 800, height: 500)
    }

    private func sourceText(for agent: AIAgentProfile?, kind: AgentInspectorKind) -> String {
        guard agent != nil else { return "" }
        switch kind {
        case .processes: return "Active process snapshot"
        case .mcp: return "~/.codex/config.toml"
        case .skills: return "~/.codex/skills, ~/.codex/plugins/cache"
        }
    }

    private func items(for agent: AIAgentProfile?, kind: AgentInspectorKind) -> [AIAgentComponent] {
        guard let agent else { return [] }
        switch kind {
        case .processes:
            return agent.loadProcesses.map {
                AIAgentComponent(
                    title: "\($0.name) pid \($0.id)",
                    path: $0.commandLine.isEmpty ? "\(MemoryInfo.formatted($0.memoryBytes)) RAM" : $0.commandLine,
                    kind: "\(MemoryInfo.formatted($0.memoryBytes)) RAM · " + String(format: "%.1f%% CPU", $0.cpuUsage),
                    exists: true
                )
            }
        case .mcp:
            return agent.mcpComponents
        case .skills:
            return agent.skillComponents
        }
    }

    private func emptyText(for agent: AIAgentProfile?, kind: AgentInspectorKind) -> String {
        guard let agent else { return "No items detected" }
        switch kind {
        case .processes:
            return "No active processes detected"
        case .mcp:
            return agent.mcpSourceFound ? "No MCP servers configured" : "MCP config source not found"
        case .skills:
            return agent.skillSourceFound ? "No skills found" : "Skills source directory not found"
        }
    }
}

private struct InspectorItemRow: View {
    let item: AIAgentComponent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(item.exists ? Color.accentGreen : Color.textTertiaryLight.opacity(0.4))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(item.path)
                    .font(.mono(10))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.kind)
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiaryLight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight))
    }
}

private struct AIHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: () -> Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            Spacer()
            trailing()
        }
    }
}

private struct AIRefreshButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .shadow(color: Color.shadowMedium, radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
        .help("Refresh AI workload snapshot")
    }
}

private struct AILoadHero: View {
    let snapshot: AIWorkloadSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Attribution")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textSecondaryLight)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(snapshot.aiCPUShare * 100))%")
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimaryLight)
                Text("AI-related CPU share")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            VStack(spacing: 8) {
                ForEach(snapshot.buckets.prefix(5)) { bucket in
                    MiniBar(value: min(bucket.cpuTotal / 100.0, 1), color: bucket.kind.color, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .surfaceCard(padding: 18)
    }
}

private struct AIRecommendationPanel: View {
    let items: [AIAdvisorRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Advisor")
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(item.severity.color).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        Text(item.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondaryLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .surfaceCard(padding: 18)
    }
}

private struct AIBucketRow: View {
    let bucket: AIWorkloadBucket

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bucket.kind.icon)
                .frame(width: 22)
                .foregroundStyle(bucket.kind.color)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(bucket.kind.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(String(format: "%.1f", bucket.cpuTotal))% CPU")
                        .font(.mono(12, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                }
                MiniBar(value: min(bucket.cpuTotal / 100, 1), color: bucket.kind.color, height: 4)
                Text("\(bucket.processes.count) processes · \(MemoryInfo.formatted(bucket.memoryTotal)) RAM")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiaryLight)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AIProcessTableHeader: View {
    var body: some View {
        HStack {
            Text("Process").frame(maxWidth: .infinity, alignment: .leading)
            Text("Class").frame(width: 120, alignment: .leading)
            Text("CPU").frame(width: 64, alignment: .trailing)
            Text("RAM").frame(width: 82, alignment: .trailing)
            Text("PID").frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.textTertiaryLight)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct AIProcessRow: View {
    let row: AIWorkloadProcess

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(row.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Label(row.kind.rawValue, systemImage: row.kind.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(row.kind.color)
                .frame(width: 120, alignment: .leading)
            Text(String(format: "%.1f", row.cpuUsage)).frame(width: 64, alignment: .trailing)
            Text(MemoryInfo.formatted(row.memoryBytes)).frame(width: 82, alignment: .trailing)
            Text("\(row.id)").frame(width: 58, alignment: .trailing)
        }
        .font(.mono(11))
        .foregroundStyle(Color.textSecondaryLight)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.surfaceLight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderLight))
            }
        }
    }
}
