import Combine
import RealityKit
import UIKit

struct MeccaPhotoPlacement: Equatable, Sendable {
    var horizontal: Float
    var vertical: Float

    /// Default UV for the character's face (upper front of the body), not the
    /// torso center. `vertical` is measured from the feet upward.
    static let faceDefault = MeccaPhotoPlacement(horizontal: 0.5, vertical: 0.88)

    /// Compatibility alias used by older call sites and the placement editor.
    static let initial = faceDefault

    var clamped: MeccaPhotoPlacement {
        MeccaPhotoPlacement(
            horizontal: min(max(horizontal, 0), 1),
            vertical: min(max(vertical, 0), 1)
        )
    }
}

@MainActor
enum MeccaEntityFactory {
    /// Scale 1 is a 30 mm character; the placement default is 25 mm.
    static let referenceHeightMeters: Float = 0.03
    private static let faceOverlayName = "mecca-face-photo"
    private static var cachedTemplates: [MeccaPose: Entity] = [:]
    private static var loadTasks: [MeccaPose: Task<Entity, Never>] = [:]

    static func make(pose: MeccaPose = .classic) async -> Entity {
        return await template(for: pose).clone(recursive: true)
    }

    /// Warms a cached pose template ahead of time so its first `make()` only
    /// pays for a cheap clone, not a full USDZ import.
    static func preload(pose: MeccaPose = .classic) async {
        _ = await template(for: pose)
    }

    /// Returns the shared, prepared template for a pose, loading it once.
    private static func template(for pose: MeccaPose) async -> Entity {
        if let cachedTemplate = cachedTemplates[pose] {
            return cachedTemplate
        }

        // Coalesce concurrent callers onto a single in-flight load so multiple
        // Meccas with the same pose don't each import the asset.
        if let loadTask = loadTasks[pose] {
            return await loadTask.value
        }

        let task = Task { () -> Entity in
            do {
                let imported = try await loadImportedModel(pose: pose)
                return prepare(imported)
            } catch {
                return makeProceduralFallback()
            }
        }
        loadTasks[pose] = task
        let template = await task.value
        cachedTemplates[pose] = template
        loadTasks[pose] = nil
        return template
    }

    private static func loadImportedModel(pose: MeccaPose) async throws -> Entity {
        for try await entity in Entity.loadAsync(
            named: pose.resourceName,
            in: .main
        ).values {
            return entity
        }

        throw ModelLoadError.noEntity
    }

    private static func prepare(_ imported: Entity) -> Entity {
        let root = Entity()
        root.name = "mecca"
        root.addChild(imported)

        // Sketchfab exports retain their authoring units and origin. Normalize
        // the visible bounds so placement code can use predictable real-world
        // sizes, and move the lowest point to the anchor plane.
        // This asset declares Y-up, but its longest/standing axis is +Z.
        imported.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        let bounds = imported.visualBounds(relativeTo: root)
        let height = bounds.extents.y
        if height > 0.0001 {
            let normalizationScale = referenceHeightMeters / height
            // Preserve RealityKit's scale for the USD stage's centimeters and
            // apply our normalization as a ratio. Replacing the imported scale
            // drops that unit conversion and makes this asset about 100x larger.
            imported.scale = imported.scale
                * SIMD3<Float>(repeating: normalizationScale)

            let lowestPoint = bounds.center.y - (height / 2)
            imported.position = [
                -bounds.center.x * normalizationScale,
                -lowestPoint * normalizationScale,
                -bounds.center.z * normalizationScale
            ]

            // A simple box is much cheaper than generating a convex collision
            // shape from this relatively dense prototype mesh.
            let collisionEntity = Entity()
            collisionEntity.name = "mecca-collision"
            collisionEntity.position = [0, referenceHeightMeters / 2, 0]
            collisionEntity.components.set(
                CollisionComponent(shapes: [
                    .generateBox(
                        size: [
                            max(bounds.extents.x * normalizationScale, 0.01),
                            referenceHeightMeters,
                            max(bounds.extents.z * normalizationScale, 0.01)
                        ]
                    )
                ])
            )
            root.addChild(collisionEntity)
        }

        return root
    }

