import Foundation
import Cocoa
import CoreGraphics
import SwiftUI

enum Tab: String, CaseIterable {
    case dashboard = "Dashboard"
    case about     = "About"
    case processes = "Processes"
    case fans      = "Fans"
    case cleaner   = "Optimize"
    case windows   = "Windows"
    case disk      = "Disk"
    case storage   = "Storage"
    case desktop = "Desktop"
    case webApps = "Pake Apps"
    case aiAgents = "Agents"
    case aiIndexes = "Indexes"
    case aiLibrary = "Library"
    case maintenance = "Utilities"

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .about:     return "info.circle"
        case .processes: return "cpu"
        case .fans:      return "fanblades"
        case .cleaner:   return "sparkles"
        case .windows:   return "macwindow.on.rectangle"
        case .disk:      return "internaldrive"
        case .storage: return "externaldrive.badge.timemachine"
        case .desktop: return "desktopcomputer"
        case .webApps: return "globe.badge.chevron.backward"
        case .aiAgents: return "cpu.fill"
        case .aiIndexes: return "point.3.connected.trianglepath.dotted"
        case .aiLibrary: return "books.vertical"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }
}

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var selectedTab: Tab = .dashboard
    @State private var ramCleaningFlow: RAMCleaningFlow = .idle
    @State private var cleanerOperationActive = false
    @State private var storageOperationActive = false
    @State private var storageAnalysisOperationActive = false
    @State private var desktopOperationActive = false
    @State private var cleanerSelectedTool: CleanerTool? = nil
    @State private var storageSelectedTool: InternalStorageTool? = nil
    @State private var showingLaunchIntro = true
    @State private var storageViewPrepared = false
    
    // Global state for Storage and Uninstaller tools
    @StateObject private var uninstallerService = UninstallerService()
    @StateObject private var analyzerService = StorageAnalyzerService()
    @StateObject private var storageWorkspace = StorageWorkspaceService()
    @StateObject private var desktopService = DesktopService()
    @StateObject private var cleanerViewState = CleanerViewState()
    @StateObject private var webAppsPackager = PakePackager()
    @StateObject private var updateService = UpdateService.shared

    @StateObject private var themeManager = ThemeManager.shared

    private var isCleanerWorking: Bool {
        ramCleaningFlow.isActive || cleanerOperationActive
    }

    private var isStorageWorking: Bool {
        storageOperationActive || storageAnalysisOperationActive || storageWorkspace.isWorking
            || uninstallerService.isScanning || analyzerService.isScanning || analyzerService.isScanningJunk
    }

    private var isDesktopWorking: Bool {
        desktopOperationActive || desktopService.isScanning || desktopService.isScanningDesktopSummary
    }
    
    private var isWebAppsOverlayActive: Bool {
        selectedTab == .webApps && webAppsPackager.shouldShowStatus
    }

    var body: some View {
        ZStack {
            mainContent
                .blur(radius: isWebAppsOverlayActive ? 8 : 0)
                .disabled(isWebAppsOverlayActive || showingLaunchIntro)

            if isWebAppsOverlayActive {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .transition(.opacity)

                PakeStatusPanel(packager: webAppsPackager)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 640)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if showingLaunchIntro {
                LaunchIntroView {
                    showingLaunchIntro = false
                }
                .zIndex(10)
                .transition(.opacity)
            }
        }
        .background(Color.surfaceLight)
        .animation(.easeInOut(duration: 0.22), value: isWebAppsOverlayActive)
        .animation(.easeInOut(duration: 0.36), value: showingLaunchIntro)
        .preferredColorScheme(themeManager.effectiveColorScheme)
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            SidebarView(
                selectedTab: $selectedTab,
                monitor: monitor,
                isCleanerWorking: isCleanerWorking,
                isStorageWorking: isStorageWorking,
                isDesktopWorking: isDesktopWorking,
                cleanerMode: $cleanerViewState.mode
            )
                .frame(width: 240)
                .frame(maxHeight: .infinity, alignment: .top)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

            Rectangle()
                .fill(Color.borderLight)
                .frame(width: 1)

            VStack(spacing: 0) {
                ZStack {
                    switch selectedTab {
                    case .dashboard: DashboardView(monitor: monitor)
                    case .about:     AboutView(monitor: monitor)
                    case .processes: ProcessesView(monitor: monitor)
                    case .fans:      FansView(monitor: monitor)
                    case .cleaner:
                        CleanerView(
                            monitor: monitor,
                            state: cleanerViewState,
                            activeTool: $cleanerSelectedTool,
                            ramFlow: $ramCleaningFlow,
                            operationActive: $cleanerOperationActive
                        )
                    case .windows:   WindowsView(monitor: monitor)
                    case .disk:      DiskDetailView(monitor: monitor)
                    case .storage:
                        Color.clear
                    case .desktop:
                        DesktopManagerView(service: desktopService, operationActive: $desktopOperationActive)
                    case .webApps:
                        WebAppsView(packager: webAppsPackager)
                    case .aiAgents: AIAgentsView(monitor: monitor)
                    case .aiIndexes: AILoadView(monitor: monitor)
                    case .aiLibrary: AILibraryView()
                    case .maintenance: MaintenanceView()
                    }

                    if storageViewPrepared {
                        StorageView(
                            selectedTool: $storageSelectedTool,
                            uninstallerService: uninstallerService,
                            analyzerService: analyzerService,
                            storageWorkspace: storageWorkspace,
                            operationActive: $storageOperationActive,
                            analysisOperationActive: $storageAnalysisOperationActive
                        )
                        .opacity(selectedTab == .storage ? 1 : 0)
                        .allowsHitTesting(selectedTab == .storage)
                        .accessibilityHidden(selectedTab != .storage)
                        .zIndex(selectedTab == .storage ? 1 : -1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surfaceLight)
                
                // Footer with version and theme toggle
                AppFooter(
                    version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                    updateService: updateService
                )
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .background(Color.surfaceLight)
        .onChange(of: storageWorkspace.isWorking) { isWorking in
            storageAnalysisOperationActive = isWorking
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                updateService.checkInBackground()
            }
            guard !storageViewPrepared else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                storageViewPrepared = true
            }
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: Tab
    @ObservedObject var monitor: SystemMonitor
    let isCleanerWorking: Bool
    let isStorageWorking: Bool
    let isDesktopWorking: Bool
    @Binding var cleanerMode: CleanerMode

    private var ramColor: Color {
        monitor.memory.usedPercent > 0.85 ? .accentRed
            : monitor.memory.usedPercent > 0.65 ? .accentAmber : .accentGreen
    }
    private var cpuColor: Color {
        monitor.cpu.totalUsage > 0.85 ? .accentRed
            : monitor.cpu.totalUsage > 0.65 ? .accentAmber : .textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App name
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text("MacCleaner")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Nav — main tabs
            VStack(spacing: 4) {
                ForEach([Tab.dashboard, .processes, .fans, .disk], id: \.self) { tab in
                    SidebarItemLight(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }

                // Divider before Cleaner
                HStack {
                    Rectangle().fill(Color.borderLight).frame(height: 1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                CleanerSidebarItem(
                    isSelected: selectedTab == .cleaner,
                    isWorking: isCleanerWorking,
                    mode: $cleanerMode
                ) {
                    selectedTab = .cleaner
                }

                SidebarItemLight(tab: .storage, isSelected: selectedTab == .storage, isWorking: isStorageWorking) {
                    selectedTab = .storage
                }

                SidebarItemLight(tab: .desktop, isSelected: selectedTab == .desktop, isWorking: isDesktopWorking) {
                    selectedTab = .desktop
                }

                SidebarItemLight(tab: .webApps, isSelected: selectedTab == .webApps) {
                    selectedTab = .webApps
                }

                HStack {
                    Rectangle().fill(Color.borderLight).frame(height: 1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

                ForEach([Tab.aiAgents, .aiLibrary], id: \.self) { tab in
                    SidebarItemLight(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }

                // Tools
                HStack {
                    Rectangle().fill(Color.borderLight).frame(height: 1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ToolSidebarButton(
                    title: "Tools",
                    icon: "wrench.and.screwdriver",
                    isSelected: selectedTab == .maintenance
                ) {
                    selectedTab = .maintenance
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Live stats in glass cards
            VStack(spacing: 8) {
                StatCardLight(
                    label: "Memory",
                    value: String(format: "%.0f%%", monitor.memory.usedPercent * 100),
                    color: ramColor
                )
                
                StatCardLight(
                    label: "CPU",
                    value: String(format: "%.0f%%", monitor.cpu.totalUsage * 100),
                    color: cpuColor
                )
            }
            .padding(.horizontal, 12)

            // About at bottom
            Button(action: { selectedTab = .about }) {
                HStack(spacing: 8) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 10))
                    Text(HardwareInfo.macModelName)
                        .font(.system(size: 10))
                    Spacer()
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .opacity(0.5)
                }
                .foregroundStyle(Color.textTertiaryLight)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.surfaceLight)
    }
}

private struct ToolSidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentBlue : Color.textSecondaryLight)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.textPrimaryLight : Color.textSecondaryLight)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white : Color.clear)
                    .shadow(color: isSelected ? Color.shadowMedium : .clear, radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SidebarItem: View {
    let tab: Tab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
                    .frame(width: 18)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accent.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SidebarStatRow: View {
    let label: String
    let value: Double
    let text: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(.textTertiary)
                Spacer()
                Text(text)
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(color)
            }
            MiniBar(value: value, color: color, height: 2)
        }
    }
}

struct CleaningActivityIndicator: View {
    var color: Color
    var size: CGFloat = 12
    @State private var isRotating = false
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: max(1, size * 0.14))

            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: max(1.5, size * 0.16), lineCap: .round)
                )
                .rotationEffect(.degrees(isRotating ? 360 : 0))

            Circle()
                .fill(color.opacity(0.18))
                .scaleEffect(isPulsing ? 1.35 : 0.8)
                .opacity(isPulsing ? 0.05 : 0.35)
        }
        .frame(width: size, height: size)
        .onAppear {
            isRotating = true
            isPulsing = true
        }
        .animation(.linear(duration: 0.85).repeatForever(autoreverses: false), value: isRotating)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
        .accessibilityLabel("Cleaner is running")
    }
}

