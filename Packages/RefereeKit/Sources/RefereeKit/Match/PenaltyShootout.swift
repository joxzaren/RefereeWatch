import Foundation

/// One kick in a penalty shootout. Versioned and merged like an event.
public struct PenaltyKick: Codable, Sendable, Hashable, Identifiable, Versioned {
    public var id: UUID
    public var side: Side
    public var shirtNumber: Int?
    public var scored: Bool
    /// Position in the shootout, starting at 1 and counting both teams.
    public var order: Int
    /// The device that logged the kick. Undo last only touches this device's kicks.
    public var createdBy: String
    public var createdAt: Date
    public var version: Version

    public init(
        id: UUID = UUID(),
        side: Side,
        shirtNumber: Int? = nil,
        scored: Bool,
        order: Int,
        createdBy: String,
        createdAt: Date,
        version: Version
    ) {
        self.id = id
        self.side = side
        self.shirtNumber = shirtNumber
        self.scored = scored
        self.order = order
        self.createdBy = createdBy
        self.createdAt = SyncCoding.normalize(createdAt)
        self.version = version
    }

    public var isLive: Bool { !version.deleted }
}

/// Reads a shootout from its kicks. Tombstoned kicks are ignored.
public struct PenaltyShootout: Sendable, Hashable {
    public static let regulationKicks = 5

    /// Live kicks in shootout order.
    public let kicks: [PenaltyKick]

    public init(kicks: [PenaltyKick]) {
        self.kicks = kicks.filter(\.isLive).sorted {
            ($0.order, $0.createdAt, $0.id.uuidString) < ($1.order, $1.createdAt, $1.id.uuidString)
        }
    }

    public var score: Score {
        var score = Score()
        for kick in kicks where kick.scored { score[kick.side] += 1 }
        return score
    }

    /// Kicks taken by each team.
    public var taken: Score {
        var taken = Score()
        for kick in kicks { taken[kick.side] += 1 }
        return taken
    }

    /// The winner, decided at the first kick after which the result is certain:
    /// - In the first five kicks each, as soon as one team cannot catch up even if it
    ///   scores all its remaining kicks and the other misses all of its.
    /// - After five each (sudden death), when both have taken the same number of kicks
    ///   and the scores differ.
    /// Kicks logged after the decision do not change it.
    public var winner: Side? {
        var goals = Score()
        var taken = Score()
        for kick in kicks {
            taken[kick.side] += 1
            if kick.scored { goals[kick.side] += 1 }
            if let side = Self.decided(goals: goals, taken: taken) { return side }
        }
        return nil
    }

    /// True once a winner is known.
    public var isDecided: Bool { winner != nil }

    static func decided(goals: Score, taken: Score) -> Side? {
        let n = regulationKicks
        if taken.home <= n && taken.away <= n {
            if goals.home + (n - taken.home) < goals.away { return .away }
            if goals.away + (n - taken.away) < goals.home { return .home }
            return nil
        }
        if taken.home == taken.away && goals.home != goals.away {
            return goals.home > goals.away ? .home : .away
        }
        return nil
    }
}