    private static func makeProceduralFallback() -> Entity {
        let root = Entity()
        root.name = "mecca"
        let content = Entity()
        root.addChild(content)

        let white = SimpleMaterial(
            color: UIColor(white: 0.96, alpha: 1),
            roughness: 0.82,
            isMetallic: false
        )

        let head = ModelEntity(
            mesh: .generateSphere(radius: 0.055),
            materials: [white]
        )
        head.position = [0, 0.31, 0]
        content.addChild(head)

        addBox(
            to: content,
            size: [0.12, 0.16, 0.06],
            position: [0, 0.205, 0],
            material: white
        )

        addLimb(
            to: content,
            position: [-0.085, 0.205, 0],
            angle: 0.12,
            material: white
        )
        addLimb(
            to: content,
            position: [0.085, 0.205, 0],
            angle: -0.12,
            material: white
        )

        addBox(
            to: content,
            size: [0.045, 0.135, 0.05],
            position: [-0.033, 0.0675, 0],
            material: white
        )
        addBox(
            to: content,
            size: [0.045, 0.135, 0.05],
            position: [0.033, 0.0675, 0],
            material: white
        )

        let originalHeight: Float = 0.365
        let fallbackScale = referenceHeightMeters / originalHeight
        content.scale = SIMD3<Float>(repeating: fallbackScale)
        root.generateCollisionShapes(recursive: true)
        return root
    }

    /// The scale factor that renders a Mecca at the given real-world height.
    static func scale(forMillimeters millimeters: Double) -> Float {
        Float(millimeters / Double(referenceHeightMeters * 1_000))
    }

    /// Applies a saved appearance (size, rotation, color) to a Mecca entity so it
    /// looks identical wherever it is rendered. Pass `displayScale` to override
    /// the real-world size (e.g. to keep a distant GPS marker visible).
    static func apply(
        _ appearance: MeccaAppearance,
        to entity: Entity,
        displayScale: Float? = nil
    ) {
        let scale = displayScale ?? scale(forMillimeters: appearance.sizeMillimeters)
        entity.scale = [scale, scale, scale]

        let xRadians = Float(appearance.xRotationDegrees) * .pi / 180
        let yRadians = Float(appearance.yRotationDegrees) * .pi / 180
        entity.orientation =
            simd_quatf(angle: yRadians, axis: [0, 1, 0])
            * simd_quatf(angle: xRadians, axis: [1, 0, 0])

        applyColor(
            UIColor(
                red: CGFloat(appearance.red),
                green: CGFloat(appearance.green),
                blue: CGFloat(appearance.blue),
                alpha: 1
            ),
            to: entity
        )
    }

    static func applyColor(_ color: UIColor, to entity: Entity) {
        guard entity.name != faceOverlayName else { return }

        if let modelEntity = entity as? ModelEntity,
           var model = modelEntity.model {
            let tinted = SimpleMaterial(
                color: color,
                roughness: 0.82,
                isMetallic: false
            )
            // Recolor every material slot the mesh uses. Replacing the whole
            // array with a single material would leave multi-material meshes
            // only partially tinted (the source of the color picker glitch).
            if model.materials.isEmpty {
                model.materials = [tinted]
            } else {
                model.materials = Array(
                    repeating: tinted,
                    count: model.materials.count
                )
            }
            modelEntity.model = model
        }

        entity.children.forEach { child in
            applyColor(color, to: child)
        }
    }

