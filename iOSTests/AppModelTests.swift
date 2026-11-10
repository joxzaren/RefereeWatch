import Foundation
import Testing
import RefereeKit
@testable import RefereeWatch

@MainActor
final class FakeLink: WatchLink {
    var setups: [SetupMessage] = []
    var matches: [Match] = []
    func sendSetup(_ setup: SetupMessage) { setups.append(setup) }
    func sendMatch(_ match: Match) { matches.append(match) }
}

@MainActor
@Suite struct AppModelTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "AppModelTests-\(UUID().uuidString)")
    let suiteName = "AppModelTests-\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    var store: MatchStore { MatchStore(directory: directory) }

    func makeModel(now: Date = Fixtures.kickOff) -> (AppModel, FakeLink) {
        let model = AppModel(store: store, defaults: defaults, now: { now })
        let link = FakeLink()
        model.connect(link)
        return (model, link)
    }

    @Test func sendingASetupVersionsItAndKeepsTheMatchID() {
        let (model, link) = makeModel()
        model.draft.homeName = "Lions"
        let first = model.sendSetup()
        model.draft.awayName = "Bears"
        let second = model.sendSetup()

        #expect(link.setups == [first, second])
        #expect(second.matchID == first.matchID)
        #expect(SyncMerge.beats(second.version, first.version))
        #expect(second.version.deviceID == model.deviceID)
        #expect(second.config.awayName == "Bears")
        #expect(model.lastSetup == second)

        model.startNewSetup()
        let third = model.sendSetup()
        #expect(third.matchID != first.matchID)
        #expect(SyncMerge.beats(third.version, second.version))
    }

    @Test func lastSetupSurvivesARelaunch() {
        let (model, _) = makeModel()
        model.draft.homeName = "Lions"
        let sent = model.sendSetup()

        let (relaunched, _) = makeModel()
        #expect(relaunched.lastSetup == sent)
        #expect(relaunched.isEditingSentMatch)
        #expect(relaunched.draft.homeName == "Lions")
        let next = relaunched.sendSetup()
        #expect(next.matchID == sent.matchID)
        #expect(SyncMerge.beats(next.version, sent.version))
    }

    @Test func receivingANewMatchSavesItWithoutSendingBack() throws {
        let (model, link) = makeModel()
        let match = Fixtures.fullMatch()
        model.receive(match)
        #expect(model.matches.map(\.id) == [match.id])
        #expect(try store.load(id: match.id) == match.normalized())
        #expect(link.matches.isEmpty)

        model.receive(match)
        #expect(link.matches.isEmpty)
    }

    @Test func receivingAnOlderCopySendsTheMergedMatchBack() throws {
        let (model, link) = makeModel()
        let full = Fixtures.fullMatch()
        model.receive(full)

        var stale = Match(config: full.config, deviceID: Fixtures.deviceID, now: Fixtures.kickOff)
        stale.id = full.id
        stale.configVersion = full.configVersion
        stale.clockVersion = full.clockVersion
        stale.createdAt = full.createdAt
        model.receive(stale)

        #expect(link.matches.count == 1)
        #expect(link.matches.first?.liveEvents.count == full.liveEvents.count)
    }

    @Test func editingAnEventSavesAndSends() throws {
        let (model, link) = makeModel(now: Fixtures.kickOff.addingTimeInterval(3_600 * 3))
        let match = Fixtures.fullMatch()
        model.receive(match)
        let goal = try #require(match.liveEvents.first { $0.kind == .goal && $0.shirtNumber == nil })

        var draft = EventDraft(event: goal)
        draft.shirtNumber = "14"
        draft.side = .home
        #expect(model.saveEvent(draft, eventID: goal.id, matchID: match.id))

        let saved = try #require(try store.load(id: match.id)?.event(goal.id))
        #expect(saved.shirtNumber == 14)
        #expect(saved.side == .home)
        #expect(saved.version.deviceID == model.deviceID)
        #expect(link.matches.last?.event(goal.id)?.shirtNumber == 14)
        #expect(model.match(match.id)?.score == Score(home: 3, away: 1))
    }

    @Test func addingAndDeletingEvents() throws {
        let (model, link) = makeModel(now: Fixtures.kickOff.addingTimeInterval(3_600 * 3))
        let match = Fixtures.fullMatch()
        model.receive(match)

        var draft = EventDraft()
        draft.kind = .red
        draft.side = .away
        draft.period = .secondHalf
        draft.minuteBase = 88
        draft.shirtNumber = "5"
        #expect(model.saveEvent(draft, eventID: nil, matchID: match.id))
        let added = try #require(model.match(match.id)?.liveEvents.first { $0.kind == .red })
        #expect(added.shirtNumber == 5)
        #expect(added.minute == MatchMinute(base: 88))

        #expect(model.deleteEvent(added.id, matchID: match.id))
        #expect(model.match(match.id)?.liveEvents.contains { $0.id == added.id } == false)
        #expect(link.matches.count == 2)
        #expect(!model.deleteEvent(added.id, matchID: match.id))
    }
}