// MARK: - Light Theme Sidebar Components

struct SidebarItemLight: View {
    let tab: Tab
    let isSelected: Bool
    var isWorking: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentBlue : Color.textSecondaryLight)
                    .frame(width: 20)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.textPrimaryLight : Color.textSecondaryLight)
                if isWorking {
                    CleaningActivityIndicator(color: .accentBlue, size: 11)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white : Color.clear)
                    .shadow(color: isSelected ? Color.shadowMedium : .clear, radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CleanerSidebarItem: View {
    let isSelected: Bool
    let isWorking: Bool
    @Binding var mode: CleanerMode
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: Tab.cleaner.icon)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(isSelected ? Color.accentBlue : Color.textSecondaryLight)
                        .frame(width: 20)
                    Text(Tab.cleaner.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.textPrimaryLight : Color.textSecondaryLight)
                    if isWorking {
                        CleaningActivityIndicator(color: .accentBlue, size: 11)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                HStack(spacing: 0) {
                    Button {
                        mode = .professional
                    } label: {
                        Text("Pro")
                            .font(.system(size: 9, weight: mode == .professional ? .semibold : .medium))
                            .foregroundStyle(mode == .professional ? .white : Color.textSecondaryLight)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(mode == .professional ? Color.accentBlue : Color.surfaceCardLight)
                    }
                    .buttonStyle(.plain)

                    Button {
                        mode = .optimization
                    } label: {
                        Text("Opt")
                            .font(.system(size: 9, weight: mode == .optimization ? .semibold : .medium))
                            .foregroundStyle(mode == .optimization ? .white : Color.textSecondaryLight)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(mode == .optimization ? Color.accentBlue : Color.surfaceCardLight)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.surfaceCardLight)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.borderLight))
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white : Color.clear)
                .shadow(color: isSelected ? Color.shadowMedium : .clear, radius: 4, x: 0, y: 2)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct StatCardLight: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondaryLight)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: Color.shadowLight, radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.borderLight, lineWidth: 1)
        )
    }
}

