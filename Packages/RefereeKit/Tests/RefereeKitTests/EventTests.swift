import Foundation
import Testing
@testable import RefereeKit

/// Shared fixtures for the event, sync and report tests.
enum Fixture {
    static let watch = "watch"
    static let phone = "phone"
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    static func match(id: UUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!) -> Match {
        Match(id: id, config: MatchConfig(homeName: "Rovers", awayName: "United", competition: "League"),
              deviceID: watch, now: t0)
    }
}

@Suite struct EventTests {
    @Test func logAppendsALiveEventWithVersion() {
        var m = Fixture.match()
        let e = m.log(.goal, side: .home, shirtNumber: 9, period: .firstHalf,
                      minute: MatchMinute(base: 12), deviceID: Fixture.watch, now: Fixture.at(700))
        #expect(m.events == [e])
        #expect(e.isLive)
        #expect(e.createdBy == Fixture.watch)
        #expect(e.version == Version(modifiedAt: Fixture.at(700), deviceID: Fixture.watch, deleted: false))
        #expect(e.shirtNumber == 9)
    }

    @Test func undoLastTombstonesOnlyOwnMostRecentLiveEvent() {
        var m = Fixture.match()
        let a = m.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 1), deviceID: Fixture.watch, now: Fixture.at(10))
        let b = m.log(.yellow, side: .away, period: .firstHalf, minute: .init(base: 2), deviceID: Fixture.watch, now: Fixture.at(20))
        let p = m.log(.red, side: .away, period: .firstHalf, minute: .init(base: 3), deviceID: Fixture.phone, now: Fixture.at(30))

        let undone = m.undoLast(deviceID: Fixture.watch, now: Fixture.at(40))
        #expect(undone?.id == b.id)
        #expect(undone?.version.deleted == true)
        #expect(m.event(p.id)?.isLive == true)
        #expect(m.liveEvents.map(\.id) == [a.id, p.id])

        // Next undo skips the tombstone and takes the earlier own event.
        let outcome101 = m.undoLast(deviceID: Fixture.watch, now: Fixture.at(50))
        #expect(outcome101?.id == a.id)
        let outcome102 = m.undoLast(deviceID: Fixture.watch, now: Fixture.at(60))
        #expect(outcome102 == nil)
        #expect(m.liveEvents.map(\.id) == [p.id])
        #expect(m.events.count == 3)
    }

    @Test func undoLastPicksTheLatestCreatedEvenWithEqualClockReadings() {
        var m = Fixture.match()
        _ = m.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 5), deviceID: Fixture.watch, now: Fixture.at(10))
        let second = m.log(.goal, side: .away, period: .firstHalf, minute: .init(base: 4), deviceID: Fixture.watch, now: Fixture.at(10))
        let outcome103 = m.undoLast(deviceID: Fixture.watch, now: Fixture.at(11))
        #expect(outcome103?.id == second.id)
    }

    @Test func editWritesNewVersionAndKeepsIdentity() {
        var m = Fixture.match()
        let e = m.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 10), deviceID: Fixture.watch, now: Fixture.at(600))
        let ok = m.edit(e.id, deviceID: Fixture.phone, now: Fixture.at(4000)) { ev in
            ev.shirtNumber = 7
            ev.side = .away
            ev.createdBy = "hacker"
        }
        #expect(ok)
        let edited = m.event(e.id)!
        #expect(edited.shirtNumber == 7)
        #expect(edited.side == .away)
        #expect(edited.createdBy == Fixture.watch)
        #expect(edited.createdAt == e.createdAt)
        #expect(edited.version == Version(modifiedAt: Fixture.at(4000), deviceID: Fixture.phone))
        #expect(m.events.count == 1)
    }

    @Test func editVersionIsLaterThanPreviousEvenWhenDeviceClockIsBehind() {
        var m = Fixture.match()
        let e = m.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 10), deviceID: Fixture.watch, now: Fixture.at(600))
        let outcome104 = m.edit(e.id, deviceID: Fixture.phone, now: Fixture.at(100)) { $0.shirtNumber = 4 }
        #expect(outcome104)
        let edited = m.event(e.id)!
        #expect(SyncMerge.beats(edited.version, e.version))
    }

    @Test func editAndDeleteRefuseUnknownOrDeletedEvents() {
        var m = Fixture.match()
        let e = m.log(.yellow, side: .home, period: .firstHalf, minute: .init(base: 3), deviceID: Fixture.watch, now: Fixture.at(100))
        let outcome105 = m.edit(UUID(), deviceID: Fixture.watch, now: Fixture.at(200)) { $0.shirtNumber = 1 }
        #expect(!outcome105)
        let outcome1 = m.delete(e.id, deviceID: Fixture.phone, now: Fixture.at(200))
        #expect(outcome1)
        #expect(m.event(e.id)?.version == Version(modifiedAt: Fixture.at(200), deviceID: Fixture.phone, deleted: true))
        let outcome2 = m.delete(e.id, deviceID: Fixture.phone, now: Fixture.at(300))
        #expect(!outcome2)
        let outcome106 = m.edit(e.id, deviceID: Fixture.phone, now: Fixture.at(300)) { $0.shirtNumber = 1 }
        #expect(!outcome106)
        #expect(m.liveEvents.isEmpty)
        #expect(m.events.count == 1)
    }

    @Test func liveEventsAreOrderedByPeriodThenMinuteThenVersionTime() {
        var m = Fixture.match()
        let late2nd = m.log(.goal, side: .home, period: .secondHalf, minute: .init(base: 46), deviceID: Fixture.watch, now: Fixture.at(10))
        let added = m.log(.yellow, side: .home, period: .firstHalf, minute: .init(base: 45, added: 2), deviceID: Fixture.watch, now: Fixture.at(20))
        let normal45 = m.log(.yellow, side: .away, period: .firstHalf, minute: .init(base: 45), deviceID: Fixture.watch, now: Fixture.at(30))
        let first = m.log(.red, side: .away, period: .firstHalf, minute: .init(base: 3), deviceID: Fixture.watch, now: Fixture.at(40))
        let sameMinuteLater = m.log(.goal, side: .away, period: .firstHalf, minute: .init(base: 3), deviceID: Fixture.watch, now: Fixture.at(50))
        let et = m.log(.goal, side: .home, period: .extraTimeFirst, minute: .init(base: 95), deviceID: Fixture.watch, now: Fixture.at(5))
        #expect(m.liveEvents.map(\.id) == [first.id, sameMinuteLater.id, normal45.id, added.id, late2nd.id, et.id])
    }

    @Test func substitutionKeepsBothNumbers() {
        var m = Fixture.match()
        let s = m.log(.substitution, side: .away, playerOff: 7, playerOn: 14, period: .secondHalf,
                      minute: .init(base: 60), deviceID: Fixture.phone, now: Fixture.at(1))
        #expect(s.playerOff == 7 && s.playerOn == 14 && s.shirtNumber == nil)
    }

    @Test func matchStateUpdatesWriteVersions() {
        var m = Fixture.match()
        m.updateClock(MatchClock(), deviceID: Fixture.phone, now: Fixture.at(5))
        #expect(m.clockVersion == Version(modifiedAt: Fixture.at(5), deviceID: Fixture.phone))
        m.setWorkout(WorkoutSummary(distanceMeters: 9000, savedToHealth: true), deviceID: Fixture.watch, now: Fixture.at(6))
        #expect(m.workoutVersion?.modifiedAt == Fixture.at(6))
        m.markKickedOff(now: Fixture.at(7))
        m.markKickedOff(now: Fixture.at(8))
        #expect(m.kickedOffAt == Fixture.at(7))
        m.finish(deviceID: Fixture.watch, now: Fixture.at(9))
        m.finish(deviceID: Fixture.watch, now: Fixture.at(10))
        #expect(m.finishedAt == Fixture.at(9))
        #expect(m.finishVersion == Version(modifiedAt: Fixture.at(9), deviceID: Fixture.watch))
        #expect(m.isFinished)
    }
}
