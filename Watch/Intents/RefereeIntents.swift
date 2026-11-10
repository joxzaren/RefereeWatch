import AppIntents
import Foundation
import WatchKit

/// The only workout style the app offers.
enum RefereeWorkoutStyle: String, AppEnum {
    case match

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Referee workout" }
    static var caseDisplayRepresentations: [RefereeWorkoutStyle: DisplayRepresentation] {
        [.match: "Referee match"]
    }
}

/// Lets the Action button open the app. It never starts a match by itself: the app shows the
/// running match, or the pre-match screen with its permission warnings, and the referee kicks
/// off there. Further presses are delivered to `ToggleStoppageIntent`.
struct StartRefereeMatchIntent: StartWorkoutIntent {
    static let title: LocalizedStringResource = "Start match"

    @Parameter(title: "Workout")
    var workoutStyle: RefereeWorkoutStyle

    init() {
        workoutStyle = .match
    }

    static var suggestedWorkouts: [StartRefereeMatchIntent] {
        [StartRefereeMatchIntent()]
    }

    var displayRepresentation: DisplayRepresentation {
        "Referee match"
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        MatchController.shared.openFromActionButton()
        return .result(actionButtonIntent: ToggleStoppageIntent())
    }
}

/// Starts or ends a stoppage in the running match. Does nothing outside a playing period,
/// including after full time, so a press can never change the full time screen or start a match.
struct ToggleStoppageIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle stoppage"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let controller = MatchController.shared
        guard controller.isInPlayingPeriod else { return .result() }
        if controller.toggleStoppage() {
            WKInterfaceDevice.current().play(.click)
        }
        return .result()
    }
}
