import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authorizationContinuation: CheckedContinuation<Bool, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        await ensureAuthorization()
    }

    func currentCoordinate() async -> CLLocationCoordinate2D? {
        guard await ensureAuthorization() else { return nil }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }?.coordinate
    }

    private func ensureAuthorization() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .restricted, .denied:
            return false
        case .notDetermined:
            // Resume any prior waiter so we never leak a continuation.
            if let stale = authorizationContinuation {
                authorizationContinuation = nil
                stale.resume(returning: false)
            }
            return await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
                // Safety: if the system never delivers a terminal status, don’t hang forever.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard let pending = self.authorizationContinuation else { return }
                    self.authorizationContinuation = nil
                    let ok = self.manager.authorizationStatus == .authorizedAlways
                        || self.manager.authorizationStatus == .authorizedWhenInUse
                    pending.resume(returning: ok)
                }
            }
        @unknown default:
            return false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            // Still prompting — wait for a terminal callback (don’t clear the continuation).
            if status == .notDetermined { return }
            guard let continuation = authorizationContinuation else { return }
            authorizationContinuation = nil
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                continuation.resume(returning: true)
            case .denied, .restricted:
                continuation.resume(returning: false)
            default:
                continuation.resume(returning: false)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locationContinuation?.resume(returning: locations.first)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}