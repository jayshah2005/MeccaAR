import Foundation

struct GeoCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double?
}

enum SpatialAnchorMethod: String, Codable, Hashable, Sendable {
    case worldMap
    case geoAnchor
}

enum PlacementState: String, Codable, Hashable, Sendable {
    case active
    case expired
    case removed
}

struct MeccaPlacement: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let coordinate: GeoCoordinate
    let anchorMethod: SpatialAnchorMethod
    let anchorPayloadID: String
    let createdAt: Date
    let expiresAt: Date
    let state: PlacementState
}

struct HuntClaim: Codable, Hashable, Sendable {
    let placementID: UUID
    let hunterID: UUID
    let claimedAt: Date
    let awardedPoints: Int
}

