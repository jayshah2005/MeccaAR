import CoreLocation
import Observation

/// Observable wrapper around `CLLocationManager` that publishes the device's
/// current location, heading, and authorization so SwiftUI features can react
/// to movement (proximity, floor, and AR bearing).
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var currentLocation: CLLocation?
    private(set) var heading: CLHeading?
    private(set) var authorizationStatus: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    /// When non-nil, incoming fixes are collected here for `captureBestLocation`.
    @ObservationIgnored private var captureBuffer: [CLLocation]?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Best current horizontal accuracy in metres, or nil if unknown.
    var horizontalAccuracy: Double? {
        guard let accuracy = currentLocation?.horizontalAccuracy, accuracy >= 0 else {
            return nil
        }
        return accuracy
    }

    /// Samples location for `seconds`, then returns a fix built from the most
    /// accurate readings (averaged) to smooth out GPS noise. Ask the user to
    /// hold the phone still at the spot while this runs.
    func captureBestLocation(seconds: Double = 4) async -> CLLocation? {
        captureBuffer = []
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let samples = (captureBuffer ?? []).filter { $0.horizontalAccuracy >= 0 }
        captureBuffer = nil

        guard let best = samples.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else {
            return currentLocation
        }

        // Average only the fixes whose accuracy is close to the best one.
        let threshold = best.horizontalAccuracy * 1.5 + 3
        let good = samples.filter { $0.horizontalAccuracy <= threshold }
        guard good.count > 1 else { return best }

        let count = Double(good.count)
        let latitude = good.map(\.coordinate.latitude).reduce(0, +) / count
        let longitude = good.map(\.coordinate.longitude).reduce(0, +) / count
        let altitude = good.map(\.altitude).reduce(0, +) / count
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: best.horizontalAccuracy,
            verticalAccuracy: best.verticalAccuracy,
            timestamp: Date()
        )
    }

    func start() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        if let latest = locations.last {
            currentLocation = latest
            if captureBuffer != nil {
                captureBuffer?.append(contentsOf: locations)
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        heading = newHeading
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Transient CoreLocation errors are expected indoors; ignore and wait
        // for the next fix rather than surfacing noise to the UI.
    }
}
