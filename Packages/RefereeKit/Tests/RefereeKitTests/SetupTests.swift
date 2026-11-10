import Foundation
import Testing
@testable import RefereeKit

@Suite struct SetupTests {
    let matchID = UUID()

    func message(_ seconds: Double, device: String = Fixture.phone, home: String = "Rovers") -> SetupMessage {
        SetupMessage(matchID: matchID, config: MatchConfig(homeName: home),
                     version: Version(modifiedAt: Fixture.at(seconds), deviceID: device))
    }

    @Test func firstSetupApplies() {
        #expect(SetupPolicy.shouldApply(message(1), current: nil, matchKickedOff: false))
    }

    @Test func newerApplies() {
        #expect(SetupPolicy.shouldApply(message(2, home: "City"), current: message(1), matchKickedOff: false))
        // Same time, greater device id wins.
        #expect(SetupPolicy.shouldApply(message(1, device: "zz", home: "City"), current: message(1), matchKickedOff: false))
    }

    @Test func olderAndDuplicateAreDropped() {
        #expect(!SetupPolicy.shouldApply(message(1), current: message(2, home: "City"), matchKickedOff: false))
        #expect(!SetupPolicy.shouldApply(message(2), current: message(2), matchKickedOff: false))
        // Same version but different content is not a win either.
        #expect(!SetupPolicy.shouldApply(message(2, home: "City"), current: message(2), matchKickedOff: false))
    }

    @Test func neverAfterKickOff() {
        #expect(!SetupPolicy.shouldApply(message(9, home: "City"), current: message(1), matchKickedOff: true))
        #expect(!SetupPolicy.shouldApply(message(9), current: nil, matchKickedOff: true))
    }

    @Test func roundTrips() throws {
        let m = message(3.5)
        let data = try SyncCoding.makeEncoder().encode(m)
        #expect(try SyncCoding.makeDecoder().decode(SetupMessage.self, from: data) == m)
    }
}
