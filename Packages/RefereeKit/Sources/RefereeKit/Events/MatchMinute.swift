import Foundation

/// The minute an event happened, in football notation: 23, 45+2, 90+4.
public struct MatchMinute: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public var base: Int
    /// Minute within added time, starting at 1, or nil inside normal time.
    public var added: Int?

    public init(base: Int, added: Int? = nil) {
        self.base = base
        self.added = added
    }

    /// Minute for a match clock value inside a playing period.
    /// Inside normal time the minute is floor(elapsed / 60) + 1, so 0:00 to 0:59 is minute 1.
    /// After the normal end it is the end minute plus the minute of added time, so
    /// 45:00 to 45:59 in the first half is 45+1 and 46:01 is 45+2.
    public static func at(elapsed: TimeInterval, period: Period, config: MatchConfig) -> MatchMinute {
        let end = period.normalEnd(config)
        let clamped = max(elapsed, period.startOffset(config))
        if clamped < end {
            return MatchMinute(base: Int((clamped / 60).rounded(.down)) + 1)
        }
        let overrun = clamped - end
        return MatchMinute(base: Int((end / 60).rounded(.down)), added: Int((overrun / 60).rounded(.down)) + 1)
    }

    public var description: String {
        if let added { return "\(base)+\(added)" }
        return "\(base)"
    }

    public static func < (lhs: MatchMinute, rhs: MatchMinute) -> Bool {
        if lhs.base != rhs.base { return lhs.base < rhs.base }
        return (lhs.added ?? 0) < (rhs.added ?? 0)
    }
}
