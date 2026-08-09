import Foundation

/// A geographic point on Earth where a Mecca has been hidden.
struct GeoCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    /// Metres above sea level, used to distinguish floors of a building.
    let altitude: Double?
}

/// A Mecca hidden by a user and stored in Neon, as seen by a hunter.
struct Mecca: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let ownerUsername: String
    let name: String
    let coordinate: GeoCoordinate
    let createdAt: Date
    /// Number of hunters who have already claimed this Mecca.
    let claimCount: Int
    /// Whether the requesting hunter has already claimed this Mecca.
    let claimedByMe: Bool

    var latitude: Double { coordinate.latitude }
    var longitude: Double { coordinate.longitude }
    var altitude: Double? { coordinate.altitude }
}

/// A single successful hunt, recording who found which Mecca.
struct HuntClaim: Codable, Hashable, Sendable {
    let meccaID: UUID
    let hunterID: UUID
    let claimedAt: Date
    let awardedPoints: Int
}
