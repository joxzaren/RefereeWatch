import Foundation

/// Which team an event belongs to.
public enum Side: String, Codable, Sendable, CaseIterable, Hashable {
    case home
    case away

    public var other: Side { self == .home ? .away : .home }
}

/// Everything about a match that is decided before kick off.
/// Settled decision 6 gives the defaults.
public struct MatchConfig: Codable, Sendable, Equatable, Hashable {
    public var homeName: String
    public var awayName: String
    /// Colours as `#RRGGBB`.
    public var homeColorHex: String
    public var awayColorHex: String
    public var competition: String
    public var kickOff: Date?

    public var halfLength: TimeInterval
    public var halfTimeLength: TimeInterval
    /// Seconds before the end of normal time at which a warning fires, largest first.
    public var warningOffsets: [TimeInterval]

    public var extraTimeEnabled: Bool
    public var extraTimeHalfLength: TimeInterval
    /// Break between the end of the second half and the start of extra time.
    public var extraTimeBreakLength: TimeInterval
    /// Short break between the two halves of extra time.
    public var extraTimeHalfTimeLength: TimeInterval
    public var penaltiesEnabled: Bool

    public init(
        homeName: String = "Home",
        awayName: String = "Away",
        homeColorHex: String = "#D32F2F",
        awayColorHex: String = "#1976D2",
        competition: String = "",
        kickOff: Date? = nil,
        halfLength: TimeInterval = 45 * 60,
        halfTimeLength: TimeInterval = 15 * 60,
        warningOffsets: [TimeInterval] = [5 * 60, 60],
        extraTimeEnabled: Bool = false,
        extraTimeHalfLength: TimeInterval = 15 * 60,
        extraTimeBreakLength: TimeInterval = 5 * 60,
        extraTimeHalfTimeLength: TimeInterval = 60,
        penaltiesEnabled: Bool = false
    ) {
        self.homeName = homeName
        self.awayName = awayName
        self.homeColorHex = homeColorHex
        self.awayColorHex = awayColorHex
        self.competition = competition
        self.kickOff = kickOff
        self.halfLength = halfLength
        self.halfTimeLength = halfTimeLength
        self.warningOffsets = warningOffsets.sorted(by: >)
        self.extraTimeEnabled = extraTimeEnabled
        self.extraTimeHalfLength = extraTimeHalfLength
        self.extraTimeBreakLength = extraTimeBreakLength
        self.extraTimeHalfTimeLength = extraTimeHalfTimeLength
        self.penaltiesEnabled = penaltiesEnabled
    }

    public static let standard = MatchConfig()

    public func name(of side: Side) -> String { side == .home ? homeName : awayName }
}
