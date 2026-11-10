import RefereeKit
import SwiftUI
import WatchKit

/// The main clock for every playing period, including extra time.
/// Values are recomputed from the anchors on each timeline tick; nothing counts ticks.
struct ClockPage: View {
    @Environment(MatchController.self) private var controller
    @State private var crownValue = 0.0
    @State private var crown = CrownAccumulator()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if let match = controller.match {
                content(match, now: controller.now())
            }
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue, from: -100_000, through: 100_000,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: false,
            onChange: { event in crownChanged(event.offset) },
            onIdle: { crown.idle() })
    }

    @ViewBuilder
    private func content(_ match: Match, now: RefereeKit.Anchor) -> some View {
        let clock = match.clock
        let display = clock.display(at: now, config: match.config)
        let panel = AddedTimePanel.make(clock: clock, config: match.config, now: now)
        VStack(spacing: 3) {
            HStack {
                Text(clock.period.title).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                ScoreLine(match: match)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(display.main)
                    .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                if let overrun = display.overrun {
                    Text(overrun)
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityElement(children: .combine)

            if let panel {
                AddedTimePanelView(panel: panel)
            }
            StoppageButton(match: match, now: now)
            WarningBanners(compact: true)
        }
    }

    private func crownChanged(_ offset: Double) {
        guard let match = controller.match, match.clock.period.isPlaying else { return }
        let now = controller.now()
        if AddedTimePanel.make(clock: match.clock, config: match.config, now: now) != nil {
            let steps = crown.minuteSteps(offset: offset)
            if steps != 0, controller.adjustAddedTime(by: steps) {
                WKInterfaceDevice.current().play(.click)
            }
        } else if crown.toggle(offset: offset) {
            if controller.toggleStoppage() {
                WKInterfaceDevice.current().play(.click)
            }
        }
    }
}

private struct AddedTimePanelView: View {
    let panel: AddedTimePanel

    var body: some View {
        HStack(spacing: 6) {
            Text(panel.headline)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(panel.pastNormalEnd ? .orange : .primary)
            Text(panel.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            Image(systemName: panel.pastNormalEnd ? "plus" : "digitalcrown.arrow.clockwise")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.18)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Added time \(panel.announced) minutes. \(panel.detail)")
    }
}

private struct StoppageButton: View {
    @Environment(MatchController.self) private var controller
    let match: Match
    let now: RefereeKit.Anchor

    var body: some View {
        let open = match.clock.isStoppageOpen
        Button {
            if controller.toggleStoppage() {
                WKInterfaceDevice.current().play(.click)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: open ? "pause.circle.fill" : "pause.circle")
                if open {
                    Text("Stoppage \(ClockDisplay.clockString(runningStoppage))")
                        .monospacedDigit()
                } else {
                    Text("Stoppage")
                }
            }
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(open ? .red : .gray)
        .accessibilityLabel(open ? "End stoppage" : "Start stoppage")
    }

    private var runningStoppage: TimeInterval {
        guard let last = match.clock.stoppages(in: match.clock.period).last, last.isOpen else { return 0 }
        return now.seconds(since: last.start)
    }
}
