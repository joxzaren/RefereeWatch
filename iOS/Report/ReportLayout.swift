import Foundation
import RefereeKit

/// What the report screen and the PDF show, built from `MatchReport` lines.
///
/// Event rows also carry the id of the event they show, so the screen can open the editor.
/// `MatchReport` writes one `.event` line per entry of `match.liveEvents`, in that order,
/// which is how each line is paired with its event.
struct ReportLayout: Sendable, Equatable {
    struct Row: Sendable, Equatable, Identifiable {
        var id: String
        /// Short leading text such as the minute, or nil.
        var lead: String?
        var text: String
        var eventID: UUID?
    }

    struct Section: Sendable, Equatable, Identifiable {
        var id: String
        var title: String
        var rows: [Row]
    }

    var title: String
    /// Competition and kick off date, when known.
    var subtitle: String
    var score: String
    var penalties: String?
    /// One section per period with events, then the penalty shootout.
    var sections: [Section]
    var workout: [Row]
    /// The match's date, used for the share file name.
    var date: Date

    init(match: Match, timeZone: TimeZone = .current, locale: Locale = .current) {
        let report = MatchReport(match: match, timeZone: timeZone)
        let liveEvents = match.liveEvents
        var eventIndex = 0

        title = report.title
        subtitle = ""
        score = ""
        penalties = nil
        sections = []
        workout = []
        date = match.createdAt

        for (lineIndex, line) in report.lines.enumerated() {
            switch line {
            case let .header(_, _, competition, date):
                self.date = date
                let when = Self.dateText(date, timeZone: timeZone, locale: locale)
                subtitle = competition.isEmpty ? when : "\(competition), \(when)"
            case let .finalScore(home, away, score, penalties):
                self.score = "\(home) \(score.home) - \(score.away) \(away)"
                self.penalties = penalties.map { "Penalties \($0.home) - \($0.away)" }
            case let .period(period):
                sections.append(Section(id: "period-\(period.rawValue)", title: period.title, rows: []))
            case let .event(event):
                let id = eventIndex < liveEvents.count ? liveEvents[eventIndex].id : nil
                eventIndex += 1
                appendRow(Row(
                    id: id?.uuidString ?? "line-\(lineIndex)",
                    lead: "\(event.minute)'",
                    text: Self.eventText(event),
                    eventID: id))
            case let .penaltyKick(team, shirtNumber, scored, order):
                appendRow(Row(
                    id: "penalty-\(order)",
                    lead: "\(order)",
                    text: "\(team), \(ShirtNumber.label(shirtNumber)), \(scored ? "scored" : "missed")",
                    eventID: nil))
            case let .workout(summary):
                workout = Self.workoutRows(summary)
            }
        }
    }

    private mutating func appendRow(_ row: Row) {
        if sections.isEmpty {
            sections.append(Section(id: "events", title: "Events", rows: []))
        }
        sections[sections.count - 1].rows.append(row)
    }

    var hasEvents: Bool { sections.contains { !$0.rows.isEmpty } }

    /// For example "Goal, Lions, #9" or "Substitution, Lions, off #4, on #12".
    static func eventText(_ event: ReportEvent) -> String {
        let head = "\(event.kind.title), \(event.team)"
        if event.kind == .substitution {
            return "\(head), off \(ShirtNumber.label(event.playerOff)), on \(ShirtNumber.label(event.playerOn))"
        }
        return "\(head), \(ShirtNumber.label(event.shirtNumber))"
    }

    static func workoutRows(_ summary: WorkoutSummary) -> [Row] {
        var rows: [Row] = []
        if let distance = summary.distanceMeters {
            rows.append(Row(id: "distance", lead: "Distance", text: String(format: "%.2f km", distance / 1000), eventID: nil))
        }
        if let heartRate = summary.averageHeartRate {
            rows.append(Row(id: "heart-rate", lead: "Average heart rate", text: "\(Int(heartRate.rounded())) bpm", eventID: nil))
        }
        if let duration = summary.durationSeconds {
            rows.append(Row(id: "duration", lead: "Duration", text: durationText(duration), eventID: nil))
        }
        rows.append(Row(
            id: "health",
            lead: nil,
            text: summary.savedToHealth ? "Saved to Apple Health" : "Not saved to Apple Health",
            eventID: nil))
        return rows
    }

    /// `1:42:05`.
    static func durationText(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    static func dateText(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = timeZone
        style.locale = locale
        return date.formatted(style)
    }
}

/// Builds the file name for a shared report: "Lions v Bears 2026-11-10.pdf".
enum ReportFileName {
    static func make(home: String, away: String, date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "\(clean(home)) v \(clean(away)) \(day).pdf"
    }

    static func make(match: Match, timeZone: TimeZone = .current) -> String {
        let date = match.config.kickOff ?? match.kickedOffAt ?? match.createdAt
        return make(home: match.config.homeName, away: match.config.awayName, date: date, timeZone: timeZone)
    }

    /// Removes characters that are not allowed or awkward in file names.
    static func clean(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.newlines).union(.controlCharacters)
        let parts = name.components(separatedBy: forbidden).joined(separator: "-")
        let trimmed = parts.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Team" : trimmed
    }
}
