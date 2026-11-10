import Foundation
import Testing
@testable import RefereeKit

@Suite struct SyncMergeTests {
    let t = Fixture.t0

    @Test func laterTimeWins() {
        let older = Version(modifiedAt: t, deviceID: "z", deleted: true)
        let newer = Version(modifiedAt: t.addingTimeInterval(1), deviceID: "a")
        #expect(SyncMerge.winner(older, newer) == newer)
        #expect(SyncMerge.winner(newer, older) == newer)
    }

    @Test func onEqualTimesDeletionWins() {
        let edit = Version(modifiedAt: t, deviceID: "z")
        let tomb = Version(modifiedAt: t, deviceID: "a", deleted: true)
        #expect(SyncMerge.winner(edit, tomb) == tomb)
        #expect(SyncMerge.winner(tomb, edit) == tomb)
    }

    @Test func thenGreaterDeviceIDWins() {
        let a = Version(modifiedAt: t, deviceID: "phone")
        let b = Version(modifiedAt: t, deviceID: "watch")
        #expect(SyncMerge.winner(a, b) == b)
        #expect(SyncMerge.winner(b, a) == b)
        // Plain String comparison: "Z" < "a".
        #expect(SyncMerge.winner(Version(modifiedAt: t, deviceID: "Z"), Version(modifiedAt: t, deviceID: "a")).deviceID == "a")
    }

    @Test func identicalVersionsAreEqual() {
        let a = Version(modifiedAt: t, deviceID: "x", deleted: true)
        #expect(SyncMerge.winner(a, a) == a)
        #expect(!SyncMerge.beats(a, a))
        #expect(SyncMerge.resolve(a, a) == a)
    }

