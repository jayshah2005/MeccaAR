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
    var pose: MeccaPose

    private enum CodingKeys: String, CodingKey {
        case sizeMillimeters
        case xRotationDegrees
        case yRotationDegrees
        case red
        case green
        case blue
        case pose
    }

    init(
        sizeMillimeters: Double,
        xRotationDegrees: Double,
        yRotationDegrees: Double,
        red: Double,
        green: Double,
        blue: Double,
        pose: MeccaPose = .classic
    ) {
        self.sizeMillimeters = sizeMillimeters
        self.xRotationDegrees = xRotationDegrees
        self.yRotationDegrees = yRotationDegrees
        self.red = red
        self.green = green
        self.blue = blue
        self.pose = pose
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sizeMillimeters: try values.decode(Double.self, forKey: .sizeMillimeters),
            xRotationDegrees: try values.decode(Double.self, forKey: .xRotationDegrees),
            yRotationDegrees: try values.decode(Double.self, forKey: .yRotationDegrees),
            red: try values.decode(Double.self, forKey: .red),
            green: try values.decode(Double.self, forKey: .green),
            blue: try values.decode(Double.self, forKey: .blue),
            pose: try values.decodeIfPresent(MeccaPose.self, forKey: .pose) ?? .classic
        )
    }

    static let `default` = MeccaAppearance(
        sizeMillimeters: 25,
        xRotationDegrees: 0,
        yRotationDegrees: 0,
        red: 1,
        green: 1,
        blue: 1,
        pose: .classic
    )
}

/// A Mecca hidden by a user and stored in Neon, as seen by a hunter.
struct Mecca: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
    let ownerUsername: String
    let name: String
    let coordinate: GeoCoordinate
    /// Owner-chosen pose, color, size, and rotation, applied wherever it renders.
    let appearance: MeccaAppearance
    let createdAt: Date
    /// Number of hunters who have already claimed this Mecca.
    let claimCount: Int
    /// Whether the requesting hunter has already claimed this Mecca.
    let claimedByMe: Bool
    /// Whether a centimeter-accurate ARKit world map is stored for this Mecca,
    /// enabling precise visual relocalization instead of GPS-only guidance.
    let hasWorldMap: Bool
    /// Whether an owner face photo is stored for this Mecca.
    let hasFacePhoto: Bool
    /// How this Mecca was anchored: outdoor geo tracking or an AR world map.
    let placementMode: MeccaPlacementMode

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
