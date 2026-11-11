import Foundation
import Testing
@testable import RefereeKit

@Suite struct WireMessageTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func setupRoundTrips() throws {
        let setup = SetupMessage(
            matchID: UUID(),
            config: MatchConfig(homeName: "Lions", awayName: "Bears"),
            version: Version(modifiedAt: now, deviceID: "phone")
        )
        let dict = try WireMessage.setup(setup).dictionary()
        #expect(dict[WireMessage.kindKey] as? String == "setup")
        #expect(WireMessage(dictionary: dict) == .setup(setup))
    }

    @Test func matchRoundTrips() throws {
        var match = Match(config: .standard, deviceID: "watch", now: now)
        match.log(.goal, side: .home, shirtNumber: 9, period: .firstHalf,
                  minute: MatchMinute(base: 12), deviceID: "watch", now: now)
        let dict = try WireMessage.match(match).dictionary()
        guard case .match(let decoded)? = WireMessage(dictionary: dict) else {
            Issue.record("expected a match message")
            return
        }
        #expect(decoded.score == Score(home: 1, away: 0))
        #expect(decoded.id == match.id)
    }

    @Test func rejectsUnknownOrMalformed() {
        #expect(WireMessage(dictionary: [:]) == nil)
        #expect(WireMessage(dictionary: ["kind": "other", "data": Data()]) == nil)
        #expect(WireMessage(dictionary: ["kind": "setup", "data": Data("x".utf8)]) == nil)
    }

    @Test func deviceIdentityIsStable() throws {
        let suite = "WireMessageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = DeviceIdentity.current(defaults: defaults)
        #expect(!first.isEmpty)
        #expect(DeviceIdentity.current(defaults: defaults) == first)
    }
}
