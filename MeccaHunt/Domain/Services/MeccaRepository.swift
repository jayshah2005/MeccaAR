import Foundation

/// Backend boundary for map discovery and server-authoritative scoring.
/// The initial setup intentionally provides no network implementation.
protocol MeccaRepository: Sendable {
    func nearby(
        coordinate: GeoCoordinate,
        radiusMeters: Double
    ) async throws -> [MeccaPlacement]

    func publish(_ placement: MeccaPlacement) async throws

    func claim(
        placementID: UUID,
        hunterCoordinate: GeoCoordinate
    ) async throws -> HuntClaim
}

/// Storage boundary for encrypted spatial payloads such as ARWorldMap archives.
protocol SpatialAnchorRepository: Sendable {
    func upload(payload: Data, placementID: UUID) async throws -> String
    func download(payloadID: String) async throws -> Data
}

