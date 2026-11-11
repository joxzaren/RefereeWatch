import Foundation
import Testing
@testable import RefereeKit

@Suite struct PresetTests {
    @Test func builtInPresets() {
        let presets = MatchPreset.builtIn
        #expect(presets.map(\.name) == [
            "Standard 2 x 45", "Youth 2 x 35", "Youth 2 x 30", "Cup with extra time and penalties",
        ])
        #expect(Set(presets.map(\.id)).count == presets.count)
        #expect(presets[0].config == .standard)
        #expect(presets[1].config.halfLength == 35 * 60)
        #expect(presets[2].config.halfLength == 30 * 60)
        #expect(!presets[1].config.extraTimeEnabled)
        let cup = presets[3].config
        #expect(cup.halfLength == 45 * 60)
        #expect(cup.extraTimeEnabled && cup.penaltiesEnabled)
        #expect(Period.extraTimeSecond.next(cup) == .penalties)
    }

    @Test func presetsRoundTrip() throws {
        let data = try SyncCoding.makeEncoder().encode(MatchPreset.builtIn)
        #expect(try SyncCoding.makeDecoder().decode([MatchPreset].self, from: data) == MatchPreset.builtIn)
    }
}
