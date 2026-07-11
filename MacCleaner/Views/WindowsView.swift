import SwiftUI

private let systemAppNames: Set<String> = [
    "Window Server", "Dock", "SystemUIServer", "ControlCenter",
    "NotificationCenter", "Spotlight"
]

struct WindowsView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var searchText = ""
    @State private var sortByMem = true

    private var grouped: [(app: String, windows: [WindowInfo], totalMem: UInt64)] {
        let allWins = monitor.windows.filter { win in
            let isSystemApp = systemAppNames.contains(win.ownerName)
            return !isSystemApp || win.memoryBytes > 0
        }
        let wins = searchText.isEmpty
            ? allWins
            : allWins.filter { $0.ownerName.localizedCaseInsensitiveContains(searchText) || $0.name.localizedCaseInsensitiveContains(searchText) }

        var dict: [String: [WindowInfo]] = [:]
        for w in wins { dict[w.ownerName, default: []].append(w) }

        return dict.map { (app: $0.key, windows: $0.value, totalMem: $0.value.reduce(0) { $0 + $1.memoryBytes }) }
            .sorted { sortByMem ? $0.totalMem > $1.totalMem : $0.app < $1.app }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Windows")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("\(monitor.windows.count) on-screen windows")
                        .font(.mono(10))
                        .foregroundStyle(.textTertiary)
                }
                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.textTertiary)
                    TextField("Filter...", text: $searchText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .foregroundStyle(.textPrimary)
                        .frame(width: 130)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderSubtle))

            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Rectangle().fill(Color.borderSubtle).frame(height: 1)

            // Table header — clickable
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.12)) { sortByMem = false } } label: {
                    HStack(spacing: 3) {
                        Text("APP")
                            .font(.mono(10, weight: !sortByMem ? .semibold : .medium))
                            .foregroundStyle(!sortByMem ? Color.accent : Color.textTertiary)
                        if !sortByMem {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .semibold)).foregroundStyle(.accent)
                        }
                    }
                }.buttonStyle(.plain)
                Text("WINDOWS")
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(.textTertiary)
                    .padding(.leading, 8)
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.12)) { sortByMem = true } } label: {
                    HStack(spacing: 3) {
                        Text("MEMORY")
                            .font(.mono(10, weight: sortByMem ? .semibold : .medium))
                            .foregroundStyle(sortByMem ? Color.accent : Color.textTertiary)
                        if sortByMem {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold)).foregroundStyle(.accent)
                        }
                    }
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 7)

            Rectangle().fill(Color.borderSubtle).frame(height: 1)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(grouped, id: \.app) { group in
                        AppWindowGroup(group: group,
                                       maxMem: grouped.first?.totalMem ?? 1)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.surfacePrimary)
        .onAppear {
            monitor.setConsumer(.windows, active: true)
            monitor.refresh(forceProcesses: true)
        }
        .onDisappear {
            monitor.setConsumer(.windows, active: false)
        }
    }
}

struct AppWindowGroup: View {
    let group: (app: String, windows: [WindowInfo], totalMem: UInt64)
    let maxMem: UInt64
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            // App row
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.textTertiary)
                        .frame(width: 12)

                    Text(group.app)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    Text("\(group.windows.count) window\(group.windows.count == 1 ? "" : "s")")
                        .font(.mono(10))
                        .foregroundStyle(.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Spacer()

                    if group.totalMem > 0 {
                        Text(MemoryInfo.formatted(group.totalMem))
                            .font(.mono(11, weight: .medium))
                            .foregroundStyle(.textSecondary)

                        MiniBar(value: maxMem > 0 ? Double(group.totalMem) / Double(maxMem) : 0,
                                color: .accent, height: 2)
                            .frame(width: 60)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(group.windows) { win in
                    WindowRow(win: win)
                    if win.id != group.windows.last?.id {
                        Rectangle().fill(Color.borderSubtle.opacity(0.4)).frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }
}

struct WindowRow: View {
    let win: WindowInfo

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.borderSubtle).frame(width: 1, height: 28)
                .padding(.leading, 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(win.name.isEmpty ? win.ownerName : win.name)
                    .font(.system(size: 12))
                    .foregroundStyle(win.name.isEmpty ? Color.textSecondary : Color.textSecondary)
                    .lineLimit(1)
                Text("PID \(win.ownerPID) · \(win.isOnScreen ? "on screen" : "off screen")")
                    .font(.mono(9))
                    .foregroundStyle(.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
    }
}
