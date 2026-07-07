import SwiftUI
import AppKit

struct WebAppsView: View {
    @ObservedObject var packager: PakePackager
    @State private var urlText = ""
    @State private var showEfficiency = false
    @State private var efficiencyAnimated = false
    @State private var pendingDeleteApp: InstalledWebApp? = nil
    @State private var showDeleteConfirm = false
    private let contentMaxWidth: CGFloat = 980
    private let contentHorizontalPadding: CGFloat = 28

    private var cardMaxWidth: CGFloat {
        contentMaxWidth - contentHorizontalPadding * 2
    }

    private var composerRowMaxWidth: CGFloat {
        cardMaxWidth
    }

    private let presets: [WebAppPreset] = [
        WebAppPreset(name: "ChatGPT", description: "OpenAI assistant for everyday work, coding, writing, and research.", url: "https://chatgpt.com", icon: "icon_chatgpt", accent: .accentGreen),
        WebAppPreset(name: "Gemini", description: "Google AI assistant for multimodal tasks, search-backed research, and drafting.", url: "https://gemini.google.com", icon: "icon_gemini", accent: .accentBlue),
        WebAppPreset(name: "Claude", description: "Anthropic assistant for documents, coding, and long-context analysis.", url: "https://claude.ai", icon: "icon_claude", accent: .accentAmber),
        WebAppPreset(name: "Claude Code", description: "Anthropic coding assistant for agentic software development.", url: "https://claude.ai/code", icon: "icon_claude_code", accent: .accentAmber),
        WebAppPreset(name: "Perplexity", description: "Answer engine for web research with source-oriented results.", url: "https://www.perplexity.ai", icon: "icon_perplexity", accent: .accentBlue),
        WebAppPreset(name: "Discord", description: "Communities, team chats, calls, and persistent channels.", url: "https://discord.com/app", icon: "icon_discord", accent: .accentBlue),
        WebAppPreset(name: "YouTube", description: "Video platform for channels, playlists, subscriptions, and research.", url: "https://www.youtube.com", icon: "icon_youtube", accent: .accentRed),
        WebAppPreset(name: "GitHub", description: "Code hosting, pull requests, issues, projects, and notifications.", url: "https://github.com", icon: "icon_github", accent: .textPrimaryLight),
        WebAppPreset(name: "Figma", description: "Collaborative design files, prototypes, and product mockups.", url: "https://www.figma.com", icon: "icon_figma", accent: .accentPurple),
        WebAppPreset(name: "Notion", description: "Workspace for docs, notes, databases, and project pages.", url: "https://www.notion.so", icon: "icon_notion", accent: .textPrimaryLight),
        WebAppPreset(name: "Linear", description: "Issue tracking, product planning, cycles, and team workflows.", url: "https://linear.app", icon: "icon_linear", accent: .accentPurple),
        WebAppPreset(name: "Slack", description: "Team messaging, channels, huddles, and work notifications.", url: "https://app.slack.com/client", icon: "icon_slack", accent: .accentGreen)
    ]

    private var visiblePresets: [WebAppPreset] {
        let installedNames = Set(packager.installedApps.map { normalizedName($0.name) })
        return presets.filter { !installedNames.contains(normalizedName($0.name)) }
    }

