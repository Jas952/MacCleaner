import AppKit
import SwiftUI

private struct MacBookKey: Identifiable {
    let id: String
    let primary: String
    var secondary: String? = nil
    var systemImage: String? = nil
    let width: CGFloat
    var keyCodes: Set<Int64> = []
    var alignLeading = false

    var isTestable: Bool { !keyCodes.isEmpty }
}

private enum MacBookKeyboardLayout {
    static let totalUnits: CGFloat = 14.65

    static let functionRow: [MacBookKey] = [
        MacBookKey(id: "esc", primary: "esc", width: 1.05, keyCodes: [53]),
        MacBookKey(id: "f1", primary: "F1", systemImage: "sun.min", width: 1, keyCodes: [122]),
        MacBookKey(id: "f2", primary: "F2", systemImage: "sun.max", width: 1, keyCodes: [120]),
        MacBookKey(id: "f3", primary: "F3", systemImage: "rectangle.3.group", width: 1, keyCodes: [99]),
        MacBookKey(id: "f4", primary: "F4", systemImage: "magnifyingglass", width: 1, keyCodes: [118]),
        MacBookKey(id: "f5", primary: "F5", systemImage: "mic", width: 1, keyCodes: [96]),
        MacBookKey(id: "f6", primary: "F6", systemImage: "moon", width: 1, keyCodes: [97]),
        MacBookKey(id: "f7", primary: "F7", systemImage: "backward.fill", width: 1, keyCodes: [98]),
        MacBookKey(id: "f8", primary: "F8", systemImage: "playpause.fill", width: 1, keyCodes: [100]),
        MacBookKey(id: "f9", primary: "F9", systemImage: "forward.fill", width: 1, keyCodes: [101]),
        MacBookKey(id: "f10", primary: "F10", systemImage: "speaker.slash.fill", width: 1, keyCodes: [109]),
        MacBookKey(id: "f11", primary: "F11", systemImage: "speaker.wave.1.fill", width: 1, keyCodes: [103]),
        MacBookKey(id: "f12", primary: "F12", systemImage: "speaker.wave.3.fill", width: 1, keyCodes: [111]),
        MacBookKey(id: "touch-id", primary: "Touch ID", systemImage: "power", width: 1.40)
    ]

    static let numberRow: [MacBookKey] = [
        MacBookKey(id: "grave", primary: "`", secondary: "ё", width: 1, keyCodes: [50]),
        MacBookKey(id: "1", primary: "1", width: 1, keyCodes: [18]),
        MacBookKey(id: "2", primary: "2", width: 1, keyCodes: [19]),
        MacBookKey(id: "3", primary: "3", width: 1, keyCodes: [20]),
        MacBookKey(id: "4", primary: "4", width: 1, keyCodes: [21]),
        MacBookKey(id: "5", primary: "5", width: 1, keyCodes: [23]),
        MacBookKey(id: "6", primary: "6", width: 1, keyCodes: [22]),
        MacBookKey(id: "7", primary: "7", width: 1, keyCodes: [26]),
        MacBookKey(id: "8", primary: "8", width: 1, keyCodes: [28]),
        MacBookKey(id: "9", primary: "9", width: 1, keyCodes: [25]),
        MacBookKey(id: "0", primary: "0", width: 1, keyCodes: [29]),
        MacBookKey(id: "minus", primary: "-", width: 1, keyCodes: [27]),
        MacBookKey(id: "equal", primary: "=", width: 1, keyCodes: [24]),
        MacBookKey(id: "delete", primary: "delete", width: 1.65, keyCodes: [51], alignLeading: true)
    ]

