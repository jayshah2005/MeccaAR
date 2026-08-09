import Foundation

/// A player's standing on the leaderboard: total points and number of finds.
struct LeaderboardEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let username: String
    let points: Int
    let finds: Int
}

/// Time window for the hunter leaderboard.
enum LeaderboardPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Yearly"
        }
    }

    /// The Postgres interval literal for filtering claim timestamps. This is a
    /// fixed, enum-controlled string (never user input), so it is safe to embed.
    var sqlInterval: String {
        switch self {
        case .week: return "7 days"
        case .month: return "30 days"
        case .year: return "365 days"
        }
    }
}
