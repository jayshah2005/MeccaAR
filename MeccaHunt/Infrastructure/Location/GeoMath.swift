import CoreLocation
import Foundation

/// Great-circle helpers for distance and bearing between coordinates, plus
/// vertical (floor) reasoning based on GPS altitude.
enum GeoMath {
    private static let earthRadiusMeters = 6_371_000.0

    /// Roughly one storey of a building, used to decide "same floor".
    static let metersPerFloor = 3.5
    /// Altitude difference under this is treated as the same floor.
    static let sameFloorToleranceMeters = 3.0

    static func distanceMeters(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }

    /// Initial bearing in degrees, clockwise from true north (0° = north).
    static func bearingDegrees(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Relationship between a hunter's altitude and a Mecca's altitude.
    enum FloorRelation: Equatable {
        case sameFloor
        case above(floors: Int, meters: Double)
        case below(floors: Int, meters: Double)
    }

    static func floorRelation(
        hunterAltitude: Double?,
        meccaAltitude: Double?
    ) -> FloorRelation {
        guard
            let hunterAltitude,
            let meccaAltitude
        else {
            return .sameFloor
        }

        let delta = meccaAltitude - hunterAltitude
        if abs(delta) <= sameFloorToleranceMeters {
            return .sameFloor
        }

        let floors = max(1, Int((abs(delta) / metersPerFloor).rounded()))
        return delta > 0
            ? .above(floors: floors, meters: delta)
            : .below(floors: floors, meters: -delta)
    }
}
