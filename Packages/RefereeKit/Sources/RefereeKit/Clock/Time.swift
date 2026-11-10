import Foundation

/// One recorded instant. Monotonic time is used whenever two anchors come from
/// the same boot session; across a reboot the wall clock is the fallback.
public struct Anchor: Codable, Sendable, Hashable {
    /// `clock_gettime_nsec_np(CLOCK_MONOTONIC)`, which keeps counting during sleep
    /// and ignores changes to the system time.
    public var monotonicNanos: UInt64
    /// `kern.bootsessionuuid` at the time of reading.
    public var bootSessionID: String
    public var wall: Date

    public init(monotonicNanos: UInt64, bootSessionID: String, wall: Date) {
        self.monotonicNanos = monotonicNanos
        self.bootSessionID = bootSessionID
        self.wall = wall
    }

    /// Seconds from `earlier` to `self`. Negative when `earlier` is in fact later.
    public func seconds(since earlier: Anchor) -> TimeInterval {
        guard bootSessionID == earlier.bootSessionID else {
            return wall.timeIntervalSince(earlier.wall)
        }
        if monotonicNanos >= earlier.monotonicNanos {
            return TimeInterval(monotonicNanos - earlier.monotonicNanos) / 1_000_000_000
        }
        return -TimeInterval(earlier.monotonicNanos - monotonicNanos) / 1_000_000_000
    }

    /// The anchor `seconds` later (or earlier, when negative) in the same boot session.
    public func adding(seconds: TimeInterval) -> Anchor {
        let nanos = (abs(seconds) * 1_000_000_000).rounded()
        let delta = nanos >= Double(UInt64.max) ? UInt64.max : UInt64(nanos)
        let mono: UInt64
        if seconds >= 0 {
            let (sum, overflow) = monotonicNanos.addingReportingOverflow(delta)
            mono = overflow ? UInt64.max : sum
        } else {
            mono = monotonicNanos >= delta ? monotonicNanos - delta : 0
        }
        return Anchor(monotonicNanos: mono, bootSessionID: bootSessionID, wall: wall.addingTimeInterval(seconds))
    }
}

/// Source of anchors. Tests inject a fake one.
public protocol TimeSource: Sendable {
    func now() -> Anchor
}

/// Reads the real monotonic clock, boot session id and wall clock.
public struct SystemTimeSource: TimeSource {
    public init() {}

    public func now() -> Anchor {
        Anchor(
            monotonicNanos: clock_gettime_nsec_np(CLOCK_MONOTONIC),
            bootSessionID: Self.bootSessionID,
            wall: Date()
        )
    }

    /// Read once per process; it cannot change without a reboot.
    public static let bootSessionID: String = readBootSessionID()

    private static func readBootSessionID() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
