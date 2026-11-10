import Foundation
import RefereeKit

/// The setup form's state, in the units the form shows (whole minutes).
/// Converts to and from `MatchConfig`, which stores seconds.
struct SetupDraft: Equatable {
    var presetID: UUID?

    var homeName: String
    var awayName: String
    var homeColorHex: String
    var awayColorHex: String
    var competition: String
    var hasKickOff: Bool
    var kickOff: Date

    var halfMinutes: Int
    var halfTimeMinutes: Int
    /// Minutes before the end of normal time, in any order. `config` sorts and cleans them.
    var warningMinutes: [Int]

    var extraTimeEnabled: Bool
    var extraTimeHalfMinutes: Int
    var extraTimeBreakMinutes: Int
    var extraTimeHalfTimeMinutes: Int
    var penaltiesEnabled: Bool

    static let defaultHomeName = "Home"
    static let defaultAwayName = "Away"

    init(config: MatchConfig, presetID: UUID? = nil, now: Date = .now) {
        self.presetID = presetID
        homeName = config.homeName
        awayName = config.awayName
        homeColorHex = config.homeColorHex
        awayColorHex = config.awayColorHex
        competition = config.competition
        hasKickOff = true
        kickOff = config.kickOff ?? Self.nextQuarterHour(after: now)
        halfMinutes = 0
        halfTimeMinutes = 0
        warningMinutes = []
        extraTimeEnabled = false
        extraTimeHalfMinutes = 0
        extraTimeBreakMinutes = 0
        extraTimeHalfTimeMinutes = 0
        penaltiesEnabled = false
        applyTimings(of: config)
    }

    /// A draft from the first built in preset.
    static func fromFirstPreset(now: Date = .now) -> SetupDraft {
        let preset = MatchPreset.builtIn[0]
        return SetupDraft(config: preset.config, presetID: preset.id, now: now)
    }

    /// Takes the timings, extra time and penalties of the preset. Keeps teams, colours,
    /// competition and kick off, which a preset does not describe.
    mutating func apply(_ preset: MatchPreset) {
        presetID = preset.id
        applyTimings(of: preset.config)
    }

    private mutating func applyTimings(of config: MatchConfig) {
        halfMinutes = Self.minutes(config.halfLength)
        halfTimeMinutes = Self.minutes(config.halfTimeLength)
        warningMinutes = config.warningOffsets.map(Self.minutes)
        extraTimeEnabled = config.extraTimeEnabled
        extraTimeHalfMinutes = Self.minutes(config.extraTimeHalfLength)
        extraTimeBreakMinutes = Self.minutes(config.extraTimeBreakLength)
        extraTimeHalfTimeMinutes = Self.minutes(config.extraTimeHalfTimeLength)
        penaltiesEnabled = config.penaltiesEnabled
    }

    /// The configuration to send. Names fall back to Home and Away, colours to the defaults,
    /// and warnings keep only distinct values inside the half, largest first.
    var config: MatchConfig {
        let standard = MatchConfig.standard
        let half = max(halfMinutes, 1)
        let warnings = Set(warningMinutes.filter { $0 > 0 && $0 < half }).sorted(by: >)
        return MatchConfig(
            homeName: Self.cleaned(homeName, fallback: Self.defaultHomeName),
            awayName: Self.cleaned(awayName, fallback: Self.defaultAwayName),
            homeColorHex: HexColor.normalized(homeColorHex, fallback: standard.homeColorHex),
            awayColorHex: HexColor.normalized(awayColorHex, fallback: standard.awayColorHex),
            competition: competition.trimmingCharacters(in: .whitespacesAndNewlines),
            kickOff: hasKickOff ? kickOff : nil,
            halfLength: TimeInterval(half * 60),
            halfTimeLength: TimeInterval(max(halfTimeMinutes, 0) * 60),
            warningOffsets: warnings.map { TimeInterval($0 * 60) },
            extraTimeEnabled: extraTimeEnabled,
            extraTimeHalfLength: TimeInterval(max(extraTimeHalfMinutes, 1) * 60),
            extraTimeBreakLength: TimeInterval(max(extraTimeBreakMinutes, 0) * 60),
            extraTimeHalfTimeLength: TimeInterval(max(extraTimeHalfTimeMinutes, 0) * 60),
            penaltiesEnabled: penaltiesEnabled)
    }

    static func minutes(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded())
    }

    static func nextQuarterHour(after date: Date) -> Date {
        let quarter: TimeInterval = 15 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
    }

    private static func cleaned(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

/// Builds versioned setups. Each new setup is strictly newer than the last one this phone
/// sent, for the same match or a new one, because the watch keeps a single current setup
/// and applies an incoming one only when its version wins.
enum SetupFactory {
    static func make(matchID: UUID, config: MatchConfig, previous: SetupMessage?, deviceID: String, now: Date) -> SetupMessage {
        SetupMessage(
            matchID: matchID,
            config: config,
            version: Version.next(after: previous?.version, deviceID: deviceID, now: now))
    }
}
