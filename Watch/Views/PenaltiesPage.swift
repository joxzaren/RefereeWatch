import RefereeKit
import SwiftUI
import WatchKit

/// Penalty shootout: a kick per side as scored or missed, with an optional number.
struct PenaltiesPage: View {
    @Environment(MatchController.self) private var controller
    @State private var number = 0

    var body: some View {
        if let match = controller.match {
            let shootout = match.shootout
            let score = shootout.score
            let taken = shootout.taken
            let next = PenaltyLogic.nextSide(shootout)
            ScrollView {
                VStack(spacing: 6) {
                    HStack {
                        Text("Penalties").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Text("Match \(match.score.home)–\(match.score.away)").font(.footnote)
                    }
                    Text("\(score.home) – \(score.away)")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .accessibilityLabel("Shootout \(score.home) to \(score.away)")
                    Text("Kicks \(taken.home) / \(taken.away)").font(.caption2).foregroundStyle(.secondary)
                    if let winner = shootout.winner {
                        Text("\(match.config.name(of: winner)) win")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Text("Next: \(match.config.name(of: next))").font(.caption2)
                    }

                    ShirtNumberPicker(title: "Number", number: $number)

                    ForEach(Side.allCases, id: \.self) { side in
                        kickRow(match, side: side, highlighted: side == next && !shootout.isDecided)
                    }

                    Button {
                        controller.undoLastPenalty()
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        Label("Undo last kick", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!shootout.kicks.contains { $0.createdBy == controller.deviceID })

                    ForEach(shootout.kicks.reversed()) { kick in
                        HStack {
                            Image(systemName: kick.scored ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(kick.scored ? .green : .red)
                            Text("\(kick.order). \(Format.teamShort(match.config.name(of: kick.side)))")
                            if let n = kick.shirtNumber { Text("#\(n)").foregroundStyle(.secondary) }
                            Spacer()
                        }
                        .font(.footnote)
                    }
                }
            }
        }
    }

    private func kickRow(_ match: Match, side: Side, highlighted: Bool) -> some View {
        VStack(spacing: 2) {
            Text(match.config.name(of: side))
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(highlighted ? .primary : .secondary)
            HStack(spacing: 6) {
                Button {
                    log(side, scored: true)
                } label: {
                    Label("Scored", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(.green)
                .accessibilityLabel("\(match.config.name(of: side)) scored")
                Button {
                    log(side, scored: false)
                } label: {
                    Label("Missed", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(.red)
                .accessibilityLabel("\(match.config.name(of: side)) missed")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(match.config.color(of: side), lineWidth: highlighted ? 2 : 1))
    }

    private func log(_ side: Side, scored: Bool) {
        controller.logPenalty(side: side, shirtNumber: number.optionalNumber, scored: scored)
        WKInterfaceDevice.current().play(scored ? .success : .failure)
        number = 0
    }
}
