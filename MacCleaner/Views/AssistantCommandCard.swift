import AppKit
import SwiftUI

struct AssistantCommandCard: View {
    @EnvironmentObject private var modalCoordinator: AppModalCoordinator
    let tool: AssistantToolPresentation
    let phase: AssistantPreviewPhase
    let rows: [AssistantCardRow]
    var summary: String? = nil
    var isPreview = true
    var allowsInteraction = true
    var resultActionTitle: String? = nil
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}
    var onOpenResult: () -> Void = {}
    var onRowAction: (AssistantCardRow) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.accentBlue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(tool.title).font(.system(size: 13, weight: .semibold))
                if tool.id == "list_startup_items", phase == .result {
                    Button("macOS Login Items") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(AssistantActionButtonStyle())
                }
                if phase == .result, let resultActionTitle {
                    Button(action: onOpenResult) {
                        Label(resultActionTitle, systemImage: "arrow.up.right")
                    }
                    .buttonStyle(AssistantActionButtonStyle())
                }
                Spacer()
                Label(phase.rawValue, systemImage: phaseIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(phaseColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(phaseColor.opacity(0.08))
                    .clipShape(Capsule())
            }
            switch phase {
            case .running:
                activityLine
                if allowsInteraction { HStack { Spacer(); Button("Cancel", action: onCancel) } }
            case .deferred:
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.textSecondaryLight)
                        .lineSpacing(2)
                }
                activityLine
                if let resultActionTitle {
                    HStack { Spacer(); Button(resultActionTitle, action: onOpenResult).buttonStyle(.bordered) }
                }
            case .result:
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.textSecondaryLight)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                resultContent
            case .confirmation:
                Label("Review the action", systemImage: "hand.raised")
                    .font(.subheadline.weight(.medium))
                Text("Changes are applied only after confirmation.")
                    .font(.callout).foregroundStyle(.secondary)
                rowList
                HStack {
                    Button("Cancel", action: onCancel).disabled(!allowsInteraction)
                    Spacer()
                    Button(isPreview ? "Confirm preview" : "Confirm", action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .disabled(!allowsInteraction)
                }
            case .empty:
                Label("No matching data found", systemImage: "tray")
                Text("Try changing the request. An empty result is not an error.")
                    .font(.callout).foregroundStyle(.secondary)
            case .failed:
                Label("The command could not be completed", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text(summary ?? "No result is available. Please try again.")
                    .font(.callout).foregroundStyle(.secondary)
            case .cancelled:
                Label("Execution stopped", systemImage: "stop.circle")
                Text("Any partial result remains visible in the chat.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if isPreview {
                Divider()
                Text("Preview data. No command was run on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCardLight.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.075)))
        .animation(.easeInOut(duration: 0.24), value: phase)
    }

    private var phaseIcon: String {
        switch phase {
        case .running, .deferred: return "ellipsis"
        case .result: return "checkmark"
        case .confirmation: return "hand.raised"
        case .empty: return "tray"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .result: return Color.accentGreen
        case .failed: return Color.orange
        case .cancelled: return Color.textSecondaryLight
        default: return Color.accentBlue
        }
    }

    private var activityLine: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentBlue.opacity(0.08))
                Image(systemName: tool.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(activityLabels[0])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textPrimaryLight)
                    Spacer()
                    Text("Working locally")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color.accentBlue)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.accentBlue.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var activityLabels: [String] {
        switch tool.layout {
        case .metrics: return ["Reading", "Measuring", "Formatting"]
        case .files: return ["Scanning", "Comparing", "Sorting"]
        case .applications: return ["Locating", "Inspecting", "Preparing"]
        case .processes: return ["Sampling", "Ranking", "Formatting"]
        case .operation: return ["Preparing", "Running", "Verifying"]
        case .navigation: return ["Locating", "Opening", "Ready"]
        case .clarification: return ["Reading", "Checking", "Asking"]
        }
    }

    @ViewBuilder private var resultContent: some View {
        switch tool.layout {
        case .metrics:
            ForEach(metricSections, id: \.title) { section in
                if !section.title.isEmpty {
                    Text(section.title).font(.system(size: 12, weight: .semibold)).padding(.top, 4)
                }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 8)], spacing: 8) {
                ForEach(section.rows) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(metricColor(for: row))
                                .frame(width: 6, height: 6)
                            Text(tool.id == "check_thermal_state" ? String(row.title.split(separator: "·", maxSplits: 1).last ?? Substring(row.title)).trimmingCharacters(in: .whitespaces) : row.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.textSecondaryLight)
                                .lineLimit(2)
                        }
                        Text(row.value).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        Text(row.detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.textTertiaryLight)
                            .lineLimit(2)
                            .help(row.detail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.accentBlue.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accentBlue.opacity(0.07)))
                }
            }
            }
        case .files, .applications, .processes:
            if !rows.isEmpty {
                HStack {
                    Text("Results").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(rows.count)").font(.caption).foregroundStyle(.secondary)
                }
                rowList
            }
        case .operation:
            rowList
        case .navigation:
            Label("Navigation result", systemImage: "rectangle.on.rectangle")
            rowList
        case .clarification:
            Text("Which item should I use?")
            Text("Reply in the input field and I will prepare the exact action.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    static func liveRows(for tool: AssistantToolPresentation, resultText: String) -> [AssistantCardRow] {
        guard !resultText.hasPrefix("Executing ") else { return [] }

        switch tool.id {
        case "check_battery_health":
            let values = [
                ("Health", capture("Health:\\s*([^;,.]+)", in: resultText)),
                ("Charge", capture("charge:\\s*([^;,.]+)", in: resultText)),
                ("Cycles", capture("cycles:\\s*([^;,.]+)", in: resultText)),
            ].compactMap { title, value in value.map { (title, $0) } }
            if !values.isEmpty {
                return values.enumerated().map { .init(id: "battery-\($0.offset)", title: $0.element.0, detail: "Current reading", value: $0.element.1) }
            }
        case "check_thermal_state":
            let readings = resultText
                .replacingOccurrences(of: "Thermal check complete.", with: "")
                .split(separator: ",")
                .prefix(6)
            if !readings.isEmpty {
                return readings.enumerated().map { index, reading in
                    let parts = reading.split(separator: ":", maxSplits: 1).map(String.init)
                    return .init(id: "thermal-\(index)", title: parts.first?.trimmingCharacters(in: .whitespaces) ?? "Sensor", detail: "Live sensor", value: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "Read")
                }
            }
        case "list_processes", "find_heavy_processes", "show_ai_workloads":
            if let range = resultText.range(of: "Top:") {
                let names = resultText[range.upperBound...].split(separator: ",").prefix(6)
                return names.enumerated().map { .init(id: "process-\($0.offset)", title: $0.element.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)), detail: "Active process", value: "Running") }
            }
        default:
            break
        }

        return []
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rowList: some View {
        VStack(spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 11) {
                    rowIcon(row)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).font(.system(size: 12, weight: .semibold))
                        Text(row.detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if let fraction = row.loadFraction {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                ForEach(0..<16) { index in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(index < Int(ceil(fraction * 16)) ? loadColor(fraction, name: row.title) : Color.primary.opacity(0.06))
                                        .frame(width: 6, height: 16)
                                }
                            }
                            Text(row.value).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("CPU capacity: \(row.value)")
                    }
                    VStack(alignment: .trailing, spacing: 6) {
                        if row.loadFraction == nil { Text(row.value)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        }
                        rowActionControl(row)
                    }
                    .frame(minWidth: row.loadFraction == nil ? nil : 74, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    @ViewBuilder
    private func rowIcon(_ row: AssistantCardRow) -> some View {
        if let path = row.iconPath, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
                .accessibilityLabel("\(row.title) icon")
        } else {
            Image(systemName: row.fallbackIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 28, height: 28)
                .background(Color.accentBlue.opacity(0.075))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder
    private func rowActionControl(_ row: AssistantCardRow) -> some View {
        switch row.actionState {
        case .idle:
            if let action = row.action {
                Button {
                    modalCoordinator.present(title: actionTitle(for: action), subtitle: row.title, width: 420, height: 240) {
                        rowActionConfirmation(row)
                    }
                } label: {
                    Label(actionTitle(for: action), systemImage: actionIcon(for: action))
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(AssistantActionButtonStyle(tint: actionTint(for: action)))
            }
        case .running:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Working…")
            }
            .font(.system(size: 10))
            .foregroundStyle(Color.textSecondaryLight)
        case .succeeded(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.accentGreen)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.orange)
                .lineLimit(2)
        }
    }

    private func actionTitle(for action: AssistantRowAction) -> String {
        switch action {
        case .quitProcess: return "Quit"
        case .uninstallApplication: return "Move to Trash"
        case .disableStartup: return "Disable"
        case .organizeFiles: return "Move files"
        }
    }

    private func actionIcon(for action: AssistantRowAction) -> String {
        switch action {
        case .quitProcess: return "xmark.circle"
        case .uninstallApplication: return "trash"
        case .disableStartup: return "power"
        case .organizeFiles: return "folder"
        }
    }

    private func actionTint(for action: AssistantRowAction) -> Color {
        switch action {
        case .quitProcess: return Color.orange
        case .uninstallApplication: return Color.red
        case .disableStartup: return Color.orange
        case .organizeFiles: return Color.accentBlue
        }
    }

    private func confirmationText(for row: AssistantCardRow) -> String {
        guard let action = row.action else { return "Nothing will be changed." }
        switch action {
        case .quitProcess(_, _, let instanceCount):
            return instanceCount > 1
                ? "Quit all \(instanceCount) \(row.title) processes? Unsaved work may be lost."
                : "Quit \(row.title)? Unsaved work may be lost."
        case .uninstallApplication:
            return "Move \(row.title) and its selected related files to Trash?"
        case .disableStartup:
            return "Disable \(row.title) at startup? Its LaunchAgent will be backed up and can be restored from Startup Items."
        case .organizeFiles(let items):
            return "Move \(items.count) files into \(items.first?.destination.deletingLastPathComponent().path ?? row.title)? Existing files will not be overwritten. Changed files will be skipped."
        }
    }

    private func metricColor(for row: AssistantCardRow) -> Color {
        let detail = row.detail.lowercased()
        if detail.contains("very hot") || detail.contains("service") { return .red }
        if detail.contains("warm") || detail.contains("worn") { return .orange }
        return Color.accentBlue
    }

    private var metricSections: [(title: String, rows: [AssistantCardRow])] {
        guard tool.id == "check_thermal_state" else { return [("", rows)] }
        let groups = Dictionary(grouping: rows) { String($0.title.split(separator: "·").first ?? "System").trimmingCharacters(in: .whitespaces) }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    private func loadColor(_ value: Double, name: String) -> Color {
        if value >= 0.8 { return .red }
        let colors: [Color] = [.blue, .purple, .teal, .indigo, .orange]
        return colors[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colors.count]
    }

    private func rowActionConfirmation(_ row: AssistantCardRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Confirm action", systemImage: "exclamationmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(actionTint(for: row.action ?? .quitProcess(pid: 0, name: "", instanceCount: 1)))
            Text(confirmationText(for: row))
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondaryLight)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { modalCoordinator.dismiss() }
                    .buttonStyle(AssistantActionButtonStyle(tint: .secondary))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(row.action.map { actionTitle(for: $0) } ?? "Continue") {
                    modalCoordinator.dismiss()
                    onRowAction(row)
                }
                .buttonStyle(.borderedProminent)
                .tint(row.action.map { actionTint(for: $0) } ?? Color.accentBlue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AssistantActionButtonStyle: ButtonStyle {
    var tint: Color = .accentBlue
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint.opacity(configuration.isPressed ? 0.17 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.12)))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct AssistantLoadingIndicator: View {
    let title: String
    let subtitle: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(Color.accentBlue.opacity(animating ? 0.85 : 0.30))
                        .frame(width: 4, height: 14)
                        .scaleEffect(y: animating ? 1 : 0.4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65).repeatForever(autoreverses: true).delay(Double(index) * 0.16), value: animating)
                }
            }
            .frame(width: 34, height: 34)
            .background(Color.accentBlue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .onAppear { animating = !reduceMotion }
        .accessibilityElement(children: .combine)
    }
}

