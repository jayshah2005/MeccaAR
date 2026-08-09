import Foundation

/// A geographic point on Earth where a Mecca has been hidden.
struct GeoCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    /// Metres above sea level, used to distinguish floors of a building.
    let altitude: Double?
}

/// The visual customization the owner chose when hiding a Mecca, persisted so
/// it renders identically for everyone who finds it. Colors are 0...1 sRGB
/// components; rotations are degrees; size is the real-world height in mm.
struct MeccaAppearance: Codable, Hashable, Sendable {
    var sizeMillimeters: Double
    var xRotationDegrees: Double
    var yRotationDegrees: Double
    var red: Double
    var green: Double
    var blue: Double

    static let `default` = MeccaAppearance(
        sizeMillimeters: 25,
        xRotationDegrees: 0,
        yRotationDegrees: 0,
        red: 1,
        green: 1,
        blue: 1
    )
}

/// A Mecca hidden by a user and stored in Neon, as seen by a hunter.
struct Mecca: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let ownerUsername: String
    let name: String
    let coordinate: GeoCoordinate
    /// Owner-chosen color, size, and rotation, applied wherever it is rendered.
    let appearance: MeccaAppearance
    let createdAt: Date
    /// Number of hunters who have already claimed this Mecca.
    let claimCount: Int
    /// Whether the requesting hunter has already claimed this Mecca.
    let claimedByMe: Bool
    /// Whether a centimeter-accurate ARKit world map is stored for this Mecca,
    /// enabling precise visual relocalization instead of GPS-only guidance.
    let hasWorldMap: Bool

    var latitude: Double { coordinate.latitude }
    var longitude: Double { coordinate.longitude }
    var altitude: Double? { coordinate.altitude }

    /// Whole days this Mecca has been hidden.
    var daysHidden: Int { MeccaScoring.daysHidden(since: createdAt) }
    /// Current point value, which grows the longer it stays hidden.
    var currentPoints: Int { MeccaScoring.points(since: createdAt) }
    /// Rarity tier for display.
    var rarity: MeccaScoring.Tier { MeccaScoring.tier(since: createdAt) }
    /// Whether it has passed the expiry age and should no longer appear.
    var isExpired: Bool { MeccaScoring.isExpired(createdAt: createdAt) }
}

/// A single successful hunt, recording who found which Mecca.
struct HuntClaim: Codable, Hashable, Sendable {
    let meccaID: UUID
    let hunterID: UUID
    let claimedAt: Date
    let awardedPoints: Int
}
