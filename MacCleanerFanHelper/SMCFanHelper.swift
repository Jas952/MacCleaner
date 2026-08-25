import Foundation
import AppKit
import IOKit
import Security

@objc protocol MacCleanerFanHelperProtocol {
    func status(withReply reply: @escaping (Bool, String?) -> Void)
    func setManualRPM(_ rpm: Int, fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func setAutomatic(fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void)
    func setAllAutomatic(withReply reply: @escaping (Bool, String?) -> Void)
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers0: UInt8 = 0; var vers1: UInt8 = 0; var vers2: UInt8 = 0; var vers3: UInt8 = 0
    var vers4: UInt16 = 0
    var pLim0: UInt16 = 0; var pLim1: UInt16 = 0
    var pLim2: UInt32 = 0; var pLim3: UInt32 = 0; var pLim4: UInt32 = 0
    var infoSize: UInt32 = 0; var infoType: UInt32 = 0; var infoAttr: UInt8 = 0
    var result: UInt8 = 0; var status: UInt8 = 0; var data8: UInt8 = 0
    var pad0: UInt8 = 0; var pad1: UInt8 = 0; var data32: UInt32 = 0
    var bytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
}

private final class SMCWriter {
    private var connection: io_connect_t = 0
    private var modeKeys: [String] = []
    private var hasForceTest = false

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
        for key in ["F0Md", "F0md"] where keyExists(key) { modeKeys.append(key) }
        hasForceTest = keyExists("Ftst")
        guard !modeKeys.isEmpty else { close(); return nil }
    }

    deinit { close() }

    func setManual(rpm: Int, fan: Int) -> (Bool, String?) {
        guard fan >= 0, fan < 16, let modeKey = modeKey(for: fan) else { return (false, "Fan mode key is unavailable.") }
        guard (0...16_383).contains(rpm) else { return (false, "Fan target is outside the FPE2 range.") }
        var forceTestEnabled = false
        if !writeUInt8(key: modeKey, value: 1) {
            guard hasForceTest, writeUInt8(key: "Ftst", value: 1) else {
                return (false, "Firmware rejected manual mode.")
            }
            forceTestEnabled = true
            // thermalmonitord yields asynchronously after Ftst is enabled.
            // Keep the retry bounded so a broken firmware cannot hang the UI.
            let deadline = Date().addingTimeInterval(10)
            var unlocked = false
            while Date() < deadline {
                if writeUInt8(key: modeKey, value: 1) { unlocked = true; break }
                usleep(100_000)
            }
            guard unlocked else {
                _ = writeUInt8(key: "Ftst", value: 0)
                return (false, "Timed out waiting for thermal management to yield control.")
            }
        }
        let targetKey = String(format: "F%dTg", fan)
        guard writeFPE2(key: targetKey, value: rpm) else {
            _ = writeUInt8(key: modeKey, value: 0)
            if forceTestEnabled { _ = writeUInt8(key: "Ftst", value: 0) }
            return (false, "Firmware rejected the fan target; automatic mode was restored.")
        }
        return (true, nil)
    }

    func setAuto(fan: Int) -> (Bool, String?) {
        guard let modeKey = modeKey(for: fan), writeUInt8(key: modeKey, value: 0) else {
            return (false, "Firmware rejected automatic mode.")
        }
        return (true, nil)
    }

    func setAllAuto() -> (Bool, String?) {
        var firstError: String?
        for fan in 0..<16 where modeKey(for: fan) != nil {
            let result = setAuto(fan: fan)
            if !result.0, firstError == nil { firstError = result.1 }
        }
        if hasForceTest { _ = writeUInt8(key: "Ftst", value: 0) }
        return (firstError == nil, firstError)
    }

    private func modeKey(for fan: Int) -> String? {
        let upper = String(format: "F%dMd", fan)
        if keyExists(upper) { return upper }
        let lower = String(format: "F%dmd", fan)
        return keyExists(lower) ? lower : nil
    }

    private func keyExists(_ key: String) -> Bool { readKeyInfo(key: key) != nil }

