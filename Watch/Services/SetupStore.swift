import Foundation
import RefereeKit

/// Keeps the last setup applied from the iPhone as JSON in Application Support.
struct SetupStore: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    static func defaultURL() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appending(path: "LastSetup.json", directoryHint: .notDirectory)
    }

    func load() -> SetupMessage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SyncCoding.makeDecoder().decode(SetupMessage.self, from: data)
    }

    func save(_ setup: SetupMessage) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try SyncCoding.makeEncoder(pretty: true).encode(setup)
        try data.write(to: url, options: .atomic)
    }
}
