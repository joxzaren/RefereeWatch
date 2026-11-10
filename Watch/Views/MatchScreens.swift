import RefereeKit
import SwiftUI

/// Chooses the screen for the match state.
struct RootView: View {
    @Environment(MatchController.self) private var controller

    var body: some View {
        NavigationStack {
            if let match = controller.match {
                if match.isFinished {
                    FullTimeView()
                } else {
                    MatchPagesView(period: match.clock.period)
                }
            } else {
                PreMatchView()
            }
        }
    }
}

/// Horizontal pages for a running match. The first page depends on the period.
/// Horizontal paging leaves the Digital Crown to the clock page.
struct MatchPagesView: View {
    let period: Period
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            if period.isPlaying {
                ClockPage().tag(0)
                LogEventPage().tag(1)
                EventListPage().tag(2)
                PeriodPage().tag(3)
            } else if period == .penalties {
                PenaltiesPage().tag(0)
                PeriodPage().tag(1)
                EventListPage().tag(2)
            } else {
                BreakPage().tag(0)
                EventListPage().tag(1)
            }
        }
        .tabViewStyle(.page)
        .onChange(of: period) { selection = 0 }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Full time summary.
struct FullTimeView: View {
    @Environment(MatchController.self) private var controller

    var body: some View {
        if let match = controller.match {
            let score = match.score
            ScrollView {
                VStack(spacing: 6) {
                    Text("Full time").font(.headline)
                    HStack {
                        Text(match.config.homeName).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        Text("\(score.home)–\(score.away)").font(.title2.bold().monospacedDigit())
                        Spacer()
                        Text(match.config.awayName).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    if let pens = match.penaltyScore {
                        Text("Penalties \(pens.home)–\(pens.away)").font(.footnote)
                        if let winner = match.shootout.winner {
                            Text("\(match.config.name(of: winner)) win").foregroundStyle(.green)
                        }
                    }
                    summaryRow("Events", "\(match.liveEvents.count)")
                    if let workout = match.workout {
                        summaryRow("Distance", Format.distance(workout.distanceMeters))
                        summaryRow("Avg HR", Format.heartRate(workout.averageHeartRate))
                        summaryRow("Duration", Format.duration(workout.durationSeconds))
                        summaryRow("Health", workout.savedToHealth ? (workout.hasRoute ? "Saved with route" : "Saved") : "Not saved")
                    } else if controller.workout.isRunning {
                        Text("Saving workout…").font(.footnote).foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        EventListPage()
                    } label: {
                        Label("Events", systemImage: "list.bullet")
                    }
                    Button {
                        controller.newMatch()
                    } label: {
                        Text("New match").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.footnote)
    }
}
