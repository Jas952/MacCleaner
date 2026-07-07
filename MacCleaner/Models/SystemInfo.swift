import Foundation

struct MemoryInfo {
    let total: UInt64
    let used: UInt64
    let free: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64

    var usedPercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }

    static func formatted(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

struct CPUInfo {
    let totalUsage: Double
    let coreUsages: [Double]
    let processorCount: Int
}

struct DiskInfo: Identifiable {
    let id = UUID()
    let mountPoint: String
    let volumeName: String
    let total: UInt64
    let used: UInt64
    let free: UInt64

    var usedPercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }

    static func formatted(_ bytes: UInt64) -> String {
        let tb = Double(bytes) / 1_099_511_627_776
        if tb >= 1 { return String(format: "%.1f TB", tb) }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

struct BatteryInfo {
    var currentCapacity: Int    = 0   // mAh
    var maxCapacity: Int        = 0   // mAh (current max)
    var designCapacity: Int     = 0   // mAh (factory design)
    var cycleCount: Int         = 0
    var voltage: Double         = 0   // V
    var amperage: Double        = 0   // A (neg = discharging)
    var temperature: Double     = 0   // °C
    var isCharging: Bool        = false
    var isPluggedIn: Bool       = false
    var chargePercent: Int      = 0
    var timeRemaining: Int      = 0   // minutes, -1 = calculating
    var devices: [BatteryDeviceInfo] = []

    var healthPercent: Double {
        guard designCapacity > 0 else { return 0 }
        return min(100, Double(maxCapacity) / Double(designCapacity) * 100)
    }

    var healthLabel: String {
        let h = healthPercent
        if h > 90 { return "Normal" }
        if h > 75 { return "Good" }
        if h > 60 { return "Fair" }
        return "Replace Soon"
    }

    var healthColor: String {   // named for UI
        let h = healthPercent
        if h > 90 { return "green" }
        if h > 75 { return "amber" }
        return "red"
    }

    var wattage: Double { abs(voltage * amperage) }
}

struct BatteryDeviceInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let chargePercent: Int
    let isCharging: Bool
}

struct NetworkInfo {
    var downloadBytesPerSecond: Double = 0
    var uploadBytesPerSecond: Double = 0
    var interfaceName: String = "N/A"
    var address: String = "N/A"
    var totalReceived: UInt64 = 0
    var totalSent: UInt64 = 0

    var isActive: Bool {
        downloadBytesPerSecond > 1 || uploadBytesPerSecond > 1
    }

    static func formattedRate(_ bytesPerSecond: Double) -> String {
        let absValue = max(0, bytesPerSecond)
        if absValue >= 1_048_576 {
            return String(format: "%.1f MB/s", absValue / 1_048_576)
        }
        if absValue >= 1024 {
            return String(format: "%.0f KB/s", absValue / 1024)
        }
        return String(format: "%.0f B/s", absValue)
    }
}

struct AppProcessInfo: Identifiable {
    let id: Int32
    let name: String
    let cpuUsage: Double
    let memoryBytes: UInt64
}
