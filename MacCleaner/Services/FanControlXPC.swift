import Foundation
import AppKit

@objc protocol MacCleanerFanHelperProtocol {
    func status(withReply reply: @escaping (Bool, String?) -> Void)
    func setManualRPM(_ rpm: Int, fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func setAutomatic(fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func setAllAutomatic(withReply reply: @escaping (Bool, String?) -> Void)
    func boostForTenSeconds(withReply reply: @escaping (Bool, String?) -> Void)
    func controlState(withReply reply: @escaping (Int, [NSNumber], String?) -> Void)
    func heartbeat(withReply reply: @escaping () -> Void)
}

enum FanControlAvailability: Equatable {
    case notAppleSilicon
    case helperNotInstalled
    case helperUnavailable(String)
    case ready
}

/// One connection owns this app’s manual targets. Closing it restores Auto;
/// a helper-side lease also covers hangs and unexpected process loss.
final class FanControlXPCClient {
    static let shared = FanControlXPCClient()
    private var connection: NSXPCConnection?
    private let lock = NSRecursiveLock()
    private var heartbeatTimer: DispatchSourceTimer?
    private init() {}

    var availability: FanControlAvailability {
        #if arch(arm64)
        return FanHelperInstaller.isCurrent ? .ready : .helperNotInstalled
        #else
        return .notAppleSilicon
        #endif
    }
    func installHelper(completion: @escaping (Bool, String?) -> Void) {
        // The action is commonly initiated from the menu bar popover. Bring the
        // owning app forward before osascript asks SecurityAgent for approval,
        // otherwise the administrator sheet can open behind another MacCleaner
        // copy or behind the dismissed popover and look as if Enable did nothing.
        NSApp.activate(ignoringOtherApps: true)
        resetConnection()
        DispatchQueue.global(qos: .userInitiated).async {
            switch FanHelperInstaller.install() {
            case .success:
                self.checkStatus(completion: completion)
            case .failure(let error):
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }
    func checkStatus(completion: @escaping (Bool, String?) -> Void) {
        perform(completion) { $0.status(withReply: $1) }
    }
    func setManualRPM(_ rpm: Int, fanIndex: Int, completion: @escaping (Bool, String?) -> Void) {
        perform(completion) { $0.setManualRPM(rpm, fanIndex: fanIndex, withReply: $1) }
    }
    func setAutomatic(fanIndex: Int, completion: @escaping (Bool, String?) -> Void) {
        perform(completion) { $0.setAutomatic(fanIndex: fanIndex, withReply: $1) }
    }
    func setAllAutomatic(completion: @escaping (Bool, String?) -> Void) {
        perform(completion) { $0.setAllAutomatic(withReply: $1) }
    }
    func boostForTenSeconds(completion: @escaping (Bool, String?) -> Void) {
        perform(completion) { $0.boostForTenSeconds(withReply: $1) }
    }
    func controlState(completion: @escaping (Int, Set<Int>, String?) -> Void) {
        // Reuse the bounded, exactly-once RPC path for polling too.
        var seconds = 0
        var controlledFanIDs: Set<Int> = []
        perform({ _, error in completion(seconds, controlledFanIDs, error) }) { proxy, done in
            proxy.controlState { remaining, fanIDs, error in
                DispatchQueue.main.async {
                    seconds = remaining
                    controlledFanIDs = Set(fanIDs.map(\.intValue))
                    done(error == nil, error)
                }
            }
        }
    }
    private func perform(_ completion: @escaping (Bool, String?) -> Void,
                         operation: @escaping (MacCleanerFanHelperProtocol, @escaping (Bool, String?) -> Void) -> Void) {
        let once = ReplyOnce(completion)
        do {
            let connection = try makeConnection()
            let timeout = DispatchWorkItem { [weak self, weak connection] in
                if once.finish(false, "Fan helper timed out. Automatic recovery is running.") {
                    if let connection { self?.invalidate(connection) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
            let finish: (Bool, String?) -> Void = { success, message in
                timeout.cancel(); _ = once.finish(success, message)
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
                self?.invalidate(connection)
                finish(false, "Fan helper unavailable: \(error.localizedDescription)")
            }) as? MacCleanerFanHelperProtocol else {
                finish(false, "Fan helper unavailable."); return
            }
            operation(proxy, finish)
        } catch { _ = once.finish(false, error.localizedDescription) }
    }
    private func makeConnection() throws -> NSXPCConnection {
        lock.lock(); defer { lock.unlock() }
        if let connection { return connection }
        let requirement = try FanHelperInstaller.requirement(for: FanHelperInstaller.bundledHelper)
        let connection = NSXPCConnection(machServiceName: FanHelperInstaller.helperIdentifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: MacCleanerFanHelperProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        connection.invalidationHandler = { [weak self, weak connection] in
            if let connection { self?.invalidate(connection) }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume(); self.connection = connection
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak connection] in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? MacCleanerFanHelperProtocol else { return }
            proxy.heartbeat {}
        }
        timer.resume(); heartbeatTimer = timer
        return connection
    }
    private func resetConnection() {
        lock.lock(); defer { lock.unlock() }
        if let connection { invalidate(connection) }
    }
    private func invalidate(_ connection: NSXPCConnection) {
        lock.lock(); defer { lock.unlock() }
        if self.connection === connection {
            self.connection = nil
            heartbeatTimer?.cancel(); heartbeatTimer = nil
            connection.invalidate()
        }
    }
}

private final class ReplyOnce {
    private let lock = NSLock()
    private var completed = false
    private let completion: (Bool, String?) -> Void
    init(_ completion: @escaping (Bool, String?) -> Void) { self.completion = completion }
    @discardableResult func finish(_ success: Bool, _ message: String?) -> Bool {
        lock.lock()
        guard !completed else { lock.unlock(); return false }
        completed = true; lock.unlock()
        DispatchQueue.main.async { self.completion(success, message) }
        return true
    }
}