// MARK: - Storage Home Screen Card

struct StorageToolCard: View {
    let tool: InternalStorageTool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(tool.color.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: tool.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tool.color)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tool.rawValue)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(tool.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 20)
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            isHovered ? tool.color.opacity(0.5) : Color.borderSubtle,
                            lineWidth: isHovered ? 1.5 : 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Tool Splash Screen (shared by DiskMap / LargeFiles / Junk)

struct ToolSplashScreen: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        StorageFeatureEmptyState(
            icon: icon,
            color: color,
            title: title,
            subtitle: subtitle,
            actionTitle: buttonTitle,
            actionIcon: icon,
            action: action
        )
    }
}

// MARK: - Scanning Placeholder

struct ScanningPlaceholder: View {
    let icon: String
    let color: Color
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(color.opacity(0.10)).frame(width: 110, height: 110)
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Color.textSecondary)
            ProgressView().tint(color)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


enum UninstallerSortOrder: String, CaseIterable {
    case lastUsed = "Last opened"
    case name = "A–Z"
    case installationDate = "Date added"
}

struct UninstallerView: View {
    @ObservedObject var service: UninstallerService
    @Binding var operationActive: Bool
    @State private var selectedAppId: UUID?
    @State private var isUninstalling = false
    @State private var isSuccess = false
    @State private var sortOrder: UninstallerSortOrder = .lastUsed
    
    var sortedApps: [InstalledApp] {
        switch sortOrder {
        case .lastUsed:
            return service.apps.sorted { lhs, rhs in
                switch (lhs.lastUsed, rhs.lastUsed) {
                case let (l?, r?): return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        case .name:
            return service.apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .installationDate:
            return service.apps.sorted { lhs, rhs in
                switch (lhs.installationDate, rhs.installationDate) {
                case let (l?, r?): return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }
    
    var selectedAppIndex: Int? {
        service.apps.firstIndex { $0.id == selectedAppId }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left list
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Applications")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)

                    Spacer()

                    Menu {
                        ForEach(UninstallerSortOrder.allCases, id: \.self) { order in
                            Button(action: { sortOrder = order }) {
                                if sortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sortOrder.rawValue)
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(Color.textSecondaryLight)
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(service.isScanning || isUninstalling)

                    Button(action: { service.scan() }) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(service.isScanning ? 360 : 0))
                            .animation(service.isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: service.isScanning)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(service.isScanning ? Color.textTertiaryLight : Color.accentBlue)
                    .disabled(service.isScanning || isUninstalling)
                }
                .padding(16)
                .background(Color.surfaceCardLight)

                if service.scanWasLimited, !service.isScanning {
                    HStack(spacing: 5) {
                        Image(systemName: "leaf.fill")
                        Text("All apps listed · some size estimates are partial after \(service.scannedEntryCount.formatted()) measured entries")
                            .lineLimit(2)
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.accentAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.surfaceCardLight)
                }

                Rectangle().fill(Color.borderLight).frame(height: 1)

                List(selection: $selectedAppId) {
                    ForEach(sortedApps) { app in
                        AppRow(app: app)
                            .tag(app.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.surfaceCardLight)
                .disabled(isUninstalling)
            }
            .frame(width: 260)
            
            Rectangle().fill(Color.borderLight).frame(width: 1)
            
            // Right detail
            if let selectedAppIndex {
                AppDetailView(app: $service.apps[selectedAppIndex], onUninstall: {
                    let app = service.apps[selectedAppIndex]
                    let alert = NSAlert()
                    alert.messageText = "Удалить \(app.name)?"
                    alert.informativeText = "Вы уверены, что хотите безвозвратно удалить \(app.name) и все связанные файлы?"
                    alert.addButton(withTitle: "Удалить")
                    alert.addButton(withTitle: "Отмена")
                    alert.alertStyle = .warning
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        operationActive = true
                        isUninstalling = true
                        isSuccess = false
                        service.uninstall(apps: [app]) { success in
                            withAnimation {
                                if success {
                                    isSuccess = true
                                } else {
                                    isUninstalling = false
                                    operationActive = false
                                }
                            }
                            
                            if success {
                                // Wait 2 seconds before removing from UI
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation {
                                        service.apps.removeAll { $0.id == app.id }
                                        isUninstalling = false
                                        operationActive = false
                                        isSuccess = false
                                        selectedAppId = nil
                                    }
                                }
                            }
                        }
                    }
                }, isUninstalling: isUninstalling, isSuccess: isSuccess)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textTertiaryLight)
                    Text("Select an application")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondaryLight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surfaceLight)
            }
        }
        .background(Color.surfaceLight)
        .onAppear {
            if service.apps.isEmpty {
                service.scan()
            }
        }
    }
}

struct AppRow: View {
    let app: InstalledApp
    
    private var isStale: Bool {
        guard let date = app.lastUsed else { return true }
        return Date().timeIntervalSince(date) > 90 * 86400
    }
    
    private var staleHelpText: String {
        guard let date = app.lastUsed else { return "This app has no recent open date." }
        let days = Int(Date().timeIntervalSince(date) / 86400)
        return "This app has not been opened for \(days) days."
    }
    
    private var lastUsedText: String {
        guard let date = app.lastUsed else { return "" }
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86400)
        if days < 1 { return "today" }
        if days < 30 { return "\(days)d ago" }
        if days < 365 { return "\(days / 30)mo ago" }
        return "\(days / 365)y ago"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimaryLight)
                        .lineLimit(1)
                    if isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentAmber)
                            .help(staleHelpText)
                    }
                }
                HStack(spacing: 6) {
                    if !app.version.isEmpty {
                        Text(app.version)
                    }
                    if !lastUsedText.isEmpty {
                        Text("·")
                        Text(lastUsedText)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiaryLight)
            }
            Spacer()
            Text(MemoryInfo.formatted(app.totalSize))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondaryLight)
        }
        .padding(.vertical, 4)
    }
}

struct AppDetailView: View {
    @Binding var app: InstalledApp
    let onUninstall: () -> Void
    let isUninstalling: Bool
    let isSuccess: Bool
    
