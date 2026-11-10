import Foundation

/// Who changed a record last and when. A version with `deleted == true` is a tombstone.
public struct Version: Codable, Sendable, Hashable {
    public var modifiedAt: Date
    public var deviceID: String
    public var deleted: Bool

    /// `modifiedAt` is normalized to the sync date format so it round trips exactly.
    public init(modifiedAt: Date, deviceID: String, deleted: Bool = false) {
        self.modifiedAt = SyncCoding.normalize(modifiedAt)
        self.deviceID = deviceID
        self.deleted = deleted
    }

    /// A new version written by `deviceID` at `now`, strictly later than `previous`.
    public static func next(after previous: Version?, deviceID: String, now: Date, deleted: Bool = false) -> Version {
        Version(
            modifiedAt: SyncCoding.stamp(now, after: previous?.modifiedAt),
            deviceID: deviceID,
            deleted: deleted)
    }
}

/// A record that is merged by id under `SyncMerge.winner`.
public protocol Versioned: Identifiable, Encodable where ID == UUID {
    var version: Version { get }
}
