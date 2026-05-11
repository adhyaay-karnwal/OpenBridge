import CoreLocation
import Foundation
import OSLog

private let logger = Logger(subsystem: Logger.loggingSubsystem, category: "LocationService")

/// One-shot location provider backed by CoreLocation.
///
/// Mirrors the browser `navigator.geolocation.getCurrentPosition` flow used by
/// the web app: the caller awaits a single fix, authorization is prompted on
/// first use, and transient failures (timeout, no fix) are surfaced as errors.
@MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    struct LocationFix: Sendable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
    }

    enum LocationError: Error, LocalizedError {
        case denied
        case restricted
        case servicesDisabled
        case timeout
        case underlying(String)

        /// Localized description for user-facing surfaces.
        var errorDescription: String? {
            switch self {
            case .denied:
                String(localized: "Location permission denied")
            case .restricted:
                String(localized: "Location services are restricted")
            case .servicesDisabled:
                String(localized: "Location services are disabled")
            case .timeout:
                String(localized: "Location request timed out")
            case let .underlying(message):
                message
            }
        }

        /// Stable English description embedded into `<user-reminder>` blocks
        /// sent to the agent. Kept non-localized so the agent sees a
        /// deterministic contract regardless of the user's locale, matching
        /// the web app which forwards the (English) browser error message.
        var agentDescription: String {
            switch self {
            case .denied:
                "User denied Geolocation"
            case .restricted:
                "Location services are restricted"
            case .servicesDisabled:
                "Location services are disabled"
            case .timeout:
                "Location request timed out"
            case let .underlying(message):
                message
            }
        }
    }

    private let manager: CLLocationManager
    private var fixContinuations: [CheckedContinuation<LocationFix, Error>] = []
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Error>] = []
    private var fixTimeoutTask: Task<Void, Never>?
    private var authorizationTimeoutTask: Task<Void, Never>?

    override private init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Request a single geographic fix. Prompts the user for permission the
    /// first time it is called and completes as soon as CoreLocation delivers
    /// a location update, the timeout elapses, or permission is refused.
    ///
    /// The same `timeout` covers both the permission prompt (if the user has
    /// not yet decided) and the subsequent fix, so a user who ignores the
    /// macOS dialog can't hang the request indefinitely.
    func requestLocation(timeout: TimeInterval = 10) async throws -> LocationFix {
        let initialStatus = manager.authorizationStatus
        let resolvedStatus: CLAuthorizationStatus
        switch initialStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            resolvedStatus = try await awaitAuthorizationChange(timeout: timeout)
        default:
            resolvedStatus = initialStatus
        }

        switch resolvedStatus {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied:
            throw LocationError.denied
        case .restricted:
            throw LocationError.restricted
        case .notDetermined:
            throw LocationError.servicesDisabled
        @unknown default:
            throw LocationError.servicesDisabled
        }

        return try await withCheckedThrowingContinuation { continuation in
            fixContinuations.append(continuation)
            manager.requestLocation()
            scheduleFixTimeout(timeout: timeout)
        }
    }

    private func awaitAuthorizationChange(timeout: TimeInterval) async throws -> CLAuthorizationStatus {
        scheduleAuthorizationTimeout(timeout: timeout)
        return try await withCheckedThrowingContinuation { continuation in
            authorizationContinuations.append(continuation)
        }
    }

    private func scheduleFixTimeout(timeout: TimeInterval) {
        fixTimeoutTask?.cancel()
        fixTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.failPendingFixes(with: .timeout)
        }
    }

    private func scheduleAuthorizationTimeout(timeout: TimeInterval) {
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.failPendingAuthorizations(with: .timeout)
        }
    }

    private func deliverFix(_ fix: LocationFix) {
        let continuations = fixContinuations
        fixContinuations = []
        for continuation in continuations {
            continuation.resume(returning: fix)
        }
        fixTimeoutTask?.cancel()
        fixTimeoutTask = nil
    }

    private func failPendingFixes(with error: LocationError) {
        let continuations = fixContinuations
        fixContinuations = []
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
        fixTimeoutTask?.cancel()
        fixTimeoutTask = nil
    }

    private func deliverAuthorization(_ status: CLAuthorizationStatus) {
        // `locationManagerDidChangeAuthorization` can fire immediately with the
        // current status. Only resume the request-time continuations once the
        // status has actually moved away from `.notDetermined`.
        guard status != .notDetermined else { return }
        let continuations = authorizationContinuations
        authorizationContinuations = []
        for continuation in continuations {
            continuation.resume(returning: status)
        }
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = nil
    }

    private func failPendingAuthorizations(with error: LocationError) {
        let continuations = authorizationContinuations
        authorizationContinuations = []
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = nil
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )
        Task { @MainActor [weak self] in
            self?.deliverFix(fix)
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        let description = error.localizedDescription
        Task { @MainActor [weak self] in
            logger.info("CLLocationManager failed: \(description, privacy: .public)")
            self?.failPendingFixes(with: .underlying(description))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.deliverAuthorization(status)
        }
    }
}
