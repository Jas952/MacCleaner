import Foundation

/// Narrow IPC boundary for the Apple Silicon privileged fan helper.
///
/// The main application must never write restricted SMC keys directly. The
/// helper is installed separately with SMJobBless and validates every request.
@objc protocol MacCleanerFanHelperProtocol {
    func status(withReply reply: @escaping (Bool, String?) -> Void)
    func setManualRPM(_ rpm: Int, fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func setAutomatic(fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func setAllAutomatic(withReply reply: @escaping (Bool, String?) -> Void)
}

enum FanControlAvailability: Equatable {
    case notAppleSilicon
    case helperNotInstalled
    case helperUnavailable(String)
    case ready
}

/// Main-process client. Calls are bounded and fail closed when the helper is
/// absent, so the UI never silently reports a successful fan change.
final class FanControlXPCClient {
    static let shared = FanControlXPCClient()

    private let machServiceName = "com.maccleaner.fanhelper"
    private var connection: NSXPCConnection?
    private let lock = NSLock()

    private init() {}

    func installHelper(completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            switch FanHelperInstaller.install() {
            case .success:
                DispatchQueue.main.async { completion(true, nil) }
            case .failure(let error):
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }

    var availability: FanControlAvailability {
        guard ProcessInfo.processInfo.isAppleSilicon else { return .notAppleSilicon }
        let installedPath = "/Library/PrivilegedHelperTools/\(machServiceName)"
        return FileManager.default.isExecutableFile(atPath: installedPath) ? .ready : .helperNotInstalled
    }

    func setManualRPM(_ rpm: Int, fanIndex: Int, completion: @escaping (Bool, String?) -> Void) {
        guard (0...16_383).contains(rpm), fanIndex >= 0 else {
            completion(false, "The requested fan value is outside the safe range.")
            return
        }
        withProxy(completion: completion) { proxy in
            proxy.setManualRPM(rpm, fanIndex: fanIndex, withReply: completion)
        }
    }

    func setAutomatic(fanIndex: Int, completion: @escaping (Bool, String?) -> Void) {
        guard fanIndex >= 0 else {
            completion(false, "Invalid fan index.")
            return
        }
        withProxy(completion: completion) { proxy in
            proxy.setAutomatic(fanIndex: fanIndex, withReply: completion)
        }
    }

    func setAllAutomatic(completion: @escaping (Bool, String?) -> Void) {
        withProxy(completion: completion) { proxy in
            proxy.setAllAutomatic(withReply: completion)
        }
    }

    private func withProxy(completion: @escaping (Bool, String?) -> Void,
                           operation: @escaping (MacCleanerFanHelperProtocol) -> Void) {
        let connection = makeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            self.invalidate(connection)
            completion(false, "Fan helper is unavailable: \(error.localizedDescription)")
        } as? MacCleanerFanHelperProtocol
        guard let proxy else {
            invalidate(connection)
            completion(false, "Fan helper is not installed.")
            return
        }
        operation(proxy)
    }

    private func makeConnection() -> NSXPCConnection {
        lock.lock(); defer { lock.unlock() }
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: MacCleanerFanHelperProtocol.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let connection else { return }
            self?.invalidate(connection)
        }
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let connection else { return }
            self?.invalidate(connection)
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func invalidate(_ connection: NSXPCConnection) {
        lock.lock(); defer { lock.unlock() }
        if self.connection === connection {
            self.connection = nil
        }
    }
}

private extension ProcessInfo {
    var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