    var body: some View {
        content
        .background(Color.surfaceLight)
        .onAppear {
            packager.refreshInstalledApps(matching: presets)
        }
        .alert("Delete web app", isPresented: $showDeleteConfirm) {
            Button("Move to Trash", role: .destructive) {
                if let pendingDeleteApp {
                    packager.deleteInstalledApp(pendingDeleteApp)
                    self.pendingDeleteApp = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteApp = nil
            }
        } message: {
            Text("Move \(pendingDeleteApp?.name ?? "this app") to Trash?")
        }
        .onDisappear {
            packager.dismissStatus()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 14)
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceLight)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showEfficiency {
                        efficiencyPanel
                            .transition(.asymmetric(
                                insertion: .push(from: .top).combined(with: .opacity),
                                removal: .push(from: .bottom).combined(with: .opacity)
                            ))
                    }

                    if !packager.installedApps.isEmpty {
                        installedSection
                    }
                    if !visiblePresets.isEmpty {
                        presetsSection
                    }
                }
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.vertical, 18)
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            bottomComposer
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 38, height: 38)
                .background(Color.accentBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Pake Apps")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)

                    Button(action: toggleEfficiencyPanel) {
                        Image(systemName: showEfficiency ? "bolt.fill" : "bolt")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(showEfficiency ? Color.accentBlue : Color.textTertiaryLight)
                            .frame(width: 18, height: 18)
                            .background(showEfficiency ? Color.accentBlue.opacity(0.10) : Color.surfaceCardLight)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(
                                showEfficiency ? Color.accentBlue.opacity(0.3) : Color.borderLight,
                                lineWidth: 1
                            ))
                    }
                    .buttonStyle(.plain)
                }

                Text("Turn any website into a lightweight standalone macOS app in seconds.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondaryLight)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Installed apps")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)

                Spacer()

                Button("Refresh") {
                    packager.refreshInstalledApps(matching: presets)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
            }

            VStack(spacing: 8) {
                ForEach(packager.installedApps) { app in
                    InstalledWebAppRow(
                        app: app,
                        openAction: {
                            packager.openInstalledApp(app.url)
                        },
                        deleteAction: {
                            pendingDeleteApp = app
                            showDeleteConfirm = true
                        }
                    )
                }
            }
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preset apps")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)

            VStack(spacing: 8) {
                ForEach(visiblePresets) { preset in
                    WebAppPresetRow(
                        preset: preset,
                        isPackaging: packager.isPackaging && packager.activeAppName == preset.name
                    ) {
                        packager.package(urlString: preset.url, appName: preset.name)
                    }
                }
            }
        }
    }

    private var efficiencyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        Text("Pake uses ")
                            .foregroundStyle(Color.textSecondaryLight)
                        Text("Rust")
                            .foregroundStyle(Color.accentBlue)
                            .fontWeight(.semibold)
                        Text(" and ")
                            .foregroundStyle(Color.textSecondaryLight)
                        Text("Tauri")
                            .foregroundStyle(Color.accentBlue)
                            .fontWeight(.semibold)
                        Text(" to wrap websites without bundling a full browser engine.")
                            .foregroundStyle(Color.textSecondaryLight)
                    }
                    .font(.system(size: 12))

                    HStack(spacing: 6) {
                        Text("For more details, see")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiaryLight)
                        Link(destination: URL(string: "https://github.com/tw93/Pake")!) {
                            HStack(spacing: 5) {
                                Image("icon_github")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 10, height: 10)
                                Text("GitHub")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.accentBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentBlue.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentBlue.opacity(0.22), lineWidth: 1))
                        }
                    }
                }

                Spacer()

                Button(action: toggleEfficiencyPanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textTertiaryLight)
                        .frame(width: 20, height: 20)
                        .background(Color.surfaceLight)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderLight, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            VStack(spacing: 8) {
                EfficiencyBar(
                    icon: "archivebox",
                    label: "App size",
                    pakeValue: "~8 MB",
                    comparisonValue: "~150 MB Electron",
                    color: Color.accentGreen,
                    fraction: efficiencyAnimated ? 0.06 : 0
                )
                EfficiencyBar(
                    icon: "memorychip",
                    label: "Memory use",
                    pakeValue: "~150 MB",
                    comparisonValue: "~400 MB Electron",
                    color: Color.accentBlue,
                    fraction: efficiencyAnimated ? 0.38 : 0
                )
                EfficiencyBar(
                    icon: "bolt.fill",
                    label: "Startup weight",
                    pakeValue: "Low",
                    comparisonValue: "Higher bundled runtime",
                    color: Color.accentAmber,
                    fraction: efficiencyAnimated ? 0.42 : 0
                )
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Our ChatGPT test")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)

                    EfficiencyBar(
                        icon: "app.dashed",
                        label: "Local app size",
                        pakeValue: "10 MB",
                        comparisonValue: "149 MB official app",
                        color: Color.accentPurple,
                        fraction: efficiencyAnimated ? 0.07 : 0
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(" ")
                        .font(.system(size: 12, weight: .semibold))

                    EfficiencyBar(
                        icon: "memorychip",
                        label: "Local RAM idle",
                        pakeValue: "~65 MB",
                        comparisonValue: "~145–185 MB official app",
                        color: Color.accentBlue,
                        fraction: efficiencyAnimated ? 0.36 : 0
                    )
                }
            }
            .padding(10)
            .background(Color.surfaceLight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderLight, lineWidth: 1))

        }
        .padding(12)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderLight, lineWidth: 1))
    }

    private var bottomComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("https://example.com", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.surfaceCardLight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderLight, lineWidth: 1))
                    .onSubmit(packageCustomURL)

                Button(action: packageCustomURL) {
                    Label(packager.isPackaging ? "Packaging" : "Create app", systemImage: "shippingbox")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(packager.isPackaging ? Color.textTertiaryLight : Color.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(packager.isPackaging)
            }

            Text("Paste a URL to any website and it will be packaged as a standalone macOS app.")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiaryLight)
        }
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceLight)
        .overlay(Rectangle().fill(Color.borderLight).frame(height: 1), alignment: .top)
    }

    private func normalizedName(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }

    private func toggleEfficiencyPanel() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            showEfficiency.toggle()
            if showEfficiency { efficiencyAnimated = false }
        }
        if !showEfficiency { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.55)) { efficiencyAnimated = true }
        }
    }

    private func packageCustomURL() {
        guard let url = PakePackager.normalizedURL(from: urlText) else {
            packager.setValidationError("Invalid URL. Add a domain like chatgpt.com.")
            return
        }

        packager.package(url: url, appName: PakePackager.derivedAppName(from: url))
    }
}

