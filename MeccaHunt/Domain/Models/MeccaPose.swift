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

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .pose09: "Pose 9"
        case .pose10: "Pose 10"
        case .pose11: "Pose 11"
        case .pose12: "Pose 12"
        case .pose13: "Pose 13"
        case .pose14: "Pose 14"
        case .pose15: "Pose 15"
        case .pose16: "Pose 16"
        case .pose17: "Pose 17"
        case .pose18: "Pose 18"
        case .pose19: "Pose 19"
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
