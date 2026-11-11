import Foundation
import RefereeKit

// Small pure functions used by the watch services and screens. They hold every
// decision that does not need an Apple framework, so they are easy to reason about.

// MARK: Alerts

/// How an alert feels on the wrist.
enum HapticStyle: Sendable, Equatable {
    /// `WKHapticType.notification`.
    case notification
    /// `WKHapticType.directionUp`.
    case directionUp
}

/// One haptic burst: `repeats` plays of `style`, `interval` seconds apart.
struct HapticPattern: Sendable, Equatable {
    var style: HapticStyle
    var repeats: Int
    var interval: TimeInterval

    static func `for`(_ kind: AlertKind) -> HapticPattern {
        switch kind {
        case .normalEnd, .addedTimeEnd: HapticPattern(style: .notification, repeats: 3, interval: 0.6)
        case .warning: HapticPattern(style: .directionUp, repeats: 1, interval: 0)
        case .breakEnd: HapticPattern(style: .notification, repeats: 1, interval: 0)
        }
    }

    /// How strongly a pattern is felt, used to pick one pattern when alerts coincide.
    var weight: Int { (style == .notification ? 100 : 0) + repeats }
}

/// What actually fires: one or more planned alerts that are due at the same moment.
/// Each delivery plays one haptic burst and has one backup notification.
struct AlertDelivery: Sendable, Equatable {
    /// Ids of every planned alert in this delivery. The first is the backup notification id.
    var ids: [String]
    var kinds: [AlertKind]
    var secondsFromNow: TimeInterval
    var haptic: HapticPattern

    var primaryID: String { ids[0] }
    var includesNormalEnd: Bool { kinds.contains(.normalEnd) }

    var title: String { AlertText.title(for: kinds) }
    var body: String { AlertText.body(for: kinds) }
}

enum AlertSchedule {
    /// Alerts due within this many seconds of each other fire as one delivery.
    static let coincidenceWindow: TimeInterval = 0.5

    /// Groups the planned alerts into deliveries. When added time is 0, normal end and
    /// the end of added time are due at the same moment, so they become one delivery with
    /// a single haptic burst and a single backup notification. This is the only place
    /// that decides it.
    static func deliveries(for alerts: [PlannedAlert]) -> [AlertDelivery] {
        var result: [AlertDelivery] = []
        for alert in alerts.sorted(by: { $0.secondsFromNow < $1.secondsFromNow }) {
            let pattern = HapticPattern.for(alert.kind)
            if let last = result.indices.last,
               alert.secondsFromNow - result[last].secondsFromNow <= coincidenceWindow {
                result[last].ids.append(alert.id)
                result[last].kinds.append(alert.kind)
                if pattern.weight > result[last].haptic.weight { result[last].haptic = pattern }
            } else {
                result.append(AlertDelivery(
                    ids: [alert.id], kinds: [alert.kind],
                    secondsFromNow: alert.secondsFromNow, haptic: pattern))
            }
        }
        return result
    }

    /// The backup notification fires this long after the in-app deadline, so the in-app
    /// alert can remove it first and the wrist does not buzz twice.
    static let backupDelay: TimeInterval = 1.5

    /// An in-app alert that wakes more than this late (for example after suspension) checks
    /// whether its backup was already shown before buzzing.
    static let lateThreshold: TimeInterval = 2

    /// Seconds from now for the backup notification's trigger. At least 1 s, the system minimum.
    static func backupInterval(secondsFromNow: TimeInterval) -> TimeInterval {
        max(1, secondsFromNow + backupDelay)
    }

    static func isLate(_ lateness: Duration) -> Bool {
        lateness > .seconds(lateThreshold)
    }

    /// A late in-app alert skips its haptic when its backup notification was already delivered.
    static func shouldPlayLateHaptic(_ delivery: AlertDelivery, deliveredIDs: Set<String>) -> Bool {
        !deliveredIDs.contains(delivery.primaryID)
    }

    /// The alerts to plan for a match. Nothing is planned before kick off or after the final whistle.
    static func plan(for match: Match?, now: Anchor) -> [PlannedAlert] {
        guard let match, match.isKickedOff, !match.isFinished else { return [] }
        return AlertPlan.alerts(clock: match.clock, config: match.config, matchID: match.id, now: now)
    }
}