    private var autoCount: Int { app.autoSelected.filter(\.isSelected).count }
    private var autoSize: UInt64 { app.autoSelected.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    private var reviewCount: Int { app.needsReview.count }
    private var reviewSize: UInt64 { app.needsReview.reduce(0) { $0 + $1.size } }
    
    private var lastUsedText: String {
        guard let date = app.lastUsed else { return "Unknown" }
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86400)
        if days < 1 { return "active today" }
        if days < 30 { return "active \(days) days ago" }
        if days < 365 { return "active \(days / 30) months ago" }
        return "active \(days / 365) years ago"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .opacity(isUninstalling ? 0.5 : 1.0)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.textPrimaryLight)
                    HStack(spacing: 6) {
                        if !app.version.isEmpty {
                            Text(app.version)
                        }
                        Text("·")
                        Text(MemoryInfo.formatted(app.appSize))
                        Text("·")
                        Text(lastUsedText)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
                }
                Spacer()
                
                Button(action: onUninstall) {
                    HStack(spacing: 6) {
                        if isSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentGreen)
                            Text("Deleted")
                        } else if isUninstalling {
                            ProgressView().scaleEffect(0.7)
                            Text("Removing...")
                        } else {
                            Image(systemName: "trash")
                            Text("Uninstall")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(isSuccess ? Color.accentGreen.opacity(0.1) : (isUninstalling ? Color.surfaceLight : Color.accentRed))
                    .foregroundStyle(isSuccess ? Color.accentGreen : (isUninstalling ? Color.textSecondaryLight : .white))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(isUninstalling)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background(Color.surfaceCardLight)
            
            Rectangle().fill(Color.borderLight).frame(height: 1)
            
            // File lists
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Auto selected section ──
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentGreen)
                        Text("Auto selected")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)
                        Text("\(autoCount + 1) files · \(MemoryInfo.formatted(app.appSize + autoSize))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiaryLight)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.accentGreen.opacity(0.04))
                    
                    // Application row
                    fileRow(label: "Application", path: app.appPath.path, size: app.appSize, isAuto: true)
                    
                    // Auto-selected related files
                    ForEach($app.autoSelected) { $file in
                        relatedFileRow(file: $file, isAuto: true)
                    }
                    
                    // ── Needs review section ──
                    if !app.needsReview.isEmpty {
                        Rectangle().fill(Color.borderLight).frame(height: 1).padding(.vertical, 4)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentAmber)
                            Text("Needs review")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textPrimaryLight)
                            Text("\(reviewCount) files · \(MemoryInfo.formatted(reviewSize))")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textTertiaryLight)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.accentAmber.opacity(0.04))
                        
                        Text("Not selected by default. Review before removing.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiaryLight)
                            .padding(.horizontal, 16).padding(.bottom, 6)
                        
                        ForEach($app.needsReview) { $file in
                            relatedFileRow(file: $file, isAuto: false)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color.surfaceLight)
            .opacity(isUninstalling ? 0.5 : 1.0)
        }
        .background(Color.surfaceLight)
    }
    
    private func fileRow(label: String, path: String, size: UInt64, isAuto: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isAuto ? "checkmark.square.fill" : "square")
                .font(.system(size: 12))
                .foregroundStyle(isAuto ? Color.accentGreen : Color.textTertiaryLight)
            
            fileInfo(label: label, path: path, size: size)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
    
    private func relatedFileRow(file: Binding<AppRelatedFile>, isAuto: Bool) -> some View {
        Button(action: { file.wrappedValue.isSelected.toggle() }) {
            HStack(spacing: 10) {
                Image(systemName: file.wrappedValue.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(file.wrappedValue.isSelected ? (isAuto ? Color.accentGreen : Color.accentAmber) : Color.textTertiaryLight)
                
                fileInfo(label: file.wrappedValue.label, path: file.wrappedValue.url.path, size: file.wrappedValue.size)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
    
    private func fileInfo(label: String, path: String, size: UInt64) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textPrimaryLight)
                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiaryLight)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(MemoryInfo.formatted(size))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondaryLight)
        }
    }
}

