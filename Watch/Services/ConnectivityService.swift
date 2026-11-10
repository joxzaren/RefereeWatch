import Foundation
import RefereeKit
import WatchConnectivity

/// WatchConnectivity on the watch. Delegate callbacks arrive on a background queue, so they
/// decode the dictionary into a `Sendable` `WireMessage` there and hop to the main actor.
@MainActor
final class ConnectivityService: NSObject {
    /// Receives decoded messages on the main actor.
    var onMessage: (WireMessage) -> Void = { _ in }

    private var pending: [Match] = []
    private var activated = false

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Queues the match for the iPhone with `transferUserInfo`, which retries across disconnects.
    func send(_ match: Match) {
        guard WCSession.isSupported() else { return }
        guard activated else {
            pending.removeAll { $0.id == match.id }
            pending.append(match)
            return
        }
        guard let dictionary = try? WireMessage.match(match).dictionary() else { return }
        WCSession.default.transferUserInfo(dictionary)
    }

    fileprivate func didActivate(context: WireMessage?) {
        activated = true
        if let context { onMessage(context) }
        let queued = pending
        pending.removeAll()
        for match in queued { send(match) }
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
}
