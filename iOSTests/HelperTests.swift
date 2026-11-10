import Foundation
import SwiftUI
import Testing
import RefereeKit
@testable import RefereeWatch

@Suite struct HexColorTests {
    @Test func parsesWithAndWithoutHash() {
        #expect(HexColor.parse("#D32F2F") == HexColor.RGB(red: 0xD3, green: 0x2F, blue: 0x2F))
        #expect(HexColor.parse("1976d2") == HexColor.RGB(red: 0x19, green: 0x76, blue: 0xD2))
        #expect(HexColor.parse(" #000000 ") == HexColor.RGB(red: 0, green: 0, blue: 0))
    }

    @Test(arguments: ["", "#", "#12345", "#1234567", "#GGGGGG", "red", "#12 456"])
    func rejectsInvalid(_ text: String) {
        #expect(HexColor.parse(text) == nil)
    }

    @Test func formatsAndClamps() {
        #expect(HexColor.format(red: 1, green: 0, blue: 0.5) == "#FF0080")
        #expect(HexColor.format(red: 1.4, green: -0.2, blue: .nan) == "#FF0000")
    }

    @Test func normalizes() {
        #expect(HexColor.normalized("abcdef", fallback: "#000000") == "#ABCDEF")
        #expect(HexColor.normalized("nope", fallback: "#000000") == "#000000")
    }

    @Test(arguments: ["#D32F2F", "#1976D2", "#000000", "#FFFFFF", "#7F7F7F"])
    func roundTripsThroughColor(_ hex: String) {
        #expect(Color(hex: hex).hexString == hex)
    }
}

@Suite struct SetupDraftTests {
    @Test func startsFromTheFirstPreset() {
        let draft = SetupDraft.fromFirstPreset(now: Fixtures.kickOff)
        #expect(draft.presetID == MatchPreset.builtIn[0].id)
        #expect(draft.halfMinutes == 45)
        #expect(draft.halfTimeMinutes == 15)
        #expect(draft.warningMinutes == [5, 1])
        #expect(draft.config.warningOffsets == [300, 60])
    }

    @Test func applyingAPresetKeepsTeams() throws {
        var draft = SetupDraft.fromFirstPreset(now: Fixtures.kickOff)
        draft.homeName = "Lions"
        draft.homeColorHex = "#00FF00"
        let cup = try #require(MatchPreset.builtIn.first { $0.config.penaltiesEnabled })
        draft.apply(cup)
        #expect(draft.presetID == cup.id)
        #expect(draft.extraTimeEnabled)
        #expect(draft.penaltiesEnabled)
        #expect(draft.homeName == "Lions")
        #expect(draft.homeColorHex == "#00FF00")
    }

    @Test func everyPresetRoundTripsItsTimings() {
        for preset in MatchPreset.builtIn {
            var draft = SetupDraft(config: preset.config, now: Fixtures.kickOff)
            draft.hasKickOff = false
            #expect(draft.config == preset.config, "\(preset.name)")
        }
    }

    @Test func buildsAConfig() {
        var draft = SetupDraft.fromFirstPreset(now: Fixtures.kickOff)
        draft.homeName = "  Lions "
        draft.awayName = ""
        draft.homeColorHex = "#abcdef"
        draft.awayColorHex = "bad"
        draft.competition = " Cup "
        draft.kickOff = Fixtures.kickOff
        draft.halfMinutes = 40
        draft.halfTimeMinutes = 10
        draft.warningMinutes = [1, 5, 5, 0, 40, 2]
        draft.extraTimeEnabled = true
        draft.extraTimeHalfMinutes = 10
        draft.penaltiesEnabled = true

        let config = draft.config
        #expect(config.homeName == "Lions")
        #expect(config.awayName == "Away")
        #expect(config.homeColorHex == "#ABCDEF")
        #expect(config.awayColorHex == MatchConfig.standard.awayColorHex)
        #expect(config.competition == "Cup")
        #expect(config.kickOff == Fixtures.kickOff)
        #expect(config.halfLength == 2_400)
        #expect(config.halfTimeLength == 600)
        #expect(config.warningOffsets == [300, 120, 60])
        #expect(config.extraTimeEnabled)
        #expect(config.extraTimeHalfLength == 600)
        #expect(config.penaltiesEnabled)
    }

