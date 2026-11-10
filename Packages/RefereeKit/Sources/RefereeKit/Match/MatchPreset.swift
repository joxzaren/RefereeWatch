import Foundation

/// A named match configuration the referee can start from.
public struct MatchPreset: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var config: MatchConfig

    public init(id: UUID = UUID(), name: String, config: MatchConfig) {
        self.id = id
        self.name = name
        self.config = config
    }

    /// Presets shipped with the app. Their ids are fixed so a stored choice keeps working.
    public static let builtIn: [MatchPreset] = [
        MatchPreset(
            id: UUID(uuidString: "6E1C2F2A-0001-4C1B-9A55-5E7E2A1B0001")!,
            name: "Standard 2 x 45",
            config: MatchConfig()),
        MatchPreset(
            id: UUID(uuidString: "6E1C2F2A-0002-4C1B-9A55-5E7E2A1B0002")!,
            name: "Youth 2 x 35",
            config: MatchConfig(halfLength: 35 * 60, halfTimeLength: 10 * 60)),
        MatchPreset(
            id: UUID(uuidString: "6E1C2F2A-0003-4C1B-9A55-5E7E2A1B0003")!,
            name: "Youth 2 x 30",
            config: MatchConfig(halfLength: 30 * 60, halfTimeLength: 10 * 60)),
        MatchPreset(
            id: UUID(uuidString: "6E1C2F2A-0004-4C1B-9A55-5E7E2A1B0004")!,
            name: "Cup with extra time and penalties",
            config: MatchConfig(extraTimeEnabled: true, penaltiesEnabled: true)),
    ]
}
