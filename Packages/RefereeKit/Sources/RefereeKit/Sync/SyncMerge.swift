import Foundation

/// Last writer wins merge for matches. The result is commutative, associative and
/// idempotent because every choice is the maximum of a total order:
/// the version order below, then the canonical bytes of the content for identical versions.
public enum SyncMerge {
    /// True when `a` strictly beats `b`:
    /// (1) later `modifiedAt`, (2) on equal times a deletion, (3) the greater `deviceID`.
    public static func beats(_ a: Version, _ b: Version) -> Bool {
        if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
        if a.deleted != b.deleted { return a.deleted }
        return a.deviceID > b.deviceID
    }

    /// The winning version. Identical versions are equal, so either is returned.
    public static func winner(_ a: Version, _ b: Version) -> Version {
        beats(b, a) ? b : a
    }

    /// Alias of `winner`, the name used in the plan.
    public static func resolve(_ a: Version, _ b: Version) -> Version {
        winner(a, b)
    }

    /// Merges two copies of the same match.
    /// - Events and penalty kicks: the winner per id. Tombstones are kept forever.
    /// - Config, clock, workout and finish state: the winner of their own versions.
    /// - `createdAt` and `kickedOffAt`: the earliest known value.
    public static func merge(_ local: Match, _ remote: Match) -> Match {
        var merged = local
        merged.id = local.id.uuidString <= remote.id.uuidString ? local.id : remote.id
        merged.createdAt = min(local.createdAt, remote.createdAt)

        let config = pick(local.config, local.configVersion, remote.config, remote.configVersion)
        merged.config = config.value
        merged.configVersion = config.version

        let clock = pick(local.clock, local.clockVersion, remote.clock, remote.clockVersion)
        merged.clock = clock.value
        merged.clockVersion = clock.version

        let workout = pickOptional(local.workout, local.workoutVersion, remote.workout, remote.workoutVersion)
        merged.workout = workout.value
        merged.workoutVersion = workout.version

        let finish = pickOptional(local.finishedAt, local.finishVersion, remote.finishedAt, remote.finishVersion)
        merged.finishedAt = finish.value
        merged.finishVersion = finish.version

        merged.kickedOffAt = earliest(local.kickedOffAt, remote.kickedOffAt)
        merged.events = mergeByID(local.events, remote.events)
        merged.penalties = mergeByID(local.penalties, remote.penalties)
        merged.normalize()
        return merged
    }

    /// The winner per id across both lists, also collapsing duplicates within one list.
    public static func mergeByID<T: Versioned>(_ a: [T], _ b: [T]) -> [T] {
        var byID: [UUID: T] = [:]
        for item in a + b {
            if let existing = byID[item.id] {
                byID[item.id] = pick(existing, existing.version, item, item.version).value
            } else {
                byID[item.id] = item
            }
        }
        return Array(byID.values)
    }

    static func pick<T: Encodable>(_ a: T, _ va: Version, _ b: T, _ vb: Version) -> (value: T, version: Version) {
        if beats(va, vb) { return (a, va) }
        if beats(vb, va) { return (b, vb) }
        // Identical versions: fall back to the content so the choice does not depend on order.
        let da = SyncCoding.canonicalData(a)
        let db = SyncCoding.canonicalData(b)
        return da.lexicographicallyPrecedes(db) ? (b, vb) : (a, va)
    }

    static func pickOptional<T: Encodable>(_ a: T?, _ va: Version?, _ b: T?, _ vb: Version?) -> (value: T?, version: Version?) {
        switch (va, vb) {
        case let (va?, vb?):
            let chosen = pick(Box(a), va, Box(b), vb)
            return (chosen.value.value, chosen.version)
        case (.some, nil): return (a, va)
        case (nil, .some): return (b, vb)
        case (nil, nil):
            guard let a, let b else { return (a ?? b, nil) }
            return (pick(a, Version(modifiedAt: .distantPast, deviceID: ""), b, Version(modifiedAt: .distantPast, deviceID: "")).value, nil)
        }
    }

    static func earliest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (a?, b?): min(a, b)
        default: a ?? b
        }
    }

    private struct Box<T: Encodable>: Encodable {
        var value: T?
        init(_ value: T?) { self.value = value }
    }
}
