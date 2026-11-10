import Foundation
import Testing
@testable import RefereeKit

@Suite struct AnchorTests {
    @Test func sameBootUsesMonotonicTime() {
        let a = Anchor(monotonicNanos: 5_000_000_000, bootSessionID: "x", wall: Date(timeIntervalSince1970: 0))
        let b = Anchor(monotonicNanos: 7_500_000_000, bootSessionID: "x", wall: Date(timeIntervalSince1970: 9999))
        #expect(b.seconds(since: a) == 2.5)
        #expect(a.seconds(since: b) == -2.5)
    }

    @Test func differentBootUsesWallClock() {
        let a = Anchor(monotonicNanos: 900_000_000_000, bootSessionID: "boot-1", wall: Date(timeIntervalSince1970: 1000))
        let b = Anchor(monotonicNanos: 3_000_000_000, bootSessionID: "boot-2", wall: Date(timeIntervalSince1970: 1600))
        #expect(b.seconds(since: a) == 600)
    }

    @Test func addingMovesBothClocks() {
        let a = Anchor(monotonicNanos: 10_000_000_000, bootSessionID: "x", wall: Date(timeIntervalSince1970: 100))
        let b = a.adding(seconds: 1.5)
        #expect(b.monotonicNanos == 11_500_000_000)
        #expect(b.wall == Date(timeIntervalSince1970: 101.5))
        #expect(b.seconds(since: a) == 1.5)
        #expect(a.adding(seconds: -20).monotonicNanos == 0)
    }

    @Test func systemTimeSourceIsMonotonicWithStableBootID() {
        let source = SystemTimeSource()
        let a = source.now()
        let b = source.now()
        #expect(b.monotonicNanos >= a.monotonicNanos)
        #expect(a.bootSessionID == b.bootSessionID)
        #expect(!a.bootSessionID.isEmpty)
        #expect(b.seconds(since: a) >= 0)
    }

    @Test func systemTimeChangeDoesNotChangeElapsed() {
        let time = ClockFakeTimeSource()
        let clock = kickedOff(time)
        time.advance(600)
        time.jumpWall(-3 * 3600)
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == 600)
        time.jumpWall(24 * 3600)
        time.advance(5)
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == 605)
    }

    @Test func rebootFallsBackToWallClock() {
        let time = ClockFakeTimeSource(boot: "before")
        let clock = kickedOff(time)
        let start = time.now()
        let afterReboot = Anchor(monotonicNanos: 2_000_000_000, bootSessionID: "after", wall: start.wall.addingTimeInterval(1234))
        #expect(clock.elapsed(at: afterReboot, config: stdConfig) == 1234)
    }
}