    @discardableResult
    static func applyFacePhoto(
        _ image: UIImage?,
        placement: MeccaPhotoPlacement,
        to entity: Entity
    ) -> Bool {
        entity.findEntity(named: faceOverlayName)?.removeFromParent()

        guard let cgImage = image?.cgImage,
              let texture = try? TextureResource.generate(
                  from: cgImage,
                  options: .init(semantic: .color)
              ) else {
            return false
        }

        let bounds = entity.visualBounds(relativeTo: entity)
        let projection = PhotoProjection(bounds: bounds)
        guard projection.verticalExtent > 0.0001 else { return false }

        let selectedPlacement = placement.clamped
        // Face-sized disk: large enough to read, small enough to sit on the
        // head instead of covering the chest.
        let faceDiameter = projection.verticalExtent * 0.09
        var material = UnlitMaterial()
        material.baseColor = .texture(texture)
        if #available(iOS 18.0, *) {
            material.faceCulling = .none
        }
        let faceOverlay = ModelEntity(
            mesh: .generatePlane(
                width: faceDiameter,
                depth: faceDiameter,
                cornerRadius: faceDiameter / 2
            ),
            materials: [material]
        )
        faceOverlay.name = faceOverlayName
        faceOverlay.position = projection.position(
            for: selectedPlacement,
            surfaceOffset: max(faceDiameter * 0.02, 0.00005)
        )
        faceOverlay.orientation = projection.overlayOrientation
        entity.addChild(faceOverlay)
        return true
    }

    /// Places the photo on the detected head region when no owner UV exists.
    @discardableResult
    static func applyFacePhoto(_ image: UIImage?, to entity: Entity) -> Bool {
        applyFacePhoto(
            image,
            placement: facePlacement(on: entity),
            to: entity
        )
    }

    /// UV for the character head: prefer a named head/face mesh, otherwise the
    /// upper front of the overall bounds.
    static func facePlacement(on entity: Entity) -> MeccaPhotoPlacement {
        let bodyBounds = entity.visualBounds(relativeTo: entity)
        guard bodyBounds.extents.y > 0.0001 || bodyBounds.extents.z > 0.0001 else {
            return .faceDefault
        }

        if let headBounds = namedHeadBounds(in: entity, relativeTo: entity) {
            let projection = PhotoProjection(bounds: bodyBounds)
            let horizontalSpan = max(
                projection.horizontalAxis.value(in: bodyBounds.extents),
                0.0001
            )
            let verticalSpan = max(projection.verticalExtent, 0.0001)
            let headCenter = headBounds.center
            let horizontal = (
                projection.horizontalAxis.value(in: headCenter)
                    - projection.horizontalAxis.value(in: bodyBounds.min)
            ) / horizontalSpan
            let vertical = (
                projection.verticalAxis.value(in: headCenter)
                    - projection.verticalAxis.value(in: bodyBounds.min)
            ) / verticalSpan
            return MeccaPhotoPlacement(
                horizontal: horizontal,
                // Bias slightly upward within the head so the photo sits on the
                // face rather than the neck.
                vertical: min(vertical + 0.02, 0.97)
            ).clamped
        }

        return .faceDefault
    }

    private static func namedHeadBounds(
        in entity: Entity,
        relativeTo reference: Entity
    ) -> BoundingBox? {
        var best: BoundingBox?
        var stack: [Entity] = [entity]
        while let current = stack.popLast() {
            stack.append(contentsOf: current.children)
            let name = current.name.lowercased()
            guard name.contains("head") || name.contains("face") else {
                continue
            }
            let bounds = current.visualBounds(relativeTo: reference)
            guard bounds.extents.max() > 0.0001 else { continue }
            if let existing = best {
                // Prefer the highest head-like mesh when several match.
                if bounds.center.y >= existing.center.y {
                    best = bounds
                }
            } else {
                best = bounds
            }
        }
        return best
    }

    /// Rotates a clone into the exact front projection used by the drag editor.
    /// The placed AR entity is never passed here, so this does not change the
    /// user's X/Y rotation controls.
    static func preparePhotoPlacementPreview(_ entity: Entity) {
        let bounds = entity.visualBounds(relativeTo: entity)
        entity.orientation = PhotoProjection(bounds: bounds).previewOrientation
    }

    private struct PhotoProjection {
        let bounds: BoundingBox
        let horizontalAxis: ModelAxis
        let verticalAxis: ModelAxis
        let depthAxis: ModelAxis
        let frontSign: Float

        init(bounds: BoundingBox) {
            self.bounds = bounds

            // Some USDZ import paths leave this particular model standing on Y,
            // while others expose its authored Z standing axis. Detect the
            // longest visible dimension instead of hard-coding either layout.
            if bounds.extents.z > bounds.extents.y,
               bounds.extents.z > bounds.extents.x {
                horizontalAxis = .x
                verticalAxis = .z
                depthAxis = .y
                frontSign = -1
            } else if bounds.extents.y >= bounds.extents.x {
                horizontalAxis = .x
                verticalAxis = .y
                depthAxis = .z
                frontSign = 1
            } else {
                horizontalAxis = .z
                verticalAxis = .x
                depthAxis = .y
                frontSign = 1
            }
        }

        var verticalExtent: Float {
            verticalAxis.value(in: bounds.extents)
        }

        var overlayOrientation: simd_quatf {
            if verticalAxis == .y, depthAxis == .z, frontSign > 0 {
                let faceForward = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                let standUpright = simd_quatf(angle: .pi, axis: [0, 0, 1])
                return standUpright * faceForward
            }

            if verticalAxis == .z, depthAxis == .y, frontSign < 0 {
                return simd_quatf(angle: .pi, axis: [0, 0, 1])
            }

            let front = depthAxis.unitVector * frontSign
            let vertical = verticalAxis.unitVector
            let faceForward = simd_quatf(from: [0, 1, 0], to: front)
            let currentVertical = faceForward.act([0, 0, 1])
            let standUpright = simd_quatf(from: currentVertical, to: vertical)
            return standUpright * faceForward
        }

        var previewOrientation: simd_quatf {
            if verticalAxis == .y, depthAxis == .z, frontSign > 0 {
                return simd_quatf(angle: 0, axis: [0, 1, 0])
            }

            if verticalAxis == .z, depthAxis == .y, frontSign < 0 {
                return simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            }

            return simd_quatf(from: verticalAxis.unitVector, to: [0, 1, 0])
        }

        func position(
            for placement: MeccaPhotoPlacement,
            surfaceOffset: Float
        ) -> SIMD3<Float> {
            var result = bounds.center
            let horizontal = horizontalAxis.value(in: bounds.min)
                + horizontalAxis.value(in: bounds.extents) * placement.horizontal
            let vertical = verticalAxis.value(in: bounds.min)
                + verticalAxis.value(in: bounds.extents) * placement.vertical
            let depth = depthAxis.value(in: bounds.center)
                + frontSign * (
                    depthAxis.value(in: bounds.extents) / 2 + surfaceOffset
                )
            horizontalAxis.set(horizontal, in: &result)
            verticalAxis.set(vertical, in: &result)
            depthAxis.set(depth, in: &result)
            return result
        }
    }

    private enum ModelAxis: Equatable {
        case x
        case y
        case z

        var unitVector: SIMD3<Float> {
            switch self {
            case .x: return [1, 0, 0]
            case .y: return [0, 1, 0]
            case .z: return [0, 0, 1]
            }
        }

        func value(in vector: SIMD3<Float>) -> Float {
            switch self {
            case .x: return vector.x
            case .y: return vector.y
            case .z: return vector.z
            }
        }

        func set(_ value: Float, in vector: inout SIMD3<Float>) {
            switch self {
            case .x: vector.x = value
            case .y: vector.y = value
            case .z: vector.z = value
            }
        }
    }

    private static func addLimb(
        to root: Entity,
        position: SIMD3<Float>,
        angle: Float,
        material: SimpleMaterial
    ) {
        let limb = ModelEntity(
            mesh: .generateBox(size: [0.035, 0.14, 0.04]),
            materials: [material]
        )
        limb.position = position
        limb.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
        root.addChild(limb)
    }

    private static func addBox(
        to root: Entity,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        material: SimpleMaterial
    ) {
        let box = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [material]
        )
        box.position = position
        root.addChild(box)
    }

    private enum ModelLoadError: Error {
        case noEntity
    }
}
