import RefereeKit
import SwiftUI

/// The period transition, separate from the clock so it is never hit by accident.
struct PeriodPage: View {
    @Environment(MatchController.self) private var controller

    var body: some View {
        if let match = controller.match, let title = TransitionLogic.title(from: match.clock.period, config: match.config) {
            VStack(spacing: 8) {
                Text(match.clock.period.title).font(.headline)
                HoldToConfirmButton(
                    title: title,
                    subtitle: TransitionLogic.subtitle(from: match.clock.period, config: match.config),
                    tint: .orange
                ) {
                    controller.advance()
                }
                Text("Hold about 1 s").font(.caption2).foregroundStyle(.secondary)
                WarningBanners()
            }
        }
    }
}

/// Half time and the extra time breaks: a countdown from `breakRemaining` and the next period.
struct BreakPage: View {
    @Environment(MatchController.self) private var controller

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if let match = controller.match {
                let now = controller.now()
                let clock = match.clock
                let remaining = clock.breakRemaining(at: now, config: match.config) ?? 0
                let display = clock.display(at: now, config: match.config)
                VStack(spacing: 4) {
                    HStack {
                        Text(clock.period.title).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        ScoreLine(match: match)
                    }
                    Text(ClockDisplay.clockString(remaining))
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(remaining > 0 ? Color.primary : Color.orange)
                    if let overrun = display.overrun {
                        Text("Over by \(overrun)").font(.footnote).foregroundStyle(.orange)
                    }
                    if let title = TransitionLogic.title(from: clock.period, config: match.config) {
                        HoldToConfirmButton(
                            title: title,
                            subtitle: "Hold to confirm",
                            tint: .green
                        ) {
                            controller.advance()
                        }
                    }
                    WarningBanners(compact: true)
                }
            }
        }
    }
}
