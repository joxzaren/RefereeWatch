import Foundation

/// A phase of a match. Extra time and penalties exist from the start so
/// Phase 3 is configuration and UI rather than a redesign.
public enum Period: String, Codable, Sendable, CaseIterable, Hashable {
    case notStarted
    case firstHalf
    case halfTime
    case secondHalf
    case extraTimeBreak
    case extraTimeFirst
    case extraTimeHalfTime
    case extraTimeSecond
    case penalties
    case finished

    /// A period in which the match clock runs and events are timed.
    public var isPlaying: Bool {
        switch self {
        case .firstHalf, .secondHalf, .extraTimeFirst, .extraTimeSecond: true
        default: false
        }
    }

    /// A timed break such as half time.
    public var isBreak: Bool {
        switch self {
        case .halfTime, .extraTimeBreak, .extraTimeHalfTime: true
        default: false
        }
    }

    /// Where the match clock starts in this period, for example 45:00 for the second half.
    public func startOffset(_ config: MatchConfig) -> TimeInterval {
        switch self {
        case .secondHalf: config.halfLength
        case .extraTimeFirst: 2 * config.halfLength
        case .extraTimeSecond: 2 * config.halfLength + config.extraTimeHalfLength
        default: 0
        }
    }

    /// Normal length of a playing period, or the length of a break. Zero otherwise.
    public func length(_ config: MatchConfig) -> TimeInterval {
        switch self {
        case .firstHalf, .secondHalf: config.halfLength
        case .extraTimeFirst, .extraTimeSecond: config.extraTimeHalfLength
        case .halfTime: config.halfTimeLength
        case .extraTimeBreak: config.extraTimeBreakLength
        case .extraTimeHalfTime: config.extraTimeHalfTimeLength
        default: 0
        }
    }

    /// Match clock value at which normal time in this period ends, for example 90:00.
    public func normalEnd(_ config: MatchConfig) -> TimeInterval {
        startOffset(config) + length(config)
    }

    /// The period that follows this one for the given configuration.
    public func next(_ config: MatchConfig) -> Period {
        switch self {
        case .notStarted: .firstHalf
        case .firstHalf: .halfTime
        case .halfTime: .secondHalf
        case .secondHalf:
            config.extraTimeEnabled ? .extraTimeBreak : (config.penaltiesEnabled ? .penalties : .finished)
        case .extraTimeBreak: .extraTimeFirst
        case .extraTimeFirst: .extraTimeHalfTime
        case .extraTimeHalfTime: .extraTimeSecond
        case .extraTimeSecond: config.penaltiesEnabled ? .penalties : .finished
        case .penalties: .finished
        case .finished: .finished
        }
    }

    public var title: String {
        switch self {
        case .notStarted: "Not started"
        case .firstHalf: "1st half"
        case .halfTime: "Half time"
        case .secondHalf: "2nd half"
        case .extraTimeBreak: "Before extra time"
        case .extraTimeFirst: "Extra time 1"
        case .extraTimeHalfTime: "Extra time break"
        case .extraTimeSecond: "Extra time 2"
        case .penalties: "Penalties"
        case .finished: "Full time"
        }
    }
}
