import Foundation

enum UtilityToolCategory: String, CaseIterable, Identifiable {
    case essentials = "Essentials"
    case capture = "Capture"
    case media = "Media"
    case system = "System"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }
}

enum UtilityToolID: String, CaseIterable, Identifiable, Codable {
    case welcome
    case shelf
    case colorPicker
    case mediaCompressor
    case homebrew
    case audioMixer
    case chargeLimit
    case physical
    case keyboard
    case speaker
    case storage
    case network

    var id: String { rawValue }

    static var configurableCases: [Self] { allCases.filter { $0 != .welcome } }
    static var availableCases: [Self] { configurableCases.filter(\.isAvailableInTools) }

    var isBeta: Bool {
        [.mediaCompressor, .audioMixer, .chargeLimit].contains(self)
    }

    var isAvailableInTools: Bool { !isBeta }

    var title: String {
        switch self {
        case .welcome: return "Tools Home"
        case .shelf: return "Drop Shelf"
        case .colorPicker: return "Color Picker"
        case .mediaCompressor: return "Media Compressor"
        case .homebrew: return "Homebrew"
        case .audioMixer: return "App Audio Report"
        case .chargeLimit: return "Charge Limit"
        case .physical: return "Physical Maintenance"
        case .keyboard: return "Input Test"
        case .speaker: return "Speaker Test"
        case .storage: return "Device Health"
        case .network: return "Network Test"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "A focused workspace for everyday utilities"
        case .shelf: return "Park files, links and text temporarily"
        case .colorPicker: return "Sample any screen pixel"
        case .mediaCompressor: return "Compress images locally"
        case .homebrew: return "Audit and maintain installed packages"
        case .audioMixer: return "Inspect audio routes and mixer compatibility"
        case .chargeLimit: return "Battery capability and system settings"
        case .physical: return "Screen blackout and keyboard lock"
        case .keyboard: return "Keyboard, trackpad and mouse"
        case .speaker: return "Left/right channel check"
        case .storage: return "SSD, APFS and battery"
        case .network: return "Reachability and latency"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "sparkles"
        case .shelf: return "tray.and.arrow.down"
        case .colorPicker: return "eyedropper"
        case .mediaCompressor: return "arrow.down.right.and.arrow.up.left"
        case .homebrew: return "mug"
        case .audioMixer: return "waveform.and.magnifyingglass"
        case .chargeLimit: return "battery.75percent"
        case .physical: return "wrench.and.screwdriver"
        case .keyboard: return "keyboard"
        case .speaker: return "speaker.wave.3"
        case .storage: return "stethoscope"
        case .network: return "network"
        }
    }

    var category: UtilityToolCategory {
        switch self {
        case .welcome, .shelf: return .essentials
        case .colorPicker: return .capture
        case .mediaCompressor: return .media
        case .homebrew, .chargeLimit: return .system
        case .audioMixer: return .diagnostics
        case .physical, .keyboard, .speaker, .storage, .network: return .diagnostics
        }
    }

    var enabledByDefault: Bool {
        switch self {
        case .physical, .keyboard, .speaker, .storage, .network, .shelf, .colorPicker:
            return true
        default:
            return false
        }
    }

    var supportsMenuBar: Bool {
        [.shelf, .colorPicker].contains(self)
    }
}

enum MenuBarGaugeValueFormat: String, Codable, Identifiable {
    case percent
    case value
    case cores
    case temperature
    case fahrenheit
    case time

    var id: String { rawValue }

    var compactTitle: String {
        switch self {
        case .percent: return "P"
        case .value: return "V"
        case .cores: return "C"
        case .temperature: return "C"
        case .fahrenheit: return "F"
        case .time: return "T"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .percent: return "Percent"
        case .value: return "Value"
        case .cores: return "Core count"
        case .temperature: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        case .time: return "Time remaining"
        }
    }
}

enum MenuBarGaugeDisplayStyle: String, CaseIterable, Codable, Identifiable {
    case battery
    case value

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: return "Battery"
        case .value: return "Values"
        }
    }

    var icon: String {
        switch self {
        case .battery: return "battery.75percent"
        case .value: return "percent"
        }
    }

    var detail: String {
        switch self {
        case .battery: return "Compact fill indicators"
        case .value: return "Percentages and numbers"
        }
    }
}

enum MenuBarGauge: String, CaseIterable, Identifiable {
    case cpu
    case ram
    case gpu
    case temperature
    case battery

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .ram: return "Memory"
        case .gpu: return "GPU"
        case .temperature: return "Temperature"
        case .battery: return "Battery"
        }
    }

    var shortTitle: String {
        switch self {
        case .ram: return "RAM"
        case .temperature: return "TEMP"
        case .battery: return "BAT"
        default: return rawValue.uppercased()
        }
    }

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .ram: return "memorychip"
        case .gpu: return "rectangle.3.group"
        case .temperature: return "thermometer.medium"
        case .battery: return "battery.75percent"
        }
    }

    var valueFormats: [MenuBarGaugeValueFormat] {
        switch self {
        case .cpu: return [.percent, .cores]
        case .ram: return [.percent, .value]
        case .gpu: return [.percent, .temperature]
        case .temperature: return [.temperature, .fahrenheit]
        case .battery: return [.percent, .time]
        }
    }

    func formatMarker(for format: MenuBarGaugeValueFormat) -> MenuBarGaugeFormatMarker {
        switch self {
        case .cpu:
            return .text(format == .cores ? "C" : "%")
        case .ram:
            return .text(format == .value ? "G" : "%")
        case .gpu:
            return .text(format == .temperature ? "°" : "%")
        case .temperature:
            return .text(format == .fahrenheit ? "F" : "C")
        case .battery:
            return format == .time ? .symbol("clock") : .text("%")
        }
    }
}

enum MenuBarGaugeFormatMarker: Equatable {
    case text(String)
    case symbol(String)
}
