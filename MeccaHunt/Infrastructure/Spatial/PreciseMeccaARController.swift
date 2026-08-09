import ARKit
import RealityKit
import UIKit
import simd

/// Drives a centimeter-accurate AR session by relocalizing against a previously
/// captured `ARWorldMap`. When the device recognizes the saved space, ARKit
/// resolves the Mecca's saved world anchor to its true physical position.
///
/// Crucially, we wait for the resolved transform to stay stable under normal
/// tracking before "baking" the Mecca into a fixed world-space anchor. From
/// then on it stays pinned and is visible from any angle — the player does not
/// have to hold the exact original viewpoint.
///
/// Shared by Hunt and MyMeccas; each feature wraps it in its own AR container.
@MainActor
final class PreciseMeccaARController: NSObject, ARSessionDelegate,
    ARCoachingOverlayViewDelegate {
    /// Name given to the Mecca's `ARAnchor` at placement time so it can be found
    /// again after relocalization.
    static let anchorName = "mecca"

    /// How long the resolved transform must stay still under normal tracking
    /// before we trust it enough to bake.
    private static let stabilityDuration: TimeInterval = 0.7
    /// Max position drift (metres) allowed during the stability window.
    private static let stabilityToleranceMeters: Float = 0.025

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
    private var facePhoto: UIImage?
    private var coachingOverlay: ARCoachingOverlayView?

    /// True once tracking has reached full quality (i.e. relocalized against the
    /// saved map). Saved anchor transforms are only trustworthy after this.
    private var relocalized = false
    /// The most recent world transform reported for the saved Mecca anchor.
    private var resolvedTransform: simd_float4x4?
    /// True once the Mecca has been pinned into world space.
    private var placed = false

    /// Anchor of the stability window: first sample of a stable run.
    private var stabilityOrigin: SIMD3<Float>?
    private var stabilityStartedAt: Date?

    func start(
        worldMap: ARWorldMap,
        appearance: MeccaAppearance,
        facePhoto: UIImage? = nil,
        in arView: ARView
    ) {
        self.arView = arView
        self.appearance = appearance
        self.facePhoto = facePhoto
        arView.session.delegate = self

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        configuration.initialWorldMap = worldMap

        // Use the LiDAR 3D scan when available: a live scene mesh plus depth give
        // ARKit far more geometry to lock onto, so it can recognize the saved
        // space from a wider range of angles and distances, and tracking stays
        // solid once the Mecca is pinned.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )

        installCoachingOverlay(in: arView)
        onStateChange?(.relocalizing)
    }

    /// Adds ARKit's built-in relocalization coaching overlay, which actively
    /// prompts the user to move the device until it re-recognizes the saved
    /// space. This is the key to locking on from a fresh viewpoint rather than
    /// only from the exact angle the Mecca was placed at.
    private func installCoachingOverlay(in arView: ARView) {
        guard coachingOverlay == nil else { return }
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.delegate = self
        coaching.goal = .tracking
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
        ])
        coachingOverlay = coaching
    }

    /// Whether a tapped entity is the Mecca (or part of it).
    func contains(_ entity: Entity) -> Bool {
        guard let meccaEntity else { return false }
        return entity == meccaEntity || entity.isDescendant(of: meccaEntity)
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors where anchor.name == Self.anchorName {
            noteResolvedTransform(anchor.transform)
        }
        placeIfReady()
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors where anchor.name == Self.anchorName {
            noteResolvedTransform(anchor.transform)
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
            resetStability()
            if !placed { onStateChange?(.relocalizing) }
        case .limited:
            resetStability()
            // Once placed, a transient tracking dip doesn't hide the Mecca —
            // odometry keeps it pinned — so keep reporting located.
            onStateChange?(placed ? .located : .relocalizing)
        case .notAvailable:
            resetStability()
            if !placed { onStateChange?(.initializing) }
        @unknown default:
            resetStability()
            if !placed { onStateChange?(.relocalizing) }
        }
    }

    /// Records a candidate transform and tracks whether it has stayed put long
    /// enough to trust. Jumping positions (common during early relocalization)
    /// reset the stability window so we never bake a wrong spot.
    private func noteResolvedTransform(_ transform: simd_float4x4) {
        resolvedTransform = transform
        let position = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )

        if let origin = stabilityOrigin {
            let drift = simd_length(position - origin)
            if drift > Self.stabilityToleranceMeters {
                stabilityOrigin = position
                stabilityStartedAt = Date()
            }
        } else {
            stabilityOrigin = position
            stabilityStartedAt = Date()
        }
    }

    private func resetStability() {
        stabilityOrigin = nil
        stabilityStartedAt = nil
    }

    private var isTransformStable: Bool {
        guard
            let started = stabilityStartedAt,
            stabilityOrigin != nil
        else { return false }
        return Date().timeIntervalSince(started) >= Self.stabilityDuration
    }

    /// Bakes the Mecca into a fixed world anchor once we have normal tracking
    /// and a transform that has stayed put long enough to trust.
    private func placeIfReady() {
        guard
            !placed,
            relocalized,
            isTransformStable,
            let arView,
            let transform = resolvedTransform
        else { return }

        placed = true
        coachingOverlay?.setActive(false, animated: true)

        // Anchor to a fixed world transform (not the live ARAnchor) so the Mecca
        // remains visible and stationary from every angle, even if the session's
        // relocalization confidence later fluctuates.
        let anchorEntity = AnchorEntity(world: transform)
        arView.scene.addAnchor(anchorEntity)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let entity = await MeccaEntityFactory.make()
            MeccaEntityFactory.apply(self.appearance, to: entity)
            if let facePhoto = self.facePhoto {
                _ = MeccaEntityFactory.applyFacePhoto(facePhoto, to: entity)
            }
            anchorEntity.addChild(entity)
            self.meccaEntity = entity
            self.onStateChange?(.located)
        }
    }

    // MARK: ARCoachingOverlayViewDelegate

    func coachingOverlayViewWillActivate(_ overlayView: ARCoachingOverlayView) {
        if !placed { onStateChange?(.relocalizing) }
    }

    func coachingOverlayViewDidDeactivate(_ overlayView: ARCoachingOverlayView) {
        // Coaching finished; if the anchor already resolved and is stable, pin.
        placeIfReady()
    }
}
