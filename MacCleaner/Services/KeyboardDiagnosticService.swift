import AppKit
import Foundation

enum KeyboardDiagnosticPhase: String {
    case down
    case up
    case repeatDown
    case modifierChanged

    var label: String {
        switch self {
        case .down: return "Down"
        case .up: return "Up"
        case .repeatDown: return "Repeat"
        case .modifierChanged: return "Mod"
        }
    }
}

struct KeyboardDiagnosticLogEntry: Identifiable {
    let id = UUID()
    let keyCode: Int64
    let label: String
    let phase: KeyboardDiagnosticPhase
    let timestamp: Date
}

private struct KeyboardDiagnosticSavedState: Codable {
    let testedKeyCodes: [Int64]
    let pressCount: Int
    let repeatCount: Int
    let lastUsedAt: Date
}

final class KeyboardDiagnosticService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var activeKeyCodes: Set<Int64> = []
    @Published private(set) var testedKeyCodes: Set<Int64> = []
    @Published private(set) var eventLog: [KeyboardDiagnosticLogEntry] = []
    @Published private(set) var pressCount = 0
    @Published private(set) var repeatCount = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var hasFocus = false
    @Published private(set) var lastUsedAt: Date?

    private let maxLogCount = 12
    private static let modifierKeyCodes: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    private static let persistenceKey = "MacCleaner.Diagnostics.Keyboard.lastState"

    var testedCount: Int { testedKeyCodes.count }
    var activeCount: Int { activeKeyCodes.count }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
              let state = try? JSONDecoder().decode(KeyboardDiagnosticSavedState.self, from: data)
        else { return }
        testedKeyCodes = Set(state.testedKeyCodes)
        pressCount = state.pressCount
        repeatCount = state.repeatCount
        lastUsedAt = state.lastUsedAt
    }

    func start() {
        clearSession()
        isRunning = true
        startedAt = Date()
        persistState()
    }

    func stop() {
        isRunning = false
        activeKeyCodes.removeAll()
        hasFocus = false
    }

    func reset() {
        clearSession()
        startedAt = isRunning ? Date() : nil
        persistState()
    }

    func setFocus(_ focused: Bool) {
        guard hasFocus != focused else { return }
        hasFocus = focused
        if !focused {
            activeKeyCodes.removeAll()
        }
    }

    func handle(_ event: NSEvent, phase: KeyboardDiagnosticPhase) {
        guard isRunning else { return }

        handle(
            keyCode: Int64(event.keyCode),
            phase: phase,
            isRepeat: event.isARepeat,
            modifierFlags: event.modifierFlags
        )
    }

    func handle(keyCode: Int64, phase: KeyboardDiagnosticPhase, isRepeat: Bool = false) {
        guard isRunning else { return }

        handle(
            keyCode: keyCode,
            phase: phase,
            isRepeat: isRepeat,
            modifierFlags: nil
        )
    }

    private func handle(
        keyCode: Int64,
        phase: KeyboardDiagnosticPhase,
        isRepeat: Bool,
        modifierFlags: NSEvent.ModifierFlags?
    ) {
        let resolvedPhase = isRepeat && phase == .down ? KeyboardDiagnosticPhase.repeatDown : phase

        switch resolvedPhase {
        case .down:
            activeKeyCodes.insert(keyCode)
            testedKeyCodes.insert(keyCode)
            pressCount += 1
        case .repeatDown:
            activeKeyCodes.insert(keyCode)
            testedKeyCodes.insert(keyCode)
            repeatCount += 1
        case .up:
            activeKeyCodes.remove(keyCode)
        case .modifierChanged:
            guard Self.modifierKeyCodes.contains(keyCode) else { break }

            testedKeyCodes.insert(keyCode)
            if Self.isModifierActive(keyCode: keyCode, flags: modifierFlags) {
                activeKeyCodes.insert(keyCode)
                pressCount += 1
            } else {
                activeKeyCodes.remove(keyCode)
                if keyCode == 57 {
                    pressCount += 1
                }
            }
        }

        appendLog(keyCode: keyCode, phase: resolvedPhase)
        persistState()
    }

    func label(for keyCode: Int64) -> String {
        Self.keyName(for: keyCode)
    }

    private func appendLog(keyCode: Int64, phase: KeyboardDiagnosticPhase) {
        let entry = KeyboardDiagnosticLogEntry(
            keyCode: keyCode,
            label: Self.keyName(for: keyCode),
            phase: phase,
            timestamp: Date()
        )
        eventLog.insert(entry, at: 0)
        if eventLog.count > maxLogCount {
            eventLog.removeLast(eventLog.count - maxLogCount)
        }
    }

    private func clearSession() {
        activeKeyCodes.removeAll()
        testedKeyCodes.removeAll()
        eventLog.removeAll()
        pressCount = 0
        repeatCount = 0
    }

    private func persistState() {
        let now = Date()
        lastUsedAt = now
        let state = KeyboardDiagnosticSavedState(
            testedKeyCodes: Array(testedKeyCodes).sorted(),
            pressCount: pressCount,
            repeatCount: repeatCount,
            lastUsedAt: now
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private static func isModifierActive(keyCode: Int64, flags modifierFlags: NSEvent.ModifierFlags?) -> Bool {
        let flags = modifierFlags?.intersection(.deviceIndependentFlagsMask) ?? []
        switch Int(keyCode) {
        case 56, 60: return flags.contains(.shift)
        case 59, 62: return flags.contains(.control)
        case 58, 61: return flags.contains(.option)
        case 55, 54: return flags.contains(.command)
        case 57: return flags.contains(.capsLock)
        case 63: return flags.contains(.function)
        default: return false
        }
    }

    private static func keyName(for keyCode: Int64) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Esc"
        case 54: return "Right Cmd"
        case 55: return "Cmd"
        case 56: return "Left Shift"
        case 57: return "Caps Lock"
        case 58: return "Option"
        case 59: return "Control"
        case 60: return "Right Shift"
        case 61: return "Right Option"
        case 62: return "Right Control"
        case 63: return "Fn"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        default: return "Key \(keyCode)"
        }
    }
}
