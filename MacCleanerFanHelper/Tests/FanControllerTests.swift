import Foundation

final class FakeSMC: FanSMC {
    var values: [String: Float] = ["FNum": 2, "F0Md": 0, "F1Md": 0, "F0Mn": 2317, "F1Mn": 2317,
        "F0Mx": 6800, "F1Mx": 6800, "F0Tg": 2317, "F1Tg": 2502, "Ftst": 0]
    var writes: [String] = []
    var unlockDelay = 0
    var resetDelay = 0
    var releasing = false
    var rejectTarget = false
    var rejectAuto = false
    var delayTarget = 0
    var pending: (String, Float)?
    func number(_ key: String) throws -> Float {
        guard let value = values[key] else { throw FanError("Missing \(key)") }
        return value
    }
    func writeByte(_ key: String, _ value: UInt8) throws {
        if key.hasSuffix("Md") && value == 1 && unlockDelay > 0 { throw FanError("Thermal manager has not yielded yet") }
        if key == "Ftst" && value == 0 && resetDelay > 0 { releasing = true; return }
        if rejectAuto && value == 0 { throw FanError("Injected restore failure") }
        writes.append(key); values[key] = Float(value)
    }
    func writeRPM(_ key: String, _ value: Int) throws {
        writes.append(key)
        if rejectTarget { throw FanError("Injected target failure") }
        if delayTarget > 0 { pending = (key, Float(value)) }
        else { values[key] = Float(value) }
    }
    func advance() {
        if values["Ftst"] == 1 && unlockDelay > 0 { unlockDelay -= 1 }
        if releasing && resetDelay > 0 { resetDelay -= 1; if resetDelay == 0 { values["Ftst"] = 0; releasing = false } }
        if delayTarget > 0 { delayTarget -= 1 }
        if delayTarget == 0, let pending { values[pending.0] = pending.1; self.pending = nil }
    }
}

@main struct FanControllerTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name); count += 1; print("PASS \(name)")
        }
        func rejected(_ action: () throws -> Void) -> Bool { do { try action(); return false } catch { return true } }
        let smc = FakeSMC(), id = UUID()
        let controller = FanController(smc: smc)
        var clock = Date(timeIntervalSince1970: 100)
        controller.now = { clock }; controller.pause = { smc.advance() }
        check(rejected { try controller.manual(2000, fan: 0, session: id) }, "below hardware minimum rejected")
        check(rejected { try controller.manual(6801, fan: 0, session: id) }, "above hardware maximum rejected")
        check(smc.writes.isEmpty, "invalid requests perform no writes")
        smc.values["F0Md"] = 1
        check(rejected { try controller.boost(session: id) }, "foreign manual controller rejected")
        check(smc.writes.isEmpty, "foreign controller left untouched")
        smc.values["F0Md"] = 0
        smc.values["Ftst"] = 1
        check(rejected { try controller.boost(session: id) }, "foreign diagnostic mode rejected")
        check(smc.writes.isEmpty, "foreign diagnostic mode left untouched")
        smc.values["Ftst"] = 0
        smc.delayTarget = 2
        try controller.manual(3300, fan: 0, session: id)
        check(smc.values["F0Tg"] == 3300 && controller.owner == id, "delayed readback accepted")
        check(rejected { try controller.manual(3500, fan: 1, session: UUID()) }, "second session cannot take over")
        controller.disconnected(UUID())
        check(smc.values["F0Md"] == 1, "unrelated disconnect does not reset owner")
        controller.disconnected(id)
        check(smc.values["F0Md"] == 0 && controller.owner == nil, "owner disconnect restores Auto")
        try controller.boost(session: id)
        check(smc.values["F0Tg"] == 6800 && smc.values["F1Tg"] == 6800, "boost uses both hardware maxima")
        clock.addTimeInterval(9); controller.tick()
        check(smc.values["F0Md"] == 1, "boost stays active before deadline")
        controller.heartbeat(id)
        clock.addTimeInterval(1); controller.tick()
        check(smc.values["F0Md"] == 0 && smc.values["F1Md"] == 0, "boost deadline independent of heartbeat")
        try controller.manual(3300, fan: 0, session: id)
        clock.addTimeInterval(16); controller.tick()
        check(controller.owner == nil && smc.values["F0Md"] == 0, "lost heartbeat restores Auto")
        smc.rejectTarget = true
        check(rejected { try controller.manual(3300, fan: 0, session: id) }, "failed target reports failure")
        check(smc.values["F0Md"] == 0, "failed target restores Auto")
        smc.rejectTarget = false
        try controller.manual(3300, fan: 0, session: id)
        smc.rejectAuto = true
        check(controller.restoreAll() != nil && !controller.controlled.isEmpty, "failed restoration retained for retry")
        controller.heartbeat(id)
        smc.rejectAuto = false; controller.tick()
        check(controller.controlled.isEmpty && smc.values["F0Md"] == 0, "watchdog retries restoration despite heartbeat")
        try controller.manual(3300, fan: 0, session: id)
        smc.values["F0Md"] = 3; smc.rejectAuto = true
        let writesBeforeSystemAuto = smc.writes.count
        check(controller.restoreAll() == nil, "system Auto after sleep is accepted without redundant write")
        check(smc.writes.count == writesBeforeSystemAuto && controller.controlled.isEmpty, "system Auto clears ownership without writes")
        smc.rejectAuto = false; smc.values["F0Md"] = 0
        smc.unlockDelay = 40; smc.values["F0Md"] = 3
        try controller.manual(3300, fan: 0, session: id)
        check(smc.values["F0Md"] == 1 && controller.forceTestEnabled, "system manual unlock waits beyond two seconds")
        smc.resetDelay = 3
        check(controller.restoreAll() == nil && smc.values["Ftst"] == 0, "delayed Ftst reset is verified")
        smc.unlockDelay = 1; smc.values["F0Md"] = 3
        try controller.manual(3400, fan: 0, session: id)
        smc.values["F1Md"] = 1 // Ftst can expose Manual globally in telemetry.
        try controller.manual(3600, fan: 1, session: id)
        try controller.automatic(fan: 0, session: id)
        check(
            controller.controlled == [1] && smc.values["F0Md"] == 0 && smc.values["F1Md"] == 1,
            "forced mode keeps fan channels independent"
        )
        check(smc.values["F1Tg"] == 3600, "remaining fan target survives independent Auto")
        controller.restoreAll()
        controller.lastError = "old failure"
        try controller.automatic(fan: 0, session: id)
        check(controller.lastError == nil, "verified Auto clears obsolete error")
        var recoveryPrepared = false, recoveryCleared = false
        controller.prepareRecovery = { recoveryPrepared = true }
        controller.clearRecovery = { recoveryCleared = true }
        try controller.manual(3300, fan: 0, session: id)
        check(recoveryPrepared, "crash recovery prepared before control")
        controller.restoreAll()
        check(recoveryCleared, "recovery marker cleared after verified Auto")
        print("\(count) checks passed")
    }
}
