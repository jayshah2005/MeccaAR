import Foundation

/// A player's standing on the leaderboard: total points and number of finds.
struct LeaderboardEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let username: String
    let points: Int
    let finds: Int
}
