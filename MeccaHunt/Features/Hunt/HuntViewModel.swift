import CoreLocation
import Foundation
import Observation

/// A Mecca evaluated against the hunter's current position: how far, which
/// floor, and whether it can be hunted right now.
struct NearbyMecca: Identifiable {
    let mecca: Mecca
    let distanceMeters: Double
    let floorRelation: GeoMath.FloorRelation
    let isMine: Bool

    var id: UUID { mecca.id }

    var isSameFloor: Bool { floorRelation == .sameFloor }

    /// Huntable when it's someone else's, unclaimed, on your floor, and within
    /// the hunt radius.
    var isHuntable: Bool {
        !isMine
            && !mecca.claimedByMe
            && isSameFloor
            && distanceMeters <= HuntTuning.huntRadiusMeters
    }
}

/// Shared tuning for proximity, hints, and clustering.
enum HuntTuning {
    static let huntRadiusMeters = 8.0
    static let hintUntilMeters = 4.0
    static let clusterRadiusMeters = 4.0
    /// Horizontal radius within which an off-floor Mecca is worth flagging
    /// ("above/below you") even though it isn't huntable.
    static let floorHintRadiusMeters = 12.0
    static let awardedPoints = 100
}

@MainActor
@Observable
final class HuntViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var meccas: [Mecca] = []
    private(set) var clusters: [MeccaCluster] = []
    private(set) var loadState: LoadState = .idle

    private let repository: MeccaRepository

    init(repository: MeccaRepository) {
        self.repository = repository
    }

    func load(hunterID: UUID) async {
        if case .loaded = loadState {} else {
            loadState = .loading
        }
        do {
            let fetched = try await repository.allMeccas(hunterID: hunterID)
            meccas = fetched
            clusters = MeccaClustering.cluster(fetched, withinMeters: HuntTuning.clusterRadiusMeters)
            loadState = .loaded
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            loadState = .failed(message)
        }
    }

    /// Meccas ranked by distance from the hunter, annotated with floor info.
    func nearby(from location: CLLocation?, currentUserID: UUID) -> [NearbyMecca] {
        guard let location else { return [] }
        let origin = location.coordinate
        let hunterAltitude = location.verticalAccuracy >= 0 ? location.altitude : nil

        return meccas
            .map { mecca in
                let target = CLLocationCoordinate2D(
                    latitude: mecca.latitude,
                    longitude: mecca.longitude
                )
                return NearbyMecca(
                    mecca: mecca,
                    distanceMeters: GeoMath.distanceMeters(from: origin, to: target),
                    floorRelation: GeoMath.floorRelation(
                        hunterAltitude: hunterAltitude,
                        meccaAltitude: mecca.altitude
                    ),
                    isMine: mecca.ownerID == currentUserID
                )
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// Nearby Meccas the hunter can claim right now.
    func huntable(from location: CLLocation?, currentUserID: UUID) -> [NearbyMecca] {
        nearby(from: location, currentUserID: currentUserID).filter(\.isHuntable)
    }

    /// Nearby Meccas that are close horizontally but on another floor.
    func offFloor(from location: CLLocation?, currentUserID: UUID) -> [NearbyMecca] {
        nearby(from: location, currentUserID: currentUserID).filter { candidate in
            !candidate.isMine
                && !candidate.mecca.claimedByMe
                && !candidate.isSameFloor
                && candidate.distanceMeters <= HuntTuning.floorHintRadiusMeters
        }
    }

    @discardableResult
    func claim(_ mecca: Mecca, hunterID: UUID) async throws -> HuntClaim {
        try await repository.claim(meccaID: mecca.id, hunterID: hunterID)
    }
}