// MARK: - Efficiency Bar

struct TechnologyChip: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.22), lineWidth: 1))
    }
}

struct EfficiencyBar: View {
    let icon: String
    let label: String
    let pakeValue: String
    let comparisonValue: String
    let color: Color
    let fraction: Double

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 7) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimaryLight)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.surfaceLight)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.borderLight, lineWidth: 1))

                        RoundedRectangle(cornerRadius: 5)
                            .fill(color.opacity(0.72))
                            .frame(width: max(8, geo.size.width * fraction))

                        Rectangle()
                            .fill(Color.textPrimaryLight.opacity(0.75))
                            .frame(width: 2)
                            .offset(x: max(8, geo.size.width * fraction) - 1)
                    }
                }
                .frame(height: 18)

                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle().fill(color.opacity(0.72)).frame(width: 6, height: 6)
                        Text("Pake: \(pakeValue)")
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color.surfaceLight).frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color.borderLight, lineWidth: 1))
                        Text(comparisonValue)
                    }
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Color.textTertiaryLight)
            }
        }
    }
}

struct PakeStatusPanel: View {
    @ObservedObject var packager: PakePackager

    var body: some View {
        Group {
            if packager.shouldShowStatus {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    PackagingStatusGlyph(
                        isPackaging: packager.isPackaging,
                        isError: packager.lastResultWasError,
                        progress: packager.progress
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(packager.statusTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.textPrimaryLight)

                            if packager.isPackaging {
                                Text("\(Int(packager.progress * 100))%")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.accentBlue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentBlue.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(packager.statusMessage ?? "Preparing package...")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondaryLight)
                            .lineLimit(2)
                    }

                    Spacer()

                    if let appURL = packager.lastBuiltAppURL, !packager.isPackaging, !packager.lastResultWasError {
                        Button("Open") {
                            packager.openInstalledApp(appURL)
                            packager.dismissStatus()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }

                    Button {
                        packager.dismissStatus()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textTertiaryLight)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                if packager.isPackaging {
                    ProgressView(value: packager.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.accentBlue)
                }
            }
            .padding(14)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderLight, lineWidth: 1))
            .shadow(color: Color.shadowLight, radius: 8, x: 0, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.22), value: packager.shouldShowStatus)
            }
        }
    }
}

