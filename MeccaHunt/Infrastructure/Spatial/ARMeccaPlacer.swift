import ARKit
import RealityKit

/// Positions a Mecca entity in a compass-aligned AR scene so it always sits in
/// the real-world direction of a target coordinate, at the current GPS distance.
///
/// Re-pointing on every GPS update (rather than anchoring once) prevents a
/// single bad initial fix from placing the Mecca far away. Once the user is
/// within `freezeWithinMeters`, the Mecca is locked in place so they can walk
/// the last stretch and find it themselves.
@MainActor
final class ARMeccaPlacer {
    private(set) var meccaRoot: Entity?
    private var anchor: AnchorEntity?
    private var isCreating = false
    private var frozen = false

    /// - Parameters:
    ///   - bearingDegrees: Clockwise bearing from true north to the target.
    ///   - distanceMeters: Horizontal GPS distance to the target.
    ///   - freezeWithinMeters: Stop re-pointing once this close.
    func update(
        bearingDegrees: Double,
        distanceMeters: Double,
        freezeWithinMeters: Double,
        in arView: ARView
    ) {
        ensureEntity(in: arView)

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
                scale: SIMD3<Float>(repeating: 0.6),
                rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                translation: target
            ),
            relativeTo: nil,
            duration: 0.35
        )

        if distanceMeters <= freezeWithinMeters {
            frozen = true
        }
    }

    /// Whether a tapped entity is the Mecca (or part of it).
    func contains(_ entity: Entity) -> Bool {
        guard let meccaRoot else { return false }
        return entity == meccaRoot || entity.isDescendant(of: meccaRoot)
    }

    private func ensureEntity(in arView: ARView) {
        guard meccaRoot == nil, !isCreating else { return }
        isCreating = true

        let anchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(anchor)
        self.anchor = anchor

        Task { @MainActor [weak self] in
            let entity = await MeccaEntityFactory.make()
            entity.scale = [0.6, 0.6, 0.6]
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
