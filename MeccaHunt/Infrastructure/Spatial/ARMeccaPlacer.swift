import ARKit
import RealityKit
import UIKit

/// Positions a Mecca entity once in a compass-aligned AR scene, using the
/// target's saved coordinate. Once the first AR camera frame provides a stable
/// world origin, the entity is fixed and later GPS/camera updates cannot move it.
@MainActor
final class ARMeccaPlacer {
    /// The GPS estimate is intentionally larger than the real millimetre-scale
    /// character so it is visible while a precise room scan is still loading.
    private static let displayScale: Float = 2
    /// Do not render an approximate marker farther away than this or it becomes
    /// effectively invisible on a phone screen.
    private static let maximumDisplayDistanceMeters: Double = 4

    private struct PendingPlacement {
        let bearingDegrees: Double
        let distanceMeters: Double
        let lateralOffsetMeters: Double
        let headingDegrees: Double?
    }

    private(set) var meccaRoot: Entity?
    private var anchor: AnchorEntity?
    private var isCreating = false
    private var isAnchored = false
    private var appearance: MeccaAppearance = .default
    private var pendingPlacement: PendingPlacement?
    private var frameRetryTask: Task<Void, Never>?
    private var generation = 0
    private var facePhoto: UIImage?
    private var appliedFacePhotoIdentity: ObjectIdentifier?

    private var appearanceOrientation: simd_quatf {
        let xRadians = Float(appearance.xRotationDegrees) * .pi / 180
        let yRadians = Float(appearance.yRotationDegrees) * .pi / 180
        return simd_quatf(angle: yRadians, axis: [0, 1, 0])
            * simd_quatf(angle: xRadians, axis: [1, 0, 0])
    }

    /// - Parameters:
    ///   - bearingDegrees: Clockwise bearing from true north to the target.
    ///   - distanceMeters: Horizontal GPS distance to the target.
    ///   - freezeWithinMeters: Retained for source compatibility. Every Mecca
    ///     now freezes as soon as its first world position is established.
    ///   - lateralOffsetMeters: Small room-layout offset used to keep nearby
    ///     Meccas from occupying exactly the same point.
    ///   - appearance: The owner's saved color/size/rotation for the Mecca.
    func update(
        bearingDegrees: Double,
        distanceMeters: Double,
        freezeWithinMeters: Double,
        lateralOffsetMeters: Double = 0,
        headingDegrees: Double? = nil,
        appearance: MeccaAppearance = .default,
        facePhoto: UIImage? = nil,
        in arView: ARView
    ) {
        _ = freezeWithinMeters
        self.appearance = appearance
        self.facePhoto = facePhoto
        pendingPlacement = PendingPlacement(
            bearingDegrees: bearingDegrees,
            distanceMeters: distanceMeters,
            lateralOffsetMeters: lateralOffsetMeters,
            headingDegrees: headingDegrees
        )
        ensureEntity(in: arView)
        if !positionLatest(in: arView) {
            retryWhenCameraFrameIsReady(in: arView)
        }
        applyFacePhotoIfNeeded()
    }

    /// Camera-relative compatibility for world-map/geo callers. It still uses
    /// the anchor-once path, so later compass and camera updates cannot move the
    /// visible Mecca.
    func updateCameraRelative(
        targetBearingDegrees: Double,
        deviceHeadingDegrees: Double,
        distanceMeters: Double,
        freezeWithinMeters: Double,
        appearance: MeccaAppearance = .default,
        facePhoto: UIImage? = nil,
        in arView: ARView
    ) {
        update(
            bearingDegrees: targetBearingDegrees,
            distanceMeters: distanceMeters,
            freezeWithinMeters: freezeWithinMeters,
            headingDegrees: deviceHeadingDegrees,
            appearance: appearance,
            facePhoto: facePhoto,
            in: arView
        )
    }