@MainActor
final class PakePackager: ObservableObject {
    @Published var isPackaging = false
    @Published var statusMessage: String?
    @Published var statusTitle = "Packaging"
    @Published var activeAppName: String?
    @Published var lastResultWasError = false
    @Published var progress: Double = 0
    @Published var lastBuiltAppURL: URL?
    @Published var installedApps: [InstalledWebApp] = []
    @Published private var statusDismissed = true
    private var knownPresets: [WebAppPreset] = []
    private var storedApps: [String: StoredWebAppInfo] = PakePackager.loadStoredApps()

    var shouldShowStatus: Bool {
        !statusDismissed && (isPackaging || statusMessage != nil)
    }

    private let outputDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .appendingPathComponent("Pake Apps")
    }()

    func package(urlString: String, appName: String) {
        guard let url = Self.normalizedURL(from: urlString) else {
            setValidationError("Invalid preset URL: \(urlString)")
            return
        }

        package(url: url, appName: appName)
    }

    func package(url: URL, appName: String) {
        guard !isPackaging else { return }

        let cleanName = Self.sanitizedAppName(appName)
        guard !cleanName.isEmpty else {
            setValidationError("Could not derive app name from URL.")
            return
        }

        if let existingApp = existingAppURL(named: cleanName) {
            rememberInstalledApp(name: cleanName, sourceURL: url.absoluteString)
            lastBuiltAppURL = existingApp
            statusTitle = "\(cleanName) is ready"
            statusMessage = "App already exists. Click Open to launch it."
            lastResultWasError = false
            isPackaging = false
            progress = 1
            statusDismissed = false
            refreshInstalledApps()
            return
        }

        isPackaging = true
        activeAppName = cleanName
        lastResultWasError = false
        lastBuiltAppURL = nil
        statusDismissed = false
        progress = 0.04
        statusTitle = "Packaging \(cleanName)"
        statusMessage = "Building a standalone macOS app with Pake…"
        animateProgress()

        Task.detached(priority: .utility) { [outputDirectory] in
            let result = Self.runPake(url: url, appName: cleanName, outputDirectory: outputDirectory)

            await MainActor.run {
                self.isPackaging = false
                self.activeAppName = nil
                self.progress = result.success ? 1 : self.progress
                self.lastResultWasError = !result.success

                if result.success, let appURL = self.findBuiltApp(named: cleanName) {
                    self.rememberInstalledApp(name: cleanName, sourceURL: url.absoluteString)
                    self.lastBuiltAppURL = appURL
                    self.statusTitle = "\(cleanName) created"
                    self.statusMessage = "Done. Click Open to launch the app."
                    self.refreshInstalledApps()
                } else if result.success {
                    self.statusTitle = "Packaging finished"
                    self.statusMessage = "\(cleanName).app was not found in the output folder."
                    self.lastResultWasError = true
                } else {
                    self.statusTitle = "Packaging failed"
                    self.statusMessage = result.userMessage
                }
            }
        }
    }

    func setValidationError(_ message: String) {
        statusTitle = "Check URL"
        statusMessage = message
        activeAppName = nil
        lastBuiltAppURL = nil
        lastResultWasError = true
        isPackaging = false
        statusDismissed = false
    }

    func dismissStatus() {
        guard !isPackaging else { return }
        statusDismissed = true
    }

    func openInstalledApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func deleteInstalledApp(_ app: InstalledWebApp) {
        guard !isPackaging else { return }

        Task {
            await deleteInstalledAppBundle(app)
        }
    }

    private func deleteInstalledAppBundle(_ app: InstalledWebApp) async {
        do {
            await terminateRunningApp(for: app)
            try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
            storedApps.removeValue(forKey: Self.normalizedName(app.name))
            if let presetName = app.presetName {
                storedApps.removeValue(forKey: Self.normalizedName(presetName))
            }
            Self.saveStoredApps(storedApps)
            refreshInstalledApps()
            lastBuiltAppURL = nil
            lastResultWasError = false
            isPackaging = false
            statusMessage = nil
            statusDismissed = true
        } catch {
            statusTitle = "Delete failed"
            statusMessage = "Failed to delete \(app.presetName ?? app.name)."
            lastBuiltAppURL = nil
            lastResultWasError = true
            isPackaging = false
            statusDismissed = false
        }
    }

    private func terminateRunningApp(for app: InstalledWebApp) async {
        let runningApps = NSWorkspace.shared.runningApplications.filter { runningApp in
            if let bundleURL = runningApp.bundleURL?.standardizedFileURL,
               bundleURL == app.url.standardizedFileURL {
                return true
            }

            if let localizedName = runningApp.localizedName {
                return Self.namesMatch(localizedName, app.name)
                    || app.presetName.map { Self.namesMatch(localizedName, $0) } == true
            }

            return false
        }

        guard !runningApps.isEmpty else { return }

        runningApps.forEach { $0.terminate() }
        if await waitForTermination(of: runningApps, attempts: 20) {
            return
        }

        runningApps
            .filter { !$0.isTerminated }
            .forEach { $0.forceTerminate() }
        _ = await waitForTermination(of: runningApps, attempts: 10)
    }

    private func waitForTermination(of runningApps: [NSRunningApplication], attempts: Int) async -> Bool {
        for _ in 0..<attempts {
            if runningApps.allSatisfy(\.isTerminated) {
                return true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return runningApps.allSatisfy(\.isTerminated)
    }

    func refreshInstalledApps(matching presets: [WebAppPreset] = []) {
        if !presets.isEmpty {
            knownPresets = presets
        }

        installedApps = installedAppURLs()
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                let preset = knownPresets.first { Self.namesMatch($0.name, name) }
                let stored = storedApps[Self.normalizedName(name)]

                return InstalledWebApp(
                    name: name,
                    url: url,
                    presetName: preset?.name,
                    description: preset?.description ?? stored?.description ?? "Created from a web app with Pake.",
                    sourceURL: preset?.url ?? stored?.sourceURL,
                    icon: preset?.icon ?? "app.dashed",
                    accent: preset?.accent ?? .accentBlue
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func normalizedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let host = url.host,
              host.contains(".") else {
            return nil
        }

        return url
    }

    nonisolated static func derivedAppName(from url: URL) -> String {
        let host = (url.host ?? "WebApp")
            .replacingOccurrences(of: "www.", with: "")
            .split(separator: ".")
            .first
            .map(String.init) ?? "WebApp"

        return sanitizedAppName(host)
    }

    nonisolated private static func sanitizedAppName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let filteredScalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let words = String(filteredScalars).split(separator: " ")

        return words
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    nonisolated private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedName(lhs) == normalizedName(rhs)
    }

    nonisolated private static func normalizedName(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }

    nonisolated private static func runPake(url: URL, appName: String, outputDirectory: URL) -> PakeRunResult {
        let firstAttempt = runPakeAttempt(url: url, appName: appName, outputDirectory: outputDirectory, useCnMirror: false)
        guard !firstAttempt.success, firstAttempt.shouldRetryWithCnMirror else {
            return firstAttempt
        }

        let retry = runPakeAttempt(url: url, appName: appName, outputDirectory: outputDirectory, useCnMirror: true)
        if retry.success {
            return retry
        }

        return PakeRunResult(
            success: false,
            userMessage: "Pake failed after retrying with CN mirrors. \(retry.userMessage)",
            shouldRetryWithCnMirror: false
        )
    }

    nonisolated private static func runPakeAttempt(url: URL, appName: String, outputDirectory: URL, useCnMirror: Bool) -> PakeRunResult {
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = outputDirectory
            process.arguments = ["pake", url.absoluteString, "--name", appName]
            process.environment = processEnvironment(useCnMirror: useCnMirror)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let outputBuffer = ProcessOutputBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                outputBuffer.append(chunk)
            }

            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in semaphore.signal() }
            try process.run()
            if semaphore.wait(timeout: .now() + 300) == .timedOut {
                process.terminate()
                pipe.fileHandleForReading.readabilityHandler = nil
                return PakeRunResult(
                    success: false,
                    userMessage: "Pake timed out while installing dependencies.",
                    shouldRetryWithCnMirror: !useCnMirror
                )
            }

            pipe.fileHandleForReading.readabilityHandler = nil
            let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
            outputBuffer.append(remainingData)
            let data = outputBuffer.data()
            let log = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                return PakeRunResult(success: true, userMessage: "Pake finished.", shouldRetryWithCnMirror: false)
            }

            let shouldRetryWithCnMirror = !useCnMirror && Self.shouldRetryPakeWithCnMirror(log)
            let message: String
            if process.terminationStatus == 127 || log.localizedCaseInsensitiveContains("not found") {
                message = "Pake CLI is not installed or not available in PATH."
            } else if log.localizedCaseInsensitiveContains("permission") {
                message = "Pake failed because of a permission issue."
            } else if log.localizedCaseInsensitiveContains("rust") {
                message = "Pake needs a working Rust toolchain before packaging."
            } else if log.localizedCaseInsensitiveContains("network") || log.localizedCaseInsensitiveContains("timed out") {
                message = "Pake failed while downloading dependencies or website assets."
            } else if log.localizedCaseInsensitiveContains("installing package") || log.localizedCaseInsensitiveContains("npm install") {
                message = useCnMirror
                    ? "Pake failed while installing its dependencies with CN mirrors. \(Self.shortLogSummary(log))"
                    : "Pake failed while installing its dependencies. Retrying with CN mirrors..."
            } else {
                let summary = Self.shortLogSummary(log)
                message = summary.isEmpty
                    ? "Pake failed with exit code \(process.terminationStatus)."
                    : "Pake failed with exit code \(process.terminationStatus). \(summary)"
            }

            return PakeRunResult(success: false, userMessage: message, shouldRetryWithCnMirror: shouldRetryWithCnMirror)
        } catch {
            return PakeRunResult(success: false, userMessage: "Could not start Pake CLI.", shouldRetryWithCnMirror: false)
        }
    }

    nonisolated private static func processEnvironment(useCnMirror: Bool) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PAKE_CREATE_APP"] = "1"
        if useCnMirror {
            environment["PAKE_USE_CN_MIRROR"] = "1"
        }

        let existingPath = environment["PATH"] ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = "\(home)/Library/pnpm:\(home)/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = existingPath.isEmpty ? commonPaths : "\(commonPaths):\(existingPath)"

        return environment
    }

    nonisolated private static func shouldRetryPakeWithCnMirror(_ log: String) -> Bool {
        let lower = log.lowercased()
        return lower.contains("pake_use_cn_mirror=1")
            || lower.contains("downloads are slow in china")
            || lower.contains("using npm for package management")
            || lower.contains("installation failed")
    }

    nonisolated private static func shortLogSummary(_ log: String) -> String {
        let cleanedLines = log
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("objc[") }

        return cleanedLines.suffix(3).joined(separator: " ")
    }

    private func rememberInstalledApp(name: String, sourceURL: String) {
        let key = Self.normalizedName(name)
        storedApps[key] = StoredWebAppInfo(name: name, sourceURL: sourceURL, description: "Created from a web app with Pake.")
        Self.saveStoredApps(storedApps)
        refreshInstalledApps()
    }

    nonisolated private static func loadStoredApps() -> [String: StoredWebAppInfo] {
        guard let data = UserDefaults.standard.data(forKey: "pakeWebAppsRegistry"),
              let decoded = try? JSONDecoder().decode([String: StoredWebAppInfo].self, from: data) else {
            return [:]
        }

        return decoded
    }

    nonisolated private static func saveStoredApps(_ apps: [String: StoredWebAppInfo]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: "pakeWebAppsRegistry")
    }

    private func animateProgress() {
        Task { @MainActor in
            while isPackaging {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard isPackaging else { break }
                let ceiling = 0.92
                let remaining = ceiling - progress
                if remaining > 0.01 {
                    progress += max(0.01, remaining * 0.18)
                }
            }
        }
    }

    private func existingAppURL(named appName: String) -> URL? {
        installedAppURLs().first {
            $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }
    }

    private func findBuiltApp(named appName: String) -> URL? {
        if let existing = existingAppURL(named: appName) {
            return existing
        }

        guard let enumerator = FileManager.default.enumerator(
            at: outputDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            if url.pathExtension == "app" && url.deletingPathExtension().lastPathComponent == appName {
                return url
            }
        }

        return nil
    }

    private func installedAppURLs() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { $0.pathExtension == "app" }
    }
}