struct AssistantPreviewGallery: View {
    @Binding var selectedToolID: String
    var onAdd: (AssistantToolPresentation, AssistantPreviewPhase) -> Void = { _, _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var phase = AssistantPreviewPhase.running
    private var tool: AssistantToolPresentation {
        AssistantToolPresentation.all.first { $0.id == selectedToolID } ?? AssistantToolPresentation.all[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Команды в чате").font(.title2.weight(.semibold))
                    Text("39 команд · процесс, результат и исключения").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Picker("Команда", selection: $selectedToolID) {
                ForEach(AssistantToolPresentation.all) { Text($0.title).tag($0.id) }
            }
            Picker("Состояние", selection: $phase) {
                ForEach(AssistantPreviewPhase.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer(minLength: 100)
                        Text("Запрос: \(tool.title.lowercased())")
                            .padding(12).background(Color.accentBlue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    HStack(alignment: .top) {
                        Image(systemName: "bubble.left").foregroundStyle(.secondary).padding(.top, 18)
                        AssistantCommandCard(tool: tool, phase: phase, rows: Self.fixtureRows(for: tool),
                            onCancel: { phase = .cancelled }, onConfirm: { phase = .running })
                    }
                }.padding(3)
            }
            Text("Переключатели меняют только предпросмотр. Показатели и объекты ниже — примеры оформления.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Показать этот пример в чате") { onAdd(tool, phase); dismiss() }
        }.padding(24).frame(width: 710, height: 590)
    }

    static func fixtureRows(for tool: AssistantToolPresentation) -> [AssistantCardRow] {
        let fields: [(String, String, String)]
        switch tool.id {
        case "check_battery_health": fields = [("Ёмкость", "От исходной ёмкости · пример", "94%"), ("Циклы", "Источник: пример диагностики", "120")]
        case "check_thermal_state": fields = [("CPU", "Показание датчика · пример", "62 °C"), ("Тепловое состояние", "Системная оценка · пример", "Норма")]
        case "show_fan_status": fields = [("Левый вентилятор", "Текущая скорость · пример", "2 100 RPM"), ("Правый вентилятор", "Текущая скорость · пример", "2 050 RPM")]
        case "run_network_test": fields = [("Доступность", "Контрольный адрес · пример", "Доступен"), ("Задержка", "Один замер · пример", "24 ms")]
        case "check_ssd_health": fields = [("SMART", "Диагностический статус · пример", "Пройден"), ("Свободно", "На выбранном томе · пример", "128 GB")]
        case "show_disk_map": fields = [("Приложения", "Категория · пример", "42 GB"), ("Документы", "Категория · пример", "18 GB")]
        default:
            switch tool.layout {
            case .metrics: fields = [("CPU", "Текущая загрузка · пример", "12%"), ("Память", "Использовано · пример", "8 / 18 GB")]
            case .files: fields = [("Archive.zip", "Downloads · пример объекта", "2,4 GB"), ("Project.dmg", "Downloads · пример объекта", "1,2 GB")]
            case .applications: fields = [("Example App", "Пример приложения или элемента списка", "240 MB")]
            case .processes: fields = [("Example Process", "CPU · 320 MB RAM · пример", "18%"), ("Another Process", "CPU · 120 MB RAM · пример", "4%")]
            case .operation: fields = [("Выбранный объект", "Детали и результат шага · пример", "1 объект")]
            case .navigation: fields = [("Раздел / окно", "Назначение перехода · пример", "Открыто")]
            case .clarification: fields = []
            }
        }
        return fields.enumerated().map { .init(id: String($0.offset), title: $0.element.0, detail: $0.element.1, value: $0.element.2) }
    }
}
