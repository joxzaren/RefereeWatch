import Foundation
import os
import RefereeKit
import WatchConnectivity

/// WatchConnectivity on the watch. Delegate callbacks arrive on a background queue, so they
/// decode the dictionary into a `Sendable` `WireMessage` there and hop to the main actor.
///
/// Which matches still need sending is owned by `MatchController`, which persists the ids
/// and resends them when the session activates.
@MainActor
final class ConnectivityService: NSObject {
    /// Receives decoded messages on the main actor.
    var onMessage: (WireMessage) -> Void = { _ in }
    /// Called on the main actor once the session is active, so pending matches can be resent.
    var onActivated: () -> Void = {}
    /// Called on the main actor when a match transfer has been delivered to the iPhone.
    var onMatchDelivered: (UUID) -> Void = { _ in }

    private(set) var activated = false
    nonisolated private static let log = Logger(subsystem: "com.refereewatch.app.watchkitapp", category: "connectivity")

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Queues the match for the iPhone with `transferUserInfo`, which retries across disconnects.
    /// Before activation this does nothing; the controller resends pending matches on activation.
    func send(_ match: Match) {
        guard WCSession.isSupported(), activated else { return }
        guard let dictionary = try? WireMessage.match(match).dictionary() else {
            Self.log.error("Could not encode match \(match.id.uuidString, privacy: .public)")
            return
        }
        WCSession.default.transferUserInfo(dictionary)
    }

    /// Match ids whose transfers the system still has queued, so a resend does not duplicate them.
    func queuedMatchIDs() -> Set<UUID> {
        guard WCSession.isSupported(), activated else { return [] }
        var ids: Set<UUID> = []
        for transfer in WCSession.default.outstandingUserInfoTransfers where transfer.isTransferring {
            if case .match(let match) = WireMessage(dictionary: transfer.userInfo) { ids.insert(match.id) }
        }
        return ids
    }

    fileprivate func didActivate(context: WireMessage?) {
        activated = true
        if let context { onMessage(context) }
        onActivated()
    }

    fileprivate func received(_ message: WireMessage) {
        onMessage(message)
    }
}

extension ConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        // A setup sent while the watch app was not running waits in the application context.
        let context = WireMessage(dictionary: session.receivedApplicationContext)
        Task { @MainActor in self.didActivate(context: context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let message = WireMessage(dictionary: applicationContext) else { return }
        Task { @MainActor in self.received(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let message = WireMessage(dictionary: userInfo) else { return }
        Task { @MainActor in self.received(message) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: (any Error)?) {
        guard case .match(let match) = WireMessage(dictionary: userInfoTransfer.userInfo) else { return }
        let id = match.id
        if let error {
            // The id stays pending and is resent on the next activation.
            Self.log.error("Match transfer \(id.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        Task { @MainActor in self.onMatchDelivered(id) }
    }
}