struct DiskAnalyzerView: View {
    @ObservedObject var service: StorageAnalyzerService
    @Binding var operationActive: Bool
    @State private var isDeleting = false
    @State private var highlightedNodeId: UUID? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                if !service.navigationStack.isEmpty {
                    Button(action: { service.navigateBack() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                            Text(service.currentNode?.name ?? "Root")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondaryLight)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(diskMapStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiaryLight)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !service.selectedDiskNodes.isEmpty {
                    Button(action: { withAnimation { service.selectedDiskNodes.removeAll() } }) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textTertiaryLight)
                    }.buttonStyle(.plain)
                    Text("\(service.selectedDiskNodes.count) selected (\(MemoryInfo.formatted(service.selectedTotalSize)))")
                        .font(.system(size: 12)).foregroundStyle(Color.textSecondaryLight)
                    Button(action: {
                        isDeleting = true
                        operationActive = true
                        service.deleteSelectedDiskNodes { _ in
                            isDeleting = false
                            operationActive = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isDeleting { ProgressView().scaleEffect(0.65) } else { Image(systemName: "trash") }
                            Text(isDeleting ? "Deleting…" : "Delete")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(isDeleting ? Color.surfaceLight : Color.accentRed)
                        .foregroundStyle(isDeleting ? Color.textSecondaryLight : .white)
                        .clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(isDeleting)
                } else if service.isScanning {
                    Button("Stop") { service.cancel() }
                        .buttonStyle(.plain).font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.surfaceLight).clipShape(Capsule())
                } else if service.currentNode != nil {
                    Button(action: { service.scan() }) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12))
                    }.buttonStyle(.plain).foregroundStyle(Color.accentBlue)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.surfaceCardLight)
            
            Rectangle().fill(Color.borderLight).frame(height: 1)
            
            // Content
            if service.packedCircles.isEmpty {
                if service.isScanning {
                    ScanningPlaceholder(icon: "network", color: .indigo, message: "Building disk map\u{2026}")
                } else {
                    ToolSplashScreen(
                        icon: "network",
                        color: .indigo,
                        title: "Disk Map Analysis",
                        subtitle: "Run a bounded fast scan of your home folder. Results are labelled partial if a time or entry limit is reached.",
                        buttonTitle: "Start Scan",
                        action: { service.scan() }
                    )
                }
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        // Outline Tree View (Left)
                        VStack(spacing: 0) {
                            Text("Contents")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textSecondaryLight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.surfaceCardLight)
                            
                            Rectangle().fill(Color.borderLight).frame(height: 1)
                            
                            if let current = service.currentNode, let children = current.children {
                                ScrollViewReader { proxy in
                                    ScrollView {
                                        LazyVStack(spacing: 0) {
                                        ForEach(children) { node in
                                            let isSelected = service.selectedDiskNodes.contains(node)
                                            HStack {
                                                // Checkbox or lock
                                                if node.isDeletable {
                                                    Button(action: {
                                                        if isSelected {
                                                            service.selectedDiskNodes.remove(node)
                                                        } else {
                                                            service.selectedDiskNodes.insert(node)
                                                        }
                                                    }) {
                                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                            .font(.system(size: 14))
                                                            .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiaryLight)
                                                    }
                                                    .buttonStyle(.plain)
                                                } else {
                                                    Image(systemName: "lock.fill")
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(Color.textTertiaryLight.opacity(0.4))
                                                        .frame(width: 20)
                                                }
                                                
                                                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                                                    .foregroundStyle(node.isDeletable ? node.category.color : Color.textTertiaryLight.opacity(0.5))
                                                    .frame(width: 16)
                                                
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(node.name)
                                                        .font(.system(size: 12))
                                                        .lineLimit(1)
                                                        .truncationMode(.tail)
                                                        .foregroundStyle(node.isDeletable ? Color.textPrimaryLight : Color.textTertiaryLight)
                                                    Text(relativePath(node.url))
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                        .foregroundStyle(Color.textTertiaryLight.opacity(0.5))
                                                }
                                                
                                                Spacer()
                                                
                                                Text(MemoryInfo.formatted(node.size))
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(Color.textTertiaryLight)
                                                
                                                if node.isDirectory && node.children != nil {
                                                    Button(action: {
                                                        withAnimation { service.navigateTo(node: node) }
                                                    }) {
                                                        Image(systemName: "chevron.right")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundStyle(Color.textTertiaryLight)
                                                            .padding(.leading, 4)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 4)
                                            .background(highlightedNodeId == node.id ? Color.accentBlue.opacity(0.08) : Color.clear)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .opacity(isDeleting ? 0.5 : 1.0)
                                            .id(node.id)
                                            Rectangle().fill(Color.borderLight.opacity(0.5)).frame(height: 1).padding(.leading, 36)
                                        }   // end ForEach
                                        }   // end LazyVStack
                                    }       // end ScrollView
                                    .disabled(isDeleting)
                                    .onChange(of: highlightedNodeId) { id in
                                        if let id = id {
                                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                if self.highlightedNodeId == id {
                                                    withAnimation { self.highlightedNodeId = nil }
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                Spacer()
                            }
                        }
                        .frame(width: geo.size.width * 0.35)
                        
                        Rectangle().fill(Color.borderLight).frame(width: 1)
                        
                        // Organic Graph Canvas (Right)
                        ZStack {
                            Color.surfaceLight
                            
                            if service.isScanning && service.packedCircles.isEmpty {
                                ProgressView()
                            } else {
                                OrganicGraphView(
                                    circles: service.packedCircles,
                                    rootName: service.currentNode?.name ?? "Root",
                                    highlightedNodeId: $highlightedNodeId,
                                    onNavigate: { node in
                                        if node.isDirectory && node.children != nil {
                                            withAnimation { service.navigateTo(node: node) }
                                        }
                                    },
                                    onDelete: { node in
                                        service.deleteSingleNode(node)
                                    }
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                            }
                        }
                        .frame(width: geo.size.width * 0.65)
                    }
                }
            }
        }
    }

    private var diskMapStatusText: String {
        if service.isScanning {
            let percent = Int((service.scanProgress * 100).rounded())
            return "\(service.currentPath) · \(service.scannedEntryCount) items · \(percent)%"
        }
        if service.scanWasLimited {
            return "Partial fast scan · \(service.scannedEntryCount) items"
        }
        if let current = service.currentNode {
            return "Fast scan · depth 3 · \(current.name)"
        }
        return ""
    }
}

struct OrganicGraphView: View {
    let circles: [PackedCircle]
    let rootName: String
    @Binding var highlightedNodeId: UUID?
    let onNavigate: (FSNode) -> Void
    let onDelete: (FSNode) -> Void
    
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var appearScale: CGFloat = 0.0
    @State private var zoomScale: CGFloat = 1.0
    @State private var hoveredNodeId: UUID? = nil
    
    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2 + offset.width + dragOffset.width
            let cy = geo.size.height / 2 + offset.height + dragOffset.height
            
