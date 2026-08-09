import Foundation

/// Identity boundary. Usernames are the only credential: signing in finds the
/// existing account or creates a new one on first use.
protocol AuthRepository: Sendable {
    func signIn(username: String) async throws -> User
}
