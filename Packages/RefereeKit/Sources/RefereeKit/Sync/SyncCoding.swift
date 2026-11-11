import Foundation

/// The single JSON format used for sync payloads, stored match files and merge tie breaks.
///
/// Dates are ISO 8601 strings in UTC with millisecond fractional seconds, formatted and parsed
/// through integer milliseconds. Every timestamp the domain creates goes through `normalize`,
/// so it is already on the millisecond grid and survives an encode and decode unchanged.
/// Equal timestamps therefore stay equal on every device, which the merge rule depends on.
public enum SyncCoding {
    static let plainStyle = Date.ISO8601FormatStyle()

    /// Whole milliseconds since 1970, the precision of the wire format.
    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// The date as it will read back after an encode and decode: rounded to the millisecond.
    /// Idempotent, and `parse(format(d)) == normalize(d)` for every date.
    public static func normalize(_ date: Date) -> Date {
        Self.date(milliseconds: milliseconds(date))
    }

    /// `2026-11-10T14:30:05.123Z`. Formatted from integer milliseconds so it never drifts.
    public static func format(_ date: Date) -> String {
        let ms = milliseconds(date)
        let seconds = ms.quotientAndRemainder(dividingBy: 1000)
        var whole = seconds.quotient
        var fraction = seconds.remainder
        if fraction < 0 {
            whole -= 1
            fraction += 1000
        }
        let base = plainStyle.format(Date(timeIntervalSince1970: Double(whole)))
        guard base.hasSuffix("Z") else { return base }
        return String(base.dropLast()) + "." + String(format: "%03lld", fraction) + "Z"
    }

    /// Parses ISO 8601 with or without fractional seconds. Digits beyond milliseconds are rounded.
    public static func parse(_ text: String) -> Date? {
        guard let dot = text.firstIndex(of: ".") else {
            return (try? plainStyle.parse(text)).map(normalize)
        }
        let afterDot = text[text.index(after: dot)...]
        let digits = afterDot.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let suffix = afterDot.dropFirst(digits.count)
        guard let wholeDate = try? plainStyle.parse(String(text[..<dot]) + suffix) else { return nil }
        let whole = Int64(wholeDate.timeIntervalSince1970.rounded())
        guard let fraction = Double("0." + digits) else { return nil }
        return date(milliseconds: whole * 1000 + Int64((fraction * 1000).rounded()))
    }

    /// A normalized timestamp for `now` that is strictly later than `previous`.
    /// Used for new versions so a local change always wins over the version it replaces,
    /// even when this device's clock is behind the one that wrote `previous`.
    public static func stamp(_ now: Date, after previous: Date?) -> Date {
        let stamped = normalize(now)
        guard let previous, stamped <= previous else { return stamped }
        var candidate = normalize(previous.addingTimeInterval(0.001))
        while candidate <= previous {
            candidate = normalize(candidate.addingTimeInterval(0.001))
        }
        return candidate
    }

    public static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(format(date))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = parse(text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an ISO 8601 date, got \(text)")
        }
        return decoder
    }

    /// Canonical bytes of a value (sorted keys, normalized dates). Used to break ties
    /// between different contents that carry identical versions, and to compare matches.
    public static func canonicalData<T: Encodable>(_ value: T) -> Data {
        (try? makeEncoder().encode(value)) ?? Data()
    }
}
