import Foundation

/// What happened. Penalty shootout kicks are `PenaltyKick`, not events.
public enum EventKind: String, Codable, Sendable, CaseIterable {
    case goal
    case yellow
    case red
    case substitution

    public var title: String {
        switch self {
        case .goal: "Goal"
        case .yellow: "Yellow card"
        case .red: "Red card"
        case .substitution: "Substitution"
        }
    }
}