private struct PakeRunResult {
    let success: Bool
    let userMessage: String
    let shouldRetryWithCnMirror: Bool
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private var value = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        lock.lock()
        value.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let copy = value
        lock.unlock()
        return copy
    }
}

struct WebAppPreset: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let url: String
    let icon: String
    let accent: Color
}

struct InstalledWebApp: Identifiable {
    var id: String { url.path }
    let name: String
    let url: URL
    let presetName: String?
    let description: String
    let sourceURL: String?
    let icon: String
    let accent: Color
}

private struct StoredWebAppInfo: Codable {
    let name: String
    let sourceURL: String
    let description: String
}

private struct PackagingStatusGlyph: View {
    let isPackaging: Bool
    let isError: Bool
    let progress: Double
    @State private var rotating = false
    @State private var successScale = 0.7

    var body: some View {
        ZStack {
            if isPackaging {
                Circle()
                    .stroke(Color.accentBlue.opacity(0.16), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(Color.accentBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(rotating ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
                    .onAppear { rotating = true }
            } else {
                Circle()
                    .fill((isError ? Color.accentRed : Color.accentGreen).opacity(0.14))
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isError ? Color.accentRed : Color.accentGreen)
                    .scaleEffect(successScale)
                    .animation(.spring(response: 0.35, dampingFraction: 0.55), value: successScale)
                    .onAppear { successScale = 1 }
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(isPackaging ? "Packaging \(Int(progress * 100)) percent" : (isError ? "Packaging failed" : "Packaging complete"))
    }
}

private struct WebAppIconView: View {
    let name: String
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(accent.opacity(0.12))

            if name.hasPrefix("icon_") {
                Image(name)
                    .resizable()
                    .renderingMode(name == "icon_discord" ? .original : .template)
                    .scaledToFit()
                    .foregroundStyle(accent)
                    .frame(width: name == "icon_discord" ? 22 : 19, height: name == "icon_discord" ? 22 : 19)
            } else {
                Image(systemName: name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 34, height: 34)
    }
}

private struct InstalledWebAppRow: View {
    let app: InstalledWebApp
    let openAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            WebAppIconView(name: app.icon, accent: app.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text(app.presetName ?? app.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)

                Text(app.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondaryLight)
                    .lineLimit(1)

                if let sourceURL = app.sourceURL {
                    PakeCommandTokens(url: sourceURL, name: app.presetName ?? app.name)
                } else {
                    Text(app.url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: openAction) {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentBlue)

                Button(action: deleteAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiaryLight)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCardLight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderLight, lineWidth: 1))
        .shadow(color: Color.shadowLight, radius: 6, x: 0, y: 2)
    }
}

private struct WebAppPresetRow: View {
    let preset: WebAppPreset
    let isPackaging: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                WebAppIconView(name: preset.icon, accent: preset.accent)

                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)

                    Text(preset.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondaryLight)
                        .lineLimit(1)

                    PakeCommandTokens(url: preset.url, name: preset.name)
                }

                Spacer()

                if isPackaging {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    Label("Create", systemImage: "shippingbox")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceCardLight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borderLight, lineWidth: 1))
            .shadow(color: Color.shadowLight, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct PakeCommandTokens: View {
    let url: String
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            token("pake")
            Text(url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textSecondaryLight)
                .lineLimit(1)
            token("--name")
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textSecondaryLight)
                .lineLimit(1)
        }
    }

    private func token(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.accentBlue)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.accentBlue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
