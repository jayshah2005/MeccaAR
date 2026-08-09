import ARKit
import CoreLocation
import Foundation

/// Picks the best placement/hunt strategy for the current surroundings.
///
/// - Outdoors + Apple geo imagery available → `ARGeoTracking` (fast, no orbit).
/// - Otherwise → world-map + LiDAR mesh when the device supports it.
@MainActor
enum PlacementEnvironment {
    case outdoorGeo
    case indoorOrWorldMap(hasLiDAR: Bool)

    var placementMode: MeccaPlacementMode {
        switch self {
        case .outdoorGeo: return .geo
        case .indoorOrWorldMap: return .worldMap
        }
    }

    var usesLiDAR: Bool {
        if case .indoorOrWorldMap(let hasLiDAR) = self { return hasLiDAR }
        return false
    }

    /// Soft outdoor heuristic: a usable GPS fix that isn't obviously room-bound.
    static func looksOutdoors(_ location: CLLocation?) -> Bool {
        guard let location, location.horizontalAccuracy >= 0 else { return false }
        return location.horizontalAccuracy <= 35
    }

    static var deviceHasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// Resolves the best environment for the current GPS fix. Geo availability is
    /// async because ARKit may need to hit Apple's servers.
    static func resolve(location: CLLocation?) async -> PlacementEnvironment {
        let hasLiDAR = deviceHasLiDAR
        guard
            ARGeoTrackingConfiguration.isSupported,
            looksOutdoors(location),
            let coordinate = location?.coordinate
        else {
            return .indoorOrWorldMap(hasLiDAR: hasLiDAR)
        }

        let geoAvailable = await checkGeoAvailability(at: coordinate)
        return geoAvailable
            ? .outdoorGeo
            : .indoorOrWorldMap(hasLiDAR: hasLiDAR)
    }

    private static func checkGeoAvailability(
        at coordinate: CLLocationCoordinate2D
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            ARGeoTrackingConfiguration.checkAvailability(at: coordinate) { available, _ in
                continuation.resume(returning: available)
            }
        }
    }
}
