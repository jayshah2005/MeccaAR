import Foundation

/// How a Mecca was anchored in the real world. Chooses the hunt/locate path:
/// geo tracking outdoors when Apple localization imagery is available, otherwise
/// an ARKit world map (with LiDAR indoors when present).
enum MeccaPlacementMode: String, Codable, Hashable, Sendable {
    case worldMap = "world_map"
    case geo = "geo"

    var title: String {
        switch self {
        case .worldMap: return "AR map"
        case .geo: return "GPS geo"
        }
    }
}
