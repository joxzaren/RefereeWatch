import Foundation
import Testing
@testable import RefereeKit

@Suite struct StoreTests {
    func makeStore() throws -> (MatchStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "RefereeKitStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (MatchStore(directory: dir), dir)
    }

    @Test func saveLoadOverwriteLoadAllDelete() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try store.loadAll().isEmpty)
        #expect(try store.load(id: UUID()) == nil)

        var older = Match(config: MatchConfig(homeName: "A"), deviceID: Fixture.watch, now: Fixture.at(0))
        older.log(.goal, side: .home, period: .firstHalf, minute: .init(base: 3), deviceID: Fixture.watch, now: Fixture.at(180.123_4))
        let newer = Match(config: MatchConfig(homeName: "B"), deviceID: Fixture.watch, now: Fixture.at(86_400))
        try store.save(older)
        try store.save(newer)
        #expect(try store.load(id: older.id) == older)
        #expect(try store.loadAll().map(\.id) == [newer.id, older.id])

        // Overwrite the same file atomically: the new content replaces the old, no extra files.
        older.log(.red, side: .away, period: .firstHalf, minute: .init(base: 9), deviceID: Fixture.watch, now: Fixture.at(540))
        try store.save(older)
        #expect(try store.load(id: older.id) == older)
        #expect(try store.load(id: older.id)?.events.count == 2)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        #expect(files.sorted() == ["\(newer.id.uuidString).json", "\(older.id.uuidString).json"].sorted())

        try store.delete(id: older.id)
        #expect(try store.load(id: older.id) == nil)
        #expect(try store.loadAll().map(\.id) == [newer.id])
        try store.delete(id: older.id)  // deleting again is fine
    }

    @Test func damagedFileDoesNotHideOthers() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let m = Fixture.match()
        try store.save(m)
        try Data("not json".utf8).write(to: dir.appending(path: "\(UUID().uuidString).json"))
        #expect(try store.loadAll().map(\.id) == [m.id])
    }

    @Test func storedFileUsesISODatesWithFractionalSeconds() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let m = Match(config: .standard, deviceID: Fixture.watch, now: Fixture.at(0.25))
        try store.save(m)
        let text = try String(contentsOf: store.fileURL(for: m.id), encoding: .utf8)
        #expect(text.contains("2027-01-15T08:00:00.250Z"))
    }
}
