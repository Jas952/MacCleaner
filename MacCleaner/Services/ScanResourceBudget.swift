import Foundation

/// A single sequential budget shared by every root in one filesystem scan.
/// It prevents many individually bounded directory walks from adding up to an
/// unbounded app-wide I/O burst.
struct ScanResourceBudget: Sendable {
    let maximumEntries: Int
    let deadline: Date
    private(set) var consumedEntries = 0
    private(set) var wasLimited = false

    init(maximumEntries: Int, maximumDuration: TimeInterval, startedAt: Date = Date()) {
        self.maximumEntries = max(maximumEntries, 1)
        self.deadline = startedAt.addingTimeInterval(max(maximumDuration, 0))
    }

    mutating func beginRoot(now: Date = Date()) -> Bool {
        guard consumedEntries < maximumEntries, now < deadline else {
            wasLimited = true
            return false
        }
        return true
    }

    mutating func consumeEntry() -> Bool {
        guard consumedEntries < maximumEntries else {
            wasLimited = true
            return false
        }
        if consumedEntries.isMultiple(of: 64), Date() >= deadline {
            wasLimited = true
            return false
        }
        consumedEntries += 1
        return true
    }

    mutating func markLimited() {
        wasLimited = true
    }
}
