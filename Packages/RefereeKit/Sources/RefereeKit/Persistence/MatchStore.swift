import Foundation

/// One JSON file per match, written atomically after every change.
///
/// A `final class` that is `Sendable` because its only state is an immutable directory URL.
/// Each call is a self contained file operation, so it is safe from any thread or task.
/// Callers that save the same match from several tasks should serialize those saves.
public final class MatchStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Application Support/Matches, created if missing.
    public static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appending(path: "Matches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    /// Writes the match, replacing any earlier file for it atomically.
    public func save(_ match: Match) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try SyncCoding.makeEncoder(pretty: true).encode(match.normalized())
        try data.write(to: fileURL(for: match.id), options: .atomic)
    }

    /// The stored match, or nil when there is no file for it.
    public func load(id: UUID) throws -> Match? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try SyncCoding.makeDecoder().decode(Match.self, from: Data(contentsOf: url))
    }

    /// Every stored match, newest first by creation time.
    /// A file that cannot be decoded is skipped so one damaged file never hides the others.
    public func loadAll() throws -> [Match] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let decoder = SyncCoding.makeDecoder()
        let matches = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Match.self, from: $0) } }
        return matches.sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
    }

    /// Removes the match's file. Does nothing when there is none.
    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
