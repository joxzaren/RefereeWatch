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

/// Lets the Action button start or open a match. After it runs, further presses during the
/// session are delivered to `ToggleStoppageIntent`.
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
        MatchController.shared.startOrOpenFromIntent()
        return .result(actionButtonIntent: ToggleStoppageIntent())
    }
}

/// Starts or ends a stoppage in the running match.
struct ToggleStoppageIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle stoppage"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        if MatchController.shared.toggleStoppage() {
            WKInterfaceDevice.current().play(.click)
        }
        return .result()
    }
}
