import Foundation
import os
import RefereeKit
import WatchConnectivity

/// The iPhone side of WatchConnectivity.
///
/// - Setups go out with `updateApplicationContext` (latest only) and `transferUserInfo` (queued).
/// - Matches go out with `transferUserInfo`.
/// - Received matches are handed to `onMatch` on the main actor. Setups are ignored on the phone.
///
/// Delegate callbacks arrive on a background queue. They decode the dictionary there into a
/// `Sendable` `WireMessage` and then hop to the main actor, so no non-Sendable value crosses.
@MainActor
final class ConnectivityService: NSObject, WCSessionDelegate, WatchLink {
    var onMatch: ((Match) -> Void)?

    private let session: WCSession?
    /// Messages sent before activation completed, sent once it has.
    private var pending: [WireMessage] = []
    nonisolated private static let log = Logger(subsystem: "com.refereewatch.app", category: "connectivity")

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: Sending

    func sendSetup(_ setup: SetupMessage) {
        send(.setup(setup))
    }

    func sendMatch(_ match: Match) {
        send(.match(match))
    }

    private func send(_ message: WireMessage) {
        guard let session else { return }
        guard session.activationState == .activated else {
            pending.append(message)
            if session.activationState == .notActivated { activate() }
            return
        }
        let dictionary: [String: Any]
        do {
            dictionary = try message.dictionary()
        } catch {
            Self.log.error("Could not encode a \(message.kind, privacy: .public) message: \(error.localizedDescription, privacy: .public)")
            return
        }
        if case .setup = message {
            do {
                try session.updateApplicationContext(dictionary)
            } catch {
                // transferUserInfo below still queues the setup.
                Self.log.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        session.transferUserInfo(dictionary)
    }

    private func flushPending() {
        guard let session, session.activationState == .activated else { return }
        let messages = pending
        pending.removeAll()
        messages.forEach(send)
    }

    private func handle(_ message: WireMessage?) {
        switch message {
        case .match(let match):
            onMatch?(match)
        case .setup, nil:
            // The phone only sends setups. Unknown or malformed messages are dropped.
            break
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?
    ) {
        if let error {
            Self.log.error("Activation failed: \(error.localizedDescription, privacy: .public)")
        }
        Task { @MainActor in self.flushPending() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let message = WireMessage(dictionary: userInfo)
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let message = WireMessage(dictionary: applicationContext)
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        // Happens when the user switches watches. Incoming data is still delivered until
        // the session deactivates; nothing new should be sent until then.
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so the session connects to the newly paired watch.
        session.activate()
    }
}