@Suite struct MatchClockTransitionTests {
    @Test func notStartedIsZero() {
        let time = ClockFakeTimeSource()
        let clock = MatchClock()
        #expect(clock.period == .notStarted)
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == 0)
        #expect(clock.display(at: time.now(), config: stdConfig) == ClockDisplay(main: "00:00"))
        #expect(clock.breakRemaining(at: time.now(), config: stdConfig) == nil)
        #expect(MatchClock() == clock)
    }

    @Test func kickOffAndNormalMatch() {
        let time = ClockFakeTimeSource()
        var clock = MatchClock()
        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.period == .firstHalf)
        time.advance(mins(47))
        #expect(clock.period == .firstHalf, "a half never ends by itself")
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == mins(47))

        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.period == .halfTime)
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == 0)
        time.advance(mins(10))
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == mins(10))
        #expect(clock.breakRemaining(at: time.now(), config: stdConfig) == mins(5))
        time.advance(mins(6))
        #expect(clock.breakRemaining(at: time.now(), config: stdConfig) == 0)

        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.period == .secondHalf)
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == mins(45))
        #expect(clock.display(at: time.now(), config: stdConfig).main == "45:00")
        #expect(clock.minute(at: time.now(), config: stdConfig).description == "46")
        time.advance(mins(46))
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == mins(91))

        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.period == .finished)
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == 0)
        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.period == .finished)
    }

    @Test func extraTimeAndPenalties() {
        let config = MatchConfig(extraTimeEnabled: true, penaltiesEnabled: true)
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time, config: config)
        let expected: [Period] = [.halfTime, .secondHalf, .extraTimeBreak, .extraTimeFirst,
                                  .extraTimeHalfTime, .extraTimeSecond, .penalties, .finished]
        for period in expected {
            time.advance(30)
            clock.advance(at: time.now(), config: config)
            #expect(clock.period == period)
            switch period {
            case .extraTimeBreak:
                #expect(clock.breakRemaining(at: time.now(), config: config) == mins(5))
            case .extraTimeFirst:
                #expect(clock.display(at: time.now(), config: config).main == "90:00")
                time.advance(mins(15))
                #expect(clock.display(at: time.now(), config: config) == ClockDisplay(main: "105:00", overrun: "+0:00"))
                #expect(clock.minute(at: time.now(), config: config).description == "105+1")
            case .extraTimeHalfTime:
                #expect(clock.breakRemaining(at: time.now(), config: config) == 60)
            case .extraTimeSecond:
                #expect(clock.elapsed(at: time.now(), config: config) == mins(105))
                time.advance(mins(14) + 59)
                #expect(clock.display(at: time.now(), config: config).main == "119:59")
            case .penalties:
                #expect(clock.elapsed(at: time.now(), config: config) == 0)
                do { let ok = clock.startStoppage(at: time.now()); #expect(!ok) }
            default: break
            }
        }
    }

    @Test func secondHalfGoesStraightToPenalties() {
        let config = MatchConfig(penaltiesEnabled: true)
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time, config: config)
        clock.advance(at: time.now(), config: config)
        clock.advance(at: time.now(), config: config)
        clock.advance(at: time.now(), config: config)
        #expect(clock.period == .penalties)
    }

    @Test func clockKeepsRunningDuringStoppage() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(10))
        do { let ok = clock.startStoppage(at: time.now()); #expect(ok) }
        #expect(clock.isStoppageOpen)
        do { let ok = clock.startStoppage(at: time.now()); #expect(!ok) }
        time.advance(90)
        #expect(clock.elapsed(at: time.now(), config: stdConfig) == mins(11.5))
        do { let ok = clock.endStoppage(at: time.now()); #expect(ok) }
        do { let ok = clock.endStoppage(at: time.now()); #expect(!ok) }
        #expect(!clock.isStoppageOpen)
    }

    @Test func stoppagesRefusedOutsidePlay() {
        let time = ClockFakeTimeSource()
        var clock = MatchClock()
        do { let ok = clock.startStoppage(at: time.now()); #expect(!ok) }
        do { let ok = clock.endStoppage(at: time.now()); #expect(!ok) }
        clock.advance(at: time.now(), config: stdConfig)
        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.period == .halfTime)
        do { let ok = clock.startStoppage(at: time.now()); #expect(!ok) }
    }

    @Test func endingPeriodClosesOpenStoppage() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(46))
        clock.startStoppage(at: time.now())
        time.advance(30)
        let end = time.now()
        clock.advance(at: end, config: stdConfig)
        #expect(clock.period == .halfTime)
        #expect(!clock.isStoppageOpen)
        #expect(clock.stoppages(in: .firstHalf) == [Stoppage(start: end.adding(seconds: -30), end: end)])
    }

    @Test func displayAndOverrunFormat() {
        let time = ClockFakeTimeSource()
        let clock = kickedOff(time)
        let start = time.now()
        func show(_ s: TimeInterval) -> ClockDisplay { clock.display(at: start.adding(seconds: s), config: stdConfig) }
        #expect(show(0) == ClockDisplay(main: "00:00"))
        #expect(show(5 * 60 + 7.9) == ClockDisplay(main: "05:07"))
        #expect(show(mins(45) - 0.5).main == "44:59")
        #expect(!show(mins(45) - 0.5).isOverrun)
        #expect(show(mins(45)).main == "45:00")
        #expect(show(mins(45) + 133) == ClockDisplay(main: "45:00", overrun: "+2:13"))
        #expect(show(mins(45) + 133).isOverrun)
        #expect(show(mins(45) + 605).overrun == "+10:05")
    }

    @Test func breakDisplayCountsDown() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        clock.advance(at: time.now(), config: stdConfig)
        time.advance(mins(2) + 30)
        #expect(clock.display(at: time.now(), config: stdConfig) == ClockDisplay(main: "12:30"))
        time.advance(mins(13) + 5)
        #expect(clock.display(at: time.now(), config: stdConfig) == ClockDisplay(main: "00:00", overrun: "+0:35"))
    }

    @Test func minutesAndNormalEnd() {
        let time = ClockFakeTimeSource()
        let clock = kickedOff(time)
        let start = time.now()
        func at(_ s: TimeInterval) -> Anchor { start.adding(seconds: s) }
        #expect(clock.minute(at: at(0), config: stdConfig).description == "1")
        #expect(clock.minute(at: at(59), config: stdConfig).description == "1")
        #expect(clock.minute(at: at(60), config: stdConfig).description == "2")
        #expect(clock.minute(at: at(mins(45) - 1), config: stdConfig).description == "45")
        #expect(clock.minute(at: at(mins(45)), config: stdConfig).description == "45+1")
        #expect(clock.minute(at: at(mins(46) + 1), config: stdConfig).description == "45+2")
        #expect(!clock.isPastNormalEnd(at: at(mins(45) - 1), config: stdConfig))
        #expect(clock.isPastNormalEnd(at: at(mins(45)), config: stdConfig))
    }

    @Test func codableRoundTripRestoresIdenticalResults() throws {
        let config = MatchConfig(extraTimeEnabled: true)
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time, config: config)
        time.advance(mins(10)); clock.startStoppage(at: time.now())
        time.advance(70); clock.endStoppage(at: time.now())
        clock.advance(at: time.now(), config: config)
        time.advance(mins(15)); clock.advance(at: time.now(), config: config)
        time.advance(mins(44)); clock.startStoppage(at: time.now())
        time.advance(90); clock.endStoppage(at: time.now())
        clock.adjustAddedTime(by: 1, at: time.now(), config: config)
        time.advance(mins(1)); clock.startStoppage(at: time.now())
        time.advance(20)

        let data = try JSONEncoder().encode(clock)
        let restored = try JSONDecoder().decode(MatchClock.self, from: data)
        #expect(restored == clock)

        for extra in [0.0, 30, 400] {
            let now = time.now().adding(seconds: extra)
            #expect(restored.period == clock.period)
            #expect(restored.isStoppageOpen == clock.isStoppageOpen)
            #expect(restored.elapsed(at: now, config: config) == clock.elapsed(at: now, config: config))
            #expect(restored.display(at: now, config: config) == clock.display(at: now, config: config))
            #expect(restored.stoppedTime(at: now, config: config) == clock.stoppedTime(at: now, config: config))
            #expect(restored.announcedAddedMinutes(at: now, config: config) == clock.announcedAddedMinutes(at: now, config: config))
            #expect(restored.addedTimeDeadline(at: now, config: config) == clock.addedTimeDeadline(at: now, config: config))
            let id = UUID()
            #expect(AlertPlan.alerts(clock: restored, config: config, matchID: id, now: now)
                    == AlertPlan.alerts(clock: clock, config: config, matchID: id, now: now))
        }
        #expect(restored.recordedAnnouncedMinutes(for: .firstHalf) == clock.recordedAnnouncedMinutes(for: .firstHalf))

        // Restored state keeps working.
        var resumed = restored
        do { let ok = resumed.endStoppage(at: time.now()); #expect(ok) }
        #expect(resumed.addedTimeDeadline(at: time.now(), config: config) != nil)
    }

    @Test func freshClockDecodesAsNotStarted() throws {
        let data = try JSONEncoder().encode(MatchClock())
        let clock = try JSONDecoder().decode(MatchClock.self, from: data)
        #expect(clock.period == .notStarted)
    }
}
