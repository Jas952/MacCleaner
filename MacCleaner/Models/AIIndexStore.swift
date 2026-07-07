import Foundation

enum AIIndexStoreStatus: String {
    case active = "Active"
    case idle = "Idle"
    case installed = "Installed"
    case missing = "Not found"
}

struct AIIndexStore: Identifiable {
    let id: String
    let name: String
    let kind: String
    let status: AIIndexStoreStatus
    let rootPath: String
    let diskBytes: UInt64
    let processes: [AIWorkloadProcess]
    let components: [AIAgentComponent]
    let dependencies: [AIAgentComponent]

    var memoryBytes: UInt64 {
        processes.reduce(0) { $0 + $1.memoryBytes }
    }

    var cpuTotal: Double {
        processes.reduce(0) { $0 + $1.cpuUsage }
    }
}

