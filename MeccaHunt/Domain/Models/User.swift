import Foundation

/// An application account identified purely by a unique username.
struct User: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let username: String
    let createdAt: Date
}
