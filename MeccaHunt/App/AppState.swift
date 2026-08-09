import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Route: Hashable {
        /// Username-only sign in.
        case login
        /// Main page: the map of hidden Meccas (Hunt feature).
        case map
        /// AR placement of a new Mecca (Placement feature).
        case place
        /// List of the current user's own hidden Meccas (MyMeccas feature).
        case myMeccas
    }

    var route: Route
    private(set) var currentUser: User?

    let dependencies: Dependencies

    private let sessionKey = "mecca.session.user"

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        let restored = Self.restoreUser(key: sessionKey)
        currentUser = restored
        route = restored == nil ? .login : .map
    }

    func completeSignIn(_ user: User) {
        currentUser = user
        persist(user)
        route = .map
    }

    func signOut() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
        route = .login
    }

    /// Permanently delete the signed-in account, then return to sign in.
    func deleteAccount() async throws {
        guard let userID = currentUser?.id else { return }
        try await dependencies.auth.deleteAccount(userID: userID)
        signOut()
    }

    // MARK: Session persistence

    private func persist(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    private static func restoreUser(key: String) -> User? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }
}
