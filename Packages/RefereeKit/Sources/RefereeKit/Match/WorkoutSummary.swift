import Foundation

/// What the watch workout recorded, for the report.
public struct WorkoutSummary: Codable, Sendable, Hashable {
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var durationSeconds: Double?
    public var savedToHealth: Bool
    public var hasRoute: Bool

    public init(
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        durationSeconds: Double? = nil,
        savedToHealth: Bool = false,
        hasRoute: Bool = false
    ) {
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.durationSeconds = durationSeconds
        self.savedToHealth = savedToHealth
        self.hasRoute = hasRoute
    }
}
