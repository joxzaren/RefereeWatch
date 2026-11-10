import Foundation

/// One live event as it appears in the report.
public struct ReportEvent: Sendable, Hashable {
    public var kind: EventKind
    public var side: Side
    public var team: String
    public var period: Period
    public var minute: MatchMinute
    public var shirtNumber: Int?
    public var playerOff: Int?
    public var playerOn: Int?

    public init(event: MatchEvent, config: MatchConfig) {
        kind = event.kind
        side = event.side
        team = config.name(of: event.side)
        period = event.period
        minute = event.minute
        shirtNumber = event.shirtNumber
        playerOff = event.playerOff
        playerOn = event.playerOn
    }
}

/// A line of the match report, in order. The iPhone renders these to PDF.
public enum ReportLine: Sendable, Hashable {
    case header(home: String, away: String, competition: String, date: Date)
    case finalScore(home: String, away: String, score: Score, penalties: Score?)
    /// Starts the events of a period.
    case period(Period)
    case event(ReportEvent)
    case penaltyKick(team: String, shirtNumber: Int?, scored: Bool, order: Int)
    case workout(WorkoutSummary)

    /// Plain text for the line. Numbers use a fixed format; the date uses `timeZone`.
    public func text(timeZone: TimeZone = .current) -> String {
        switch self {
        case let .header(home, away, competition, date):
            var parts = ["\(home) vs \(away)"]
            if !competition.isEmpty { parts.append(competition) }
            parts.append(Self.format(date, timeZone: timeZone))
            return parts.joined(separator: ", ")
        case let .finalScore(home, away, score, penalties):
            var text = "Final score: \(home) \(score.home) - \(score.away) \(away)"
            if let penalties { text += ", penalties \(penalties.home) - \(penalties.away)" }
            return text
        case let .period(period):
            return period.title
        case let .event(event):
            let head = "\(event.minute)' \(event.kind.title), \(event.team)"
            if event.kind == .substitution {
                return "\(head), off \(Self.number(event.playerOff)), on \(Self.number(event.playerOn))"
            }
            return "\(head), \(Self.number(event.shirtNumber))"
        case let .penaltyKick(team, shirtNumber, scored, order):
            return "Penalty \(order), \(team), \(Self.number(shirtNumber)), \(scored ? "scored" : "missed")"
        case let .workout(summary):
            var parts: [String] = []
            if let distance = summary.distanceMeters {
                parts.append(String(format: "distance %.2f km", distance / 1000))
            }
            if let heartRate = summary.averageHeartRate {
                parts.append("average heart rate \(Int(heartRate.rounded())) bpm")
            }
            if let duration = summary.durationSeconds {
                let total = Int(duration.rounded())
                parts.append(String(format: "duration %d:%02d:%02d", total / 3600, total / 60 % 60, total % 60))
            }
            parts.append(summary.savedToHealth ? "saved to Health" : "not saved to Health")
            parts.append(summary.hasRoute ? "route recorded" : "no route")
            return "Workout: " + parts.joined(separator: ", ")
        }
    }

    static func number(_ value: Int?) -> String {
        value.map { "#\($0)" } ?? "no number"
    }

    static func format(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}

/// The ordered report of a match: header, final score, live events by period and minute,
/// penalty kicks, and the workout summary when present.
public struct MatchReport: Sendable {
    public var title: String
    public var lines: [ReportLine]
    /// Time zone for the date in `text`.
    public var timeZone: TimeZone

    public init(match: Match, timeZone: TimeZone = .current) {
        let config = match.config
        self.timeZone = timeZone
        title = "\(config.homeName) vs \(config.awayName)"

        var lines: [ReportLine] = [
            .header(
                home: config.homeName,
                away: config.awayName,
                competition: config.competition,
                date: config.kickOff ?? match.kickedOffAt ?? match.createdAt),
            .finalScore(home: config.homeName, away: config.awayName, score: match.score, penalties: match.penaltyScore),
        ]

        var currentPeriod: Period?
        for event in match.liveEvents {
            if event.period != currentPeriod {
                lines.append(.period(event.period))
                currentPeriod = event.period
            }
            lines.append(.event(ReportEvent(event: event, config: config)))
        }

        let kicks = match.shootout.kicks
        if !kicks.isEmpty {
            if currentPeriod != .penalties { lines.append(.period(.penalties)) }
            for (index, kick) in kicks.enumerated() {
                lines.append(.penaltyKick(
                    team: config.name(of: kick.side), shirtNumber: kick.shirtNumber, scored: kick.scored, order: index + 1))
            }
        }

        if let workout = match.workout {
            lines.append(.workout(workout))
        }
        self.lines = lines
    }

    /// Every line as text.
    public var text: [String] { lines.map { $0.text(timeZone: timeZone) } }
}