enum AlertText {
    static func title(for kinds: [AlertKind]) -> String {
        if kinds.contains(.normalEnd) && kinds.contains(.addedTimeEnd) { return "Time is up" }
        if kinds.contains(.addedTimeEnd) { return "Added time over" }
        if kinds.contains(.normalEnd) { return "Normal time over" }
        if kinds.contains(.breakEnd) { return "Break over" }
        for kind in kinds {
            if case .warning(let seconds) = kind { return "\(warningText(seconds)) to go" }
        }
        return "RefereeWatch"
    }

    static func body(for kinds: [AlertKind]) -> String {
        if kinds.contains(.addedTimeEnd) { return "End the period when ready." }
        if kinds.contains(.normalEnd) { return "Added time has started." }
        if kinds.contains(.breakEnd) { return "Start the next period when ready." }
        return "Normal time ends soon."
    }

    static func warningText(_ seconds: Int) -> String {
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds) s"
    }
}

// MARK: Notifications

enum BackupAlertStatus: Sendable, Equatable {
    case on
    case notAsked
    case off
}

enum NotificationLogic {
    /// Backup alerts are off when authorization is denied, or when alerts or sound
    /// and haptics are disabled. Not yet asked also means no backup can be delivered.
    static func status(authorized: Bool?, alertEnabled: Bool, soundEnabled: Bool) -> BackupAlertStatus {
        guard let authorized else { return .notAsked }
        if !authorized || !alertEnabled || !soundEnabled { return .off }
        return .on
    }
}

// MARK: Period transitions

enum TransitionLogic {
    /// The label of the button that moves the match to the next period, or nil when finished.
    static func title(from period: Period, config: MatchConfig) -> String? {
        switch period {
        case .notStarted: "Kick off"
        case .firstHalf: "End half"
        case .halfTime: "Start 2nd half"
        case .secondHalf:
            switch period.next(config) {
            case .finished: "Full time"
            default: "End 2nd half"
            }
        case .extraTimeBreak: "Start extra time"
        case .extraTimeFirst: "End ET 1st half"
        case .extraTimeHalfTime: "Start ET 2nd half"
        case .extraTimeSecond:
            switch period.next(config) {
            case .finished: "Full time"
            default: "End extra time"
            }
        case .penalties: "End shootout"
        case .finished: nil
        }
    }

    /// What the next period will be, shown under the hold button.
    static func subtitle(from period: Period, config: MatchConfig) -> String? {
        guard period != .finished else { return nil }
        let next = period.next(config)
        return next == .finished ? "Final whistle" : "Next: \(next.title)"
    }
}

// MARK: Digital Crown

/// Turns raw crown offsets into deliberate actions. Pure, so the thresholds are easy to tune.
struct CrownAccumulator: Sendable, Equatable {
    /// Rotation needed to toggle a stoppage. Large enough that a brush does nothing.
    static let toggleThreshold: Double = 0.9
    /// Rotation per minute of added time in edit mode. Larger than the toggle threshold,
    /// so one minute needs a clear, deliberate turn.
    static let minuteStep: Double = 1.2

    private(set) var lastOffset: Double?
    private(set) var accumulated: Double = 0
    /// A toggle fires at most once per gesture; the crown must go idle to re-arm.
    private(set) var armed = true

    /// Feeds a new absolute offset and returns the change since the last one.
    mutating func delta(to offset: Double) -> Double {
        defer { lastOffset = offset }
        guard let lastOffset else { return 0 }
        return offset - lastOffset
    }

    /// True once per gesture, when the rotation since the crown was last idle passes the threshold.
    mutating func toggle(offset: Double) -> Bool {
        accumulated += delta(to: offset)
        guard armed, abs(accumulated) >= Self.toggleThreshold else { return false }
        armed = false
        return true
    }

    /// Whole minute steps (signed) since the last step. Keeps the remainder.
    mutating func minuteSteps(offset: Double) -> Int {
        accumulated += delta(to: offset)
        let steps = Int((accumulated / Self.minuteStep).rounded(.towardZero))
        accumulated -= Double(steps) * Self.minuteStep
        return steps
    }

    mutating func idle() {
        accumulated = 0
        armed = true
    }
}

// MARK: Added time panel

/// What the crown does on the clock page. It toggles a stoppage unless the referee has
/// tapped the added time panel to edit it. Edit mode ends after `timeout` with no crown
/// input, on another tap, or when the panel goes away.
struct AddedTimeEditMode: Sendable, Equatable {
    static let timeout: Duration = .seconds(3)

