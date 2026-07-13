import SwiftUI

enum ProcessSort: String, CaseIterable {
    case cpu    = "CPU"
    case memory = "MEM"
    case name   = "NAME"
}

enum ProcessTab: String, CaseIterable {
    case cpu = "ЦП"
    case memory = "Память"
    case energy = "Энергия"
    case disk = "Диск"
    case network = "Сеть"

    static var allCases: [ProcessTab] {
        [.cpu, .memory, .energy, .disk]
    }
}

struct ProcessesView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var sortBy: ProcessSort = .cpu
    @State private var selectedTab: ProcessTab = .cpu
    @State private var searchText: String = ""
    @State private var showAgents: Bool = false
    @State private var killTarget: ProcessNode? = nil
    @State private var detailProcess: ProcessNode? = nil
    @State private var killFeedback: String? = nil
    @State private var feedbackIsError: Bool = false
    @State private var processAttributions: [Int32: ProcessAttribution] = [:]
    @State private var attributionTask: Task<Void, Never>?
    @ObservedObject var helper = HelperManager.shared

    private var allNodes: [ProcessNode] { monitor.processNodes }

    private var filtered: [ProcessNode] {
        let base = searchText.isEmpty
            ? allNodes
            : allNodes.filter { node in
                node.name.localizedCaseInsensitiveContains(searchText) ||
                    (processAttributions[node.id]?.searchText.localizedCaseInsensitiveContains(searchText) == true)
            }
        let visible = showAgents ? base : base.filter { processAttributions[$0.id]?.isAgent != true }
        let grouped = ProcessAggregator.aggregate(visible)
        switch sortBy {
        case .cpu:    return grouped.sorted { $0.cpuUsage > $1.cpuUsage }
        case .memory: return grouped.sorted { $0.memoryBytes > $1.memoryBytes }
        case .name:   return grouped.sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        let visibleProcesses = filtered
        let visibleProcessCount = visibleProcesses.count
        let maxMemory = allNodes.max(by: { $0.memoryBytes < $1.memoryBytes })?.memoryBytes ?? 1

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Processes")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(summaryText(groupCount: visibleProcessCount))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                
                Spacer()
                
                // Tab Picker
                HStack(spacing: 0) {
                    ForEach(ProcessTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                            if tab == .cpu || tab == .energy { sortBy = .cpu }
                            else if tab == .memory { sortBy = .memory }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selectedTab == tab ? Color.white : Color.textSecondaryLight)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
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
                
                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiaryLight)
                    TextField("Filter...", text: $searchText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.textPrimaryLight)
                        .frame(width: 130)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.surfaceCardLight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderLight))

                // Toggle agents
                Button { showAgents.toggle() } label: {
                    Text(showAgents ? "Hide agents" : "Show agents")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(showAgents ? Color.accentAmber : Color.textTertiaryLight)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(showAgents ? Color.accentAmber.opacity(0.08) : Color.surfaceCardLight)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(showAgents ? Color.accentAmber.opacity(0.25) : Color.borderLight))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Legacy helper migration banner
            if helper.isInstalled {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Legacy Root Helper Detected")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        Text("This older background daemon is no longer used. Remove it to close its root network service.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                    Spacer()
                    if helper.isInstalling {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Button {
                            helper.removeLegacyHelper { success, error in
                                if let error = error {
                                    self.killFeedback = "Removal failed: \(error)"
                                    self.feedbackIsError = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        self.killFeedback = nil
                                    }
                                }
                            }
                        } label: {
                            Text("Remove")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.blue)
                                .foregroundStyle(Color.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            
            Rectangle().fill(Color.borderLight).frame(height: 1)

            // Table header — clickable sort columns
            HStack(spacing: 0) {
                SortHeader(label: "NAME", sort: .name, current: sortBy) { sortBy = .name }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PID")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
                    .frame(width: ProcessTableLayout.pidWidth, alignment: .trailing)
                
                if selectedTab == .cpu {
                    SortHeader(label: "TIME", sort: .cpu, current: sortBy) { }
                        .frame(width: ProcessTableLayout.timeWidth, alignment: .trailing)
                    SortHeader(label: "CPU", sort: .cpu, current: sortBy) { sortBy = .cpu }
                        .frame(width: ProcessTableLayout.cpuWidth, alignment: .trailing)
                } else if selectedTab == .memory {
                    SortHeader(label: "MEM", sort: .memory, current: sortBy) { sortBy = .memory }
                        .frame(width: 80, alignment: .trailing)
                    Text("BAR")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.clear)
                        .frame(width: 60, alignment: .trailing)
                } else if selectedTab == .energy {
                    SortHeader(label: "ENERGY IMPACT", sort: .cpu, current: sortBy) { sortBy = .cpu }
                        .frame(width: 100, alignment: .trailing)
                } else if selectedTab == .disk {
                    Text("BYTES WRITTEN")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                        .frame(width: 90, alignment: .trailing)
                    Text("BYTES READ")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                        .frame(width: 80, alignment: .trailing)
                } else if selectedTab == .network {
                    Text("BYTES SENT")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                        .frame(width: 90, alignment: .trailing)
                    Text("BYTES RCV")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                        .frame(width: 80, alignment: .trailing)
                }

                Text("ACTION")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
                    .frame(width: 74, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 7)

            Rectangle().fill(Color.borderLight).frame(height: 1)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleProcesses.enumerated()), id: \.element.id) { idx, proc in
                        ProcessRow(
                            proc: proc,
                            maxMem: maxMemory,
                            selectedTab: selectedTab,
                            attribution: attribution(for: proc),
                            onKill: { killTarget = proc },
                            onTap: { detailProcess = proc }
                        )
                        if idx < visibleProcessCount - 1 {
                            Rectangle().fill(Color.borderLight.opacity(0.5)).frame(height: 1)
                                .padding(.leading, 24)
                        }
                    }
                }
                .padding(.bottom, 24)
            }

            // Toast feedback
            if let msg = killFeedback {
                HStack(spacing: 8) {
                    Image(systemName: feedbackIsError ? "xmark.circle" : "checkmark.circle")
                        .font(.system(size: 13))
                    Text(msg)
                        .font(.system(size: 12))
                }
                .foregroundStyle(feedbackIsError ? Color.accentRed : Color.accentGreen)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.surfaceCardLight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                    feedbackIsError ? Color.accentRed.opacity(0.3) : Color.accentGreen.opacity(0.3)
                ))
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .background(Color.surfaceLight)
        .processDetailOverlay(selectedProcess: $detailProcess) { killed in
            killFeedback = "\(killed.name) terminated"
            feedbackIsError = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { killFeedback = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { monitor.refresh(forceProcesses: true) }
        }
        .onAppear {
            monitor.setConsumer(.processes, active: true)
            if monitor.processNodes.isEmpty {
                monitor.refresh(forceProcesses: true)
            }
            rebuildAttributions()
        }
        .onDisappear {
            monitor.setConsumer(.processes, active: false)
            attributionTask?.cancel()
        }
        .onReceive(monitor.$processNodes) { _ in
            rebuildAttributions(debounce: 0.15)
        }
        .alert(
            (killTarget.map { ProcessTreeService.isProtected($0) } == true)
                ? "Protected Process" : "Quit Process",
            isPresented: Binding(
                get: { killTarget != nil },
                set: { if !$0 { killTarget = nil } }
            ),
            presenting: killTarget
        ) { proc in
            if !ProcessTreeService.isProtected(proc) {
                Button(proc.instanceCount > 1 ? "Quit All \(proc.instanceCount) Processes" : "Quit \"\(proc.name)\"", role: .destructive) {
                    killTarget = nil
                    Task.detached(priority: .utility) {
                        let result = proc.instanceCount > 1
                            ? ProcessTreeService.killProcessGroup(proc)
                            : ProcessTreeService.killProcess(proc)
                        await MainActor.run {
                            switch result {
                            case .success:
                                killFeedback = proc.instanceCount > 1
                                    ? "\(proc.instanceCount) \(proc.name) processes terminated"
                                    : "\(proc.name) terminated"
                                feedbackIsError = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { killFeedback = nil }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { monitor.refresh(forceProcesses: true) }
                            case .protected(let reason):
                                killFeedback = reason
                                feedbackIsError = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { killFeedback = nil }
                            case .failed(let reason):
                                killFeedback = "Failed: \(reason)"
                                feedbackIsError = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { killFeedback = nil }
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { killTarget = nil }
        } message: { proc in
            if ProcessTreeService.isProtected(proc) {
                Text("\"\(proc.name)\" is a protected macOS system process and cannot be quit.")
            } else if proc.instanceCount > 1 {
                Text("This will quit all \(proc.instanceCount) processes in the \"\(proc.name)\" group. Unsaved data may be lost. Continue?")
            } else {
                Text("Quitting \"\(proc.name)\" (PID \(proc.id)) may cause data loss. Continue?")
            }
        }
    }

    private func summaryText(groupCount: Int) -> String {
        let agentCount = allNodes.filter { processAttributions[$0.id]?.isAgent == true }.count
        return showAgents
            ? "\(groupCount) groups · \(allNodes.count) processes · \(agentCount) agent processes"
            : "\(groupCount) groups · \(allNodes.count) processes · \(agentCount) agent processes hidden"
    }

    private func rebuildAttributions(debounce: TimeInterval = 0) {
        let processes = monitor.processNodes
        let memory = monitor.memory
        attributionTask?.cancel()
        attributionTask = Task.detached(priority: .utility) {
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
                if Task.isCancelled { return }
            }

            let snapshot = AIWorkloadService.snapshot(from: processes, memory: memory)
            let stores = AIIndexStoreService.stores(from: processes)
            let map = ProcessAttribution.build(
                agents: snapshot.agents,
                indexes: stores,
                processes: snapshot.allProcesses
            )
            if Task.isCancelled { return }

            await MainActor.run {
                processAttributions = map
            }
        }
    }

    private func attribution(for process: ProcessNode) -> ProcessAttribution? {
        let members = process.groupedInstances.isEmpty ? [process] : process.groupedInstances
        var merged = ProcessAttribution()
        for member in members {
            guard let value = processAttributions[member.id] else { continue }
            merged.agents.append(contentsOf: value.agents.filter { !merged.agents.contains($0) })
            merged.mcpTools.append(contentsOf: value.mcpTools.filter { !merged.mcpTools.contains($0) })
            merged.indexes.append(contentsOf: value.indexes.filter { !merged.indexes.contains($0) })
        }
        return merged.isAgent || merged.isIndex ? merged : nil
    }
}

struct ProcessAttribution {
    var agents: [String] = []
    var indexes: [String] = []
    var mcpTools: [String] = []

    var isAgent: Bool { !agents.isEmpty || !mcpTools.isEmpty }
    var isIndex: Bool { !indexes.isEmpty }

    var searchText: String {
        (
            agents.map { "agent \($0)" }
                + mcpTools.map { "mcp \($0)" }
                + indexes.map { "index \($0)" }
        ).joined(separator: " ")
    }

    static func build(
        agents: [AIAgentProfile],
        indexes: [AIIndexStore],
        processes: [AIWorkloadProcess]
    ) -> [Int32: ProcessAttribution] {
        var result: [Int32: ProcessAttribution] = [:]

        for agent in agents {
            var seen = Set<Int32>()
            let rows = agent.processes + agent.mcpProcesses + agent.helperProcesses + agent.terminalProcesses
            for process in rows where !seen.contains(process.id) {
                seen.insert(process.id)
                var attribution = result[process.id] ?? ProcessAttribution()
                if !attribution.agents.contains(agent.name) {
                    attribution.agents.append(agent.name)
                }
                result[process.id] = attribution
            }
        }

        for store in indexes {
            for process in store.processes {
                var attribution = result[process.id] ?? ProcessAttribution()
                if !attribution.indexes.contains(store.name) {
                    attribution.indexes.append(store.name)
                }
                result[process.id] = attribution
            }
        }

        for process in processes {
            let evidence = "\(process.name) \(process.commandLine) \(process.reason)".lowercased()
            let isMCP = evidence.contains("mcp") || evidence.contains("modelcontextprotocol")
            guard isMCP, result[process.id]?.agents.isEmpty != false else { continue }

            var attribution = result[process.id] ?? ProcessAttribution()
            attribution.mcpTools = ["Shared"]
            result[process.id] = attribution
        }

        return result
    }
}

struct SortHeader: View {
    let label: String
    let sort: ProcessSort
    let current: ProcessSort
    let action: () -> Void

    var isActive: Bool { current == sort }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(isActive ? Color.accentBlue : Color.textTertiaryLight)
                // Fixed-width slot prevents layout shift
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                    .opacity(isActive ? 1 : 0)
                    .frame(width: 10)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum ProcessTableLayout {
    static let pidWidth: CGFloat = 64
    static let timeWidth: CGFloat = 92
    static let cpuWidth: CGFloat = 68
}

struct ProcessRow: View {
    let proc: ProcessNode
    let maxMem: UInt64
    let selectedTab: ProcessTab
    let attribution: ProcessAttribution?
    let onKill: () -> Void
    var onTap: (() -> Void)? = nil

    @State private var hovered = false

    private var cpuColor: Color {
        proc.cpuUsage > 50 ? .accentRed : proc.cpuUsage > 10 ? .accentAmber : Color.textSecondaryLight
    }
    private var isProtected: Bool { ProcessTreeService.isProtected(proc) }

    var body: some View {
        HStack(spacing: 0) {
            // Name + tags
            HStack(spacing: 6) {
                ProcessIconView(commandLine: proc.commandLine, size: 18)

                Text(proc.instanceCount > 1 ? "\(proc.name) ×\(proc.instanceCount)" : proc.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimaryLight)
                    .lineLimit(1)
                if let attribution {
                    if !attribution.agents.isEmpty {
                        ProcessAttributionBadge(
                            title: attribution.agents.joined(separator: " + "),
                            prefix: attribution.agents.count > 1 ? "Agents" : "Agent",
                            color: Color.accentAmber
                        )
                    }
                    ForEach(attribution.mcpTools, id: \.self) { tool in
                        ProcessAttributionBadge(title: tool, prefix: "MCP", color: Color.accentPurple)
                    }
                    ForEach(attribution.indexes, id: \.self) { index in
                        ProcessAttributionBadge(title: index, prefix: "Index", color: Color.accentBlue)
                    }
                }
                if isProtected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.textTertiaryLight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(proc.instanceCount > 1 ? "group" : String(proc.id))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textTertiaryLight)
                .lineLimit(1)
                .frame(width: ProcessTableLayout.pidWidth, alignment: .trailing)

            if selectedTab == .cpu {
                Text(proc.cpuTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textSecondaryLight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: ProcessTableLayout.timeWidth, alignment: .trailing)
                Text(String(format: "%.1f%%", proc.cpuUsage))
                    .font(.system(size: 11, weight: proc.cpuUsage > 5 ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(cpuColor)
                    .lineLimit(1)
                    .frame(width: ProcessTableLayout.cpuWidth, alignment: .trailing)
            } else if selectedTab == .memory {
                Text(MemoryInfo.formatted(proc.memoryBytes))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textSecondaryLight)
                    .frame(width: 80, alignment: .trailing)

                MiniBar(value: maxMem > 0 ? Double(proc.memoryBytes) / Double(maxMem) : 0,
                        color: .accentBlue, height: 2)
                    .frame(width: 50)
                    .padding(.leading, 10)
                    .frame(width: 60, alignment: .trailing)
            } else if selectedTab == .energy {
                Text(String(format: "%.1f", proc.cpuUsage))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(cpuColor)
                    .frame(width: 100, alignment: .trailing)
            } else if selectedTab == .disk {
                Text(MemoryInfo.formatted(proc.diskWritten))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textPrimaryLight)
                    .frame(width: 90, alignment: .trailing)
                Text(MemoryInfo.formatted(proc.diskRead))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textPrimaryLight)
                    .frame(width: 80, alignment: .trailing)
            } else if selectedTab == .network {
                Text("-")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.borderLight)
                    .frame(width: 90, alignment: .trailing)
                Text("-")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.borderLight)
                    .frame(width: 80, alignment: .trailing)
            }

            // Kill / Protected button
            Button(action: onKill) {
                HStack(spacing: 4) {
                    if isProtected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Quit")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .frame(width: 52, height: 22)
                .foregroundStyle(isProtected ? Color.textTertiaryLight : Color.accentRed)
                .background(isProtected ? Color.clear : (hovered ? Color.accentRed.opacity(0.15) : Color.accentRed.opacity(0.07)))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                    isProtected ? Color.borderLight : Color.accentRed.opacity(0.25)
                ))
            }
            .buttonStyle(.plain)
            .help(proc.instanceCount > 1 ? "Quit all \(proc.instanceCount) processes in this group" : "Quit process")
            .onHover { hovered = $0 }
            .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(hovered ? Color.surfaceCardLight : Color.clear)
        .onHover { hovered = $0 }
        .onTapGesture { onTap?() }
    }
}

private struct ProcessAttributionBadge: View {
    let title: String
    let prefix: String
    let color: Color

    var body: some View {
        Text("\(prefix): \(title)")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("\(prefix) process used by \(title)")
    }
}

struct ProcessIconView: View {
    let commandLine: String
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let icon = ProcessDetailService.appIcon(for: commandLine) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(Color.textTertiaryLight)
            }
        }
        .frame(width: size, height: size)
    }
}
