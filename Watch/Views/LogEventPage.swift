import RefereeKit
import SwiftUI
import WatchKit

/// Kind is the first tap, team the second, Save the third. The shirt number is optional.
struct LogEventPage: View {
    @Environment(MatchController.self) private var controller

    @State private var kind: EventKind?
    @State private var side: Side?
    @State private var period: Period = .firstHalf
    @State private var minute = MatchMinute(base: 1)
    @State private var number = 0
    @State private var playerOff = 0
    @State private var playerOn = 0

    var body: some View {
        if let match = controller.match {
            if let kind, let side {
                numberStep(match, kind: kind, side: side)
            } else if let kind {
                teamStep(match, kind: kind)
            } else {
                kindStep(match)
            }
        }
    }

    private func kindStep(_ match: Match) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                kindButton(.goal, match: match, color: .green, symbol: "soccerball")
                kindButton(.yellow, match: match, color: .yellow, symbol: "rectangle.portrait.fill")
            }
            HStack(spacing: 6) {
                kindButton(.red, match: match, color: .red, symbol: "rectangle.portrait.fill")
                kindButton(.substitution, match: match, color: .blue, symbol: "arrow.left.arrow.right")
            }
        }
    }

    private func kindButton(_ kind: EventKind, match: Match, color: Color, symbol: String) -> some View {
        Button {
            // The minute is taken at the first tap, when the incident happened.
            let now = controller.now()
            period = match.clock.period
            minute = match.clock.minute(at: now, config: match.config)
            number = 0
            playerOff = 0
            playerOn = 0
            self.kind = kind
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.title3)
                Text(Format.short(kind)).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .tint(color)
        .buttonStyle(.bordered)
        .accessibilityLabel("Log \(kind.title)")
    }

    private func teamStep(_ match: Match, kind: EventKind) -> some View {
        VStack(spacing: 6) {
            Text("\(Format.short(kind)) \(minute.description)'").font(.footnote).foregroundStyle(.secondary)
            TeamButton(name: match.config.homeName, color: match.config.color(of: .home)) { side = .home }
            TeamButton(name: match.config.awayName, color: match.config.color(of: .away)) { side = .away }
            Button("Cancel", role: .cancel) { reset() }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private func numberStep(_ match: Match, kind: EventKind, side: Side) -> some View {
        VStack(spacing: 4) {
            Text("\(Format.short(kind)) \(minute.description)' \(Format.teamShort(match.config.name(of: side)))")
                .font(.footnote)
                .lineLimit(1)
            if kind == .substitution {
                HStack(spacing: 4) {
                    ShirtNumberPicker(title: "Off", number: $playerOff)
                    ShirtNumberPicker(title: "On", number: $playerOn)
                }
            } else {
                ShirtNumberPicker(title: "Number", number: $number)
            }
            Button {
                save(kind: kind, side: side)
            } label: {
                Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            Button("Cancel", role: .cancel) { reset() }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private func save(kind: EventKind, side: Side) {
        controller.logEvent(
            kind, side: side,
            shirtNumber: kind == .substitution ? nil : number.optionalNumber,
            playerOff: kind == .substitution ? playerOff.optionalNumber : nil,
            playerOn: kind == .substitution ? playerOn.optionalNumber : nil,
            period: period, minute: minute)
        WKInterfaceDevice.current().play(.success)
        reset()
    }

    private func reset() {
        kind = nil
        side = nil
    }
}
