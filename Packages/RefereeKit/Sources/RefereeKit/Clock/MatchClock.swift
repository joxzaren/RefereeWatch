import Foundation

/// Value type state machine for the match clock, stoppages and added time.
///
/// Nothing counts ticks: every value is recomputed from stored anchors and the
/// anchor passed in. Configuration is passed to each call and never stored.
public struct MatchClock: Codable, Sendable, Equatable {
    public private(set) var period: Period
    /// One record per period that has started, in order.
    public private(set) var records: [PeriodRecord]

    public init() {
        period = .notStarted
        records = []
    }

    // MARK: Transitions

    /// Moves to `period.next(config)`. Kick off is an advance from `notStarted`.
    /// Ending a playing period closes an open stoppage at `at` and records the
    /// announced added time when normal end has passed. Does nothing once finished.
    public mutating func advance(at: Anchor, config: MatchConfig) {
        guard period != .finished else { return }
        let next = period.next(config)
        if let i = currentIndex {
            if period.isPlaying {
                if let s = records[i].stoppages.indices.last, records[i].stoppages[s].isOpen {
                    records[i].stoppages[s].end = at
                }
                markAnnounced(at: at, config: config)
            }
            records[i].end = at
        }
        period = next
        records.append(PeriodRecord(period: next, start: at))
    }

    public var isStoppageOpen: Bool {
        current?.stoppages.last?.isOpen ?? false
    }

    /// Starts a stoppage. False when not in a playing period or one is already open.
    @discardableResult
    public mutating func startStoppage(at: Anchor) -> Bool {
        guard period.isPlaying, let i = currentIndex, !isStoppageOpen else { return false }
        records[i].stoppages.append(Stoppage(start: at))
        return true
    }

    /// Ends the open stoppage. False when not in a playing period or none is open.
    @discardableResult
    public mutating func endStoppage(at: Anchor) -> Bool {
        guard period.isPlaying, let i = currentIndex, let s = records[i].stoppages.indices.last,
              records[i].stoppages[s].isOpen else { return false }
        records[i].stoppages[s].end = at
        return true
    }

    // MARK: Clock values

    /// Match clock value in a playing period (it keeps running during stoppages),
    /// seconds into the break during a break, and 0 otherwise.
    public func elapsed(at: Anchor, config: MatchConfig) -> TimeInterval {
        guard let record = current else { return 0 }
        if period.isPlaying {
            return clockValue(of: at, in: record, config: config)
        }
        if period.isBreak {
            return max(0, at.seconds(since: record.start))
        }
        return 0
    }

    /// Seconds left in the current break, never below 0. Nil outside a break.
    public func breakRemaining(at: Anchor, config: MatchConfig) -> TimeInterval? {
        guard period.isBreak else { return nil }
        return max(0, period.length(config) - elapsed(at: at, config: config))
    }

    public func display(at: Anchor, config: MatchConfig) -> ClockDisplay {
        let e = elapsed(at: at, config: config)
        if period.isPlaying {
            let end = period.normalEnd(config)
            if e >= end {
                return ClockDisplay(main: ClockDisplay.clockString(end), overrun: ClockDisplay.overrunString(e - end))
            }
            return ClockDisplay(main: ClockDisplay.clockString(e))
        }
        if period.isBreak {
            let length = period.length(config)
            if e >= length {
                return ClockDisplay(main: ClockDisplay.clockString(0), overrun: ClockDisplay.overrunString(e - length))
            }
            return ClockDisplay(main: ClockDisplay.clockString(length - e))
        }
        return ClockDisplay(main: ClockDisplay.clockString(0))
    }

    /// Football minute for the current playing period. Outside a playing period
    /// it is the minute of the period's start offset.
    public func minute(at: Anchor, config: MatchConfig) -> MatchMinute {
        MatchMinute.at(elapsed: elapsed(at: at, config: config), period: period, config: config)
    }

    /// True in a playing period once the clock has reached the normal end.
    public func isPastNormalEnd(at: Anchor, config: MatchConfig) -> Bool {
        period.isPlaying && elapsed(at: at, config: config) >= period.normalEnd(config)
    }

    // MARK: Stoppages and added time

