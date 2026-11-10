import SwiftUI
import RefereeKit

/// Every stored match, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.matches.isEmpty {
                ContentUnavailableView(
                    "No matches yet",
                    systemImage: "sportscourt",
                    description: Text("Matches you referee with your Apple Watch appear here after they sync."))
            } else {
                List(model.matches) { match in
                    NavigationLink(value: match.id) {
                        MatchRow(match: match)
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: UUID.self) { id in
            ReportView(matchID: id)
        }
        .refreshable { model.reload() }
    }
}

struct MatchRow: View {
    let match: Match

    var body: some View {
        let config = match.config
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(Color(hex: config.homeColorHex)).frame(width: 10, height: 10)
                Text(config.homeName)
                Text("v").foregroundStyle(.secondary)
                Text(config.awayName)
                Circle().fill(Color(hex: config.awayColorHex)).frame(width: 10, height: 10)
                Spacer()
                Text("\(match.score.home) - \(match.score.away)")
                    .monospacedDigit()
                    .bold()
            }
            .font(.headline)
            HStack {
                Text(MatchRow.date(of: match), format: .dateTime.day().month().year().hour().minute())
                if !config.competition.isEmpty { Text(config.competition) }
                Spacer()
                if let penalties = match.penaltyScore {
                    Text("Pens \(penalties.home) - \(penalties.away)").monospacedDigit()
                }
                if !match.isFinished {
                    Text(match.isKickedOff ? "In progress" : "Not started")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    static func date(of match: Match) -> Date {
        match.config.kickOff ?? match.kickedOffAt ?? match.createdAt
    }
}
