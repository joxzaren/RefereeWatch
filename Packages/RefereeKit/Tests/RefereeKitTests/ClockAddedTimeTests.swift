import Foundation
import Testing
@testable import RefereeKit

@Suite struct StoppageSplitTests {
    @Test func stoppagesBeforeNormalEnd() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(10)); clock.startStoppage(at: time.now())
        time.advance(45); clock.endStoppage(at: time.now())
        time.advance(mins(10)); clock.startStoppage(at: time.now())
        time.advance(30)
        let split = clock.stoppedTime(at: time.now(), config: stdConfig)
        #expect(split.beforeNormalEnd == 75, "open stoppage counts up to now")
        #expect(split.duringAddedTime == 0)
    }

    @Test func closedStoppageSpanningNormalEndIsSplit() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(44)); clock.startStoppage(at: time.now())
        time.advance(100); clock.endStoppage(at: time.now())
        let split = clock.stoppedTime(at: time.now(), config: stdConfig)
        #expect(split.beforeNormalEnd == 60)
        #expect(split.duringAddedTime == 40)
    }

    @Test func openStoppageSpanningNormalEndIsSplit() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(44) + 30); clock.startStoppage(at: time.now())
        time.advance(20)
        #expect(clock.stoppedTime(at: time.now(), config: stdConfig) == (20, 0))
        time.advance(25)
        #expect(clock.stoppedTime(at: time.now(), config: stdConfig) == (30, 15))
        #expect(clock.suggestedAddedMinutes(at: time.now(), config: stdConfig) == 1)
        time.advance(600)
        #expect(clock.stoppedTime(at: time.now(), config: stdConfig) == (30, 615))
        #expect(clock.suggestedAddedMinutes(at: time.now(), config: stdConfig) == 1, "frozen after normal end")
    }

    @Test func secondHalfSplitsAtNinety() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        clock.advance(at: time.now(), config: stdConfig)
        clock.advance(at: time.now(), config: stdConfig)
        time.advance(mins(44)); clock.startStoppage(at: time.now())
        time.advance(90); clock.endStoppage(at: time.now())
        #expect(clock.stoppedTime(at: time.now(), config: stdConfig) == (60, 30))
    }

    @Test func eachPeriodHasItsOwnLedger() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(60); clock.startStoppage(at: time.now())
        time.advance(60); clock.endStoppage(at: time.now())
        clock.advance(at: time.now(), config: stdConfig)
        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.stoppedTime(at: time.now(), config: stdConfig) == (0, 0))
        #expect(clock.stoppages(in: .firstHalf).count == 1)
        #expect(clock.stoppages(in: .secondHalf).isEmpty)
    }
}

