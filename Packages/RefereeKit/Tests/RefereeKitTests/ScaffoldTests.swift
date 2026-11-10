import Testing
@testable import RefereeKit

@Suite struct ScaffoldTests {
    @Test func defaultsMatchSettledDecisionSix() {
        let c = MatchConfig.standard
        #expect(c.halfLength == 45 * 60)
        #expect(c.halfTimeLength == 15 * 60)
        #expect(c.warningOffsets == [300, 60])
    }

    @Test func minutesUseFootballNotation() {
        let c = MatchConfig.standard
        #expect(MatchMinute.at(elapsed: 0, period: .firstHalf, config: c).description == "1")
        #expect(MatchMinute.at(elapsed: 44 * 60 + 59, period: .firstHalf, config: c).description == "45")
        #expect(MatchMinute.at(elapsed: 45 * 60, period: .firstHalf, config: c).description == "45+1")
        #expect(MatchMinute.at(elapsed: 46 * 60 + 1, period: .firstHalf, config: c).description == "45+2")
        #expect(MatchMinute.at(elapsed: 45 * 60, period: .secondHalf, config: c).description == "46")
        #expect(MatchMinute.at(elapsed: 90 * 60 + 30, period: .secondHalf, config: c).description == "90+1")
    }

    @Test func periodsFollowConfiguration() {
        var c = MatchConfig.standard
        #expect(Period.secondHalf.next(c) == .finished)
        c.extraTimeEnabled = true
        c.penaltiesEnabled = true
        #expect(Period.secondHalf.next(c) == .extraTimeBreak)
        #expect(Period.extraTimeSecond.next(c) == .penalties)
        #expect(Period.extraTimeSecond.startOffset(c) == 105 * 60)
    }
}