    static let tabRow: [MacBookKey] = [
        MacBookKey(id: "tab", primary: "tab", width: 1.50, keyCodes: [48], alignLeading: true),
        MacBookKey(id: "q", primary: "Q", secondary: "Й", width: 1, keyCodes: [12]),
        MacBookKey(id: "w", primary: "W", secondary: "Ц", width: 1, keyCodes: [13]),
        MacBookKey(id: "e", primary: "E", secondary: "У", width: 1, keyCodes: [14]),
        MacBookKey(id: "r", primary: "R", secondary: "К", width: 1, keyCodes: [15]),
        MacBookKey(id: "t", primary: "T", secondary: "Е", width: 1, keyCodes: [17]),
        MacBookKey(id: "y", primary: "Y", secondary: "Н", width: 1, keyCodes: [16]),
        MacBookKey(id: "u", primary: "U", secondary: "Г", width: 1, keyCodes: [32]),
        MacBookKey(id: "i", primary: "I", secondary: "Ш", width: 1, keyCodes: [34]),
        MacBookKey(id: "o", primary: "O", secondary: "Щ", width: 1, keyCodes: [31]),
        MacBookKey(id: "p", primary: "P", secondary: "З", width: 1, keyCodes: [35]),
        MacBookKey(id: "left-bracket", primary: "[", secondary: "Х", width: 1, keyCodes: [33]),
        MacBookKey(id: "right-bracket", primary: "]", secondary: "Ъ", width: 1, keyCodes: [30]),
        MacBookKey(id: "backslash", primary: "\\", width: 1.15, keyCodes: [42])
    ]

    static let homeRow: [MacBookKey] = [
        MacBookKey(id: "caps", primary: "caps lock", width: 1.75, keyCodes: [57], alignLeading: true),
        MacBookKey(id: "a", primary: "A", secondary: "Ф", width: 1, keyCodes: [0]),
        MacBookKey(id: "s", primary: "S", secondary: "Ы", width: 1, keyCodes: [1]),
        MacBookKey(id: "d", primary: "D", secondary: "В", width: 1, keyCodes: [2]),
        MacBookKey(id: "f", primary: "F", secondary: "А", width: 1, keyCodes: [3]),
        MacBookKey(id: "g", primary: "G", secondary: "П", width: 1, keyCodes: [5]),
        MacBookKey(id: "h", primary: "H", secondary: "Р", width: 1, keyCodes: [4]),
        MacBookKey(id: "j", primary: "J", secondary: "О", width: 1, keyCodes: [38]),
        MacBookKey(id: "k", primary: "K", secondary: "Л", width: 1, keyCodes: [40]),
        MacBookKey(id: "l", primary: "L", secondary: "Д", width: 1, keyCodes: [37]),
        MacBookKey(id: "semicolon", primary: ";", secondary: "Ж", width: 1, keyCodes: [41]),
        MacBookKey(id: "quote", primary: "'", secondary: "Э", width: 1, keyCodes: [39]),
        MacBookKey(id: "return", primary: "return", width: 1.90, keyCodes: [36], alignLeading: true)
    ]

    static let shiftRow: [MacBookKey] = [
        MacBookKey(id: "left-shift", primary: "shift", width: 2.25, keyCodes: [56], alignLeading: true),
        MacBookKey(id: "z", primary: "Z", secondary: "Я", width: 1, keyCodes: [6]),
        MacBookKey(id: "x", primary: "X", secondary: "Ч", width: 1, keyCodes: [7]),
        MacBookKey(id: "c", primary: "C", secondary: "С", width: 1, keyCodes: [8]),
        MacBookKey(id: "v", primary: "V", secondary: "М", width: 1, keyCodes: [9]),
        MacBookKey(id: "b", primary: "B", secondary: "И", width: 1, keyCodes: [11]),
        MacBookKey(id: "n", primary: "N", secondary: "Т", width: 1, keyCodes: [45]),
        MacBookKey(id: "m", primary: "M", secondary: "Ь", width: 1, keyCodes: [46]),
        MacBookKey(id: "comma", primary: ",", secondary: "Б", width: 1, keyCodes: [43]),
        MacBookKey(id: "period", primary: ".", secondary: "Ю", width: 1, keyCodes: [47]),
        MacBookKey(id: "slash", primary: "/", secondary: ".", width: 1, keyCodes: [44]),
        MacBookKey(id: "right-shift", primary: "shift", width: 2.40, keyCodes: [60], alignLeading: true)
    ]

