import Foundation
import Observation
import RefereeKit

/// Owns the current match. Every mutation goes through here, is saved at once, reschedules
/// the alerts and, for a finished match, is sent to the iPhone.
@MainActor
@Observable
final class MatchController {
    static let shared = MatchController()

    /// The match on the watch: running, or finished and showing its summary. Nil before kick off.
    private(set) var match: Match?
    /// The last setup applied from the iPhone.
    private(set) var storedSetup: SetupMessage?
    private(set) var storedMatchIDs: Set<UUID> = []
    var selectedPresetID: UUID = MatchPreset.builtIn[0].id

    let workout = WorkoutManager()
    let notifications = NotificationPermissions()

    @ObservationIgnored let deviceID: String
    @ObservationIgnored private let time = SystemTimeSource()
    @ObservationIgnored private let store: MatchStore
    @ObservationIgnored private let setupStore = SetupStore(url: SetupStore.defaultURL())
    @ObservationIgnored private let alerts = AlertService()
    @ObservationIgnored private let connectivity = ConnectivityService()

    private init() {
        deviceID = DeviceIdentity.current()
        let directory = (try? MatchStore.defaultDirectory())
            ?? FileManager.default.temporaryDirectory.appending(path: "Matches", directoryHint: .isDirectory)
        store = MatchStore(directory: directory)

        let all = (try? store.loadAll()) ?? []
        storedMatchIDs = Set(all.map(\.id))
        // Recovery comes from the stored anchors; nothing counted ticks.
        match = all.first { $0.isKickedOff && !$0.isFinished }
        storedSetup = setupStore.load()

        alerts.onFire = { [weak self] delivery in self?.alertFired(delivery) }
        connectivity.onMessage = { [weak self] message in self?.receive(message) }
        connectivity.activate()

        refresh()
        if let match, match.isKickedOff, !match.isFinished {
            let kickOff = match.kickedOffAt ?? Date()
            Task { await self.workout.recoverOrStart(at: kickOff) }
        }
        Task { await self.notifications.refresh() }
    }

    // MARK: Reading

    func now() -> Anchor { time.now() }

    /// The iPhone setup that can start a new match, if any.
    var usableSetup: SetupMessage? {
        SetupLogic.usable(storedSetup, storedMatchIDs: storedMatchIDs)
    }

    var selectedPreset: MatchPreset {
        MatchPreset.builtIn.first { $0.id == selectedPresetID } ?? MatchPreset.builtIn[0]
    }

    var isRunning: Bool { match.map { $0.isKickedOff && !$0.isFinished } ?? false }

    // MARK: Lifecycle

    /// On launch and whenever the scene becomes active: records the announced added time when
    /// normal end has passed, and replans every alert from the anchors.
    func refresh() {
        markAnnouncedIfDue()
        reschedule()
        Task { await notifications.refresh() }
    }

    private func reschedule() {
        alerts.reschedule(match: match, now: time.now())
    }

    // MARK: Kick off

    /// Starts a match from the iPhone setup when there is one, otherwise from the chosen preset.
    func startMatch(useSetup: Bool) {
        guard !isRunning else { return }
        let anchor = time.now()
        var new: Match
        if useSetup, let setup = usableSetup {
            new = Match(id: setup.matchID, config: setup.config, deviceID: deviceID, now: anchor.wall)
        } else {
            new = Match(config: selectedPreset.config, deviceID: deviceID, now: anchor.wall)
        }
        var clock = new.clock
        clock.advance(at: anchor, config: new.config)
        new.updateClock(clock, deviceID: deviceID, now: anchor.wall)
        new.markKickedOff(now: anchor.wall)
        commit(new)
        Task { await workout.start(at: anchor.wall) }
    }

    /// The Action button's start: opens the running match, or starts a new one.
    func startOrOpenFromIntent() {
        if isRunning { return }
        startMatch(useSetup: usableSetup != nil)
    }

    /// Clears a finished match so the pre-match screen shows again.
    func newMatch() {
        guard match?.isFinished ?? false else { return }
        match = nil
        reschedule()
    }

    // MARK: Clock

    /// Moves to the next period. Never automatic; the screens use a hold to confirm.
    func advance() {
        guard var m = match, m.isKickedOff, !m.isFinished else { return }
        let anchor = time.now()
        var clock = m.clock
        clock.advance(at: anchor, config: m.config)
        m.updateClock(clock, deviceID: deviceID, now: anchor.wall)
        let finished = clock.period == .finished
        if finished { m.finish(deviceID: deviceID, now: anchor.wall) }
        commit(m)
        if finished { endWorkout(for: m) }
    }

    var isStoppageOpen: Bool { match?.clock.isStoppageOpen ?? false }

    /// Starts or ends a stoppage. Returns false when nothing changed.
    @discardableResult
    func toggleStoppage() -> Bool {
        isStoppageOpen ? endStoppage() : startStoppage()
    }

    @discardableResult
    func startStoppage() -> Bool {
        mutateClock { clock, anchor, _ in clock.startStoppage(at: anchor) }
    }

