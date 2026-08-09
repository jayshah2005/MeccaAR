import Foundation

/// Composition root container. Built once at launch in `MeccaHuntApp` and read
/// by features through `AppState`. Wiring lives here, not inside features.
@MainActor
final class Dependencies {
    let auth: AuthRepository
    let meccas: MeccaRepository
    let location: LocationProvider
    /// Non-nil when the Neon connection string is missing/invalid, so the UI
    /// can explain how to fix configuration instead of failing silently.
    let configurationError: String?

    init(
        auth: AuthRepository,
        meccas: MeccaRepository,
        location: LocationProvider,
        configurationError: String? = nil
    ) {
        self.auth = auth
        self.meccas = meccas
        self.location = location
        self.configurationError = configurationError
    }

    static func live() -> Dependencies {
        let location = LocationProvider()
        do {
            let configuration = try NeonConfiguration.fromInfoPlist()
            let client = NeonClient(configuration: configuration)
            return Dependencies(
                auth: NeonAuthRepository(client: client),
                meccas: NeonMeccaRepository(client: client),
                location: location
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return Dependencies(
                auth: UnavailableRepository(message: message),
                meccas: UnavailableRepository(message: message),
                location: location,
                configurationError: message
            )
        }
    }
}

/// Stand-in used when the backend is not configured; every call fails with a
/// clear, actionable message.
private struct UnavailableRepository: AuthRepository, MeccaRepository {
    let message: String

    private var failure: Error { NeonError.server(message) }

    func signIn(username: String) async throws -> User { throw failure }

    func allMeccas(hunterID: UUID) async throws -> [Mecca] { throw failure }

    func createMecca(
        ownerID: UUID,
        name: String,
        coordinate: GeoCoordinate,
        appearance: MeccaAppearance,
        notBefore: Date
    ) async throws -> Mecca { throw failure }

    func createMappedMecca(
        ownerID: UUID,
        name: String,
        coordinate: GeoCoordinate,
        appearance: MeccaAppearance,
        notBefore: Date,
        worldMapData: Data
    ) async throws -> Mecca { throw failure }

    func lastPlacement(ownerID: UUID) async throws -> Date? { throw failure }

    func claim(
        meccaID: UUID,
        hunterID: UUID,
        awardedPoints: Int
    ) async throws -> HuntClaim { throw failure }

    func leaderboard() async throws -> [LeaderboardEntry] { throw failure }

    func meccasOwned(by ownerID: UUID) async throws -> [Mecca] { throw failure }

    func deleteMecca(id: UUID, ownerID: UUID) async throws { throw failure }

    func uploadWorldMap(meccaID: UUID, compressedData: Data) async throws { throw failure }

    func worldMap(for meccaID: UUID) async throws -> Data? { throw failure }
}
