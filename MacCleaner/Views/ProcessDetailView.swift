import SwiftUI
import AppKit

// MARK: - NSVisualEffectView wrapper for frosted glass

private struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

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

    private var isProtected: Bool { ProcessTreeService.isProtected(node) }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if let info = detail {
                detailContent(info)
            }
        }
        .frame(width: 520)
        .background(
            ZStack {
                VisualEffectBlur(material: .sheet, blendingMode: .behindWindow)
                Color.white.opacity(0.88)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.borderLight, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
        .onAppear { loadDetail() }
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
            // App icon
            Group {
                if let icon = ProcessDetailService.appIcon(for: node.commandLine) {
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
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiaryLight)
                    .frame(width: 120, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(value)
                    .font(.system(size: 12, weight: .medium))
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
                ProcessDetailService.revealInFinder(commandLine: node.commandLine)
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
                    finishTermination(ProcessTreeService.killProcess(node))
                }

                // Force Quit
                actionButton(
                    label: "Force Quit",
                    icon: "xmark.circle.fill",
                    isHovered: $hoverForceQuit,
                    color: Color.accentRed,
                    bgColor: Color.accentRed.opacity(0.08)
                ) {
                    finishTermination(ProcessTreeService.forceKillProcess(node))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func finishTermination(_ result: KillResult) {
        switch result {
        case .success:
            onKill?(node)
            onDismiss()
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

    private func loadDetail() {
        Task.detached(priority: .utility) {
            let info = ProcessDetailService.fetchDetail(for: node)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) {
                    detail = info
                    isLoading = false
                }
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
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedProcess != nil)
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
