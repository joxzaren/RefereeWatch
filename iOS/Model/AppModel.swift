import Foundation
import Observation
import RefereeKit

/// Sends messages to the watch. `ConnectivityService` is the real one; tests use a fake.
@MainActor
protocol WatchLink: AnyObject {
    /// Sends with `updateApplicationContext` and `transferUserInfo`.
    func sendSetup(_ setup: SetupMessage)
    /// Sends with `transferUserInfo`.
    func sendMatch(_ match: Match)
}

/// The iPhone app's state: the setup being edited, the last setup sent, and the stored matches.
@MainActor
@Observable
final class AppModel {
    static let lastSetupKey = "RefereeWatch.lastSetup"

    private(set) var matches: [Match] = []
    private(set) var lastSetup: SetupMessage?
    var draft: SetupDraft
    /// The match the form edits. Nil until the first send of a new match.
    private(set) var draftMatchID: UUID?
    var errorMessage: String?

    let deviceID: String

    @ObservationIgnored private let store: MatchStore
    @ObservationIgnored private var link: (any WatchLink)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date

    init(store: MatchStore, defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.defaults = defaults
        self.clock = now
        self.deviceID = DeviceIdentity.current(defaults: defaults)
        self.draft = SetupDraft.fromFirstPreset(now: now())
        self.lastSetup = Self.loadLastSetup(from: defaults)
        reload()
        restoreDraft()
    }

    func connect(_ link: any WatchLink) {
        self.link = link
    }

    // MARK: Matches

    func reload() {
        do {
            matches = try store.loadAll()
        } catch {
            errorMessage = "Could not read the saved matches. \(error.localizedDescription)"
        }
    }

    func match(_ id: UUID) -> Match? {
        matches.first { $0.id == id }
    }

    /// Merges a match received from the watch, saves it when it changed, and sends the
    /// merged match back only when the watch is missing something.
    func receive(_ remote: Match) {
        let local = try? store.load(id: remote.id)
        let result = SyncPayload.mergeReceived(local: local, remote: remote)
        if result.changed {
            do {
                try store.save(result.merged)
            } catch {
                errorMessage = "Could not save the match from the watch. \(error.localizedDescription)"
                return
            }
            reload()
        }
        if result.needsSendBack {
            link?.sendMatch(result.merged)
        }
    }

    // MARK: Event editing

    /// Adds an event (`eventID == nil`) or changes one, saves the match and sends it to the watch.
    @discardableResult
    func saveEvent(_ draft: EventDraft, eventID: UUID?, matchID: UUID) -> Bool {
        updateMatch(matchID) { match, deviceID, now in
            if let eventID {
                return match.edit(eventID, deviceID: deviceID, now: now) { draft.apply(to: &$0) }
            }
            let numbers = draft.numbers
            match.log(
                draft.kind, side: draft.side, shirtNumber: numbers.shirt,
                playerOff: numbers.off, playerOn: numbers.on,
                period: draft.period, minute: draft.minute, deviceID: deviceID, now: now)
            return true
        }
    }

    /// Tombstones an event, saves the match and sends it to the watch.
    @discardableResult
    func deleteEvent(_ eventID: UUID, matchID: UUID) -> Bool {
        updateMatch(matchID) { match, deviceID, now in
            match.delete(eventID, deviceID: deviceID, now: now)
        }
    }

    private func updateMatch(_ id: UUID, change: (inout Match, String, Date) -> Bool) -> Bool {
        do {
            guard var match = try store.load(id: id) ?? self.match(id) else { return false }
            guard change(&match, deviceID, clock()) else { return false }
            try store.save(match)
            reload()
            link?.sendMatch(match.normalized())
            return true
        } catch {
            errorMessage = "Could not save the match. \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Setup

    /// True when the form edits a match that was already sent, so Send updates it.
    var isEditingSentMatch: Bool { draftMatchID != nil }

    /// Builds a setup newer than the last one sent, sends it to the watch and remembers it.
    @discardableResult
    func sendSetup() -> SetupMessage {
        let matchID = draftMatchID ?? UUID()
        let setup = SetupFactory.make(
            matchID: matchID, config: draft.config, previous: lastSetup, deviceID: deviceID, now: clock())
        lastSetup = setup
        draftMatchID = matchID
        saveLastSetup(setup)
        link?.sendSetup(setup)
        return setup
    }

    /// Starts a new match in the form. The next send uses a new match id.
    func startNewSetup() {
        draft = SetupDraft.fromFirstPreset(now: clock())
        draftMatchID = nil
    }

    /// Continues editing the last sent setup unless that match has kicked off,
    /// since the watch ignores setups for a match that has started.
    private func restoreDraft() {
        guard let lastSetup else { return }
        if let played = matches.first(where: { $0.id == lastSetup.matchID }), played.isKickedOff { return }
        let presetID = MatchPreset.builtIn.first { $0.config == Self.timings(lastSetup.config) }?.id
        draft = SetupDraft(config: lastSetup.config, presetID: presetID, now: clock())
        draftMatchID = lastSetup.matchID
    }

    /// The config with only the parts a preset describes, for matching it to a preset.
    private static func timings(_ config: MatchConfig) -> MatchConfig {
        var timings = MatchConfig()
        timings.halfLength = config.halfLength
        timings.halfTimeLength = config.halfTimeLength
        timings.warningOffsets = config.warningOffsets
        timings.extraTimeEnabled = config.extraTimeEnabled
        timings.extraTimeHalfLength = config.extraTimeHalfLength
        timings.extraTimeBreakLength = config.extraTimeBreakLength
        timings.extraTimeHalfTimeLength = config.extraTimeHalfTimeLength
        timings.penaltiesEnabled = config.penaltiesEnabled
        return timings
    }

    private func saveLastSetup(_ setup: SetupMessage) {
        if let data = try? SyncCoding.makeEncoder().encode(setup) {
            defaults.set(data, forKey: Self.lastSetupKey)
        }
    }

    private static func loadLastSetup(from defaults: UserDefaults) -> SetupMessage? {
        guard let data = defaults.data(forKey: lastSetupKey) else { return nil }
        return try? SyncCoding.makeDecoder().decode(SetupMessage.self, from: data)
    }
}
