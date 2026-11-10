import Foundation

/// What the clock face shows.
public struct ClockDisplay: Sendable, Hashable {
    /// `mm:ss`, held at the normal end (for example "45:00") once it has passed.
    /// During a break it counts down the time left in the break.
    public var main: String
    /// `+m:ss` past the normal end (or past the end of a break), otherwise nil.
    public var overrun: String?

    public init(main: String, overrun: String? = nil) {
        self.main = main
        self.overrun = overrun
    }

    public var isOverrun: Bool { overrun != nil }

    /// `mm:ss` with at least two minute digits, for example "05:07" or "105:00".
    public static func clockString(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let m = total / 60
        let s = total % 60
        return (m < 10 ? "0\(m)" : "\(m)") + ":" + (s < 10 ? "0\(s)" : "\(s)")
    }

    /// `+m:ss`, for example "+2:13".
    public static func overrunString(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let s = total % 60
        return "+\(total / 60):" + (s < 10 ? "0\(s)" : "\(s)")
    }
}
