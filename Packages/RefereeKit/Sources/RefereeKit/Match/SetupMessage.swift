import Foundation

/// A match setup sent from the iPhone to the watch.
public struct SetupMessage: Codable, Sendable, Equatable {
    public var matchID: UUID
    public var config: MatchConfig
    public var version: Version

    public init(matchID: UUID, config: MatchConfig, version: Version) {
        self.matchID = matchID
        self.config = config
        self.version = version
    }
}

/// Decides whether the watch applies a received setup. Both WatchConnectivity transports
/// may deliver the same setup, and in any order, so stale and duplicate deliveries are dropped.
public enum SetupPolicy {
    /// Apply only when the incoming version strictly wins under `SyncMerge`, the message
    /// differs from the current one, and the match has not kicked off.
    public static func shouldApply(_ incoming: SetupMessage, current: SetupMessage?, matchKickedOff: Bool) -> Bool {
        if matchKickedOff { return false }
        guard let current else { return true }
        if incoming == current { return false }
        return SyncMerge.beats(incoming.version, current.version)
    }
}