    /// Stopped time in the current period, split at the normal end. An open
    /// stoppage counts up to `at`. Zero outside a playing period.
    public func stoppedTime(at: Anchor, config: MatchConfig) -> (beforeNormalEnd: TimeInterval, duringAddedTime: TimeInterval) {
        guard period.isPlaying, let record = current else { return (0, 0) }
        let end = period.normalEnd(config)
        var before: TimeInterval = 0
        var during: TimeInterval = 0
        for stoppage in record.stoppages {
            let s = clockValue(of: stoppage.start, in: record, config: config)
            let e = max(s, clockValue(of: stoppage.end ?? at, in: record, config: config))
            before += max(0, min(e, end) - min(s, end))
            during += max(0, max(e, end) - max(s, end))
        }
        return (before, during)
    }

    /// `ceil(beforeNormalEnd / 60)`: 0 stays 0, 1 to 60 seconds is 1, 120 seconds is 2.
    public func suggestedAddedMinutes(at: Anchor, config: MatchConfig) -> Int {
        let before = stoppedTime(at: at, config: config).beforeNormalEnd
        return Int((before / 60).rounded(.up))
    }

    /// True in a playing period from the first (largest) warning offset before normal end onward.
    public func showsAddedTimeSuggestion(at: Anchor, config: MatchConfig) -> Bool {
        guard period.isPlaying else { return false }
        let lead = config.warningOffsets.max() ?? 0
        return elapsed(at: at, config: config) >= period.normalEnd(config) - lead
    }

    /// Crown input. Before normal end it sets the referee value to
    /// `max(0, shown + delta)`. After normal end only a positive delta is
    /// accepted and it adds to the increases. Returns false when refused
    /// (not in a playing period, zero delta, or a decrease after normal end).
    @discardableResult
    public mutating func adjustAddedTime(by deltaMinutes: Int, at: Anchor, config: MatchConfig) -> Bool {
        guard period.isPlaying, let i = currentIndex, deltaMinutes != 0 else { return false }
        if isPastNormalEnd(at: at, config: config) {
            guard deltaMinutes > 0 else { return false }
            records[i].addedTime.increases += deltaMinutes
            return true
        }
        let shown = records[i].addedTime.refereeMinutes ?? suggestedAddedMinutes(at: at, config: config)
        records[i].addedTime.refereeMinutes = max(0, shown + deltaMinutes)
        return true
    }

    /// `(refereeMinutes ?? suggestion) + increases` for the current period.
    /// After normal end the suggestion can no longer grow, so the value is fixed
    /// apart from increases. 0 outside a playing period.
    public func announcedAddedMinutes(at: Anchor, config: MatchConfig) -> Int {
        guard period.isPlaying, let record = current else { return 0 }
        let base = record.addedTime.refereeMinutes ?? suggestedAddedMinutes(at: at, config: config)
        return base + record.addedTime.increases
    }

    /// Match clock value at which added time ends:
    /// `normalEnd + announced * 60 + duringAddedTime`. Nil while a stoppage is
    /// open or outside a playing period. Provisional before normal end.
    public func addedTimeDeadline(at: Anchor, config: MatchConfig) -> TimeInterval? {
        guard period.isPlaying, !isStoppageOpen else { return nil }
        let during = stoppedTime(at: at, config: config).duringAddedTime
        return period.normalEnd(config) + TimeInterval(announcedAddedMinutes(at: at, config: config)) * 60 + during
    }

    /// Records the announced minutes for the current period, for the report and
    /// sync only. Idempotent. Does nothing before normal end, where the value is
    /// still provisional, or outside a playing period.
    public mutating func markAnnounced(at: Anchor, config: MatchConfig) {
        guard let i = currentIndex, isPastNormalEnd(at: at, config: config) else { return }
        records[i].addedTime.recordedAnnounced = announcedAddedMinutes(at: at, config: config)
    }

    public func recordedAnnouncedMinutes(for period: Period) -> Int? {
        records.last { $0.period == period }?.addedTime.recordedAnnounced
    }

    /// Anchor at which `period` started, if it has.
    public func startAnchor(of period: Period) -> Anchor? {
        records.last { $0.period == period }?.start
    }

    /// Stoppage intervals recorded for `period`.
    public func stoppages(in period: Period) -> [Stoppage] {
        records.last { $0.period == period }?.stoppages ?? []
    }

    // MARK: Private

    private var currentIndex: Int? {
        guard let i = records.indices.last, records[i].period == period else { return nil }
        return i
    }

    private var current: PeriodRecord? {
        currentIndex.map { records[$0] }
    }

    private func clockValue(of anchor: Anchor, in record: PeriodRecord, config: MatchConfig) -> TimeInterval {
        record.period.startOffset(config) + max(0, anchor.seconds(since: record.start))
    }
}
