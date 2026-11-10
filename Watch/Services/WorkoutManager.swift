import CoreLocation
import Foundation
import HealthKit
import Observation
import RefereeKit

/// Runs the Soccer workout from kick off to the final whistle. The match never depends on it:
/// with HealthKit denied no workout is saved and everything else keeps working.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    /// False when the session failed to start or ended early. The screen may then sleep.
    private(set) var sessionHealthy = true
    private(set) var locationStatus: CLAuthorizationStatus

    @ObservationIgnored let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var routeBuilder: HKWorkoutRouteBuilder?
    @ObservationIgnored private let locationManager = CLLocationManager()
    /// True while we are ending the session ourselves, so the end is not seen as early.
    @ObservationIgnored private var ending = false
    @ObservationIgnored private var startDate: Date?

    override init() {
        locationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        refreshHealthStatus()
    }

    var isRunning: Bool { session != nil }

    // MARK: Authorization

    static let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning),
    ]

    var healthAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Stored so the permissions screen observes changes.
    private(set) var workoutSharing: HKAuthorizationStatus = .notDetermined
    private(set) var routeSharing: HKAuthorizationStatus = .notDetermined

    func refreshHealthStatus() {
        guard healthAvailable else { return }
        workoutSharing = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        routeSharing = healthStore.authorizationStatus(for: HKSeriesType.workoutRoute())
    }

    var locationAuthorized: Bool {
        locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
    }

    func requestHealthAuthorization() async {
        guard healthAvailable else { return }
        try? await healthStore.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        refreshHealthStatus()
    }

    func requestLocationAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: Session

    /// Starts the workout at kick off. Marks the session unhealthy when it cannot start.
    func start(at date: Date) async {
        guard session == nil else { return }
        refreshHealthStatus()
        guard healthAvailable, workoutSharing == .sharingAuthorized else {
            sessionHealthy = false
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .soccer
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            self.session = session
            self.builder = builder
            startDate = date
            session.startActivity(with: date)
            try await builder.beginCollection(at: date)
            sessionHealthy = true
            startRoute()
        } catch {
            ending = true
            session?.end()
            session = nil
            builder = nil
            ending = false
            sessionHealthy = false
        }
    }

    /// After a relaunch mid match: picks up a session that is still running, or starts a new one.
    func recoverOrStart(at date: Date) async {
        guard session == nil else { return }
        if healthAvailable, let recovered = try? await healthStore.recoverActiveWorkoutSession() {
            recovered.delegate = self
            session = recovered
            builder = recovered.associatedWorkoutBuilder()
            startDate = recovered.startDate ?? date
            sessionHealthy = recovered.state == .running
            startRoute()
            return
        }
        await start(at: date)
    }

    /// Ends the workout at the final whistle and returns what it recorded.
    func end(at date: Date, fallbackDuration: TimeInterval?) async -> WorkoutSummary {
        locationManager.stopUpdatingLocation()
        guard let session, let builder else {
            return WorkoutSummary(durationSeconds: fallbackDuration, savedToHealth: false, hasRoute: false)
        }
        ending = true
        session.end()
        var summary = WorkoutSummary(durationSeconds: fallbackDuration)
        do {
            try await builder.endCollection(at: date)
            summary.distanceMeters = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter())
            summary.averageHeartRate = builder.statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            summary.durationSeconds = builder.elapsedTime
            if let workout = try await builder.finishWorkout() {
                summary.savedToHealth = true
                if let routeBuilder, Self.saveRoute(locationAuthorized: locationAuthorized, routeSharing: routeSharing) {
                    if (try? await routeBuilder.finishRoute(with: workout, metadata: nil)) != nil {
                        summary.hasRoute = true
                    }
                }
            }
        } catch {
            summary.savedToHealth = false
        }
        self.session = nil
        self.builder = nil
        routeBuilder = nil
        ending = false
        sessionHealthy = true
        return summary
    }

    /// The route is saved only when location and route sharing are both authorized.
    nonisolated static func saveRoute(locationAuthorized: Bool, routeSharing: HKAuthorizationStatus) -> Bool {
        locationAuthorized && routeSharing == .sharingAuthorized
    }

    private func startRoute() {
        guard Self.saveRoute(locationAuthorized: locationAuthorized, routeSharing: routeSharing) else { return }
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        locationManager.startUpdatingLocation()
    }

    // MARK: Delegate hops

    fileprivate func sessionChanged(to state: HKWorkoutSessionState) {
        guard !ending else { return }
        if state == .ended || state == .stopped {
            sessionHealthy = false
        }
    }

    fileprivate func sessionFailed() {
        guard !ending else { return }
        sessionHealthy = false
    }

    fileprivate func received(_ locations: [CLLocation]) {
        guard let routeBuilder else { return }
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard !good.isEmpty else { return }
        Task { try? await routeBuilder.insertRouteData(good) }
    }

    fileprivate func authorizationChanged(_ status: CLAuthorizationStatus) {
        locationStatus = status
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in self.sessionChanged(to: toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in self.sessionFailed() }
    }
}

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.received(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationChanged(status) }
    }
}
