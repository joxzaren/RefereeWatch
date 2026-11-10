import RefereeKit
import SwiftUI
import WatchKit

extension Color {
    /// `#RRGGBB`, falling back to gray.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

extension MatchConfig {
    func color(of side: Side) -> Color {
        Color(hex: side == .home ? homeColorHex : awayColorHex)
    }
}

/// A button that only acts after being held for about a second, with a filling bar.
struct HoldToConfirmButton: View {
    let title: String
    var subtitle: String?
    var tint: Color = .accentColor
    let action: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.3))
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 14)
                    .fill(tint)
                    .frame(width: geometry.size.width * progress)
            }
            VStack(spacing: 0) {
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle ?? "Hold to confirm").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 58)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 40) {
            progress = 0
            WKInterfaceDevice.current().play(.success)
            action()
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: 1.0) : .easeOut(duration: 0.15)) {
                progress = pressing ? 1 : 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Hold for one second to confirm")
        .accessibilityAction { action() }
    }
}

/// "Screen may sleep" and "Backup alerts are off" warnings.
struct WarningBanners: View {
    @Environment(MatchController.self) private var controller
    var compact = false

    var body: some View {
        let showSleep = controller.isRunning && !controller.workout.sessionHealthy
        let showBackup = controller.notifications.backupAlertsOff
        if showSleep || showBackup {
            VStack(alignment: .leading, spacing: 2) {
                if showSleep {
                    Label("Screen may sleep. Backup alerts will still buzz if notifications are on.",
                          systemImage: "moon.zzz")
                }
                if showBackup {
                    Label("Backup alerts are off", systemImage: "bell.slash")
                }
            }
            .font(compact ? .system(size: 10) : .footnote)
            .foregroundStyle(.yellow)
            .lineLimit(compact ? 2 : nil)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Home 1 – 0 Away" in a compact form.
struct ScoreLine: View {
    let match: Match

    var body: some View {
        let score = match.score
        HStack(spacing: 4) {
            Circle().fill(match.config.color(of: .home)).frame(width: 7, height: 7)
            Text("\(score.home)–\(score.away)").font(.headline.monospacedDigit())
            Circle().fill(match.config.color(of: .away)).frame(width: 7, height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(match.config.homeName) \(score.home), \(match.config.awayName) \(score.away)")
    }
}

/// A big team button with the team colour.
struct TeamButton: View {
    let name: String
    let color: Color
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .tint(color)
        .buttonStyle(.borderedProminent)
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 2)
            }
        }
    }
}

/// Optional shirt number on the crown. 0 means no number.
struct ShirtNumberPicker: View {
    let title: String
    @Binding var number: Int

    var body: some View {
        Picker(title, selection: $number) {
            Text("–").tag(0)
            ForEach(1..<100, id: \.self) { n in
                Text("\(n)").tag(n)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 56)
    }
}

extension Int {
    /// Nil for 0, the "no number" choice.
    var optionalNumber: Int? { self == 0 ? nil : self }
}
