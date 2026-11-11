import RefereeKit
import SwiftUI

@main
struct RefereeWatchWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let controller = MatchController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(controller)
        }
        .onChange(of: scenePhase) { _, phase in
            // Replan every alert and record the announced added time when coming back.
            if phase == .active { controller.refresh() }
        }
    }
}