    private func call(_ input: inout SMCKeyData, _ output: inout SMCKeyData) -> Bool {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return withUnsafeMutablePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(connection, 2, inputPointer, MemoryLayout<SMCKeyData>.stride,
                                           outputPointer, &outputSize) == kIOReturnSuccess
            }
        }
    }

    private func readKeyInfo(key: String) -> SMCKeyData? {
        var input = SMCKeyData(); var output = SMCKeyData()
        input.key = code(key); input.data8 = 9
        return call(&input, &output) ? output : nil
    }

    private func writeUInt8(key: String, value: UInt8) -> Bool {
        guard let info = readKeyInfo(key: key) else { return false }
        var input = SMCKeyData(); var output = SMCKeyData()
        input.key = code(key); input.infoSize = info.infoSize; input.data8 = 6; input.bytes.0 = value
        return call(&input, &output)
    }

    private func writeFPE2(key: String, value: Int) -> Bool {
        guard (0...16_383).contains(value), let info = readKeyInfo(key: key) else { return false }
        let raw = UInt16(value * 4)
        var input = SMCKeyData(); var output = SMCKeyData()
        input.key = code(key); input.infoSize = info.infoSize; input.data8 = 6
        input.bytes.0 = UInt8(raw >> 8); input.bytes.1 = UInt8(raw & 0xff)
        return call(&input, &output)
    }

    private func code(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func close() { if connection != 0 { IOServiceClose(connection); connection = 0 } }
}

private final class Helper: NSObject, NSXPCListenerDelegate, MacCleanerFanHelperProtocol {
    private static let authorizedClientBundleIdentifier = "com.maccleaner.app"
    private let listener = NSXPCListener(machServiceName: "com.maccleaner.fanhelper")
    private let smc = SMCWriter()
    private var manualRPMByFan: [Int: Int] = [:]

    func run() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Apple Silicon firmware resets the diagnostic/manual state on
            // wake. Re-apply only the user's active manual targets.
            guard let self, !self.manualRPMByFan.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                for (fan, rpm) in self.manualRPMByFan {
                    _ = self.smc?.setManual(rpm: rpm, fan: fan)
                }
            }
        }
        listener.delegate = self
        listener.resume()
        RunLoop.current.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isAuthorizedClient(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: MacCleanerFanHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in _ = self?.smc?.setAllAuto() }
        connection.interruptionHandler = { [weak self] in _ = self?.smc?.setAllAuto() }
        connection.resume()
        return true
    }

    private func isAuthorizedClient(_ connection: NSXPCConnection) -> Bool {
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)
        ] as CFDictionary
        var guestCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess,
              let guestCode else { return false }

        guard let teamIdentifier = Bundle.main.object(forInfoDictionaryKey: "MacCleanerAuthorizedTeamIdentifier") as? String,
              !teamIdentifier.isEmpty else { return false }
        let requirementString = "identifier \"\(Self.authorizedClientBundleIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementString as CFString,
            [],
            &requirement
        ) == errSecSuccess, let requirement else { return false }
        return SecCodeCheckValidity(guestCode, [], requirement) == errSecSuccess
    }

    func status(withReply reply: @escaping (Bool, String?) -> Void) {
        reply(smc != nil, smc == nil ? "Apple Silicon SMC fan keys are unavailable." : nil)
    }

    func setManualRPM(_ rpm: Int, fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void) {
        guard (0..<16).contains(fanIndex) else {
            reply(false, "Invalid fan index.")
            return
        }
        let result = smc?.setManual(rpm: rpm, fan: fanIndex) ?? (false, "SMC is unavailable.")
        if result.0 { manualRPMByFan[fanIndex] = rpm }
        reply(result.0, result.1)
    }

    func setAutomatic(fanIndex: Int, withReply reply: @escaping (Bool, String?) -> Void) {
        guard (0..<16).contains(fanIndex) else {
            reply(false, "Invalid fan index.")
            return
        }
        let result = smc?.setAuto(fan: fanIndex) ?? (false, "SMC is unavailable.")
        if result.0 { manualRPMByFan.removeValue(forKey: fanIndex) }
        reply(result.0, result.1)
    }

    func setAllAutomatic(withReply reply: @escaping (Bool, String?) -> Void) {
        let result = smc?.setAllAuto() ?? (false, "SMC is unavailable.")
        if result.0 { manualRPMByFan.removeAll() }
        reply(result.0, result.1)
    }
}

@main
private struct MacCleanerFanHelperMain {
    static func main() {
        let helper = Helper()
        withExtendedLifetime(helper) {
            helper.run()
        }
    }
}
