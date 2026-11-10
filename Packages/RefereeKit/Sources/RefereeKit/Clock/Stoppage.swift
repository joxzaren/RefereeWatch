import Foundation

/// One stoppage interval. `end` is nil while the stoppage is open.
public struct Stoppage: Codable, Sendable, Hashable {
    public var start: Anchor
    public var end: Anchor?

    public init(start: Anchor, end: Anchor? = nil) {
        self.start = start
        self.end = end
    }

    public var isOpen: Bool { end == nil }
}

/// Added time state for one playing period.
public struct AddedTimeState: Codable, Sendable, Hashable {
    /// Set by the crown before normal end. Overrides the suggestion.
    public var refereeMinutes: Int?
    /// Minutes added after normal end. Can only grow.
    public var increases: Int
    /// Announced minutes written for the report and sync. Never used for timing.
    public var recordedAnnounced: Int?

    public init(refereeMinutes: Int? = nil, increases: Int = 0, recordedAnnounced: Int? = nil) {
        self.refereeMinutes = refereeMinutes
        self.increases = increases
        self.recordedAnnounced = recordedAnnounced
    }
}

/// Everything recorded about one period that has started.
public struct PeriodRecord: Codable, Sendable, Hashable {
    public var period: Period
    public var start: Anchor
    /// Set when the period ends.
    public var end: Anchor?
    public var stoppages: [Stoppage]
    public var addedTime: AddedTimeState

    public init(period: Period, start: Anchor, end: Anchor? = nil, stoppages: [Stoppage] = [], addedTime: AddedTimeState = AddedTimeState()) {
        self.period = period
        self.start = start
        self.end = end
        self.stoppages = stoppages
        self.addedTime = addedTime
    }
}
