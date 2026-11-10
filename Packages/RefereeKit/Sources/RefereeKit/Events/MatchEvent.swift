import Foundation

/// One logged event. Every change writes a new `version`; a deletion is a tombstone
/// (`version.deleted == true`) that is kept forever so it wins against older edits.
public struct MatchEvent: Codable, Sendable, Hashable, Identifiable, Versioned {
    public var id: UUID
    public var kind: EventKind
    /// The team the event is credited to. For a goal, the team whose score goes up.
    public var side: Side
    public var shirtNumber: Int?
    /// Substitutions only.
    public var playerOff: Int?
    /// Substitutions only.
    public var playerOn: Int?
    public var period: Period
    public var minute: MatchMinute
    /// The device that logged the event. Undo last only touches this device's events.
    public var createdBy: String
    /// When the event was logged. Never changed by edits.
    public var createdAt: Date
    public var version: Version

    public init(
        id: UUID = UUID(),
        kind: EventKind,
        side: Side,
        shirtNumber: Int? = nil,
        playerOff: Int? = nil,
        playerOn: Int? = nil,
        period: Period,
        minute: MatchMinute,
        createdBy: String,
        createdAt: Date,
        version: Version
    ) {
        self.id = id
        self.kind = kind
        self.side = side
        self.shirtNumber = shirtNumber
        self.playerOff = playerOff
        self.playerOn = playerOn
        self.period = period
        self.minute = minute
        self.createdBy = createdBy
        self.createdAt = SyncCoding.normalize(createdAt)
        self.version = version
    }

    /// Not deleted.
    public var isLive: Bool { !version.deleted }
}

extension Period {
    /// Position in the match, used to order events. Internal to avoid clashing with the clock domain.
    var eventSortIndex: Int { Period.allCases.firstIndex(of: self) ?? 0 }
}
