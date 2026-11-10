import Foundation

public enum SyncPayloadError: Error, Equatable, Sendable {
    /// The payload was written by a newer app version with a format this one cannot read.
    case unsupportedSchemaVersion(Int)
}

/// A full match with every event version, sent both ways with `transferUserInfo`.
public struct SyncPayload: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var match: Match

    public init(match: Match, schemaVersion: Int = SyncPayload.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.match = match
    }

    public func encoded() throws -> Data {
        try SyncCoding.makeEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> SyncPayload {
        let decoder = SyncCoding.makeDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion <= currentSchemaVersion else {
            throw SyncPayloadError.unsupportedSchemaVersion(header.schemaVersion)
        }
        return try decoder.decode(SyncPayload.self, from: data)
    }

    /// Merges a received match into the local copy.
    /// - `changed`: the merged match differs from the local one, so persist it.
    /// - `needsSendBack`: the merged match has something the remote did not, so send it back.
    ///   When the remote already has everything, nothing is sent, which stops ping-pong.
    public static func mergeReceived(local: Match?, remote: Match) -> (merged: Match, changed: Bool, needsSendBack: Bool) {
        let remoteData = SyncCoding.canonicalData(remote.normalized())
        guard let local else {
            return (remote.normalized(), true, false)
        }
        let merged = SyncMerge.merge(local, remote)
        let mergedData = SyncCoding.canonicalData(merged)
        let changed = mergedData != SyncCoding.canonicalData(local.normalized())
        let needsSendBack = mergedData != remoteData
        return (merged, changed, needsSendBack)
    }

    private struct Header: Decodable {
        var schemaVersion: Int
    }
}
