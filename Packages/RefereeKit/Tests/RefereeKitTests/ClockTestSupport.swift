import Foundation
import Synchronization
@testable import RefereeKit

/// Fake time source. Starts at an arbitrary anchor and moves only when told.
final class ClockFakeTimeSource: TimeSource {
    private let state: Mutex<Anchor>

    init(boot: String = "boot-A", monotonicNanos: UInt64 = 1_000_000_000_000, wall: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        state = Mutex(Anchor(monotonicNanos: monotonicNanos, bootSessionID: boot, wall: wall))
    }

    func now() -> Anchor { state.withLock { $0 } }

    /// Moves both clocks forward and returns the new anchor.
    @discardableResult
    func advance(_ seconds: TimeInterval) -> Anchor {
        state.withLock { a in
            a = a.adding(seconds: seconds)
            return a
        }
    }

    /// Changes only the wall clock, as a user changing the system time would.
    func jumpWall(_ seconds: TimeInterval) {
        state.withLock { $0.wall = $0.wall.addingTimeInterval(seconds) }
    }
}

let stdConfig = MatchConfig.standard

func mins(_ m: Double) -> TimeInterval { m * 60 }

/// A clock that has kicked off at the fake source's current anchor.
func kickedOff(_ time: ClockFakeTimeSource, config: MatchConfig = stdConfig) -> MatchClock {
    var clock = MatchClock()
    clock.advance(at: time.now(), config: config)
    return clock
}
