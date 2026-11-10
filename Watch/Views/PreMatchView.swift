import CoreLocation
import HealthKit
import RefereeKit
import SwiftUI

/// Before kick off: the iPhone setup if there is one, otherwise a preset picker.
struct PreMatchView: View {
    @Environment(MatchController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        List {
            if let setup = controller.usableSetup {
                Section("From iPhone") {
                    SetupSummary(config: setup.config)
                    kickOffButton(useSetup: true)
                }
                Section {
                    NavigationLink("Use a preset instead") {
                        List {
                            presetPicker
                            kickOffButton(useSetup: false)
                        }
                        .navigationTitle("Preset")
                    }
                }
            } else {
                Section("Preset") {
                    presetPicker
                    SetupSummary(config: controller.selectedPreset.config)
                    kickOffButton(useSetup: false)
                }
            }
            Section {
                NavigationLink {
                    PermissionsView()
                } label: {
                    Label("Permissions", systemImage: "checkmark.shield")
                }
                if controller.notifications.backupAlertsOff {
                    Label("Backup alerts are off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("RefereeWatch")
    }

    private var presetPicker: some View {
        @Bindable var controller = controller
        return Picker("Preset", selection: $controller.selectedPresetID) {
            ForEach(MatchPreset.builtIn) { preset in
                Text(preset.name).tag(preset.id)
            }
        }
    }

    private func kickOffButton(useSetup: Bool) -> some View {
        Button {
            controller.startMatch(useSetup: useSetup)
        } label: {
            Label("Kick off", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .listItemTint(.green)
    }
}

private struct SetupSummary: View {
    let config: MatchConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(config.homeName) v \(config.awayName)").font(.headline).lineLimit(2)
            if !config.competition.isEmpty {
                Text(config.competition).font(.footnote).foregroundStyle(.secondary)
            }
            Text("2 x \(Int(config.halfLength / 60)) min, break \(Int(config.halfTimeLength / 60))")
                .font(.footnote)
            if config.extraTimeEnabled {
                Text("Extra time 2 x \(Int(config.extraTimeHalfLength / 60))").font(.footnote)
            }
            if config.penaltiesEnabled {
                Text("Penalties").font(.footnote)
            }
        }
    }
}

/// Status of each permission, each requested on its own.
struct PermissionsView: View {
    @Environment(MatchController.self) private var controller

    var body: some View {
        let workout = controller.workout
        let notifications = controller.notifications
        List {
            Section {
                row("Health", status: healthText(workout.workoutSharing), ok: workout.workoutSharing == .sharingAuthorized)
                if workout.workoutSharing == .notDetermined && workout.healthAvailable {
                    Button("Allow Health") { Task { await workout.requestHealthAuthorization() } }
                }
            } footer: {
                Text("Saves the match as a Soccer workout.")
            }
            Section {
                row("Location", status: locationText(workout.locationStatus), ok: workout.locationAuthorized)
                if workout.locationStatus == .notDetermined {
                    Button("Allow Location") { workout.requestLocationAuthorization() }
                }
            } footer: {
                Text("Records the route. The clock works without it.")
            }
            Section {
                row("Notifications", status: notifications.authorizationDescription, ok: !notifications.backupAlertsOff)
                if notifications.status == .notAsked {
                    Button("Allow Notifications") { Task { await notifications.request() } }
                }
                if notifications.status == .off {
                    Label("Backup alerts are off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.headline)
                    Text("Turn on alerts and sound for RefereeWatch in the Watch app on iPhone.")
                        .font(.footnote)
                }
            } footer: {
                Text("Backup alerts buzz if the app is suspended.")
            }
        }
        .navigationTitle("Permissions")
        .task {
            workout.refreshHealthStatus()
            await notifications.refresh()
        }
    }

    private func row(_ title: String, status: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? .green : .yellow)
            Text(title)
            Spacer()
            Text(status).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func healthText(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .sharingAuthorized: "On"
        case .sharingDenied: "Denied"
        default: "Not asked"
        }
    }

    private func locationText(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: "On"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not asked"
        }
    }
}
