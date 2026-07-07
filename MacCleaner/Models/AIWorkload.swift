import Foundation
import SwiftUI

enum AIWorkloadKind: String, CaseIterable, Identifiable {
    case system = "System"
    case userApp = "User App"
    case agent = "Agent"
    case modelRuntime = "Model Runtime"
    case vectorIndex = "Vector / Index"
    case orchestration = "Orchestration"
    case buildTool = "Build / Tooling"
    case unknown = "Unknown"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "gearshape.2"
        case .userApp: return "app.window"
        case .agent: return "sparkles"
        case .modelRuntime: return "brain.head.profile"
        case .vectorIndex: return "point.3.connected.trianglepath.dotted"
        case .orchestration: return "square.stack.3d.up"
        case .buildTool: return "hammer"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .system: return Color.textSecondaryLight
        case .userApp: return Color.accentBlue
        case .agent: return Color(red: 0.48, green: 0.36, blue: 0.9)
        case .modelRuntime: return Color.accentRed
        case .vectorIndex: return Color.accentAmber
        case .orchestration: return Color(red: 0.14, green: 0.65, blue: 0.78)
        case .buildTool: return Color.accentGreen
        case .unknown: return Color.textTertiaryLight
        }
    }
}

struct AIWorkloadProcess: Identifiable {
    let id: Int32
    let name: String
    let kind: AIWorkloadKind
    let cpuUsage: Double
    let memoryBytes: UInt64
    let diskRead: UInt64
    let diskWritten: UInt64
    let parentPID: Int32
    let reason: String
    let commandLine: String
}

enum AIAgentActivityState: String {
    case idle
    case active
    case terminalActive

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .active: return "Active"
        case .terminalActive: return "Tool running"
        }
    }
}

struct AIAgentComponent: Identifiable {
    let title: String
    let path: String
    let kind: String
    let exists: Bool

    var id: String {
        "\(kind)|\(title)|\(path)"
    }
}

struct AIAgentProfile: Identifiable {
    let id: String
    let name: String
    let description: String
    let rootPath: String
    let processes: [AIWorkloadProcess]
    let mcpProcesses: [AIWorkloadProcess]
    let helperProcesses: [AIWorkloadProcess]
    let components: [AIAgentComponent]
    let mcpComponents: [AIAgentComponent]
    let skillComponents: [AIAgentComponent]
    let mcpSourceFound: Bool
    let skillSourceFound: Bool
    let activityState: AIAgentActivityState
    let terminalProcesses: [AIWorkloadProcess]

    var cpuTotal: Double {
        loadProcesses.reduce(0) { $0 + $1.cpuUsage }
    }

    var memoryTotal: UInt64 {
        loadProcesses.reduce(0) { $0 + $1.memoryBytes }
    }

    var loadProcesses: [AIWorkloadProcess] {
        var seen = Set<Int32>()
        var rows: [AIWorkloadProcess] = []
        for process in processes + helperProcesses + terminalProcesses {
            guard !seen.contains(process.id) else { continue }
            seen.insert(process.id)
            rows.append(process)
        }
        return rows.sorted {
            if $0.memoryBytes == $1.memoryBytes { return $0.cpuUsage > $1.cpuUsage }
            return $0.memoryBytes > $1.memoryBytes
        }
    }
}

struct AIWorkloadBucket: Identifiable {
    let kind: AIWorkloadKind
    let processes: [AIWorkloadProcess]

    var id: String { kind.id }
    var cpuTotal: Double { processes.reduce(0) { $0 + $1.cpuUsage } }
    var memoryTotal: UInt64 { processes.reduce(0) { $0 + $1.memoryBytes } }
    var diskTotal: UInt64 { processes.reduce(0) { $0 + $1.diskRead + $1.diskWritten } }
}

struct AIAdvisorRecommendation: Identifiable {
    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String

    enum Severity {
        case info
        case warning
        case critical

        var color: Color {
            switch self {
            case .info: return Color.accentBlue
            case .warning: return Color.accentAmber
            case .critical: return Color.accentRed
            }
        }
    }
}

struct AIWorkloadSnapshot {
    let date: Date
    let buckets: [AIWorkloadBucket]
    let recommendations: [AIAdvisorRecommendation]
    let agents: [AIAgentProfile]
    let systemBucket: AIWorkloadBucket?
    let totalMemoryBytes: UInt64
    let usedMemoryBytes: UInt64

    static func empty(memory: MemoryInfo) -> AIWorkloadSnapshot {
        AIWorkloadSnapshot(
            date: Date(),
            buckets: [],
            recommendations: [],
            agents: [],
            systemBucket: nil,
            totalMemoryBytes: memory.total,
            usedMemoryBytes: memory.used
        )
    }

    var allProcesses: [AIWorkloadProcess] {
        buckets.flatMap(\.processes)
    }

    var agentMemoryBytes: UInt64 {
        agents.reduce(0) { $0 + $1.memoryTotal }
    }

    var agentMemoryShare: Double {
        guard totalMemoryBytes > 0 else { return 0 }
        return Double(agentMemoryBytes) / Double(totalMemoryBytes)
    }

    var memoryUsedShare: Double {
        guard totalMemoryBytes > 0 else { return 0 }
        return Double(usedMemoryBytes) / Double(totalMemoryBytes)
    }

    var systemMemoryBytes: UInt64 {
        usedMemoryBytes > agentMemoryBytes ? usedMemoryBytes - agentMemoryBytes : 0
    }

    var aiCPUShare: Double {
        let aiKinds: Set<AIWorkloadKind> = [.agent, .modelRuntime, .vectorIndex, .orchestration]
        let total = max(buckets.reduce(0) { $0 + $1.cpuTotal }, 0.01)
        let ai = buckets.filter { aiKinds.contains($0.kind) }.reduce(0) { $0 + $1.cpuTotal }
        return ai / total
    }
}
