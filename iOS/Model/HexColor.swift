import SwiftUI
import UIKit

/// Conversion between `#RRGGBB` strings, the format `MatchConfig` stores, and colour components.
enum HexColor {
    struct RGB: Equatable, Sendable {
        var red: Int
        var green: Int
        var blue: Int
    }

    /// Parses `#RRGGBB` or `RRGGBB`, in either case. Returns nil for anything else.
    static func parse(_ text: String) -> RGB? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("#") { body.removeFirst() }
        guard body.count == 6, body.allSatisfy(\.isHexDigit), let value = Int(body, radix: 16) else { return nil }
        return RGB(red: (value >> 16) & 0xFF, green: (value >> 8) & 0xFF, blue: value & 0xFF)
    }

    /// `#RRGGBB` in upper case from components in 0...1. Values outside the range are clamped.
    static func format(red: Double, green: Double, blue: Double) -> String {
        format(RGB(red: byte(red), green: byte(green), blue: byte(blue)))
    }

    static func format(_ rgb: RGB) -> String {
        String(format: "#%02X%02X%02X", rgb.red, rgb.green, rgb.blue)
    }

    /// The canonical upper case form of a valid hex colour, or `fallback` when it is not valid.
    static func normalized(_ text: String, fallback: String) -> String {
        parse(text).map(format) ?? fallback
    }

    private static func byte(_ component: Double) -> Int {
        guard component.isFinite else { return 0 }
        return Int((min(max(component, 0), 1) * 255).rounded())
    }
}

extension Color {
    /// A colour from `#RRGGBB`, or `fallback` when the text is not a valid hex colour.
    init(hex: String, fallback: Color = .gray) {
        guard let rgb = HexColor.parse(hex) else {
            self = fallback
            return
        }
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    /// The colour as `#RRGGBB` in sRGB. Opacity is ignored.
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return HexColor.format(red: Double(red), green: Double(green), blue: Double(blue))
    }
}
