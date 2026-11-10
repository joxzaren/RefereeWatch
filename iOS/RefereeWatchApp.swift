import SwiftUI
import RefereeKit

@main
struct RefereeWatchApp: App {
    @State private var model: AppModel
    @State private var connectivity: ConnectivityService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let directory = (try? MatchStore.defaultDirectory())
            ?? FileManager.default.temporaryDirectory.appending(path: "Matches", directoryHint: .isDirectory)
        let model = AppModel(store: MatchStore(directory: directory))
        let connectivity = ConnectivityService()
        connectivity.onMatch = { [weak model] match in model?.receive(match) }
        model.connect(connectivity)
        connectivity.activate()
        _model = State(initialValue: model)
        _connectivity = State(initialValue: connectivity)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
    }
}