            ZStack {
                // Lines to center
                ForEach(circles) { circle in
                    Path { path in
                        path.move(to: CGPoint(x: cx, y: cy))
                        path.addLine(to: CGPoint(x: cx + circle.center.x * zoomScale, y: cy + circle.center.y * zoomScale))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Color.textTertiary.opacity(0.5))
                }
                
                // Background transparent circles (Size)
                ForEach(circles) { circle in
                    let isHovered = hoveredNodeId == circle.node.id
                    Circle()
                        .fill(circle.node.isDeletable
                            ? circle.node.category.color.opacity(isHovered ? 0.6 : 0.3)
                            : Color(white: 0.3).opacity(isHovered ? 0.5 : 0.25))
                        .overlay(Circle().strokeBorder(circle.node.isDeletable ? Color.clear : Color.white.opacity(0.08), lineWidth: 1))
                        .frame(width: circle.radius * 2 * zoomScale, height: circle.radius * 2 * zoomScale)
                        .position(x: cx + circle.center.x * zoomScale, y: cy + circle.center.y * zoomScale)
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
                }
                
                // Root central node
                Circle()
                    .fill(Color.white)
                    .frame(width: 40 * zoomScale, height: 40 * zoomScale)
                    .position(x: cx, y: cy)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                Text(rootName)
                    .font(.system(size: max(10, 14 * zoomScale), weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .position(x: cx, y: cy - (35 * zoomScale))
                
                // Child Nodes and labels
                ForEach(circles) { circle in
                    let isHovered = hoveredNodeId == circle.node.id
                    
                    ZStack {
                        // Invisible hit area matching the background circle size
                        Circle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: circle.radius * 2 * zoomScale, height: circle.radius * 2 * zoomScale)
                            .onHover { hovering in
                                if hovering {
                                    hoveredNodeId = circle.node.id
                                } else if hoveredNodeId == circle.node.id {
                                    hoveredNodeId = nil
                                }
                            }
                            .onTapGesture {
                                highlightedNodeId = circle.node.id
                                onNavigate(circle.node)
                            }
                            .help(circle.node.name)
                            .contextMenu {
                                if circle.node.isDeletable {
                                    Button(role: .destructive, action: { onDelete(circle.node) }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } else {
                                    Button(action: {}) {
                                        Label("Protected — cannot delete", systemImage: "lock.fill")
                                    }.disabled(true)
                                }
                            }
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: max(8, circle.radius / 5) * zoomScale, height: max(8, circle.radius / 5) * zoomScale)
                            .shadow(color: isHovered ? .white.opacity(0.8) : .black.opacity(0.2), radius: isHovered ? 6 : 2, x: 0, y: 1)
                            .allowsHitTesting(false)
                        
                        if circle.radius > 30 {
                            Text(circle.node.name)
                                .font(.system(size: max(8, min(11, circle.radius / 4) * zoomScale), weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: circle.radius * 1.5 * zoomScale)
                                .padding(.horizontal, 4)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Capsule())
                                .offset(y: (circle.radius / 3) * zoomScale)
                                .allowsHitTesting(false)
                        }
                    }
                    .position(x: cx + circle.center.x * zoomScale, y: cy + circle.center.y * zoomScale)
                }
            }
            .scaleEffect(appearScale)
            .animation(.spring(response: 0.6, dampingFraction: 0.6, blendDuration: 0), value: appearScale)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: circles.count)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { val, state, _ in
                        state = val.translation
                    }
                    .onEnded { val in
                        offset.width += val.translation.width
                        offset.height += val.translation.height
                    }
            )
            .onAppear {
                appearScale = 1.0
            }
            
            // Zoom Controls
            VStack(spacing: 8) {
                Button(action: {
                    withAnimation(.spring()) { zoomScale = min(zoomScale + 0.3, 3.0) }
                }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textPrimaryLight)
                        .frame(width: 32, height: 32)
                        .background(Color.surfaceCardLight)
                        .clipShape(Circle())
                        .shadow(color: Color.shadowLight, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.spring()) { zoomScale = max(zoomScale - 0.3, 0.4) }
                }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textPrimaryLight)
                        .frame(width: 32, height: 32)
                        .background(Color.surfaceCardLight)
                        .clipShape(Circle())
                        .shadow(color: Color.shadowLight, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.spring()) {
                        zoomScale = 1.0
                        offset = .zero
                    }
                }) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.surfaceSecondary.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}