    @Test func editAgainstTombstone() {
        var base = Fixture.match()
        let e = base.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 10), deviceID: Fixture.watch, now: Fixture.at(10))

        // Watch deletes at 100, phone edits at 50 (older): the tombstone stays.
        var watch = base
        watch.delete(e.id, deviceID: Fixture.watch, now: Fixture.at(100))
        var phone = base
        phone.edit(e.id, deviceID: Fixture.phone, now: Fixture.at(50)) { $0.shirtNumber = 9 }
        #expect(SyncMerge.merge(watch, phone).event(e.id)?.isLive == false)
        #expect(SyncMerge.merge(phone, watch).event(e.id)?.isLive == false)
        #expect(SyncMerge.merge(watch, phone).score == Score())

        // Same time: the deletion wins even though "watch" > "phone" is irrelevant here.
        var phoneSame = base
        phoneSame.edit(e.id, deviceID: "zzz", now: Fixture.at(100)) { $0.shirtNumber = 9 }
        #expect(SyncMerge.merge(watch, phoneSame).event(e.id)?.isLive == false)

        // A later edit beats an earlier tombstone (last writer wins).
        var phoneLater = base
        phoneLater.edit(e.id, deviceID: Fixture.phone, now: Fixture.at(200)) { $0.shirtNumber = 9 }
        #expect(SyncMerge.merge(watch, phoneLater).event(e.id)?.shirtNumber == 9)
        #expect(SyncMerge.merge(watch, phoneLater).event(e.id)?.isLive == true)
    }

    @Test func tombstoneIsNotUndoneByALaterDeliveredOlderEdit() {
        var base = Fixture.match()
        let e = base.log(.yellow, side: .away, period: .firstHalf, minute: .init(base: 20), deviceID: Fixture.watch, now: Fixture.at(10))
        var oldEdit = base
        oldEdit.edit(e.id, deviceID: Fixture.phone, now: Fixture.at(30)) { $0.shirtNumber = 5 }
        var deleted = base
        deleted.delete(e.id, deviceID: Fixture.watch, now: Fixture.at(40))
        // The watch has the tombstone, then the phone's older edit arrives late.
        let merged = SyncMerge.merge(deleted, oldEdit)
        #expect(merged.event(e.id)?.version.deleted == true)
        #expect(merged.liveEvents.isEmpty)
        #expect(merged.events.count == 1)
    }

    @Test func mergeUnionsEventsAndPenaltiesFromBothDevices() {
        let base = Fixture.match()
        var watch = base
        let w = watch.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 5), deviceID: Fixture.watch, now: Fixture.at(300))
        watch.logPenalty(side: .home, scored: true, deviceID: Fixture.watch, now: Fixture.at(9000))
        var phone = base
        let p = phone.log(.yellow, side: .away, period: .firstHalf, minute: .init(base: 8), deviceID: Fixture.phone, now: Fixture.at(500))
        let merged = SyncMerge.merge(watch, phone)
        #expect(Set(merged.events.map(\.id)) == [w.id, p.id])
        #expect(merged.penalties.count == 1)
        #expect(merged == SyncMerge.merge(phone, watch))
    }

    @Test func versionedMatchPartsMergeByWinner() {
        let base = Fixture.match()
        var a = base
        var cfg = a.config
        cfg.homeName = "Newer"
        a.updateConfig(cfg, deviceID: Fixture.phone, now: Fixture.at(100))
        a.markKickedOff(now: Fixture.at(200))
        var b = base
        b.setWorkout(WorkoutSummary(distanceMeters: 1, savedToHealth: true), deviceID: Fixture.watch, now: Fixture.at(300))
        b.markKickedOff(now: Fixture.at(150))
        b.finish(deviceID: Fixture.watch, now: Fixture.at(6000))
        let m = SyncMerge.merge(a, b)
        #expect(m.config.homeName == "Newer")
        #expect(m.workout?.distanceMeters == 1)
        #expect(m.kickedOffAt == Fixture.at(150))
        #expect(m.finishedAt == Fixture.at(6000))
        #expect(m == SyncMerge.merge(b, a))
    }

    // MARK: Properties over generated inputs

    @Test func mergeIsCommutativeAssociativeAndIdempotent() {
        var rng = SplitMix64(seed: 0x5EED)
        let ids = (0..<6).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        let kickIDs = (0..<3).map { UUID(uuidString: String(format: "11111111-0000-0000-0000-%012d", $0))! }

        func randomVersion() -> Version {
            // Few distinct times and devices so ties are common.
            Version(modifiedAt: Fixture.at(Double(rng.next(3))),
                    deviceID: ["a", "b", "c"][rng.next(3)],
                    deleted: rng.next(3) == 0)
        }

        func randomMatch() -> Match {
            var m = Fixture.match()
            m.configVersion = randomVersion()
            m.config.homeName = ["Rovers", "City", "Town"][rng.next(3)]
            m.clockVersion = randomVersion()
            if rng.next(2) == 0 {
                m.workout = WorkoutSummary(distanceMeters: Double(rng.next(3)) * 1000, savedToHealth: rng.next(2) == 0)
                m.workoutVersion = randomVersion()
            }
            if rng.next(2) == 0 { m.kickedOffAt = Fixture.at(Double(rng.next(3))) }
            if rng.next(2) == 0 {
                let v = randomVersion()
                m.finishedAt = v.modifiedAt
                m.finishVersion = v
            }
            for id in ids where rng.next(3) != 0 {
                m.events.append(MatchEvent(
                    id: id,
                    kind: EventKind.allCases[rng.next(4)],
                    side: rng.next(2) == 0 ? .home : .away,
                    shirtNumber: rng.next(2) == 0 ? nil : rng.next(3),
                    period: .firstHalf,
                    minute: MatchMinute(base: 10),
                    createdBy: "a",
                    createdAt: Fixture.t0,
                    version: randomVersion()))
            }
            for (i, id) in kickIDs.enumerated() where rng.next(2) == 0 {
                m.penalties.append(PenaltyKick(
                    id: id, side: i % 2 == 0 ? .home : .away, scored: rng.next(2) == 0, order: i + 1,
                    createdBy: "a", createdAt: Fixture.t0, version: randomVersion()))
            }
            m.normalize()
            return m
        }

        var tiesSeen = 0
        for _ in 0..<200 {
            let a = randomMatch(), b = randomMatch(), c = randomMatch()
            if a.events.contains(where: { ea in b.events.contains { $0.id == ea.id && $0.version == ea.version && $0 != ea } }) {
                tiesSeen += 1
            }
            #expect(SyncMerge.merge(a, b) == SyncMerge.merge(b, a))
            #expect(SyncMerge.merge(SyncMerge.merge(a, b), c) == SyncMerge.merge(a, SyncMerge.merge(b, c)))
            #expect(SyncMerge.merge(a, a) == a)
            let ab = SyncMerge.merge(a, b)
            #expect(SyncMerge.merge(ab, b) == ab)
            #expect(ab.events.count == Set(a.events.map(\.id) + b.events.map(\.id)).count)
        }
        // The generator must actually exercise identical versions with different content.
        #expect(tiesSeen > 0)
    }
}

/// Deterministic generator so property tests are reproducible.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func next(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}