    @Test func kickOffCanBeLeftOut() {
        var draft = SetupDraft.fromFirstPreset(now: Fixtures.kickOff)
        draft.hasKickOff = false
        #expect(draft.config.kickOff == nil)
    }

    @Test func defaultKickOffIsTheNextQuarterHour() {
        let now = Fixtures.kickOff.addingTimeInterval(61)
        #expect(SetupDraft.nextQuarterHour(after: now) == Fixtures.kickOff.addingTimeInterval(15 * 60))
        #expect(SetupDraft.nextQuarterHour(after: Fixtures.kickOff) == Fixtures.kickOff)
    }
}

@Suite struct SetupFactoryTests {
    let id = UUID()

    @Test func firstSetupUsesNow() {
        let setup = SetupFactory.make(matchID: id, config: MatchConfig(), previous: nil, deviceID: "phone", now: Fixtures.kickOff)
        #expect(setup.matchID == id)
        #expect(setup.version == Version(modifiedAt: Fixtures.kickOff, deviceID: "phone"))
    }

    @Test func editsAreStrictlyNewerEvenWhenTheClockGoesBack() {
        let first = SetupFactory.make(matchID: id, config: MatchConfig(), previous: nil, deviceID: "phone", now: Fixtures.kickOff)
        let edit = SetupFactory.make(
            matchID: id, config: MatchConfig(homeName: "Lions"), previous: first, deviceID: "phone",
            now: Fixtures.kickOff.addingTimeInterval(-30))
        #expect(edit.version.modifiedAt > first.version.modifiedAt)
        #expect(SetupPolicy.shouldApply(edit, current: first, matchKickedOff: false))
        #expect(!SetupPolicy.shouldApply(first, current: edit, matchKickedOff: false))
    }

    @Test func aNewMatchAlsoBeatsThePreviousSetup() {
        let first = SetupFactory.make(matchID: id, config: MatchConfig(), previous: nil, deviceID: "phone", now: Fixtures.kickOff)
        let next = SetupFactory.make(matchID: UUID(), config: MatchConfig(), previous: first, deviceID: "phone", now: Fixtures.kickOff)
        #expect(SyncMerge.beats(next.version, first.version))
    }
}

@Suite struct EventDraftTests {
    @Test(arguments: [("9", 9), (" 23 ", 23), ("0", 0), ("999", 999)])
    func parsesShirtNumbers(_ text: String, _ value: Int) {
        #expect(ShirtNumber.parse(text) == value)
    }

    @Test(arguments: ["", "  ", "-1", "1000", "9a", "٣"])
    func rejectsShirtNumbers(_ text: String) {
        #expect(ShirtNumber.parse(text) == nil)
    }

    @Test func emptyIsAcceptableButJunkIsNot() {
        var draft = EventDraft()
        #expect(draft.isValid)
        draft.shirtNumber = "x"
        #expect(!draft.isValid)
        draft.kind = .substitution
        #expect(draft.isValid)
        draft.playerOn = "1000"
        #expect(!draft.isValid)
    }

    @Test func labels() {
        #expect(ShirtNumber.label(7) == "#7")
        #expect(ShirtNumber.label(nil) == "no number")
    }

    @Test func roundTripsAnEventAndSwitchesKind() throws {
        var match = Match(config: MatchConfig(), deviceID: "w", now: Fixtures.kickOff)
        let event = match.log(.substitution, side: .away, playerOff: 4, playerOn: 15, period: .secondHalf,
                              minute: MatchMinute(base: 90, added: 3), deviceID: "w", now: Fixtures.kickOff)
        var draft = EventDraft(event: event)
        #expect(draft.minute == MatchMinute(base: 90, added: 3))
        #expect(draft.playerOff == "4")
        #expect(draft.playerOn == "15")

        draft.kind = .goal
        draft.shirtNumber = "11"
        draft.minuteAdded = 0
        var edited = event
        draft.apply(to: &edited)
        #expect(edited.kind == .goal)
        #expect(edited.shirtNumber == 11)
        #expect(edited.playerOff == nil)
        #expect(edited.playerOn == nil)
        #expect(edited.minute == MatchMinute(base: 90))
    }
}