struct LargeFilesView: View {
    @ObservedObject var service: StorageAnalyzerService
    @Binding var operationActive: Bool
    @State private var selectedFileIds: Set<UUID> = []
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text(service.largeFiles.isEmpty ? "" : "\(service.largeFiles.count) files · ≥ 10 MB")
                    .font(.system(size: 12)).foregroundStyle(Color.textTertiaryLight)
                Spacer()
                if !selectedFileIds.isEmpty {
                    Button(action: deleteSelected) {
                        HStack(spacing: 4) {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.55)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 12, height: 12)
                            }
                            Text(isDeleting ? "Deleting" : "\(selectedFileIds.count)")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(height: 24)
                        .padding(.horizontal, 9)
                        .background(isDeleting ? Color.surfaceLight : Color.accentRed)
                        .foregroundStyle(isDeleting ? Color.textSecondaryLight : .white)
                        .clipShape(Capsule())
                    }.buttonStyle(.plain).disabled(isDeleting)
                } else if !service.largeFiles.isEmpty {
                    Button(action: { service.scanLargeFiles() }) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12))
                    }.buttonStyle(.plain).foregroundStyle(Color.accentBlue)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color.surfaceCardLight)
            
            Rectangle().fill(Color.borderLight).frame(height: 1)
            
            if service.largeFiles.isEmpty {
                if service.isScanning {
                    ScanningPlaceholder(icon: "doc.text.magnifyingglass", color: .accentAmber, message: "Scanning for large files\u{2026}")
                } else {
                    ToolSplashScreen(
                        icon: "doc.text.magnifyingglass",
                        color: .accentAmber,
                        title: "Large Files Finder",
                        subtitle: "Locate and remove the biggest files on your disk to free up space quickly.",
                        buttonTitle: "Scan Now",
                        action: { service.scanLargeFiles() }
                    )
                }
            } else {
                HStack {
                    let allSelected = !service.largeFiles.isEmpty && selectedFileIds.count == service.largeFiles.count
                    Button(action: {
                        if allSelected {
                            selectedFileIds.removeAll()
                        } else {
                            selectedFileIds = Set(service.largeFiles.map { $0.id })
                        }
                    }) {
                        Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(allSelected ? Color.accentBlue : Color.textTertiaryLight)
                    }
                    .buttonStyle(.plain)
                    
                    Text(allSelected ? "Deselect All" : "Select All")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimaryLight)
                    
                    Spacer()
                    
                    let selectedSize = service.largeFiles.filter { selectedFileIds.contains($0.id) }.reduce(0) { $0 + $1.size }
                    Text("\(selectedFileIds.count) selected (\(MemoryInfo.formatted(selectedSize)))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textSecondaryLight)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.surfaceLight)

                if service.largeFileScanWasLimited {
                    HStack(spacing: 7) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .foregroundStyle(Color.accentAmber)
                        Text("Partial result · \(service.largeFileScannedEntryCount.formatted()) entries checked")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        if service.largeFileScanMode == .efficient {
                            Button("Run Thorough Scan") {
                                selectedFileIds.removeAll()
                                service.scanLargeFiles(mode: .thorough)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accentAmber.opacity(0.08))
                }
                
                Rectangle().fill(Color.borderLight).frame(height: 1)
                
                List {
                    ForEach(service.largeFiles) { file in
                        Button(action: {
                            if selectedFileIds.contains(file.id) {
                                selectedFileIds.remove(file.id)
                            } else {
                                selectedFileIds.insert(file.id)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: selectedFileIds.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(selectedFileIds.contains(file.id) ? Color.accentBlue : Color.textTertiaryLight)
                                    .frame(width: 20)
                                
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(file.category.color)
                                    .frame(width: 30)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.textPrimaryLight)
                                        .lineLimit(1)
                                    Text(file.url.path)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.textTertiaryLight)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                
                                Spacer()
                                
                                if let date = file.lastAccessDate {
                                    Text(date, style: .date)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.textTertiaryLight)
                                        .frame(width: 80, alignment: .trailing)
                                }
                                
                                Text(MemoryInfo.formatted(file.size))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.textSecondaryLight)
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                            .opacity(isDeleting ? 0.5 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeleting)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.surfaceCardLight)
                .background(Color.surfaceLight)
            }
        }
        .background(Color.surfaceLight)
        .alert("Failed to Delete", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func deleteSelected() {
        let filesToDelete = service.largeFiles.filter { selectedFileIds.contains($0.id) }
        guard !filesToDelete.isEmpty else { return }
        
        isDeleting = true
        operationActive = true
        
        let dispatchGroup = DispatchGroup()
        var successfullyDeleted: Set<UUID> = []
        var errors: [String] = []
        
        for file in filesToDelete {
            dispatchGroup.enter()
            service.trashItem(url: file.url) { success, errorMsg in
                if success {
                    successfullyDeleted.insert(file.id)
                } else if let errorMsg = errorMsg {
                    errors.append("\(file.name): \(errorMsg)")
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            withAnimation {
                service.largeFiles.removeAll { successfullyDeleted.contains($0.id) }
                selectedFileIds.subtract(successfullyDeleted)
                isDeleting = false
                operationActive = false
                
                if !errors.isEmpty {
                    self.errorMessage = errors.joined(separator: "\n")
                    self.showError = true
                }
            }
        }
    }
}

// JunkCategory and JunkType are re-declared here for ContentView's internal use
// (ContentView has its own StorageAnalyzerService with junkCategories: [JunkCategory])

private struct _CVJunkCategory: Identifiable {
    let id = UUID()
    let type: _CVJunkType
    var size: UInt64
    var files: [URL]
    var name: String { type.name }
    var icon: String { type.icon }
    var color: Color { type.color }
}

private enum _CVJunkType: CaseIterable, Hashable {
    case userCache, systemCache, xcodeJunk, systemLogs, browserCache, userLogs, unusedDMG, trash, downloads, screenCaptures
    var name: String { "Кэш" }
    var icon: String { "folder" }
    var color: Color { .gray }
}

// MARK: - Animated progress bar for scanning
private struct JunkScanProgressBar: View {
    let color: Color
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let barW = w * 0.38
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: barW, height: 4)
                .offset(x: -barW + phase * (w + barW))
                .onAppear {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1.0
                    }
                }
        }
        .frame(height: 4)
        .clipped()
    }
}

// MARK: - Junk Files View

struct JunkFilesView: View {
    @ObservedObject var service: StorageAnalyzerService
    @Binding var operationActive: Bool
    @State private var selectedTypes: Set<JunkType> = []
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var cleanupNotice: String?

    private var selectedSize: UInt64 {
        service.junkCategories.filter { selectedTypes.contains($0.type) }.reduce(0) { $0 + $1.size }
    }
    private var totalSize: UInt64 {
        service.junkCategories.reduce(0) { $0 + $1.size }
    }
    private var allSelected: Bool {
        let safeTypes = Set(service.junkCategories.filter(\.isSelectedByDefault).map { $0.type })
        return !safeTypes.isEmpty && safeTypes.isSubset(of: selectedTypes)
    }

    var body: some View {
        VStack(spacing: 0) {
            if service.junkCategories.isEmpty {
                if service.isScanningJunk {
                    junkScanningView
                } else {
                    ToolSplashScreen(
                        icon: "archivebox.fill",
                        color: .purple,
                        title: "Junk Files Cleaner",
                        subtitle: "Find and remove user-space caches, logs, and temporary files to keep your Mac running smoothly.",
                        buttonTitle: "Start Scan",
                        action: { service.scanJunk() }
                    )
                }
            } else {
                junkResultsView
            }
        }
        .alert("Ошибка очистки", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Scanning Screen
    private var junkScanningView: some View {
        VStack(spacing: 0) {
            Spacer()
            // Icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(Color.purple.opacity(0.07))
                    .frame(width: 130, height: 130)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }
            .padding(.bottom, 28)

            Text("Scanning for Junk Files")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.bottom, 8)

            Text("Checking caches, logs, developer files and downloads…")
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .padding(.bottom, 32)

            // Animated progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 4)
                JunkScanProgressBar(color: .purple)
            }
            .frame(height: 4)
            .padding(.horizontal, 64)
            .padding(.bottom, 16)

            Text(service.junkScanMode == .efficient
                 ? "Utility-priority scan · up to 8 seconds or 100,000 entries"
                 : "Thorough utility-priority scan · up to 45 seconds or 500,000 entries")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary.opacity(0.6))

            Spacer()

