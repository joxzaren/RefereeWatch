import Foundation
import Testing
@testable import RefereeKit

@Suite struct ScoreTests {
    @Test func scoreCountsLiveGoalsOnly() {
        var m = Fixture.match()
        #expect(m.score == Score(home: 0, away: 0))
        let g1 = m.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 5), deviceID: Fixture.watch, now: Fixture.at(1))
        m.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 15), deviceID: Fixture.watch, now: Fixture.at(2))
        m.log(.goal, side: .away, period: .secondHalf, minute: .init(base: 50), deviceID: Fixture.phone, now: Fixture.at(3))
        m.log(.yellow, side: .away, period: .secondHalf, minute: .init(base: 51), deviceID: Fixture.phone, now: Fixture.at(4))
        m.log(.red, side: .home, period: .secondHalf, minute: .init(base: 52), deviceID: Fixture.phone, now: Fixture.at(5))
        #expect(m.score == Score(home: 2, away: 1))
        #expect(m.score.leader == .home)

        m.delete(g1.id, deviceID: Fixture.phone, now: Fixture.at(6))
        #expect(m.score == Score(home: 1, away: 1))
        #expect(m.score.leader == nil)

        // Changing the team of a goal moves it.
        let g = m.liveEvents.first { $0.kind == .goal && $0.side == .home }!
        m.edit(g.id, deviceID: Fixture.phone, now: Fixture.at(7)) { $0.side = .away }
        #expect(m.score == Score(home: 0, away: 2))
    }

    @Test func subscriptReadsAndWrites() {
        var s = Score.zero
        s[.away] += 3
        #expect(s == Score(home: 0, away: 3))
        #expect(s[.home] == 0)
    }
}
