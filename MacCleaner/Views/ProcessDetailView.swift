import SwiftUI
import AppKit

struct ProcessDetailView: View {
    let node: ProcessNode
    let onDismiss: () -> Void
    var onKill: ((ProcessNode) -> Void)? = nil

    @State private var detail: ProcessDetailInfo?
    @State private var isLoading = true
    @State private var showCommand = false
    @State private var hoverCopy = false
    @State private var hoverReveal = false
    @State private var hoverTerminate = false
    @State private var hoverForceQuit = false
    @State private var hoverClose = false
    @State private var terminationError: String?
    @State private var showsInstances = true
    @State private var terminatingInstanceIDs: Set<Int32> = []
    @State private var terminatedInstanceIDs: Set<Int32> = []
    @State private var selectedGroupInstance: ProcessNode?

    private var activeNode: ProcessNode { selectedGroupInstance ?? node }
    private var isProtected: Bool { ProcessTreeService.isProtected(activeNode) }
    private var visibleInstances: [ProcessNode] {
        node.groupedInstances.filter { !terminatedInstanceIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !node.groupedInstances.isEmpty {
                groupContent
            } else if isLoading {
                loadingState
            } else if let info = detail {
                detailContent(info)
            }
        }
        .frame(width: 520, height: 560)
        .background(Color.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 26, x: 0, y: 10)
        .onAppear {
            if node.groupedInstances.isEmpty { loadDetail(for: node) }
        }
        .alert(
            "Could Not Terminate Process",
            isPresented: Binding(
                get: { terminationError != nil },
                set: { if !$0 { terminationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { terminationError = nil }
        } message: {
            Text(terminationError ?? "The process could not be terminated.")
        }
    }

    private var groupContent: some View {
        VStack(spacing: 0) {
            groupHeader

            Divider()

            if selectedGroupInstance != nil {
                if isLoading {
                    loadingState
                        .frame(maxHeight: .infinity)
                } else if let info = detail {
                    groupInstanceDetail(info)
                }
            } else {
                groupOverview
            }
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 12) {
            ProcessIconView(commandLine: node.commandLine, size: 36)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(selectedGroupInstance.map { "PID \($0.id) details" } ?? "\(visibleInstances.count) running processes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
            }

            Spacer()

            if selectedGroupInstance != nil {
                Button(action: returnToGroup) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(width: 28, height: 28)
                        .background(Color.surfaceLight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Back to process instances")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textSecondaryLight)
                    .frame(width: 28, height: 28)
                    .background(Color.surfaceLight)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.surfaceCardLight.opacity(0.78))
    }

    private var groupOverview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                groupMetric("CPU", String(format: "%.1f%%", node.cpuUsage))
                groupMetric("MEM", MemoryInfo.formatted(node.memoryBytes))
                groupMetric("READ", MemoryInfo.formatted(node.diskRead))
                groupMetric("WRITTEN", MemoryInfo.formatted(node.diskWritten))
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(Color.surfaceLight.opacity(0.72))

            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsInstances.toggle() }
            } label: {
                HStack {
                    Text("Process instances").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(visibleInstances.count)").font(.system(size: 11, design: .monospaced))
                    Image(systemName: showsInstances ? "chevron.up" : "chevron.down")
                }
                .foregroundStyle(Color.textPrimaryLight)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsInstances {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleInstances) { instance in
                            HStack(spacing: 10) {
                                Text("PID \(instance.id)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.textPrimaryLight)
                                    .frame(width: 82, alignment: .leading)
                                Text(String(format: "%.1f%% CPU", instance.cpuUsage))
                                    .frame(width: 82, alignment: .trailing)
                                Text(MemoryInfo.formatted(instance.memoryBytes))
                                    .frame(width: 92, alignment: .trailing)
                                Text(instance.commandLine)
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    showDetail(for: instance)
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.textSecondaryLight)
                                        .frame(width: 26, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Show details for PID \(instance.id)")

                                if ProcessTreeService.isProtected(instance) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Color.textTertiaryLight)
                                        .frame(width: 42, height: 22)
                                } else {
                                    Button {
                                        terminate(instance: instance)
                                    } label: {
                                        Group {
                                            if terminatingInstanceIDs.contains(instance.id) {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Text("Quit")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                        }
                                        .foregroundStyle(Color.accentRed)
                                        .frame(width: 42, height: 22)
                                        .background(Color.accentRed.opacity(0.07))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .strokeBorder(Color.accentRed.opacity(0.25), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(terminatingInstanceIDs.contains(instance.id))
                                    .help("Quit PID \(instance.id)")
                                }
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.textSecondaryLight)
                            .padding(.horizontal, 24).padding(.vertical, 9)
                            Divider().padding(.horizontal, 24)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            Spacer(minLength: 0)
            Divider()
            HStack {
                Text("Quit affects only the PID shown on the same row.")
                    .font(.system(size: 10)).foregroundStyle(Color.textTertiaryLight)
                Spacer()
                Button("Close", action: onDismiss).buttonStyle(AppSecondaryButtonStyle())
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Color.surfaceCardLight.opacity(0.72))
        }
    }

    private func groupInstanceDetail(_ info: ProcessDetailInfo) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    descriptionBlock(info)
                        .padding(.top, 14)

                    if info.parentChain.count > 1 {
                        parentChainRow(info)
                    }

                    Divider().padding(.horizontal, 24)
                    propertyRows(info)
                    commandSection(info)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            actionBar(info)
        }
    }

    private func groupMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textTertiaryLight)
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimaryLight)
        }
        .frame(maxWidth: .infinity)
    }

    private func terminate(instance: ProcessNode) {
        guard !terminatingInstanceIDs.contains(instance.id) else { return }
        terminatingInstanceIDs.insert(instance.id)

        Task.detached(priority: .utility) {
            let result = ProcessTreeService.killProcess(instance)
            await MainActor.run {
                terminatingInstanceIDs.remove(instance.id)
                switch result {
                case .success:
                    terminatedInstanceIDs.insert(instance.id)
                    onKill?(instance)
                    if visibleInstances.isEmpty { onDismiss() }
                case .protected(let reason), .failed(let reason):
                    terminationError = reason
                }
            }
        }
    }

    private func showDetail(for instance: ProcessNode) {
        selectedGroupInstance = instance
        detail = nil
        isLoading = true
        showCommand = false
        loadDetail(for: instance)
    }

    private func returnToGroup() {
        selectedGroupInstance = nil
        detail = nil
        isLoading = true
        showCommand = false
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading process info…")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondaryLight)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail Content

    private func detailContent(_ info: ProcessDetailInfo) -> some View {
        VStack(spacing: 0) {
            // Header
            header(info)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Description + metrics line
                    descriptionBlock(info)

                    // Parent chain breadcrumb
                    if info.parentChain.count > 1 {
                        parentChainRow(info)
                    }

                    Divider().padding(.horizontal, 24)

                    // Key-value rows
                    propertyRows(info)

                    // Command disclosure
                    commandSection(info)
                }
            }
            .frame(maxHeight: 480)

            Divider()

            // Action buttons
            actionBar(info)
        }
    }

    // MARK: - Header

    private func header(_ info: ProcessDetailInfo) -> some View {
        HStack(spacing: 12) {
            if selectedGroupInstance != nil {
                Button(action: returnToGroup) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondaryLight)
                        .frame(width: 28, height: 28)
                        .background(Color.borderLight.opacity(0.45))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Back to process group")
            }

            // App icon
            Group {
                if let icon = ProcessDetailService.appIcon(for: activeNode.commandLine) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.textTertiaryLight)
                }
            }
            .frame(width: 36, height: 36)

            Text(info.name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)
                .lineLimit(1)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hoverClose ? Color.textPrimaryLight : Color.textTertiaryLight)
                    .frame(width: 24, height: 24)
                    .background(hoverClose ? Color.borderLight : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hoverClose = $0 }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(Color.surfaceCardLight.opacity(0.78))
    }

    // MARK: - Description

    private func descriptionBlock(_ info: ProcessDetailInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let source = info.likelySource {
                Text("\(info.name) appears to belong to \(source). Evidence and confidence are shown below.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondaryLight)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Metrics line
            HStack(spacing: 0) {
                Text("PID \(info.pid)")
                metricDot
                Text("CPU \(String(format: "%.1f%%", info.cpuUsage))")
                metricDot
                Text("MEM \(info.memoryFormatted)")
                metricDot
                Text(info.user)
                if info.parentPID > 1 {
                    metricDot
                    Text("Parent process")
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Color.textTertiaryLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var metricDot: some View {
        Text(" · ")
            .font(.system(size: 10))
            .foregroundStyle(Color.textTertiaryLight)
    }

    // MARK: - Parent Chain

    private func parentChainRow(_ info: ProcessDetailInfo) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(info.parentChain.enumerated()), id: \.offset) { idx, entry in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.textTertiaryLight)
                    }

                    let isLast = idx == info.parentChain.count - 1
                    HStack(spacing: 3) {
                        Text(entry.name)
                            .font(.system(size: 11, weight: isLast ? .semibold : .regular))
                            .foregroundStyle(isLast ? Color.textPrimaryLight : Color.textSecondaryLight)
                        Text("\(entry.pid)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.textTertiaryLight)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Property Rows

    private func propertyRows(_ info: ProcessDetailInfo) -> some View {
        VStack(spacing: 0) {
            if let source = info.likelySource {
                propertyRow("Likely Source", source)
            }
            if info.appBundlePath != nil {
                propertyRow("Confidence", "Medium confidence")
            }
            if let bundle = info.appBundlePath {
                propertyRow("Evidence", bundle)
            }
            propertyRow("Threads", "\(info.threads)")
            propertyRow("Open Files", "\(info.openFiles)")
            propertyRow("Disk I/O", info.diskIOFormatted)
            if !info.listeningPorts.isEmpty {
                propertyRow("Listening ports", info.listeningPorts.joined(separator: ", "))
            }
            propertyRow("Children", "\(info.childCount)")
            propertyRow("User", info.user)
            propertyRow("Started", info.startedAgo)
            propertyRow("Working Directory", info.workingDirectory)
            propertyRow("Executable", info.executablePath)
        }
    }

    private func propertyRow(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
                    .frame(width: 120, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Color.borderLight.opacity(0.5))
                .frame(height: 1)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Command Section

    private func commandSection(_ info: ProcessDetailInfo) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showCommand.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showCommand ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Paths and Command 1")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.textSecondaryLight)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCommand {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Command")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiaryLight)

                    Text(info.commandLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.textSecondaryLight)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.borderLight.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Action Bar

    private func actionBar(_ info: ProcessDetailInfo) -> some View {
        HStack(spacing: 10) {
            Spacer()

            // Copy Summary
            actionButton(
                label: "Copy Summary",
                icon: "doc.on.doc",
                isHovered: $hoverCopy,
                color: Color.textSecondaryLight,
                bgColor: Color.borderLight.opacity(0.5)
            ) {
                let summary = ProcessDetailService.copySummary(info)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(summary, forType: .string)
            }

            // Reveal
            actionButton(
                label: "Reveal",
                icon: "folder",
                isHovered: $hoverReveal,
                color: Color.textSecondaryLight,
                bgColor: Color.borderLight.opacity(0.5)
            ) {
                ProcessDetailService.revealInFinder(commandLine: activeNode.commandLine)
            }

            if !isProtected {
                // Terminate
                actionButton(
                    label: "Terminate",
                    icon: "xmark.circle",
                    isHovered: $hoverTerminate,
                    color: Color.textSecondaryLight,
                    bgColor: Color.borderLight.opacity(0.5)
                ) {
                    finishTermination(ProcessTreeService.killProcess(activeNode))
                }

                // Force Quit
                actionButton(
                    label: "Force Quit",
                    icon: "xmark.circle.fill",
                    isHovered: $hoverForceQuit,
                    color: Color.accentRed,
                    bgColor: Color.accentRed.opacity(0.08)
                ) {
                    finishTermination(ProcessTreeService.forceKillProcess(activeNode))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.surfaceCardLight.opacity(0.76))
    }

    private func finishTermination(_ result: KillResult) {
        switch result {
        case .success:
            let killedNode = activeNode
            onKill?(killedNode)
            if selectedGroupInstance != nil {
                terminatedInstanceIDs.insert(killedNode.id)
                if visibleInstances.isEmpty {
                    onDismiss()
                } else {
                    returnToGroup()
                }
            } else {
                onDismiss()
            }
        case .protected(let reason), .failed(let reason):
            terminationError = reason
        }
    }

    private func actionButton(
        label: String,
        icon: String,
        isHovered: Binding<Bool>,
        color: Color,
        bgColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered.wrappedValue ? bgColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered.wrappedValue = $0 }
    }

    // MARK: - Loading

    private func loadDetail(for process: ProcessNode) {
        Task.detached(priority: .utility) {
            let info = ProcessDetailService.fetchDetail(for: process)
            await MainActor.run {
                guard selectedGroupInstance?.id == process.id || node.id == process.id else { return }
                detail = info
                isLoading = false
            }
        }
    }
}

// MARK: - Overlay Modifier

struct ProcessDetailOverlay: ViewModifier {
    @Binding var selectedProcess: ProcessNode?
    var onKill: ((ProcessNode) -> Void)? = nil

    func body(content: Content) -> some View {
        ZStack {
            content

            if let proc = selectedProcess {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { selectedProcess = nil }

                ProcessDetailView(
                    node: proc,
                    onDismiss: { selectedProcess = nil },
                    onKill: onKill
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: selectedProcess != nil)
    }
}

extension View {
    func processDetailOverlay(
        selectedProcess: Binding<ProcessNode?>,
        onKill: ((ProcessNode) -> Void)? = nil
    ) -> some View {
        modifier(ProcessDetailOverlay(selectedProcess: selectedProcess, onKill: onKill))
    }
}