    /// The last tap or crown input while editing. Nil when not editing.
    private(set) var lastActivity: ContinuousClock.Instant?

    func isActive(at now: ContinuousClock.Instant) -> Bool {
        guard let lastActivity else { return false }
        return now - lastActivity < Self.timeout
    }

    /// A tap on the panel enters edit mode, or leaves it when already editing.
    mutating func tap(at now: ContinuousClock.Instant) {
        lastActivity = isActive(at: now) ? nil : now
    }

    /// Crown input while editing keeps edit mode open.
    mutating func touch(at now: ContinuousClock.Instant) {
        if isActive(at: now) { lastActivity = now }
    }

    mutating func exit() {
        lastActivity = nil
    }
}

/// What the added time panel shows.
struct AddedTimePanel: Sendable, Equatable {
    var announced: Int
    var suggested: Int
    /// True when the referee has set a value with the crown before normal end.
    var refereeSet: Bool
    /// After normal end the value is announced and can only increase.
    var pastNormalEnd: Bool

    var headline: String { "+\(announced)" }

    /// The panel's text outside edit mode.
    var detail: String {
        if pastNormalEnd { return "Announced. Tap to add" }
        if refereeSet { return "Your value (sugg. +\(suggested)). Tap to change" }
        return "Suggested. Tap to change"
    }

    /// The panel's text in edit mode.
    var editingDetail: String {
        pastNormalEnd ? "Turn crown to add. Up only" : "Turn crown to change"
    }

    func detail(editing: Bool) -> String { editing ? editingDetail : detail }

    /// Nil when the panel is hidden.
    static func make(clock: MatchClock, config: MatchConfig, now: Anchor) -> AddedTimePanel? {
        guard clock.showsAddedTimeSuggestion(at: now, config: config) else { return nil }
        let record = clock.records.last { $0.period == clock.period }
        return AddedTimePanel(
            announced: clock.announcedAddedMinutes(at: now, config: config),
            suggested: clock.suggestedAddedMinutes(at: now, config: config),
            refereeSet: record?.addedTime.refereeMinutes != nil,
            pastNormalEnd: clock.isPastNormalEnd(at: now, config: config))
    }
}

// MARK: Penalties

enum PenaltyLogic {
    /// The side expected to kick next: the one that has taken fewer kicks, home first.
    static func nextSide(_ shootout: PenaltyShootout) -> Side {
        let taken = shootout.taken
        return taken.away < taken.home ? .away : .home
    }
}

// MARK: Setup

enum SetupLogic {
    /// A received setup can start a new match only when no stored match already uses its id.
    /// Otherwise starting it again would overwrite the earlier match.
    static func usable(_ setup: SetupMessage?, storedMatchIDs: Set<UUID>) -> SetupMessage? {
        guard let setup, !storedMatchIDs.contains(setup.matchID) else { return nil }
        return setup
    }

    /// Whether the match a setup is for has already kicked off on this watch.
    static func kickedOff(_ setup: SetupMessage, active: Match?, stored: Match?) -> Bool {
        if let active, active.id == setup.matchID, active.isKickedOff { return true }
        return stored?.isKickedOff ?? false
    }
}

// MARK: Formatting

enum Format {
    static func eventLine(_ event: MatchEvent, config: MatchConfig) -> String {
        var text = "\(event.minute)' \(short(event.kind)) \(teamShort(config.name(of: event.side)))"
        if event.kind == .substitution {
            let off = event.playerOff.map { "#\($0)" } ?? "?"
            let on = event.playerOn.map { "#\($0)" } ?? "?"
            if event.playerOff != nil || event.playerOn != nil { text += " \(off)>\(on)" }
        } else if let number = event.shirtNumber {
            text += " #\(number)"
        }
        return text
    }

    static func short(_ kind: EventKind) -> String {
        switch kind {
        case .goal: "Goal"
        case .yellow: "Yellow"
        case .red: "Red"
        case .substitution: "Sub"
        }
    }

    static func teamShort(_ name: String) -> String {
        name.count <= 8 ? name : String(name.prefix(7)) + "."
    }

    static func distance(_ meters: Double?) -> String {
        guard let meters else { return "–" }
        return String(format: "%.2f km", meters / 1000)
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm else { return "–" }
        return "\(Int(bpm.rounded())) bpm"
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "–" }
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
