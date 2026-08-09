import Foundation

/// A bundled, static character pose. The raw value is stored in Neon so every
/// device loads the same USDZ model chosen by the player who hid the Mecca.
enum MeccaPose: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case classic
    case pose09 = "pose_09"
    case pose10 = "pose_10"
    case pose11 = "pose_11"
    case pose12 = "pose_12"
    case pose13 = "pose_13"
    case pose14 = "pose_14"
    case pose15 = "pose_15"
    case pose16 = "pose_16"
    case pose17 = "pose_17"
    case pose18 = "pose_18"
    case pose19 = "pose_19"

    var id: String { rawValue }

    /// Short labels shown under the visual pose thumbnails.
    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .pose09: "Look A"
        case .pose10: "Look B"
        case .pose11: "Look C"
        case .pose12: "Look D"
        case .pose13: "Look E"
        case .pose14: "Look F"
        case .pose15: "Look G"
        case .pose16: "Look H"
        case .pose17: "Look I"
        case .pose18: "Look J"
        case .pose19: "Look K"
        }
    }

    /// Resource name without the `.usdz` extension.
    var resourceName: String {
        switch self {
        case .classic: "Mecca"
        case .pose09: "MeccaPose09"
        case .pose10: "MeccaPose10"
        case .pose11: "MeccaPose11"
        case .pose12: "MeccaPose12"
        case .pose13: "MeccaPose13"
        case .pose14: "MeccaPose14"
        case .pose15: "MeccaPose15"
        case .pose16: "MeccaPose16"
        case .pose17: "MeccaPose17"
        case .pose18: "MeccaPose18"
        case .pose19: "MeccaPose19"
        }
    }
}