            // Bottom scan area — shows what's being scanned
            VStack(spacing: 12) {
                Divider()
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(Color.purple)
                    Text("Analyzing…")
                        .font(.mono(11))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results Screen
    private var junkResultsView: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan Complete")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(service.junkCategories.count) categories found")
                        .font(.mono(11))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Text(MemoryInfo.formatted(totalSize))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            if service.junkScanWasLimited {
                HStack(spacing: 7) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .foregroundStyle(Color.accentAmber)
                    Text("Partial low-load result · \(service.junkScannedEntryCount.formatted()) entries checked. Listed sizes are valid; additional junk may exist.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    if service.junkScanMode == .efficient {
                        Button("Run Thorough Scan") {
                            service.scanJunk(mode: .thorough)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(9)
                .background(Color.accentAmber.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            // Select all / Rescan row
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if allSelected { selectedTypes.removeAll() }
                        else { selectedTypes = Set(service.junkCategories.filter(\.isSelectedByDefault).map { $0.type }) }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13))
                            .foregroundStyle(allSelected ? Color.accent : Color.textTertiary)
	                        Text(allSelected ? "Deselect All" : "Select Safe")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            // Category rows — fills remaining space
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(service.junkCategories) { category in
                        let isSelected = selectedTypes.contains(category.type)
                        let ratio = totalSize > 0 ? CGFloat(category.size) / CGFloat(totalSize) : 0
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isSelected { selectedTypes.remove(category.type) }
                                else { selectedTypes.insert(category.type) }
                            }
                        }) {
                            VStack(spacing: 0) {
                                HStack(spacing: 14) {
                                    // Checkbox
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isSelected ? Color.accent : Color.surfaceSecondary)
                                            .frame(width: 18, height: 18)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    // Icon
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(category.color.opacity(0.15))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: category.icon)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(category.color)
                                    }
                                    // Name + bar
	                                    VStack(alignment: .leading, spacing: 6) {
	                                        HStack(spacing: 6) {
	                                            Text(category.name)
	                                                .font(.system(size: 13, weight: .medium))
	                                                .foregroundStyle(Color.textPrimary)
	                                            if category.type == .xcodeJunk {
	                                                Text("Rebuildable")
	                                                    .font(.system(size: 9, weight: .bold))
	                                                    .foregroundStyle(Color.accentBlue)
	                                                    .padding(.horizontal, 6)
	                                                    .padding(.vertical, 2)
	                                                    .background(Color.accentBlue.opacity(0.12))
	                                                    .clipShape(Capsule())
	                                            }
	                                        }
	                                        Text(category.type.detail)
	                                            .font(.system(size: 10))
	                                            .foregroundStyle(Color.textTertiary)
	                                            .lineLimit(1)
	                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Color.white.opacity(0.05))
                                                    .frame(height: 3)
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(category.color.opacity(0.7))
                                                    .frame(width: geo.size.width * ratio, height: 3)
                                            }
                                        }
                                        .frame(height: 3)
                                    }
                                    // Count + size
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(MemoryInfo.formatted(category.size))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(isSelected ? category.color : Color.textSecondary)
                                        Text("\(category.itemCount) items")
                                            .font(.mono(10))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .frame(width: 72, alignment: .trailing)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                            }
                            .background(isSelected ? category.color.opacity(0.06) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeleting)

                        Divider().padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 4)
            }

            // Footer
	            VStack(spacing: 0) {
	                Divider()
	                if let cleanupNotice {
	                    HStack(spacing: 8) {
	                        Image(systemName: "info.circle")
	                            .font(.system(size: 12, weight: .semibold))
	                        Text(cleanupNotice)
	                            .font(.system(size: 12))
	                            .lineLimit(2)
	                        Spacer()
	                        Button(action: { withAnimation { self.cleanupNotice = nil } }) {
	                            Image(systemName: "xmark")
	                                .font(.system(size: 10, weight: .bold))
	                        }
	                        .buttonStyle(.plain)
	                    }
	                    .foregroundStyle(Color.textSecondary)
	                    .padding(.horizontal, 24)
	                    .padding(.vertical, 9)
	                    .background(Color.accentBlue.opacity(0.07))
	                }
	                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        if selectedTypes.isEmpty {
                            Text("Select items to clean")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textTertiary)
                        } else {
                            Text(MemoryInfo.formatted(selectedSize))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("will be moved to Trash")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: { service.scanJunk() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 11))
                                Text("Rescan").font(.system(size: 12))
                            }
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeleting)

                        Button(action: deleteSelected) {
                            ZStack {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small).tint(.white)
                                    Text("Cleaning…")
                                }
                                .opacity(isDeleting ? 1 : 0)

                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                    Text(selectedTypes.isEmpty ? "Select items" : "Clean \(MemoryInfo.formatted(selectedSize))")
                                }
                                .opacity(isDeleting ? 0 : 1)
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 160, height: 34)
                            .background(selectedTypes.isEmpty ? Color.surfaceSecondary : Color.accent)
                            .foregroundStyle(selectedTypes.isEmpty ? Color.textTertiary : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeleting || selectedTypes.isEmpty)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color.surfaceSecondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
	    private func deleteSelected() {
	        let categoriesToClean = service.junkCategories.filter { selectedTypes.contains($0.type) }
	        guard !categoriesToClean.isEmpty else { return }
        
        isDeleting = true
        operationActive = true
        
	        let dispatchGroup = DispatchGroup()
	        var successfullyDeletedTypes: Set<JunkType> = []
	        var errors: [String] = []
	        var skippedMessages: [String] = []
	        var removedTotal = 0
	        
	        for category in categoriesToClean {
	            dispatchGroup.enter()
	            service.cleanJunkCategory(category) { result in
	                removedTotal += result.removedCount
	                if result.success {
	                    successfullyDeletedTypes.insert(category.type)
	                    if result.skippedCount > 0 {
	                        skippedMessages.append("\(category.name): \(result.skippedCount) protected items skipped")
	                    }
	                } else {
	                    errors.append("\(category.name): \(result.message ?? "Could not be removed")")
	                }
	                dispatchGroup.leave()
	            }
        }

        dispatchGroup.notify(queue: .main) {
            withAnimation {
                service.junkCategories.removeAll { successfullyDeletedTypes.contains($0.type) }
                selectedTypes.subtract(successfullyDeletedTypes)
                isDeleting = false
	                operationActive = false

	                if !errors.isEmpty {
	                    let detail = errors.joined(separator: "\n")
	                    self.errorMessage = "Some items could not be cleaned:\n\n\(detail)"
	                    self.showError = true
	                } else if !skippedMessages.isEmpty {
	                    let skipped = skippedMessages.joined(separator: " · ")
	                    self.cleanupNotice = "Cleaned \(removedTotal) items. \(skipped). Protected Apple caches are left intact by macOS."
	                } else if removedTotal > 0 {
	                    self.cleanupNotice = "Cleaned \(removedTotal) items."
	                }
	            }
	        }
    }
}
