import Foundation
import Network

@_silgen_name("proc_pid_rusage")
func proc_pid_rusage(_ pid: Int32, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer) -> Int32

struct rusage_info_v4 {
    var ri_uuid: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    var ri_user_time: UInt64 = 0
    var ri_system_time: UInt64 = 0
    var ri_pkg_idle_wkups: UInt64 = 0
    var ri_interrupt_wkups: UInt64 = 0
    var ri_pageins: UInt64 = 0
    var ri_wired_size: UInt64 = 0
    var ri_resident_size: UInt64 = 0
    var ri_phys_footprint: UInt64 = 0
    var ri_proc_start_abstime: UInt64 = 0
    var ri_proc_exit_abstime: UInt64 = 0
    var ri_child_user_time: UInt64 = 0
    var ri_child_system_time: UInt64 = 0
    var ri_child_pkg_idle_wkups: UInt64 = 0
    var ri_child_interrupt_wkups: UInt64 = 0
    var ri_child_pageins: UInt64 = 0
    var ri_child_elapsed_abstime: UInt64 = 0
    var ri_diskio_bytesread: UInt64 = 0
    var ri_diskio_byteswritten: UInt64 = 0
    var ri_cpu_time_qos_default: UInt64 = 0
    var ri_cpu_time_qos_maintenance: UInt64 = 0
    var ri_cpu_time_qos_background: UInt64 = 0
    var ri_cpu_time_qos_utility: UInt64 = 0
    var ri_cpu_time_qos_legacy: UInt64 = 0
    var ri_cpu_time_qos_user_initiated: UInt64 = 0
    var ri_cpu_time_qos_user_interactive: UInt64 = 0
    var ri_billed_system_time: UInt64 = 0
    var ri_serviced_system_time: UInt64 = 0
    var ri_logical_writes: UInt64 = 0
    var ri_lifetime_max_phys_footprint: UInt64 = 0
    var ri_instructions: UInt64 = 0
    var ri_cycles: UInt64 = 0
    var ri_billed_energy: UInt64 = 0
    var ri_serviced_energy: UInt64 = 0
    var ri_interval_max_phys_footprint: UInt64 = 0
    var ri_runnable_time: UInt64 = 0
}

struct ProcessInfoPayload: Codable {
    let pid: Int32
    let footprint: UInt64
    let diskRead: UInt64
    let diskWritten: UInt64
}

let RUSAGE_INFO_V4: Int32 = 4

func fetchAllUsage() -> [ProcessInfoPayload] {
    let task = Process()
    task.launchPath = "/bin/ps"
    task.arguments = ["-axo", "pid"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard let out = String(data: data, encoding: .utf8) else { return [] }
    
    var results: [ProcessInfoPayload] = []
    let lines = out.components(separatedBy: .newlines).dropFirst()
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let pid = Int32(trimmed) else { continue }
        
        var ru = rusage_info_v4()
        let ret = withUnsafeMutablePointer(to: &ru) { ptr in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, ptr)
        }
        if ret == 0 {
            results.append(ProcessInfoPayload(
                pid: pid,
                footprint: ru.ri_phys_footprint,
                diskRead: ru.ri_diskio_bytesread,
                diskWritten: ru.ri_diskio_byteswritten
            ))
        }
    }
    return results
}

func processName(pid: Int32) -> String {
    let task = Process()
    task.launchPath = "/bin/ps"
    task.arguments = ["-p", "\(pid)", "-o", "comm="]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func isProtectedProcess(pid: Int32) -> Bool {
    if pid <= 1 { return true }
    let name = processName(pid: pid).lowercased()
    let protectedNames = [
        "kernel_task", "launchd", "windowserver", "logd", "mds", "mds_stores",
        "coreaudiod", "configd", "opendirectoryd", "diskarbitrationd"
    ]
    if protectedNames.contains(where: { name.contains($0) }) { return true }
    return name.hasPrefix("com.apple.security") ||
        name.hasPrefix("com.apple.system") ||
        name.hasPrefix("kernel")
}

func terminateProcess(pid: Int32) -> Bool {
    guard !isProtectedProcess(pid: pid) else { return false }
    if kill(pid, SIGTERM) == 0 { return true }
    Thread.sleep(forTimeInterval: 1.0)
    if kill(pid, 0) != 0 { return true }
    return kill(pid, SIGKILL) == 0
}

func handleRequest(request: String) -> Data? {
    if request.contains("GET /processes") {
        let payload = fetchAllUsage()
        if let jsonData = try? JSONEncoder().encode(payload) {
            let responseStr = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\n\r\n"
            var respData = responseStr.data(using: .utf8)!
            respData.append(jsonData)
            return respData
        }
    } else if request.contains("POST /purge") {
        let p = Process()
        p.launchPath = "/usr/sbin/purge"
        try? p.run()
        p.waitUntilExit()
        let responseStr = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
        return responseStr.data(using: .utf8)
    } else if request.contains("POST /kill"), let urlStr = request.components(separatedBy: " ").dropFirst().first {
        if let comps = URLComponents(string: urlStr),
           let pidStr = comps.queryItems?.first(where: { $0.name == "pid" })?.value,
           let pid = Int32(pidStr) {
            if terminateProcess(pid: pid) {
                let responseStr = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
                return responseStr.data(using: .utf8)
            }
            let responseStr = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n"
            return responseStr.data(using: .utf8)
        }
    }
    let responseStr = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
    return responseStr.data(using: .utf8)
}

func startServer() {
    let queue = DispatchQueue(label: "com.maccleaner.daemon.server")
    do {
        let listener = try NWListener(using: .tcp, on: 9099)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                if let data = data, let reqStr = String(data: data, encoding: .utf8) {
                    if let resp = handleRequest(request: reqStr) {
                        connection.send(content: resp, completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                        return
                    }
                }
                connection.cancel()
            }
        }
        listener.start(queue: queue)
        print("MacCleanerDaemon started on port 9099")
        dispatchMain()
    } catch {
        print("Failed to start server: \(error)")
        exit(1)
    }
}

startServer()
