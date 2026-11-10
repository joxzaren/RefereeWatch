import Foundation

/// One match: its setup, clock, events, penalty kicks and workout summary.
///
/// Every part that can change on more than one device carries a `Version` and is merged
/// with `SyncMerge.merge`. `events` and `penalties` hold one entry per id, including
/// tombstones, kept in a canonical order (creation time, then id) so equal content
/// compares equal regardless of the order changes arrived in.
public struct Match: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var createdAt: Date

    public var config: MatchConfig
    public var configVersion: Version

    public var clock: MatchClock
    public var clockVersion: Version

    /// All event versions, including tombstones. Use `liveEvents` for display.
    public var events: [MatchEvent]
    /// All penalty kicks, including tombstones. Use `shootout` for display.
    public var penalties: [PenaltyKick]

    public var workout: WorkoutSummary?
    public var workoutVersion: Version?

    public var kickedOffAt: Date?
    public var finishedAt: Date?
    public var finishVersion: Version?

    public init(id: UUID = UUID(), config: MatchConfig, deviceID: String, now: Date) {
        let stamp = SyncCoding.normalize(now)
        self.id = id
        self.createdAt = stamp
        self.config = Self.normalized(config)
        self.configVersion = Version(modifiedAt: stamp, deviceID: deviceID)
        self.clock = MatchClock()
        self.clockVersion = Version(modifiedAt: stamp, deviceID: deviceID)
        self.events = []
        self.penalties = []
        self.workout = nil
        self.workoutVersion = nil
        self.kickedOffAt = nil
        self.finishedAt = nil
        self.finishVersion = nil
    }

    // MARK: Reading

    /// Live events ordered by period, then minute, then version time.
    public var liveEvents: [MatchEvent] {
        events.filter(\.isLive).sorted { a, b in
            if a.period != b.period { return a.period.eventSortIndex < b.period.eventSortIndex }
            if a.minute != b.minute { return a.minute < b.minute }
            if a.version.modifiedAt != b.version.modifiedAt { return a.version.modifiedAt < b.version.modifiedAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// Computed from live goals only. Never stored.
    public var score: Score { Score.goals(in: events) }

    public var shootout: PenaltyShootout { PenaltyShootout(kicks: penalties) }

    /// The shootout score, or nil when no live kick has been logged.
    public var penaltyScore: Score? {
        let shootout = shootout
        return shootout.kicks.isEmpty ? nil : shootout.score
    }

    public var isKickedOff: Bool { kickedOffAt != nil }
    public var isFinished: Bool { finishedAt != nil }

    public func event(_ id: UUID) -> MatchEvent? { events.first { $0.id == id } }

    // MARK: Events

    /// Logs a new event and returns it.
    @discardableResult
    public mutating func log(
        _ kind: EventKind,
        side: Side,
        shirtNumber: Int? = nil,
        playerOff: Int? = nil,
        playerOn: Int? = nil,
        period: Period,
        minute: MatchMinute,
        deviceID: String,
        now: Date
    ) -> MatchEvent {
        // Strictly after this device's previous event, so undo last is unambiguous.
        let lastOwn = events.filter { $0.createdBy == deviceID }.map(\.createdAt).max()
        let stamp = SyncCoding.stamp(now, after: lastOwn)
        let event = MatchEvent(
            kind: kind,
            side: side,
            shirtNumber: shirtNumber,
            playerOff: playerOff,
            playerOn: playerOn,
            period: period,
            minute: minute,
            createdBy: deviceID,
            createdAt: stamp,
            version: Version(modifiedAt: stamp, deviceID: deviceID))
        events.append(event)
        normalize()
        return event
    }

    /// Tombstones the most recently created live event that this device created.
    /// Returns the tombstoned event, or nil when there is none.
    @discardableResult
    public mutating func undoLast(deviceID: String, now: Date) -> MatchEvent? {
        guard let last = Self.lastOwnLive(events, deviceID: deviceID) else { return nil }
        guard delete(last.id, deviceID: deviceID, now: now) else { return nil }
        return event(last.id)
    }

    /// Changes a live event and writes a new version. The closure may not change the id,
    /// creator, creation time or version. Returns false when there is no live event with that id.
    @discardableResult
    public mutating func edit(_ id: UUID, deviceID: String, now: Date, change: (inout MatchEvent) -> Void) -> Bool {
        guard let index = events.firstIndex(where: { $0.id == id && $0.isLive }) else { return false }
        let original = events[index]
        var edited = original
        change(&edited)
        edited.id = original.id
        edited.createdBy = original.createdBy
        edited.createdAt = original.createdAt
        edited.version = Version.next(after: original.version, deviceID: deviceID, now: now)
        events[index] = edited
        return true
    }

    /// Tombstones a live event. Any device may delete any event.
    /// Returns false when there is no live event with that id.
    @discardableResult
    public mutating func delete(_ id: UUID, deviceID: String, now: Date) -> Bool {
        guard let index = events.firstIndex(where: { $0.id == id && $0.isLive }) else { return false }
        events[index].version = Version.next(after: events[index].version, deviceID: deviceID, now: now, deleted: true)
        return true
    }

    // MARK: Penalties

    /// Logs the next kick in the shootout and returns it.
    @discardableResult
    public mutating func logPenalty(side: Side, shirtNumber: Int? = nil, scored: Bool, deviceID: String, now: Date) -> PenaltyKick {
        let lastOwn = penalties.filter { $0.createdBy == deviceID }.map(\.createdAt).max()
        let stamp = SyncCoding.stamp(now, after: lastOwn)
        let order = (penalties.filter(\.isLive).map(\.order).max() ?? 0) + 1
        let kick = PenaltyKick(
            side: side,
            shirtNumber: shirtNumber,
            scored: scored,
            order: order,
            createdBy: deviceID,
            createdAt: stamp,
            version: Version(modifiedAt: stamp, deviceID: deviceID))
        penalties.append(kick)
        normalize()
        return kick
    }

    /// Tombstones the most recently created live kick that this device created.
    @discardableResult
    public mutating func undoLastPenalty(deviceID: String, now: Date) -> PenaltyKick? {
        guard let last = Self.lastOwnLive(penalties, deviceID: deviceID) else { return nil }
        guard deletePenalty(last.id, deviceID: deviceID, now: now) else { return nil }
        return penalties.first { $0.id == last.id }
    }

    /// Changes a live kick and writes a new version. Returns false when there is no live kick with that id.
    @discardableResult
    public mutating func editPenalty(_ id: UUID, deviceID: String, now: Date, change: (inout PenaltyKick) -> Void) -> Bool {
        guard let index = penalties.firstIndex(where: { $0.id == id && $0.isLive }) else { return false }
        let original = penalties[index]
        var edited = original
        change(&edited)
        edited.id = original.id
        edited.createdBy = original.createdBy
        edited.createdAt = original.createdAt
        edited.version = Version.next(after: original.version, deviceID: deviceID, now: now)
        penalties[index] = edited
        normalize()
        return true
    }

    /// Tombstones a live kick. Returns false when there is no live kick with that id.
    @discardableResult
    public mutating func deletePenalty(_ id: UUID, deviceID: String, now: Date) -> Bool {
        guard let index = penalties.firstIndex(where: { $0.id == id && $0.isLive }) else { return false }
        penalties[index].version = Version.next(after: penalties[index].version, deviceID: deviceID, now: now, deleted: true)
        return true
    }

    // MARK: Match state

    public mutating func updateConfig(_ config: MatchConfig, deviceID: String, now: Date) {
        self.config = Self.normalized(config)
        configVersion = Version.next(after: configVersion, deviceID: deviceID, now: now)
    }

    public mutating func updateClock(_ clock: MatchClock, deviceID: String, now: Date) {
        self.clock = clock
        clockVersion = Version.next(after: clockVersion, deviceID: deviceID, now: now)
    }

    public mutating func setWorkout(_ workout: WorkoutSummary?, deviceID: String, now: Date) {
        self.workout = workout
        workoutVersion = Version.next(after: workoutVersion, deviceID: deviceID, now: now)
    }

    /// Records the first kick off. Later calls keep the first time.
    public mutating func markKickedOff(now: Date) {
        if kickedOffAt == nil { kickedOffAt = SyncCoding.normalize(now) }
    }

    /// Records the final whistle. Later calls keep the first time.
    public mutating func finish(deviceID: String, now: Date) {
        guard finishedAt == nil else { return }
        let version = Version.next(after: finishVersion, deviceID: deviceID, now: now)
        finishedAt = version.modifiedAt
        finishVersion = version
    }

    // MARK: Canonical form

    /// Puts `events` and `penalties` in canonical order.
    public mutating func normalize() {
        events.sort { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        penalties.sort { ($0.order, $0.createdAt, $0.id.uuidString) < ($1.order, $1.createdAt, $1.id.uuidString) }
    }

    public func normalized() -> Match {
        var copy = self
        copy.normalize()
        return copy
    }

    private static func normalized(_ config: MatchConfig) -> MatchConfig {
        var config = config
        config.kickOff = config.kickOff.map(SyncCoding.normalize)
        return config
    }

    private static func lastOwnLive<T: Versioned>(_ items: [T], deviceID: String) -> T?
    where T: OwnedRecord {
        items
            .filter { $0.isLive && $0.createdBy == deviceID }
            .max { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }
}

/// A record created by one device at one time.
protocol OwnedRecord {
    var createdBy: String { get }
    var createdAt: Date { get }
    var isLive: Bool { get }
}

extension MatchEvent: OwnedRecord {}
extension PenaltyKick: OwnedRecord {}
