import Foundation

public enum AlertKind: Codable, Sendable, Hashable {
    case warning(secondsBefore: Int)
    case normalEnd
    case addedTimeEnd
    case breakEnd

    /// Stable key used in alert ids.
    public var key: String {
        switch self {
        case .warning(let s): "warning\(s)"
        case .normalEnd: "normalEnd"
        case .addedTimeEnd: "addedTimeEnd"
        case .breakEnd: "breakEnd"
        }
    }
}

public struct PlannedAlert: Sendable, Hashable {
    /// `"\(matchID)-\(period.rawValue)-\(kind.key)"`, so rescheduling replaces rather than duplicates.
    public var id: String
    public var kind: AlertKind
    /// Clock value at which it is due: the match clock in a playing period,
    /// seconds into the break during a break.
    public var dueElapsed: TimeInterval
    /// Seconds from `now` until it is due. Always greater than zero.
    public var secondsFromNow: TimeInterval

    public init(id: String, kind: AlertKind, dueElapsed: TimeInterval, secondsFromNow: TimeInterval) {
        self.id = id
        self.kind = kind
        self.dueElapsed = dueElapsed
        self.secondsFromNow = secondsFromNow
    }
}

/// What fires when, for the current period only.
public enum AlertPlan {
    /// Upcoming alerts for the current period, sorted by due time. Alerts that
    /// are due now or already past are left out. The end of added time is left
    /// out while a stoppage is open and is provisional before normal end.
    public static func alerts(clock: MatchClock, config: MatchConfig, matchID: UUID, now: Anchor) -> [PlannedAlert] {
        let period = clock.period
        let elapsed = clock.elapsed(at: now, config: config)
        var result: [PlannedAlert] = []

        func add(_ kind: AlertKind, due: TimeInterval) {
            guard due > elapsed else { return }
            result.append(PlannedAlert(
                id: "\(matchID.uuidString)-\(period.rawValue)-\(kind.key)",
                kind: kind,
                dueElapsed: due,
                secondsFromNow: due - elapsed
            ))
        }

        if period.isPlaying {
            let end = period.normalEnd(config)
            let length = period.length(config)
            for offset in Set(config.warningOffsets.map { Int($0.rounded()) }).sorted(by: >)
            where offset > 0 && TimeInterval(offset) < length {
                add(.warning(secondsBefore: offset), due: end - TimeInterval(offset))
            }
            add(.normalEnd, due: end)
            if let deadline = clock.addedTimeDeadline(at: now, config: config) {
                add(.addedTimeEnd, due: deadline)
            }
        } else if period.isBreak {
            add(.breakEnd, due: period.length(config))
        }
        return result.sorted { $0.dueElapsed < $1.dueElapsed }
    }
}
