import Foundation
import RefereeKit
import UserNotifications
import WatchKit

/// Turns the alert plan into in-app haptics and backup notifications.
///
/// Every reschedule cancels everything and replans from the match's anchors, so it never
/// depends on view redraws. Called on every controller mutation, on launch, when the scene
/// becomes active and when the normal end alert fires.
@MainActor
final class AlertService {
    /// Called on the main actor after a delivery's haptic has started.
    var onFire: (AlertDelivery) -> Void = { _ in }

    private var tasks: [Task<Void, Never>] = []
    private var generation = 0
    private let center = UNUserNotificationCenter.current()
    private let presenter = ForegroundPresenter()

    init() {
        center.delegate = presenter
    }

    /// The deliveries currently scheduled, for display and debugging.
    private(set) var scheduled: [AlertDelivery] = []

    func reschedule(match: Match?, now: Anchor) {
        cancelAll()
        let deliveries = AlertSchedule.deliveries(for: AlertSchedule.plan(for: match, now: now))
        scheduled = deliveries
        let start = ContinuousClock.now
        let generation = generation
        for delivery in deliveries {
            scheduleBackup(delivery)
            let deadline = start.advanced(by: .milliseconds(Int64((delivery.secondsFromNow * 1000).rounded())))
            tasks.append(Task { [weak self] in
                do {
                    try await Task.sleep(until: deadline, tolerance: .zero, clock: .continuous)
                } catch {
                    return
                }
                var playHaptic = true
                if AlertSchedule.isLate(ContinuousClock.now - deadline) {
                    // Woken late, for example after suspension: the backup may already have buzzed.
                    let delivered = await Self.deliveredIDs()
                    playHaptic = AlertSchedule.shouldPlayLateHaptic(delivery, deliveredIDs: delivered)
                }
                self?.fire(delivery, generation: generation, playHaptic: playHaptic)
            })
        }
    }

    func cancelAll() {
        generation += 1
        for task in tasks { task.cancel() }
        tasks.removeAll()
        scheduled = []
        center.removeAllPendingNotificationRequests()
    }

    private func fire(_ delivery: AlertDelivery, generation: Int, playHaptic: Bool) {
        guard generation == self.generation, !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: delivery.ids)
        center.removeDeliveredNotifications(withIdentifiers: delivery.ids)
        if playHaptic {
            // The burst runs in its own task: `onFire` may reschedule, which cancels the
            // alert task, and the burst must keep its spacing regardless.
            let pattern = delivery.haptic
            Task { await Self.play(pattern) }
        }
        onFire(delivery)
    }

    /// Ids of the notifications already shown, read without passing non-Sendable values across.
    private static func deliveredIDs() async -> Set<String> {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(returning: Set(notifications.map(\.request.identifier)))
            }
        }
    }

    private static func play(_ pattern: HapticPattern) async {
        let device = WKInterfaceDevice.current()
        let type: WKHapticType = pattern.style == .notification ? .notification : .directionUp
        for index in 0..<pattern.repeats {
            if index > 0 {
                try? await Task.sleep(for: .milliseconds(Int64(pattern.interval * 1000)), tolerance: .zero)
            }
            device.play(type)
        }
    }

    private func scheduleBackup(_ delivery: AlertDelivery) {
        let content = UNMutableNotificationContent()
        content.title = delivery.title
        content.body = delivery.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        // A little after the in-app deadline, so the in-app alert removes it before it shows.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: AlertSchedule.backupInterval(secondsFromNow: delivery.secondsFromNow), repeats: false)
        let request = UNNotificationRequest(identifier: delivery.primaryID, content: content, trigger: trigger)
        center.add(request) { _ in }
    }
}

/// While the app is in the foreground the in-app haptic is the alert, so backups are not shown.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
