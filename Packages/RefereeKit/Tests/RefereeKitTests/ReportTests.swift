import Foundation
import Testing
@testable import RefereeKit

@Suite struct ReportTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func linesInOrder() {
        var m = Fixture.match()
        m.markKickedOff(now: Fixture.at(0))
        m.log(.goal, side: .home, shirtNumber: 9, period: .firstHalf, minute: .init(base: 23), deviceID: Fixture.watch, now: Fixture.at(1))
        m.log(.yellow, side: .away, period: .firstHalf, minute: .init(base: 45, added: 2), deviceID: Fixture.watch, now: Fixture.at(2))
        let deleted = m.log(.goal, side: .away, shirtNumber: 4, period: .secondHalf, minute: .init(base: 50), deviceID: Fixture.watch, now: Fixture.at(3))
        m.delete(deleted.id, deviceID: Fixture.phone, now: Fixture.at(4))
        m.log(.substitution, side: .away, playerOff: 7, playerOn: nil, period: .secondHalf, minute: .init(base: 60), deviceID: Fixture.phone, now: Fixture.at(5))
        m.log(.red, side: .home, shirtNumber: 5, period: .secondHalf, minute: .init(base: 88), deviceID: Fixture.watch, now: Fixture.at(6))
        m.setWorkout(WorkoutSummary(distanceMeters: 10_234, averageHeartRate: 141.6, durationSeconds: 6_305,
                                    savedToHealth: true, hasRoute: true),
                     deviceID: Fixture.watch, now: Fixture.at(7))

        let report = MatchReport(match: m, timeZone: utc)
        #expect(report.title == "Rovers vs United")
        #expect(report.text == [
            "Rovers vs United, League, 2027-01-15 08:00",
            "Final score: Rovers 1 - 0 United",
            "1st half",
            "23' Goal, Rovers, #9",
            "45+2' Yellow card, United, no number",
            "2nd half",
            "60' Substitution, United, off #7, on no number",
            "88' Red card, Rovers, #5",
            "Workout: distance 10.23 km, average heart rate 142 bpm, duration 1:45:05, saved to Health, route recorded",
        ])
        if case let .event(e) = report.lines[3] {
            #expect(e.team == "Rovers" && e.shirtNumber == 9 && e.side == .home)
        } else {
            Issue.record("expected an event line")
        }
    }

    @Test func penaltiesAndNoWorkout() {
        var m = Match(config: MatchConfig(homeName: "A", awayName: "B", kickOff: Fixture.at(3600)),
                      deviceID: Fixture.watch, now: Fixture.at(0))
        m.log(.goal, side: .away, period: .extraTimeSecond, minute: .init(base: 118), deviceID: Fixture.watch, now: Fixture.at(1))
        m.log(.goal, side: .home, period: .secondHalf, minute: .init(base: 90, added: 4), deviceID: Fixture.watch, now: Fixture.at(2))
        m.logPenalty(side: .home, shirtNumber: 10, scored: true, deviceID: Fixture.watch, now: Fixture.at(3))
        m.logPenalty(side: .away, scored: false, deviceID: Fixture.watch, now: Fixture.at(4))
        m.setWorkout(WorkoutSummary(savedToHealth: false), deviceID: Fixture.watch, now: Fixture.at(5))
        let text = MatchReport(match: m, timeZone: utc).text
        #expect(text == [
            "A vs B, 2027-01-15 09:00",
            "Final score: A 1 - 1 B, penalties 1 - 0",
            "2nd half",
            "90+4' Goal, A, no number",
            "Extra time 2",
            "118' Goal, B, no number",
            "Penalties",
            "Penalty 1, A, #10, scored",
            "Penalty 2, B, no number, missed",
            "Workout: not saved to Health, no route",
        ])
    }
}
