import Foundation
import Observation
import UserNotifications

/// Reads and requests notification permission, which the backup alerts depend on.
@MainActor
@Observable
final class NotificationPermissions {
    private(set) var status: BackupAlertStatus = .notAsked
    private(set) var authorizationDescription = "Not asked"

    var backupAlertsOff: Bool { status != .on }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized: Bool?
        switch settings.authorizationStatus {
        case .notDetermined: authorized = nil
        case .denied: authorized = false
        default: authorized = true
        }
        status = NotificationLogic.status(
            authorized: authorized,
            alertEnabled: settings.alertSetting == .enabled,
            soundEnabled: settings.soundSetting == .enabled)
        authorizationDescription = switch status {
        case .on: "On"
        case .notAsked: "Not asked"
        case .off: authorized == false ? "Denied" : "Alerts or sound off"
        }
    }

    func request() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }
}
