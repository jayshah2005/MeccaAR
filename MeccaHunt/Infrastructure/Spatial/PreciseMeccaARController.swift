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
        /// A GPS/heading estimate is already visible while exact relocalization
        /// continues in the background.
        case approximating
        /// Locked on: the Mecca is shown at its exact real-world spot.
        case located
    }

    struct FallbackPlacement: Equatable, Sendable {
        let bearingDegrees: Double
        let distanceMeters: Double
        let headingDegrees: Double?
    }

    /// Called on the main actor whenever the relocalization state changes.
    var onStateChange: ((State) -> Void)?

    private weak var arView: ARView?
    private var meccaEntity: Entity?
    private var appearance: MeccaAppearance = .default
    private var fallbackPlacement: FallbackPlacement?
    private var fallbackAnchor: AnchorEntity?
    private var fixedAnchor: AnchorEntity?
    private var fallbackEnabled = false
    private var isCreatingEntity = false
    private var fallbackIsVisible = false
    private var generation = 0

    /// True once tracking has reached full quality (i.e. relocalized against the
    /// saved map). Saved anchor transforms are only trustworthy after this.
    private var relocalized = false
    /// The most recent world transform reported for the saved Mecca anchor.
    private var resolvedTransform: simd_float4x4?
    /// True once the Mecca has been pinned into world space.
    private var placed = false

    func start(
        worldMap: ARWorldMap,
        appearance: MeccaAppearance,
        fallbackPlacement: FallbackPlacement? = nil,
        in arView: ARView
    ) {
        self.arView = arView
        self.appearance = appearance
        self.fallbackPlacement = fallbackPlacement
        fallbackEnabled = fallbackPlacement != nil
        arView.session.delegate = self
        ensureEntity()

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        configuration.initialWorldMap = worldMap

        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )
        onStateChange?(.relocalizing)
    }

    /// Accepts fresher GPS/heading readings while relocalization is running.
    /// Once the exact anchor is resolved, fallback updates are ignored.
    func updateFallback(_ placement: FallbackPlacement?) {
        if let placement {
            fallbackPlacement = placement
            fallbackEnabled = true
        } else if !fallbackEnabled {
            return
        }
        guard !placed, let frame = arView?.session.currentFrame else { return }
        placeFallbackIfReady(using: frame, reposition: true)
    }

    /// Whether a tapped entity is the Mecca (or part of it).
    func contains(_ entity: Entity) -> Bool {
        guard let meccaEntity else { return false }
        return entity == meccaEntity || entity.isDescendant(of: meccaEntity)
    }

    /// Removes the visible Mecca while leaving the shared AR session available
    /// for the rest of a multi-Mecca room hunt.
    func clear() {
        meccaEntity?.removeFromParent()
        fallbackAnchor?.removeFromParent()
        fixedAnchor?.removeFromParent()
        fallbackAnchor = nil
        fixedAnchor = nil
        meccaEntity = nil
        fallbackIsVisible = false
        placed = false
        isCreatingEntity = false
        generation += 1
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

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        placeFallbackIfReady(using: frame)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            relocalized = true
            placeIfReady()
            reportCurrentState()
        case .limited(.relocalizing):
            if !placed { reportCurrentState() }
        case .limited:
            // Once placed, a transient tracking dip doesn't hide the Mecca —
            // odometry keeps it pinned — so keep reporting located.
            reportCurrentState()
        case .notAvailable:
            if !placed {
                onStateChange?(fallbackIsVisible ? .approximating : .initializing)
            }
        @unknown default:
            if !placed { reportCurrentState() }
        }
    }

    /// Creates the visible Mecca once. The cached factory normally makes this a
    /// cheap clone, and beginning it before the first AR frame avoids a second
    /// delay after tracking starts.
    private func ensureEntity() {
        guard meccaEntity == nil, !isCreatingEntity else { return }
        isCreatingEntity = true
        let requestedGeneration = generation

        Task { @MainActor [weak self] in
            guard let self else { return }
            let entity = await MeccaEntityFactory.make()
            guard self.generation == requestedGeneration else { return }
            MeccaEntityFactory.apply(
                self.appearance,
                to: entity,
                displayScale: 2
            )
            self.meccaEntity = entity
            self.isCreatingEntity = false

            if let frame = self.arView?.session.currentFrame {
                self.placeFallbackIfReady(using: frame)
            }
            self.placeIfReady()
        }
    }

    /// Shows a stable, immediately visible estimate in the target's compass
    /// direction. It is capped at four metres and enlarged temporarily so a
    /// millimetre-scale Mecca remains visible while the exact map resolves.
    private func placeFallbackIfReady(
        using frame: ARFrame,
        reposition: Bool = false
    ) {
        guard
            !placed,
            fallbackEnabled,
            let arView,
            let entity = meccaEntity,
            reposition || !fallbackIsVisible
        else { return }

        let cameraTransform = frame.camera.transform
        let camera = cameraTransform.columns.3
        var cameraForward = SIMD3<Float>(
            -cameraTransform.columns.2.x,
            0,
            -cameraTransform.columns.2.z
        )
        if simd_length(cameraForward) < 0.001 {
            cameraForward = [0, 0, -1]
        } else {
            cameraForward = simd_normalize(cameraForward)
        }

        let direction: SIMD3<Float>
        if let fallbackPlacement,
           let heading = fallbackPlacement.headingDegrees {
            let relativeBearing = Float(
                (fallbackPlacement.bearingDegrees - heading) * .pi / 180
            )
            direction = simd_quatf(
                angle: -relativeBearing,
                axis: [0, 1, 0]
            ).act(cameraForward)
        } else {
            direction = cameraForward
        }

        let requestedDistance = fallbackPlacement?.distanceMeters ?? 1.5
        let visibleDistance = Float(min(max(requestedDistance, 1.2), 4))
        let target = SIMD3<Float>(
            camera.x + direction.x * visibleDistance,
            camera.y - 0.5,
            camera.z + direction.z * visibleDistance
        )

        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(target.x, target.y, target.z, 1)

        if let fallbackAnchor {
            fallbackAnchor.transform = Transform(matrix: transform)
        } else {
            let anchor = AnchorEntity(world: transform)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            fallbackAnchor = anchor
        }

        fallbackIsVisible = true
        onStateChange?(.approximating)
    }

    private func reportCurrentState() {
        if placed {
            onStateChange?(.located)
        } else if fallbackIsVisible {
            onStateChange?(.approximating)
        } else {
            onStateChange?(.relocalizing)
        }
    }

    /// Bakes the Mecca into a fixed world anchor the first time we have both a
    /// good relocalization and a resolved anchor transform.
    private func placeIfReady() {
        guard
            !placed,
            relocalized,
            let arView,
            let transform = resolvedTransform,
            let entity = meccaEntity
        else { return }

        placed = true

        // Reuse the already-visible fallback entity instead of loading another
        // clone. This makes the approximate-to-exact transition immediate.
        entity.removeFromParent()
        fallbackAnchor?.removeFromParent()
        fallbackAnchor = nil
        fallbackIsVisible = false
        MeccaEntityFactory.apply(appearance, to: entity)

        // Anchor to a fixed world transform (not the live ARAnchor) so the Mecca
        // remains visible and stationary from every angle, even if the session's
        // relocalization confidence later fluctuates.
        let anchorEntity = AnchorEntity(world: transform)
        anchorEntity.addChild(entity)
        arView.scene.addAnchor(anchorEntity)
        fixedAnchor = anchorEntity
        onStateChange?(.located)
    }
}
