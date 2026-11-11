import Foundation
import Testing
@testable import RefereeKit

@Suite struct PenaltyTests {
    /// Logs kicks alternating home, away from a pattern such as "XO" (X scored, O missed).
    func shootout(_ pattern: String) -> Match {
        var m = Fixture.match()
        for (i, c) in pattern.enumerated() {
            m.logPenalty(side: i % 2 == 0 ? .home : .away, shirtNumber: i + 1, scored: c == "X",
                         deviceID: Fixture.watch, now: Fixture.at(Double(i)))
        }
        return m
    }

    @Test func undecidedWhileBothCanStillWin() {
        #expect(shootout("").shootout.winner == nil)
        #expect(shootout("XOXO").shootout.winner == nil)
        #expect(shootout("XXXXXXXXXX").shootout.winner == nil)  // 5-5 goes to sudden death
        #expect(shootout("XXXXXXXXXX").penaltyScore == Score(home: 5, away: 5))
    }

    @Test func decidedEarlyWhenTheOtherSideCannotCatchUp() {
        // Home 3 of 3, away 0 of 3: away can reach at most 2.
        #expect(shootout("XOXOXO").shootout.winner == .home)
        // Home 3 of 3, away 0 of 2: away can still reach 3, not decided.
        #expect(shootout("XOXOX").shootout.winner == nil)
        // Decided on home's 4th kick, a miss: home 1 of 4 can reach 2, away already has 3.
        #expect(shootout("XXOXOXOX").shootout.winner == .away)
        // After 4 each, home 4 away 2: decided on away's 4th kick (2 + 1 < 4).
        #expect(shootout("XXXOXXXO").shootout.winner == .home)
        // After five each 4-3.
        #expect(shootout("XXXXXXXOOO").shootout.winner == .home)
    }

    @Test func suddenDeathNeedsEqualKicks() {
        let level = "XXXXXXXXXX"
        #expect(shootout(level + "X").shootout.winner == nil)
        #expect(shootout(level + "O").shootout.winner == nil)
        #expect(shootout(level + "XO").shootout.winner == .home)
        #expect(shootout(level + "OX").shootout.winner == .away)
        #expect(shootout(level + "XXOO").shootout.winner == nil)
        #expect(shootout(level + "XXOOOX").shootout.winner == .away)
    }

    @Test func kicksAfterDecisionDoNotChangeIt() {
        #expect(shootout("XOXOXOXX").shootout.winner == .home)
    }

    @Test func undoAndDeleteUseTombstones() {
        var m = shootout("XOXO")
        let phoneKick = m.logPenalty(side: .home, scored: true, deviceID: Fixture.phone, now: Fixture.at(100))
        #expect(phoneKick.order == 5)
        let undone = m.undoLastPenalty(deviceID: Fixture.watch, now: Fixture.at(200))
        #expect(undone?.order == 4)
        #expect(undone?.version.deleted == true)
        #expect(m.shootout.kicks.map(\.order) == [1, 2, 3, 5])
        #expect(m.penaltyScore == Score(home: 3, away: 0))
        let outcome1 = m.deletePenalty(phoneKick.id, deviceID: Fixture.watch, now: Fixture.at(300))
        #expect(outcome1)
        let outcome2 = m.deletePenalty(phoneKick.id, deviceID: Fixture.watch, now: Fixture.at(400))
        #expect(!outcome2)
        #expect(m.penalties.count == 5)
        #expect(m.shootout.taken == Score(home: 2, away: 1))
        let first = m.shootout.kicks[0]
        let outcome101 = m.editPenalty(first.id, deviceID: Fixture.phone, now: Fixture.at(500)) { $0.scored = false }
        #expect(outcome101)
        #expect(m.penaltyScore == Score(home: 1, away: 0))
        #expect(m.score == Score())  // kicks never count toward the match score
    }
}
