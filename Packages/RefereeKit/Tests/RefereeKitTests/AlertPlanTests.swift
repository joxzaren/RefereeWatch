import Foundation
import Testing
@testable import RefereeKit

@Suite struct AlertPlanTests {
    let matchID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func notStartedAndFinishedHaveNoAlerts() {
        let time = ClockFakeTimeSource()
        #expect(AlertPlan.alerts(clock: MatchClock(), config: stdConfig, matchID: matchID, now: time.now()).isEmpty)
    }

    @Test func firstHalfAlertsAtKickOff() {
        let time = ClockFakeTimeSource()
        let clock = kickedOff(time)
        let alerts = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: time.now())
        let prefix = "11111111-2222-3333-4444-555555555555-firstHalf-"
        #expect(alerts == [
            PlannedAlert(id: prefix + "warning300", kind: .warning(secondsBefore: 300), dueElapsed: mins(40), secondsFromNow: mins(40)),
            PlannedAlert(id: prefix + "warning60", kind: .warning(secondsBefore: 60), dueElapsed: mins(44), secondsFromNow: mins(44)),
            PlannedAlert(id: prefix + "normalEnd", kind: .normalEnd, dueElapsed: mins(45), secondsFromNow: mins(45)),
            PlannedAlert(id: prefix + "addedTimeEnd", kind: .addedTimeEnd, dueElapsed: mins(45), secondsFromNow: mins(45)),
        ])
    }

    @Test func pastAlertsAreDroppedAndSecondsFromNowUsesClock() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        clock.advance(at: time.now(), config: stdConfig)
        clock.advance(at: time.now(), config: stdConfig)
        time.advance(mins(41) + 30)
        let alerts = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: time.now())
        #expect(alerts.map(\.kind) == [.warning(secondsBefore: 60), .normalEnd, .addedTimeEnd])
        #expect(alerts.map(\.dueElapsed) == [mins(89), mins(90), mins(90)])
        #expect(alerts.map(\.secondsFromNow) == [150, 210, 210])
        #expect(alerts[0].id == "\(matchID)-secondHalf-warning60")

        // Ids are stable across replans.
        time.advance(10)
        let later = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: time.now())
        #expect(later.map(\.id) == alerts.map(\.id))
        #expect(later[0].secondsFromNow == 140)
    }

    @Test func provisionalFinalAlertFollowsInputs() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(10)); clock.startStoppage(at: time.now())

        var alerts = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: time.now())
        #expect(!alerts.contains { $0.kind == .addedTimeEnd }, "left out while a stoppage is open")
        #expect(alerts.contains { $0.kind == .normalEnd })

        time.advance(70); clock.endStoppage(at: time.now())
        alerts = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: time.now())
        #expect(alerts.last?.kind == .addedTimeEnd)
        #expect(alerts.last?.dueElapsed == mins(47))

        clock.adjustAddedTime(by: 2, at: time.now(), config: stdConfig)
        alerts = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: time.now())
        #expect(alerts.last?.dueElapsed == mins(49))
        #expect(alerts.last?.secondsFromNow == mins(49) - clock.elapsed(at: time.now(), config: stdConfig))
    }

    @Test func afterNormalEndOnlyAddedTimeEndRemains() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        time.advance(mins(20)); clock.startStoppage(at: time.now())
        time.advance(100); clock.endStoppage(at: time.now())
        let start = clock.startAnchor(of: .firstHalf)!
        var now = start.adding(seconds: mins(45) + 20)
        var alerts = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: now)
        #expect(alerts.map(\.kind) == [.addedTimeEnd])
        #expect(alerts[0].dueElapsed == mins(47))
        #expect(alerts[0].secondsFromNow == 100)

        clock.startStoppage(at: now)
        now = now.adding(seconds: 30)
        #expect(AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: now).isEmpty)
        clock.endStoppage(at: now)
        alerts = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: now)
        #expect(alerts.map(\.dueElapsed) == [mins(47) + 30])

        now = start.adding(seconds: mins(48))
        #expect(AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: now).isEmpty)
    }

    @Test func breakEnd() {
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time)
        clock.advance(at: time.now(), config: stdConfig)
        time.advance(mins(4))
        let alerts = AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: time.now())
        #expect(alerts == [PlannedAlert(id: "\(matchID)-halfTime-breakEnd", kind: .breakEnd, dueElapsed: mins(15), secondsFromNow: mins(11))])
        time.advance(mins(12))
        #expect(AlertPlan.alerts(clock: clock, config: stdConfig, matchID: matchID, now: time.now()).isEmpty)
    }

    @Test func extraTimeWarningsLongerThanPeriodAreSkipped() {
        let config = MatchConfig(warningOffsets: [20 * 60, 60], extraTimeEnabled: true)
        let time = ClockFakeTimeSource()
        var clock = kickedOff(time, config: config)
        for _ in 0..<4 { clock.advance(at: time.now(), config: config) }
        #expect(clock.period == .extraTimeFirst)
        let kinds = AlertPlan.alerts(clock: clock, config: config, matchID: matchID, now: time.now()).map(\.kind)
        #expect(kinds == [.warning(secondsBefore: 60), .normalEnd, .addedTimeEnd])
    }
}
