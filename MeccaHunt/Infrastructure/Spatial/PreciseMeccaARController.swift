import ARKit
import RealityKit

/// Drives a centimeter-accurate AR session by relocalizing against a previously
/// captured `ARWorldMap`. When the device recognizes the saved space, ARKit
/// resolves the Mecca's saved world anchor to its true physical position.
///
/// Crucially, as soon as that happens once, we "bake" the Mecca into a fixed
/// world-space anchor at the resolved transform and stop depending on the live
/// ARAnchor. From then on the Mecca stays pinned in place and is visible from
/// any angle — the player does not have to hold the exact original viewpoint.
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
    private var meccaEntity: Entity?
    private var appearance: MeccaAppearance = .default

    /// True once tracking has reached full quality (i.e. relocalized against the
    /// saved map). Saved anchor transforms are only trustworthy after this.
    private var relocalized = false
    /// The most recent world transform reported for the saved Mecca anchor.
    private var resolvedTransform: simd_float4x4?
    /// True once the Mecca has been pinned into world space.
    private var placed = false

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
            resolvedTransform = anchor.transform
        }
        placeIfReady()
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors where anchor.name == Self.anchorName {
            resolvedTransform = anchor.transform
        }
        placeIfReady()
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            relocalized = true
            placeIfReady()
            onStateChange?(placed ? .located : .relocalizing)
        case .limited(.relocalizing):
            if !placed { onStateChange?(.relocalizing) }
        case .limited:
            // Once placed, a transient tracking dip doesn't hide the Mecca —
            // odometry keeps it pinned — so keep reporting located.
            onStateChange?(placed ? .located : .relocalizing)
        case .notAvailable:
            if !placed { onStateChange?(.initializing) }
        @unknown default:
            if !placed { onStateChange?(.relocalizing) }
        }
    }

    /// Bakes the Mecca into a fixed world anchor the first time we have both a
    /// good relocalization and a resolved anchor transform.
    private func placeIfReady() {
        guard
            !placed,
            relocalized,
            let arView,
            let transform = resolvedTransform
        else { return }

        placed = true

        // Anchor to a fixed world transform (not the live ARAnchor) so the Mecca
        // remains visible and stationary from every angle, even if the session's
        // relocalization confidence later fluctuates.
        let anchorEntity = AnchorEntity(world: transform)
        arView.scene.addAnchor(anchorEntity)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let entity = await MeccaEntityFactory.make()
            MeccaEntityFactory.apply(self.appearance, to: entity)
            anchorEntity.addChild(entity)
            self.meccaEntity = entity
            self.onStateChange?(.located)
        }
    }
}
