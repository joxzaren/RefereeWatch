import Foundation
import Testing
@testable import RefereeKit

@Suite struct SyncPayloadTests {
    func sampleMatch() -> Match {
        var m = Fixture.match()
        m.log(.goal, side: .home, shirtNumber: 9, period: .firstHalf, minute: .init(base: 45, added: 2),
              deviceID: Fixture.watch, now: Fixture.at(2830.123_456))
        let y = m.log(.yellow, side: .away, period: .secondHalf, minute: .init(base: 60), deviceID: Fixture.watch, now: Fixture.at(4000.5))
        m.delete(y.id, deviceID: Fixture.phone, now: Fixture.at(4001.000_9))
        m.setWorkout(WorkoutSummary(distanceMeters: 10_123.4, averageHeartRate: 141.6, durationSeconds: 6300,
                                    savedToHealth: true, hasRoute: false),
                     deviceID: Fixture.watch, now: Fixture.at(7000))
        m.markKickedOff(now: Fixture.at(0.0004))
        return m
    }

    @Test func roundTripIsExact() throws {
        let m = sampleMatch()
        let data = try SyncPayload(match: m).encoded()
        let decoded = try SyncPayload.decode(data)
        #expect(decoded.schemaVersion == SyncPayload.currentSchemaVersion)
        #expect(decoded.match == m)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"2027-01-15T08:00:00.000Z\""))
    }

    @Test func normalizeIsStable() {
        for offset in [0.0, 0.0004, 0.0005, 0.0015, 0.123_456_7, 1234.999_9, -0.3] {
            let d = Fixture.at(offset)
            let n = SyncCoding.normalize(d)
            #expect(SyncCoding.normalize(n) == n)
            #expect(abs(n.timeIntervalSince(d)) < 0.001)
        }
        #expect(SyncCoding.format(Fixture.at(1234.9999)) == "2027-01-15T08:20:35.000Z")
        #expect(SyncCoding.format(Fixture.at(-0.3)) == "2027-01-15T07:59:59.700Z")
        #expect(SyncCoding.parse("2027-01-15T08:00:00.1234Z") == SyncCoding.normalize(Fixture.at(0.123)))
        #expect(SyncCoding.parse("2027-01-15T08:00:00Z") == Fixture.t0)
        #expect(SyncCoding.parse("2027-01-15T09:00:00.5+01:00") == Fixture.at(0.5))
        #expect(SyncCoding.parse("nonsense") == nil)
        for ms in stride(from: Int64(1_800_000_000_000), to: 1_800_000_002_000, by: 7) {
            let d = SyncCoding.date(milliseconds: ms)
            #expect(SyncCoding.parse(SyncCoding.format(d)) == d)
        }
        let prev = SyncCoding.normalize(Fixture.at(5))
        #expect(SyncCoding.stamp(Fixture.at(5), after: prev) > prev)
        #expect(SyncCoding.stamp(Fixture.at(1), after: prev) > prev)
        #expect(SyncCoding.stamp(Fixture.at(9), after: prev) == Fixture.at(9))
    }

    @Test func newerSchemaIsRejected() throws {
        let data = try SyncPayload(match: Fixture.match(), schemaVersion: 99).encoded()
        #expect(throws: SyncPayloadError.unsupportedSchemaVersion(99)) { try SyncPayload.decode(data) }
    }

    @Test func mergeReceivedWithNoLocalCopyStoresWithoutSendingBack() {
        let m = sampleMatch()
        let r = SyncPayload.mergeReceived(local: nil, remote: m)
        #expect(r.changed)
        #expect(!r.needsSendBack)
        #expect(r.merged == m)
    }

    @Test func mergeReceivedFlags() throws {
        let base = sampleMatch()

        // Identical copies: nothing to do either way.
        let same = SyncPayload.mergeReceived(local: base, remote: base)
        #expect(!same.changed && !same.needsSendBack)

        // Remote is ahead: persist, no send back.
        var ahead = base
        ahead.log(.red, side: .home, period: .secondHalf, minute: .init(base: 70), deviceID: Fixture.phone, now: Fixture.at(5000))
        let pulled = SyncPayload.mergeReceived(local: base, remote: ahead)
        #expect(pulled.changed && !pulled.needsSendBack)
        #expect(pulled.merged == ahead)

        // Local is ahead: nothing to persist, send back.
        let pushed = SyncPayload.mergeReceived(local: ahead, remote: base)
        #expect(!pushed.changed && pushed.needsSendBack)

        // Both have something new: persist and send back.
        var other = base
        other.log(.goal, side: .away, period: .secondHalf, minute: .init(base: 80), deviceID: Fixture.watch, now: Fixture.at(5500))
        let both = SyncPayload.mergeReceived(local: other, remote: ahead)
        #expect(both.changed && both.needsSendBack)
        #expect(both.merged.liveEvents.count == 3)

        // The send back is then received by the other side and stops there.
        let echo = SyncPayload.mergeReceived(local: ahead, remote: both.merged)
        #expect(echo.changed && !echo.needsSendBack)
        let quiet = SyncPayload.mergeReceived(local: both.merged, remote: echo.merged)
        #expect(!quiet.changed && !quiet.needsSendBack)
    }

    @Test func mergeReceivedAfterWireRoundTrip() throws {
        let base = sampleMatch()
        let wire = try SyncPayload.decode(SyncPayload(match: base).encoded()).match
        let r = SyncPayload.mergeReceived(local: base, remote: wire)
        #expect(!r.changed && !r.needsSendBack)
    }
}