@Suite struct AddedTimeTests {
    @Test(arguments: [(0.0, 0), (1, 1), (60, 1), (61, 2), (120, 2)])
    func suggestionRounding(stopped: TimeInterval, expected: Int) {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(20))
        if stopped > 0 {
            clock.startStoppage(at: time.now())
            time.advance(stopped)
            clock.endStoppage(at: time.now())
        }
        #expect(clock.suggestedAddedMinutes(at: time.now(), config: stdConfig) == expected)
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == expected)
    }

    @Test func suggestionVisibleFromFirstWarning() {
        let time = ClockFakeTimeSource()
        let clock = kickedOff(time)
        let start = time.now()
        #expect(!clock.showsAddedTimeSuggestion(at: start.adding(seconds: mins(40) - 1), config: stdConfig))
        #expect(clock.showsAddedTimeSuggestion(at: start.adding(seconds: mins(40)), config: stdConfig))
        #expect(clock.showsAddedTimeSuggestion(at: start.adding(seconds: mins(50)), config: stdConfig))
        #expect(!MatchClock().showsAddedTimeSuggestion(at: start, config: stdConfig))
    }

    @Test func refereeOverrideBeforeNormalEnd() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(30)); clock.startStoppage(at: time.now())
        time.advance(150); clock.endStoppage(at: time.now())
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 3)
        do { let ok = clock.adjustAddedTime(by: 1, at: time.now(), config: stdConfig); #expect(ok) }
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 4)
        do { let ok = clock.adjustAddedTime(by: -2, at: time.now(), config: stdConfig); #expect(ok) }
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 2)
        do { let ok = clock.adjustAddedTime(by: -5, at: time.now(), config: stdConfig); #expect(ok) }
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 0, "never below zero")
        do { let ok = clock.adjustAddedTime(by: 0, at: time.now(), config: stdConfig); #expect(!ok) }

        // Further stoppages no longer change the referee's value.
        time.advance(60); clock.startStoppage(at: time.now())
        time.advance(200); clock.endStoppage(at: time.now())
        #expect(clock.suggestedAddedMinutes(at: time.now(), config: stdConfig) == 6)
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 0)
    }

    @Test func onlyIncreaseAfterNormalEnd() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(30)); clock.startStoppage(at: time.now())
        time.advance(100); clock.endStoppage(at: time.now())
        let start = clock.startAnchor(of: .firstHalf)!
        time.advance(start.adding(seconds: mins(45) + 10).seconds(since: time.now()))
        #expect(clock.isPastNormalEnd(at: time.now(), config: stdConfig))
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 2)
        do { let ok = clock.adjustAddedTime(by: -1, at: time.now(), config: stdConfig); #expect(!ok) }
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 2)
        do { let ok = clock.adjustAddedTime(by: 1, at: time.now(), config: stdConfig); #expect(ok) }
        do { let ok = clock.adjustAddedTime(by: 2, at: time.now(), config: stdConfig); #expect(ok) }
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 5)
        #expect(clock.addedTimeDeadline(at: time.now(), config: stdConfig) == mins(50))
    }

    @Test func increaseAddsToRefereeValue() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(42))
        clock.adjustAddedTime(by: 3, at: time.now(), config: stdConfig)
        time.advance(mins(4))
        clock.adjustAddedTime(by: 1, at: time.now(), config: stdConfig)
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 4)
    }

    @Test func stoppagesInAddedTimeExtendDeadline() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(20)); clock.startStoppage(at: time.now())
        time.advance(90); clock.endStoppage(at: time.now())
        #expect(clock.addedTimeDeadline(at: time.now(), config: stdConfig) == mins(47), "provisional before normal end")

        let start = clock.startAnchor(of: .firstHalf)!
        let atClock = { (s: TimeInterval) in start.adding(seconds: s) }
        clock.startStoppage(at: atClock(mins(45) + 30))
        #expect(clock.addedTimeDeadline(at: atClock(mins(46)), config: stdConfig) == nil, "nil while open")
        clock.endStoppage(at: atClock(mins(46) + 15))
        #expect(clock.addedTimeDeadline(at: atClock(mins(46) + 20), config: stdConfig) == mins(47) + 45)
        #expect(clock.announcedAddedMinutes(at: atClock(mins(46) + 20), config: stdConfig) == 2, "added-time stoppage does not change announced")
    }

    @Test func deadlineNilOutsidePlay() {
        let time = ClockFakeTimeSource()
        var clock = MatchClock()
        #expect(clock.addedTimeDeadline(at: time.now(), config: stdConfig) == nil)
        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.addedTimeDeadline(at: time.now(), config: stdConfig) == mins(45))
        clock.advance(at: time.now(), config: stdConfig)
        #expect(clock.addedTimeDeadline(at: time.now(), config: stdConfig) == nil)
        do { let ok = clock.adjustAddedTime(by: 1, at: time.now(), config: stdConfig); #expect(!ok) }
        #expect(clock.announcedAddedMinutes(at: time.now(), config: stdConfig) == 0)
    }

    @Test func markAnnouncedIsIdempotentAndRecordedOnPeriodEnd() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(30)); clock.startStoppage(at: time.now())
        time.advance(130); clock.endStoppage(at: time.now())
        clock.markAnnounced(at: time.now(), config: stdConfig)
        #expect(clock.recordedAnnouncedMinutes(for: .firstHalf) == nil, "not recorded before normal end")

        let start = clock.startAnchor(of: .firstHalf)!
        let after = start.adding(seconds: mins(45) + 1)
        clock.markAnnounced(at: after, config: stdConfig)
        let once = clock
        clock.markAnnounced(at: after, config: stdConfig)
        clock.markAnnounced(at: after.adding(seconds: 60), config: stdConfig)
        #expect(clock == once)
        #expect(clock.recordedAnnouncedMinutes(for: .firstHalf) == 3)

        clock.adjustAddedTime(by: 1, at: after, config: stdConfig)
        clock.advance(at: start.adding(seconds: mins(49)), config: stdConfig)
        #expect(clock.recordedAnnouncedMinutes(for: .firstHalf) == 4)
        #expect(clock.recordedAnnouncedMinutes(for: .secondHalf) == nil)
    }
}