    @discardableResult
    func endStoppage() -> Bool {
        mutateClock { clock, anchor, _ in clock.endStoppage(at: anchor) }
    }

    /// Crown input on the added time panel. After normal end only increases are accepted.
    @discardableResult
    func adjustAddedTime(by minutes: Int) -> Bool {
        mutateClock { clock, anchor, config in clock.adjustAddedTime(by: minutes, at: anchor, config: config) }
    }

    private func markAnnouncedIfDue() {
        guard let m = match, m.isKickedOff, !m.isFinished else { return }
        let anchor = time.now()
        guard m.clock.isPastNormalEnd(at: anchor, config: m.config) else { return }
        var clock = m.clock
        clock.markAnnounced(at: anchor, config: m.config)
        // Idempotent: no new version when the recorded value is already there.
        guard clock != m.clock else { return }
        var updated = m
        updated.updateClock(clock, deviceID: deviceID, now: anchor.wall)
        commit(updated)
    }

    private func alertFired(_ delivery: AlertDelivery) {
        if delivery.includesNormalEnd {
            markAnnouncedIfDue()
        }
        reschedule()
    }

    @discardableResult
    private func mutateClock(_ change: (inout MatchClock, Anchor, MatchConfig) -> Bool) -> Bool {
        guard var m = match, m.isKickedOff, !m.isFinished else { return false }
        let anchor = time.now()
        var clock = m.clock
        guard change(&clock, anchor, m.config), clock != m.clock else { return false }
        m.updateClock(clock, deviceID: deviceID, now: anchor.wall)
        commit(m)
        return true
    }

    // MARK: Events

    func logEvent(
        _ kind: EventKind, side: Side, shirtNumber: Int?, playerOff: Int?, playerOn: Int?,
        period: Period, minute: MatchMinute
    ) {
        mutate { m, now in
            m.log(kind, side: side, shirtNumber: shirtNumber, playerOff: playerOff, playerOn: playerOn,
                  period: period, minute: minute, deviceID: deviceID, now: now)
            return true
        }
    }

    func undoLastEvent() {
        mutate { m, now in m.undoLast(deviceID: deviceID, now: now) != nil }
    }

    func editEvent(_ id: UUID, change: (inout MatchEvent) -> Void) {
        mutate { m, now in m.edit(id, deviceID: deviceID, now: now, change: change) }
    }

    func deleteEvent(_ id: UUID) {
        mutate { m, now in m.delete(id, deviceID: deviceID, now: now) }
    }

    // MARK: Penalties

    func logPenalty(side: Side, shirtNumber: Int?, scored: Bool) {
        mutate { m, now in
            m.logPenalty(side: side, shirtNumber: shirtNumber, scored: scored, deviceID: deviceID, now: now)
            return true
        }
    }

    func undoLastPenalty() {
        mutate { m, now in m.undoLastPenalty(deviceID: deviceID, now: now) != nil }
    }

    // MARK: Workout

    private func endWorkout(for finished: Match) {
        let id = finished.id
        let fallback: TimeInterval? = {
            guard let start = finished.kickedOffAt, let end = finished.finishedAt else { return nil }
            return end.timeIntervalSince(start)
        }()
        let end = finished.finishedAt ?? Date()
        Task {
            let summary = await workout.end(at: end, fallbackDuration: fallback)
            guard var m = self.match, m.id == id else {
                // The referee already moved on; update the stored copy instead.
                if var stored = try? store.load(id: id) {
                    stored.setWorkout(summary, deviceID: deviceID, now: Date())
                    try? store.save(stored)
                    connectivity.send(stored)
                }
                return
            }
            m.setWorkout(summary, deviceID: deviceID, now: Date())
            commit(m)
        }
    }

    // MARK: Saving

    private func mutate(_ change: (inout Match, Date) -> Bool) {
        guard var m = match else { return }
        guard change(&m, Date()) else { return }
        commit(m)
    }

    /// Saves at once, replans the alerts and sends a finished match to the iPhone.
    private func commit(_ m: Match) {
        match = m
        try? store.save(m)
        storedMatchIDs.insert(m.id)
        reschedule()
        if m.isFinished {
            connectivity.send(m)
        }
    }

    // MARK: Sync

    private func receive(_ message: WireMessage) {
        switch message {
        case .setup(let setup):
            let stored = try? store.load(id: setup.matchID)
            let kickedOff = SetupLogic.kickedOff(setup, active: match, stored: stored)
            guard SetupPolicy.shouldApply(setup, current: storedSetup, matchKickedOff: kickedOff) else { return }
            storedSetup = setup
            try? setupStore.save(setup)
        case .match(let remote):
            let local = match?.id == remote.id ? match : (try? store.load(id: remote.id)) ?? nil
            let result = SyncPayload.mergeReceived(local: local, remote: remote)
            if result.changed {
                try? store.save(result.merged)
                storedMatchIDs.insert(result.merged.id)
                if match?.id == result.merged.id {
                    match = result.merged
                    reschedule()
                }
            }
            if result.needsSendBack {
                connectivity.send(result.merged)
            }
        }
    }
}
