import Foundation
import Testing
@testable import RefereeKit

/// Cases found by the REF-1 bug hunt and review.
@Suite struct RegressionTests {
    let config = MatchConfig.standard
    let start = Anchor(monotonicNanos: 5_000_000_000, bootSessionID: "boot-a",
                       wall: Date(timeIntervalSince1970: 1_800_000_000))

    @Test(arguments: 1...40)
    func exactStoppageTotalsDoNotRoundUpAMinute(parts: Int) {
        var clock = MatchClock()
        clock.advance(at: start, config: config)
        let piece = 120.0 / Double(parts)
        var t = 8.019
        for _ in 0..<parts {
            clock.startStoppage(at: start.adding(seconds: t))
            t += piece
            clock.endStoppage(at: start.adding(seconds: t))
            t += 3.3
        }
        #expect(clock.suggestedAddedMinutes(at: start.adding(seconds: 2000), config: config) == 2)
    }

    @Test func sixtySecondsInSecondHalfSuggestsOneMinute() {
        var clock = MatchClock()
        clock.advance(at: start, config: config)
        let end1 = start.adding(seconds: 2760)
        clock.advance(at: end1, config: config)
        let kick2 = end1.adding(seconds: 900)
        clock.advance(at: kick2, config: config)
        #expect(clock.period == .secondHalf)
        clock.startStoppage(at: kick2.adding(seconds: 8.019))
        clock.endStoppage(at: kick2.adding(seconds: 68.019))
        #expect(clock.suggestedAddedMinutes(at: kick2.adding(seconds: 600), config: config) == 1)
    }

    @Test func warningLongerThanHalfDoesNotShowSuggestionFromKickOff() {
        var custom = config
        custom.halfLength = 30 * 60
        custom.warningOffsets = [40 * 60, 60]
        var clock = MatchClock()
        clock.advance(at: start, config: custom)
        #expect(!clock.showsAddedTimeSuggestion(at: start.adding(seconds: 1), config: custom))
        #expect(clock.showsAddedTimeSuggestion(at: start.adding(seconds: 29 * 60), config: custom))
    }

    @Test func unknownBootSessionFallsBackToWallClock() {
        let a = Anchor(monotonicNanos: 900_000_000_000, bootSessionID: Anchor.unknownBootSession,
                       wall: Date(timeIntervalSince1970: 1_000))
        // After a reboot the monotonic clock restarts near zero.
        let b = Anchor(monotonicNanos: 1_000_000_000, bootSessionID: Anchor.unknownBootSession,
                       wall: Date(timeIntervalSince1970: 1_600))
        #expect(b.seconds(since: a) == 600)
    }

    @Test func editingAnEventKeepsItsPlace() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var match = Match(config: config, deviceID: "watch", now: now)
        let yellow = match.log(.yellow, side: .away, period: .firstHalf,
                               minute: MatchMinute(base: 23), deviceID: "watch", now: now)
        let goal = match.log(.goal, side: .home, period: .firstHalf,
                             minute: MatchMinute(base: 23), deviceID: "watch", now: now.addingTimeInterval(5))
        match.edit(yellow.id, deviceID: "phone", now: now.addingTimeInterval(600)) { $0.shirtNumber = 4 }
        #expect(match.liveEvents.map(\.id) == [yellow.id, goal.id])
    }
}
