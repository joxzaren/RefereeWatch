import Foundation
import RefereeKit

/// The event editor's state. Numbers are kept as text so an empty field means "no number".
struct EventDraft: Equatable {
    var kind: EventKind = .goal
    var side: Side = .home
    var period: Period = .firstHalf
    var minuteBase: Int = 1
    /// Minute within added time, or 0 for normal time.
    var minuteAdded: Int = 0
    var shirtNumber: String = ""
    var playerOff: String = ""
    var playerOn: String = ""

    /// Periods an event can be logged in.
    static let periods: [Period] = [.firstHalf, .secondHalf, .extraTimeFirst, .extraTimeSecond]

    init() {}

    init(event: MatchEvent) {
        kind = event.kind
        side = event.side
        period = event.period
        minuteBase = event.minute.base
        minuteAdded = event.minute.added ?? 0
        shirtNumber = event.shirtNumber.map(String.init) ?? ""
        playerOff = event.playerOff.map(String.init) ?? ""
        playerOn = event.playerOn.map(String.init) ?? ""
    }

    var minute: MatchMinute {
        MatchMinute(base: max(minuteBase, 1), added: minuteAdded > 0 ? minuteAdded : nil)
    }

    /// Writes the draft into an event. A substitution keeps players off and on and no shirt
    /// number; every other kind keeps one shirt number.
    func apply(to event: inout MatchEvent) {
        event.kind = kind
        event.side = side
        event.period = period
        event.minute = minute
        let parsed = numbers
        event.shirtNumber = parsed.shirt
        event.playerOff = parsed.off
        event.playerOn = parsed.on
    }

    /// The parsed numbers for the kind: players off and on for a substitution,
    /// one shirt number for every other kind.
    var numbers: (shirt: Int?, off: Int?, on: Int?) {
        if kind == .substitution {
            return (nil, ShirtNumber.parse(playerOff), ShirtNumber.parse(playerOn))
        }
        return (ShirtNumber.parse(shirtNumber), nil, nil)
    }

    /// True when every number field is empty or a valid shirt number.
    var isValid: Bool {
        let fields = kind == .substitution ? [playerOff, playerOn] : [shirtNumber]
        return fields.allSatisfy { ShirtNumber.isAcceptable($0) }
    }
}

enum ShirtNumber {
    static let range = 0...999

    /// A shirt number from text, or nil when the text is empty or not a number in range.
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII), let value = Int(trimmed), range.contains(value) else {
            return nil
        }
        return value
    }

    /// Empty (no number) or a valid number.
    static func isAcceptable(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parse(text) != nil
    }

    /// `#9`, or `no number`.
    static func label(_ value: Int?) -> String {
        value.map { "#\($0)" } ?? "no number"
    }
}
