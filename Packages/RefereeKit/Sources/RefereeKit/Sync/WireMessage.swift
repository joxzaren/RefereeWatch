import Foundation

/// What the watch and the iPhone send each other over WatchConnectivity.
/// Both `updateApplicationContext` and `transferUserInfo` carry the same
/// dictionary shape: `["kind": String, "data": Data]`.
public enum WireMessage: Sendable, Equatable {
    /// iPhone to watch: a match setup made before kick off.
    case setup(SetupMessage)
    /// Either direction: a whole match with every event version.
    case match(Match)

    public static let kindKey = "kind"
    public static let dataKey = "data"

    public var kind: String {
        switch self {
        case .setup: "setup"
        case .match: "match"
        }
    }

    /// The dictionary to hand to WatchConnectivity.
    public func dictionary() throws -> [String: Any] {
        let data: Data
        switch self {
        case .setup(let setup):
            data = try SyncCoding.makeEncoder().encode(setup)
        case .match(let match):
            data = try SyncPayload(match: match).encoded()
        }
        return [Self.kindKey: kind, Self.dataKey: data]
    }

    /// Decodes a received dictionary. Returns nil for anything that is not a
    /// well formed message of a known kind.
    public init?(dictionary: [String: Any]) {
        guard let kind = dictionary[Self.kindKey] as? String,
              let data = dictionary[Self.dataKey] as? Data else { return nil }
        switch kind {
        case "setup":
            guard let setup = try? SyncCoding.makeDecoder().decode(SetupMessage.self, from: data) else { return nil }
            self = .setup(setup)
        case "match":
            guard let payload = try? SyncPayload.decode(data) else { return nil }
            self = .match(payload.match)
        default:
            return nil
        }
    }
}

/// A stable id for this device, used in every `Version` it writes.
/// Stored in `UserDefaults` so it survives relaunches.
public enum DeviceIdentity {
    public static let defaultsKey = "RefereeKit.deviceID"

    public static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }
}
