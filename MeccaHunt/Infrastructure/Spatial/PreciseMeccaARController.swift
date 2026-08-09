import ARKit
import RealityKit

/// Drives a centimeter-accurate AR session by relocalizing against a previously
/// captured `ARWorldMap`. When the device recognizes the saved space, ARKit
/// re-adds the Mecca's world anchor at its true physical position and this
/// controller renders the Mecca exactly there — no GPS involved.
///
/// Shared by Hunt and MyMeccas; each feature wraps it in its own AR container.
@MainActor
final class PreciseMeccaARController: NSObject, ARSessionDelegate {
    /// Name given to the Mecca's `ARAnchor` at placement time so it can be found
    /// again after relocalization.
    static let anchorName = "mecca"

    enum State: Equatable {
        /// Session starting up; no useful tracking yet.
        case initializing
        /// Actively trying to recognize the saved space. Ask the user to scan.
        case relocalizing
        /// Locked on: the Mecca is shown at its exact real-world spot.
        case located
    }

    /// Called on the main actor whenever the relocalization state changes.
    var onStateChange: ((State) -> Void)?

    private weak var arView: ARView?
    private var meccaAnchorEntity: AnchorEntity?
    private var meccaEntity: Entity?
    private var relocalized = false
    private var appearance: MeccaAppearance = .default

    func start(worldMap: ARWorldMap, appearance: MeccaAppearance, in arView: ARView) {
        self.arView = arView
        self.appearance = appearance
        arView.session.delegate = self

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        configuration.initialWorldMap = worldMap

        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )
        onStateChange?(.relocalizing)
    }

    /// Whether a tapped entity is the Mecca (or part of it).
    func contains(_ entity: Entity) -> Bool {
        guard let meccaEntity else { return false }
        return entity == meccaEntity || entity.isDescendant(of: meccaEntity)
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors where anchor.name == Self.anchorName {
            attachMecca(to: anchor)
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            relocalized = true
            onStateChange?(meccaEntity != nil ? .located : .relocalizing)
        case .limited(.relocalizing):
            onStateChange?(.relocalizing)
        case .limited:
            onStateChange?(relocalized ? .located : .relocalizing)
        case .notAvailable:
            onStateChange?(.initializing)
        @unknown default:
            onStateChange?(.relocalizing)
        }
    }

    private func attachMecca(to anchor: ARAnchor) {
        guard let arView, meccaAnchorEntity == nil else { return }

        let anchorEntity = AnchorEntity(anchor: anchor)
        arView.scene.addAnchor(anchorEntity)
        meccaAnchorEntity = anchorEntity

        Task { @MainActor [weak self] in
            let entity = await MeccaEntityFactory.make()
            MeccaEntityFactory.apply(self?.appearance ?? .default, to: entity)
            anchorEntity.addChild(entity)
            self?.meccaEntity = entity
            if self?.relocalized == true {
                self?.onStateChange?(.located)
            }
        }
    }
}
