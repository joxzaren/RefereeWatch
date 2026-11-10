import Foundation

/// The ids of finished matches that still need to reach the iPhone, kept as a small JSON file
/// in Application Support so a relaunch resends anything whose transfer never finished.
struct PendingSendStore: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    static func defaultURL() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appending(path: "PendingMatchSends.json", directoryHint: .notDirectory)
    }

    /// The stored ids. Empty when there is no file or it cannot be read.
    func load() -> Set<UUID> {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
        return Set(ids)
    }

    func save(_ ids: Set<UUID>) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(ids.sorted { $0.uuidString < $1.uuidString })
        try data.write(to: url, options: .atomic)
    }
}
