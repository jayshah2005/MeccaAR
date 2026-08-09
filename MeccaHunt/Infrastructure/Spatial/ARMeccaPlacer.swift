import ARKit
import RealityKit
import UIKit

/// Positions a Mecca entity in a compass-aligned AR scene so it always sits in
/// the real-world direction of a target coordinate, at the current GPS distance.
///
/// Re-pointing on every GPS update (rather than anchoring once) prevents a
/// single bad initial fix from placing the Mecca far away. Once the user is
/// within `freezeWithinMeters`, the Mecca is locked in place so they can walk
/// the last stretch and find it themselves.
@MainActor
final class ARMeccaPlacer {
    /// A distant GPS marker is scaled up from its real (mm) size so it stays
    /// visible from several metres away; color and rotation still match.
    private static let displayScale: Float = 0.6

    private(set) var meccaRoot: Entity?
    private var anchor: AnchorEntity?
    private var isCreating = false
    private var frozen = false
    private var appearance: MeccaAppearance = .default
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
    ///   - freezeWithinMeters: Stop re-pointing once this close.
    ///   - appearance: The owner's saved color/size/rotation for the Mecca.
    func update(
        bearingDegrees: Double,
        distanceMeters: Double,
        freezeWithinMeters: Double,
        appearance: MeccaAppearance = .default,
        facePhoto: UIImage? = nil,
        in arView: ARView
    ) {
        self.appearance = appearance
        self.facePhoto = facePhoto
        ensureEntity(in: arView)
        applyFacePhotoIfNeeded()

        guard
            let meccaRoot,
            !frozen,
            let frame = arView.session.currentFrame
        else { return }

        // Compass-aligned world (gravityAndHeading): +x east, +z south, so
        // north is -z. Place relative to where the camera is right now.
        let camera = frame.camera.transform.columns.3
        let theta = Float(bearingDegrees * .pi / 180)
        let distance = Float(max(distanceMeters, 1.2))
        let direction = SIMD3<Float>(sin(theta), 0, -cos(theta))
        let target = SIMD3<Float>(
            camera.x + direction.x * distance,
            camera.y - 0.8,
            camera.z + direction.z * distance
        )

        meccaRoot.move(
            to: Transform(
                scale: SIMD3<Float>(repeating: Self.displayScale),
                rotation: appearanceOrientation,
                translation: target
            ),
            relativeTo: nil,
            duration: 0.35
        )

        if distanceMeters <= freezeWithinMeters {
            frozen = true
        }
    }

    /// Places the Mecca relative to the live camera using true-north bearing and
    /// the device's compass heading. Works in any AR world alignment (including
    /// world-map relocalization sessions that use `.gravity` instead of
    /// `.gravityAndHeading`), so hunters get a guide Mecca while scanning to lock on.
    func updateCameraRelative(
        targetBearingDegrees: Double,
        deviceHeadingDegrees: Double,
        distanceMeters: Double,
        freezeWithinMeters: Double,
        appearance: MeccaAppearance = .default,
        facePhoto: UIImage? = nil,
        in arView: ARView
    ) {
        self.appearance = appearance
        self.facePhoto = facePhoto
        ensureEntity(in: arView)
        applyFacePhotoIfNeeded()

        guard
            let meccaRoot,
            !frozen,
            let frame = arView.session.currentFrame
        else { return }

        let cameraTransform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        // Relative bearing from the way the phone is facing to the target.
        var relative = targetBearingDegrees - deviceHeadingDegrees
        while relative > 180 { relative -= 360 }
        while relative < -180 { relative += 360 }
        let theta = Float(relative * .pi / 180)

        // Camera forward projected onto the ground, then yawed by relative bearing.
        var forward = -SIMD3<Float>(
            cameraTransform.columns.2.x,
            0,
            cameraTransform.columns.2.z
        )
        if simd_length(forward) < 0.001 {
            forward = SIMD3<Float>(0, 0, -1)
        } else {
            forward = simd_normalize(forward)
        }
        let right = SIMD3<Float>(forward.z, 0, -forward.x)
        let direction = simd_normalize(
            forward * cos(theta) + right * sin(theta)
        )

        let distance = Float(max(distanceMeters, 1.2))
        let target = cameraPosition + direction * distance
            - SIMD3<Float>(0, 0.8, 0)

        meccaRoot.move(
            to: Transform(
                scale: SIMD3<Float>(repeating: Self.displayScale),
                rotation: appearanceOrientation,
                translation: target
            ),
            relativeTo: nil,
            duration: 0.35
        )

        if distanceMeters <= freezeWithinMeters {
            frozen = true
        }
    }

    /// Removes the guide Mecca (e.g. once precise relocalization has locked on).
    func clear() {
        anchor?.removeFromParent()
        anchor = nil
        meccaRoot = nil
        frozen = false
        isCreating = false
        appliedFacePhotoIdentity = nil
    }

    /// Whether a tapped entity is the Mecca (or part of it).
    func contains(_ entity: Entity) -> Bool {
        guard let meccaRoot else { return false }
        return entity == meccaRoot || entity.isDescendant(of: meccaRoot)
    }

    private func applyFacePhotoIfNeeded() {
        guard let meccaRoot else { return }
        let identity = facePhoto.map(ObjectIdentifier.init)
        guard identity != appliedFacePhotoIdentity else { return }
        _ = MeccaEntityFactory.applyFacePhoto(facePhoto, to: meccaRoot)
        appliedFacePhotoIdentity = identity
    }

    private func ensureEntity(in arView: ARView) {
        guard meccaRoot == nil, !isCreating else { return }
        isCreating = true

        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        self.anchor = anchor

        Task { @MainActor [weak self] in
            let entity = await MeccaEntityFactory.make()
            let appearance = self?.appearance ?? .default
            MeccaEntityFactory.apply(
                appearance,
                to: entity,
                displayScale: Self.displayScale
            )
            if let facePhoto = self?.facePhoto {
                _ = MeccaEntityFactory.applyFacePhoto(facePhoto, to: entity)
                self?.appliedFacePhotoIdentity = ObjectIdentifier(facePhoto)
            }
            anchor.addChild(entity)
            self?.meccaRoot = entity
            self?.isCreating = false
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