    static let bottomRowLeft: [MacBookKey] = [
        MacBookKey(id: "fn", primary: "fn", systemImage: "globe", width: 1, keyCodes: [63]),
        MacBookKey(id: "control", primary: "control", width: 1, keyCodes: [59]),
        MacBookKey(id: "option", primary: "option", width: 1, keyCodes: [58]),
        MacBookKey(id: "command", primary: "command", width: 1.25, keyCodes: [55]),
        MacBookKey(id: "space", primary: "", width: 5, keyCodes: [49]),
        MacBookKey(id: "right-command", primary: "command", width: 1.25, keyCodes: [54]),
        MacBookKey(id: "right-option", primary: "option", width: 1, keyCodes: [61])
    ]

    static var testableKeyCodes: Set<Int64> {
        let rows = functionRow + numberRow + tabRow + homeRow + shiftRow + bottomRowLeft
        return Set(rows.flatMap(\.keyCodes)).union([123, 124, 125, 126])
    }
}

struct KeyboardDiagnosticSection: View {
    @ObservedObject private var service: KeyboardDiagnosticService

    init(service: KeyboardDiagnosticService) {
        self._service = ObservedObject(wrappedValue: service)
    }

    private var expectedKeyCodes: Set<Int64> { MacBookKeyboardLayout.testableKeyCodes }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            VStack(spacing: 12) {
                controlStrip

                MacBookKeyboardMap(
                    activeKeyCodes: service.activeKeyCodes,
                    testedKeyCodes: service.testedKeyCodes
                )
                .frame(height: 284)
                .padding(.horizontal, 16)

                diagnosticsFooter
            }
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surfaceCardLight)
                    .shadow(color: Color.shadowMedium, radius: 5, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(service.isRunning ? Color.accentBlue.opacity(0.30) : Color.borderLight, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                KeyboardEventCaptureView(
                    isRunning: service.isRunning,
                    onEvent: { event, phase in service.handle(event, phase: phase) },
                    onKeyCode: { keyCode, phase, isRepeat in service.handle(keyCode: keyCode, phase: phase, isRepeat: isRepeat) },
                    onFocusChange: { focused in service.setFocus(focused) }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
        }
        .onDisappear {
            service.stop()
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentBlue.opacity(0.10)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Live Keyboard Matrix")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text("Start the test, then press each physical key and watch the exact keycap respond.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondaryLight)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(service.isRunning ? (service.hasFocus ? "Listening" : "Click panel") : "Ready")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(service.isRunning && service.hasFocus ? Color.accentGreen : Color.textTertiaryLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill((service.isRunning && service.hasFocus ? Color.accentGreen : Color.black).opacity(0.08))
                    )

                keyboardLastUsedBadge(service.lastUsedAt)
            }
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 10) {
            metricTile(label: "Keys Tested", value: "\(service.testedCount)/\(expectedKeyCodes.count)", color: .accentBlue)
            metricTile(label: "Pressed Now", value: "\(service.activeCount)", color: service.activeCount > 0 ? .accentGreen : .textTertiaryLight)
            metricTile(label: "Total Presses", value: "\(service.pressCount)", color: .accentPurple)
            metricTile(label: "Repeats", value: "\(service.repeatCount)", color: service.repeatCount > 0 ? .accentAmber : .textTertiaryLight)

            Spacer(minLength: 10)

            Button {
                service.isRunning ? service.stop() : service.start()
            } label: {
                Label(service.isRunning ? "Stop Test" : "Start Test", systemImage: service.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(service.isRunning ? Color.accentRed : Color.accentBlue))
            }
            .buttonStyle(.plain)

            Button {
                service.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondaryLight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.black.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    private var diagnosticsFooter: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Pressed now")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiaryLight)

                if service.activeKeyCodes.isEmpty {
                    Text(service.isRunning ? "Press keys on the MacBook keyboard." : "Start the test to capture key events.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondaryLight)
                } else {
                    HStack(spacing: 5) {
                        ForEach(Array(service.activeKeyCodes).sorted(), id: \.self) { code in
                            Text(service.label(for: code))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentBlue))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                Text("Recent events")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiaryLight)

                HStack(spacing: 5) {
                    ForEach(service.eventLog.prefix(6)) { entry in
                        Text("\(entry.label) \(entry.phase.label)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(entry.phase == .up ? Color.textSecondaryLight : Color.accentBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.04)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    private func metricTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiaryLight)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(width: 92, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.borderLight, lineWidth: 1))
        )
    }
}

private func keyboardLastUsedBadge(_ date: Date?) -> some View {
    HStack(spacing: 5) {
        Image(systemName: "clock")
            .font(.system(size: 9, weight: .semibold))
        Text(keyboardLastUsedText(date))
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
    }
    .foregroundStyle(Color.textTertiaryLight)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
        Capsule()
            .fill(Color.black.opacity(0.035))
            .overlay(Capsule().strokeBorder(Color.borderLight, lineWidth: 1))
    )
    .help(keyboardLastUsedHelp(date))
}

private func keyboardLastUsedText(_ date: Date?) -> String {
    guard let date else { return "Last used: Never" }
    return "Last used: \(KeyboardLastUsedFormatter.shared.string(from: date))"
}

private func keyboardLastUsedHelp(_ date: Date?) -> String {
    guard let date else { return "This test has not been used yet." }
    return "Last used at \(KeyboardLastUsedFormatter.shared.string(from: date))."
}

private enum KeyboardLastUsedFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct MacBookKeyboardMap: View {
    let activeKeyCodes: Set<Int64>
    let testedKeyCodes: Set<Int64>

    var body: some View {
        GeometryReader { geo in
            let gap = max(4, min(7, geo.size.width * 0.0048))
            let unit = (geo.size.width - gap * 13) / MacBookKeyboardLayout.totalUnits
            let keyHeight = max(34, min(43, unit * 0.76))
            let functionHeight = max(28, keyHeight * 0.78)

            VStack(spacing: gap) {
                keyRow(MacBookKeyboardLayout.functionRow, unit: unit, gap: gap, height: functionHeight)
                keyRow(MacBookKeyboardLayout.numberRow, unit: unit, gap: gap, height: keyHeight)
                keyRow(MacBookKeyboardLayout.tabRow, unit: unit, gap: gap, height: keyHeight)
                keyRow(MacBookKeyboardLayout.homeRow, unit: unit, gap: gap, height: keyHeight)
                keyRow(MacBookKeyboardLayout.shiftRow, unit: unit, gap: gap, height: keyHeight)
                bottomRow(unit: unit, gap: gap, height: keyHeight)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func keyRow(_ keys: [MacBookKey], unit: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(keys) { key in
                KeycapView(
                    key: key,
                    width: key.width * unit,
                    height: height,
                    isPressed: !activeKeyCodes.isDisjoint(with: key.keyCodes),
                    wasTested: !testedKeyCodes.isDisjoint(with: key.keyCodes)
                )
            }
        }
    }

    private func bottomRow(unit: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(MacBookKeyboardLayout.bottomRowLeft) { key in
                KeycapView(
                    key: key,
                    width: key.width * unit,
                    height: height,
                    isPressed: !activeKeyCodes.isDisjoint(with: key.keyCodes),
                    wasTested: !testedKeyCodes.isDisjoint(with: key.keyCodes)
                )
            }

            ArrowClusterView(
                unit: unit,
                gap: gap,
                height: height,
                activeKeyCodes: activeKeyCodes,
                testedKeyCodes: testedKeyCodes
            )
        }
    }
}

private struct KeycapView: View {
    let key: MacBookKey
    let width: CGFloat
    let height: CGFloat
    let isPressed: Bool
    let wasTested: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: min(7, height * 0.18), style: .continuous)
                .fill(fill)
                .shadow(color: isPressed ? Color.accentBlue.opacity(0.28) : Color.black.opacity(0.06),
                        radius: isPressed ? 7 : 2,
                        x: 0,
                        y: isPressed ? 2 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: min(7, height * 0.18), style: .continuous)
                        .strokeBorder(stroke, lineWidth: isPressed ? 1.35 : 0.8)
                )

            legend
                .padding(.horizontal, width > 70 ? 9 : 4)
        }
        .frame(width: width, height: height)
        .scaleEffect(isPressed ? 0.965 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var legend: some View {
        HStack {
            if key.alignLeading {
                legendContent
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                legendContent
                Spacer(minLength: 0)
            }
        }
    }

    private var legendContent: some View {
        VStack(spacing: 1) {
            if let systemImage = key.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: min(13, height * 0.34), weight: .medium))
                if !key.primary.isEmpty {
                    Text(key.primary)
                        .font(.system(size: min(8.5, height * 0.22), weight: .medium))
                }
            } else if let secondary = key.secondary {
                Text(key.primary)
                    .font(.system(size: min(12, height * 0.30), weight: .semibold))
                Text(secondary)
                    .font(.system(size: min(10.5, height * 0.26), weight: .medium))
            } else {
                Text(key.primary)
                    .font(.system(size: labelSize, weight: key.width > 1.4 ? .medium : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
        .foregroundStyle(foreground)
    }

    private var labelSize: CGFloat {
        if key.width >= 1.8 { return min(11, height * 0.28) }
        if key.width >= 1.2 { return min(10, height * 0.26) }
        return min(12, height * 0.30)
    }

    private var fill: Color {
        if isPressed { return Color.accentBlue }
        if wasTested { return Color.accentBlue.opacity(0.14) }
        if !key.isTestable { return Color.black.opacity(0.045) }
        return Color.white
    }

    private var stroke: Color {
        if isPressed { return Color.accentBlue.opacity(0.80) }
        if wasTested { return Color.accentBlue.opacity(0.35) }
        return Color.black.opacity(key.isTestable ? 0.12 : 0.06)
    }

    private var foreground: Color {
        if isPressed { return Color.white }
        if !key.isTestable { return Color.textTertiaryLight }
        return Color.textPrimaryLight
    }
}

private struct ArrowClusterView: View {
    let unit: CGFloat
    let gap: CGFloat
    let height: CGFloat
    let activeKeyCodes: Set<Int64>
    let testedKeyCodes: Set<Int64>

    private let left = MacBookKey(id: "left-arrow", primary: "", systemImage: "arrow.left", width: 1, keyCodes: [123])
    private let up = MacBookKey(id: "up-arrow", primary: "", systemImage: "arrow.up", width: 1, keyCodes: [126])
    private let down = MacBookKey(id: "down-arrow", primary: "", systemImage: "arrow.down", width: 1, keyCodes: [125])
    private let right = MacBookKey(id: "right-arrow", primary: "", systemImage: "arrow.right", width: 1, keyCodes: [124])

    var body: some View {
        let halfHeight = (height - gap) / 2

        HStack(spacing: gap) {
            arrow(left, width: unit, height: height)
            VStack(spacing: gap) {
                arrow(up, width: unit, height: halfHeight)
                arrow(down, width: unit, height: halfHeight)
            }
            arrow(right, width: unit, height: height)
        }
        .frame(width: 3 * unit + 2 * gap, height: height)
    }

    private func arrow(_ key: MacBookKey, width: CGFloat, height: CGFloat) -> some View {
        KeycapView(
            key: key,
            width: width,
            height: height,
            isPressed: !activeKeyCodes.isDisjoint(with: key.keyCodes),
            wasTested: !testedKeyCodes.isDisjoint(with: key.keyCodes)
        )
    }
}

private struct KeyboardEventCaptureView: NSViewRepresentable {
    let isRunning: Bool
    let onEvent: (NSEvent, KeyboardDiagnosticPhase) -> Void
    let onKeyCode: (Int64, KeyboardDiagnosticPhase, Bool) -> Void
    let onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onEvent = onEvent
        view.onKeyCode = onKeyCode
        view.onFocusChange = onFocusChange
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onEvent = onEvent
        nsView.onKeyCode = onKeyCode
        nsView.onFocusChange = onFocusChange
        nsView.setCapturing(isRunning)
        if isRunning {
            DispatchQueue.main.async {
                nsView.focusIfNeeded()
            }
        }
    }

    final class CaptureView: NSView {
        var onEvent: ((NSEvent, KeyboardDiagnosticPhase) -> Void)?
        var onKeyCode: ((Int64, KeyboardDiagnosticPhase, Bool) -> Void)?
        var onFocusChange: ((Bool) -> Void)?
        private var localMonitor: Any?
        private var lastReportedFocus: Bool?

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        deinit {
            removeLocalMonitor()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard localMonitor != nil else {
                reportFocus(force: true)
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.focusIfNeeded()
            }
        }

        override func mouseDown(with event: NSEvent) {
            focusIfNeeded()
        }

        override func keyDown(with event: NSEvent) {
            // Captured by the local monitor while the test is running.
        }

        override func keyUp(with event: NSEvent) {
            // Captured by the local monitor while the test is running.
        }

        override func flagsChanged(with event: NSEvent) {
            // Captured by the local monitor while the test is running.
        }

        func setCapturing(_ capturing: Bool) {
            capturing ? installLocalMonitor() : removeLocalMonitor()
            reportFocus()
        }

        func focusIfNeeded() {
            if window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
            reportFocus()
        }

        func reportFocus(force: Bool = false) {
            let focused = localMonitor != nil && (window?.isKeyWindow ?? false) && window?.firstResponder === self
            guard force || lastReportedFocus != focused else { return }
            lastReportedFocus = focused
            onFocusChange?(focused)
        }

        private func installLocalMonitor() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
                self?.capture(event)
                return event
            }
        }

        private func removeLocalMonitor() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            reportFocus(force: true)
        }

        private func capture(_ event: NSEvent) {
            switch event.type {
            case .keyDown:
                onEvent?(event, .down)
            case .keyUp:
                onEvent?(event, .up)
            case .flagsChanged:
                onEvent?(event, .modifierChanged)
            case .systemDefined:
                if let mapped = Self.mappedSystemKey(event) {
                    onKeyCode?(mapped.keyCode, mapped.phase, mapped.isRepeat)
                }
            default:
                break
            }
        }

        private static func mappedSystemKey(_ event: NSEvent) -> (keyCode: Int64, phase: KeyboardDiagnosticPhase, isRepeat: Bool)? {
            guard event.subtype.rawValue == 8 else { return nil }
            let rawKeyType = (event.data1 & 0xFFFF0000) >> 16
            let rawState = (event.data1 & 0x0000FF00) >> 8
            let repeatFlag = (event.data1 & 0x1) == 1

            let keyMap: [Int: Int64] = [
                3: 122,  // brightness down / F1
                2: 120,  // brightness up / F2
                18: 98,  // previous / F7
                16: 100, // play-pause / F8
                17: 101, // next / F9
                7: 109,  // mute / F10
                1: 103,  // volume down / F11
                0: 111   // volume up / F12
            ]

            guard let keyCode = keyMap[Int(rawKeyType)] else { return nil }
            let phase: KeyboardDiagnosticPhase = rawState == 0x0B ? .up : .down
            return (keyCode, phase, repeatFlag)
        }
    }
}
