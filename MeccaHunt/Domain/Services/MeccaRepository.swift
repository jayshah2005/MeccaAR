import Foundation

/// Backend boundary for storing hidden Meccas, loading them for the map, and
/// recording server-authoritative hunt claims.
protocol MeccaRepository: Sendable {
    /// Every active Mecca, annotated with claim info for the given hunter.
    func allMeccas(hunterID: UUID) async throws -> [Mecca]

    /// Persist a newly hidden Mecca owned by `ownerID`. Enforces the one-per-day
    /// rule atomically: the insert only happens if the owner has not created a
    /// Mecca since `notBefore`; otherwise it throws `.dailyLimitReached`.
    func createMecca(
        ownerID: UUID,
        name: String,
        coordinate: GeoCoordinate,
        appearance: MeccaAppearance,
        placementMode: MeccaPlacementMode,
        notBefore: Date
    ) async throws -> Mecca

    /// The most recent time this owner hid a Mecca, or nil if they never have.
    func lastPlacement(ownerID: UUID) async throws -> Date?

    /// Record a hunt and remove the Mecca from the map. The awarded points are
    /// the Mecca's current age-based value (server-authoritative). Fails if the
    /// hunter owns the Mecca, it has already been found, or it has expired.
    func claim(
        meccaID: UUID,
        hunterID: UUID
    ) async throws -> HuntClaim

    /// Hunters ranked by points earned from claims within the given time window.
    func hunterLeaderboard(period: LeaderboardPeriod) async throws -> [LeaderboardEntry]

    /// Every player ranked by total points earned from hunts, all time.
    func overallLeaderboard() async throws -> [LeaderboardEntry]

    /// The active Meccas hidden by this owner (still out there to be found).
    func meccasOwned(by ownerID: UUID) async throws -> [Mecca]

    /// Permanently remove a Mecca. Only its owner may delete it.
    func deleteMecca(id: UUID, ownerID: UUID) async throws

    /// Store a serialized, compressed ARKit world map for centimeter-accurate
    /// relocalization of this Mecca. Overwrites any existing map.
    func uploadWorldMap(meccaID: UUID, compressedData: Data) async throws

    /// Fetch the stored compressed world map for a Mecca, or nil if none exists.
    func worldMap(for meccaID: UUID) async throws -> Data?

    /// Store a JPEG face photo for this Mecca so hunters see the same face.
    /// Overwrites any existing photo.
    func uploadFacePhoto(meccaID: UUID, jpegData: Data) async throws

    /// Fetch the stored face photo JPEG for a Mecca, or nil if none exists.
    func facePhoto(for meccaID: UUID) async throws -> Data?
}

enum MeccaRepositoryError: LocalizedError {
    case cannotHuntOwnMecca
    case dailyLimitReached
    case unavailable
    case notFound

    var errorDescription: String? {
        switch self {
        case .cannotHuntOwnMecca:
            return "You can't hunt a Mecca you hid yourself."
        case .dailyLimitReached:
            return "You've already hidden a Mecca today. Come back tomorrow!"
        case .unavailable:
            return "This Mecca has already been found."
        case .notFound:
            return "That Mecca could not be found."
        }
    }
}