    @discardableResult
    private func positionLatest(in arView: ARView) -> Bool {
        guard
            let meccaRoot,
            !isAnchored,
            let frame = arView.session.currentFrame,
            let pendingPlacement
        else { return false }

        // Compass-aligned world (gravityAndHeading): +x east, +z south, so
        // north is -z. Place relative to where the camera is right now.
        let camera = frame.camera.transform.columns.3
        let theta = Float(pendingPlacement.bearingDegrees * .pi / 180)
        let distance = Float(
            min(
                max(pendingPlacement.distanceMeters, 1.2),
                Self.maximumDisplayDistanceMeters
            )
        )
        let direction: SIMD3<Float>
        if let headingDegrees = pendingPlacement.headingDegrees {
            let cameraTransform = frame.camera.transform
            var cameraForward = SIMD3<Float>(
                -cameraTransform.columns.2.x,
                0,
                -cameraTransform.columns.2.z
            )
            cameraForward = simd_length(cameraForward) > 0.001
                ? simd_normalize(cameraForward)
                : SIMD3<Float>(0, 0, -1)
            let relativeBearing = Float(
                (pendingPlacement.bearingDegrees - headingDegrees) * .pi / 180
            )
            direction = simd_quatf(
                angle: -relativeBearing,
                axis: [0, 1, 0]
            ).act(cameraForward)
        } else {
            direction = SIMD3<Float>(sin(theta), 0, -cos(theta))
        }
        let right = SIMD3<Float>(-direction.z, 0, direction.x)
        let lateralOffset = Float(pendingPlacement.lateralOffsetMeters)
        let target = SIMD3<Float>(
            camera.x + direction.x * distance + right.x * lateralOffset,
            camera.y - 0.8,
            camera.z + direction.z * distance + right.z * lateralOffset
        )

        meccaRoot.stopAllAnimations(recursive: true)
        meccaRoot.transform = Transform(
            scale: SIMD3<Float>(repeating: Self.displayScale),
            rotation: appearanceOrientation,
            translation: target
        )
        meccaRoot.isEnabled = true

        // This is deliberately unconditional. Recomputing this transform from
        // the live camera pose was what made a Mecca drift when it was viewed.
        isAnchored = true
        frameRetryTask?.cancel()
        frameRetryTask = nil
        return true
    }

    /// Whether a tapped entity is the Mecca (or part of it).
    func contains(_ entity: Entity) -> Bool {
        guard let meccaRoot else { return false }
        return entity == meccaRoot || entity.isDescendant(of: meccaRoot)
    }

    /// Removes this Mecca from the current AR scene. This does not delete the
    /// saved Mecca from the repository.
    func clear() {
        frameRetryTask?.cancel()
        frameRetryTask = nil
        anchor?.removeFromParent()
        anchor = nil
        meccaRoot = nil
        pendingPlacement = nil
        isCreating = false
        isAnchored = false
        appliedFacePhotoIdentity = nil
        generation += 1
    }

    private func applyFacePhotoIfNeeded() {
        guard let meccaRoot else { return }
        let identity = facePhoto.map(ObjectIdentifier.init)
        guard identity != appliedFacePhotoIdentity else { return }
        _ = MeccaEntityFactory.applyFacePhoto(
            facePhoto,
            placement: .initial,
            to: meccaRoot
        )
        appliedFacePhotoIdentity = identity
    }

    private func ensureEntity(in arView: ARView) {
        guard meccaRoot == nil, !isCreating else { return }
        isCreating = true
        let requestedGeneration = generation

        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        self.anchor = anchor

        Task { @MainActor [weak self] in
            let entity = await MeccaEntityFactory.make(
                pose: self?.appearance.pose ?? .classic
            )
            guard self?.generation == requestedGeneration else { return }
            let appearance = self?.appearance ?? .default
            MeccaEntityFactory.apply(
                appearance,
                to: entity,
                displayScale: Self.displayScale
            )
            // Hidden until the first pose is applied so it never flashes at the
            // world origin and then appears to fly to the target.
            entity.isEnabled = false
            anchor.addChild(entity)
            self?.meccaRoot = entity
            self?.isCreating = false
            self?.applyFacePhotoIfNeeded()
            if self?.positionLatest(in: arView) == false {
                self?.retryWhenCameraFrameIsReady(in: arView)
            }
        }
    }

    /// SwiftUI can deliver the first placement update before ARKit has produced
    /// a camera frame. Retry briefly at frame cadence rather than waiting for a
    /// later GPS update, which previously looked like a multi-second load.
    private func retryWhenCameraFrameIsReady(in arView: ARView) {
        guard frameRetryTask == nil, !isAnchored else { return }

        frameRetryTask = Task { @MainActor [weak self, weak arView] in
            for _ in 0..<120 {
                guard
                    !Task.isCancelled,
                    let self,
                    let arView
                else { return }

                if self.positionLatest(in: arView) { return }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            self?.frameRetryTask = nil
        }
    }
}

extension Entity {
    func isDescendant(of ancestor: Entity) -> Bool {
        var current: Entity? = parent
        while let node = current {
            if node == ancestor { return true }
            current = node.parent
        }
        return false
    }
}
