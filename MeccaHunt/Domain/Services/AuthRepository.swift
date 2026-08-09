import Foundation

/// Identity boundary. Usernames are the only credential: signing in finds the
/// existing account or creates a new one on first use.
protocol AuthRepository: Sendable {
    func signIn(username: String) async throws -> User

    /// Permanently delete an account and everything tied to it: the user's
    /// hidden Meccas (and their world maps), and every hunt claim made by or
    /// against them.
    func deleteAccount(userID: UUID) async throws
}
