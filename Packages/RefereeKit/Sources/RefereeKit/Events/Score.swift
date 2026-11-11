import Foundation

/// Goals per team. Always computed from live events or kicks, never stored on a match.
public struct Score: Codable, Sendable, Hashable {
    public var home: Int
    public var away: Int

    public init(home: Int = 0, away: Int = 0) {
        self.home = home
        self.away = away
    }

    public static let zero = Score()

    public subscript(side: Side) -> Int {
        get { side == .home ? home : away }
        set {
            if side == .home { home = newValue } else { away = newValue }
        }
    }

    /// The side ahead, or nil when level.
    public var leader: Side? {
        home == away ? nil : (home > away ? .home : .away)
    }

    /// Score from the live goal events in `events`. Tombstoned goals do not count.
    public static func goals(in events: some Sequence<MatchEvent>) -> Score {
        var score = Score()
        for event in events where event.isLive && event.kind == .goal {
            score[event.side] += 1
        }
        return score
    }
}
