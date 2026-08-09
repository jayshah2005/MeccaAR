import Combine
import RealityKit
import UIKit

@MainActor
enum MeccaEntityFactory {
    /// Scale 1 is a 30 mm character; the placement default of 0.5 is 15 mm.
    static let referenceHeightMeters: Float = 0.03
    private static let faceOverlayName = "mecca-face-photo"
    private static var cachedTemplate: Entity?
    private static var loadTask: Task<Entity, Never>?

    static func make() async -> Entity {
        return await template().clone(recursive: true)
    }

    /// Warms the cached model template ahead of time so the first `make()` (e.g.
    /// when a Mecca comes into frame) only pays for a cheap clone, not the full
    /// asset load. Safe to call repeatedly; the load happens at most once.
    static func preload() async {
        _ = await template()
    }

    /// Returns the shared, prepared template, loading it once and caching it.
    private static func template() async -> Entity {
        if let cachedTemplate {
            return cachedTemplate
        }

        // Coalesce concurrent callers onto a single in-flight load so multiple
        // Meccas appearing at once don't each import the asset.
        if let loadTask {
            return await loadTask.value
        }

        let task = Task { () -> Entity in
            do {
                let imported = try await loadImportedModel()
                return prepare(imported)
            } catch {
                return makeProceduralFallback()
            }
        }
        loadTask = task
        let template = await task.value
        cachedTemplate = template
        loadTask = nil
        return template
    }

    private static func loadImportedModel() async throws -> Entity {
        for try await entity in Entity.loadAsync(
            named: "Mecca",
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
            model.materials = [
                SimpleMaterial(
                    color: color,
                    roughness: 0.82,
                    isMetallic: false
                )
            ]
            modelEntity.model = model
        }

        entity.children.forEach { child in
            applyColor(color, to: child)
        }
    }

    @discardableResult
    static func applyFacePhoto(_ image: UIImage?, to entity: Entity) -> Bool {
        entity.findEntity(named: faceOverlayName)?.removeFromParent()

        guard let cgImage = image?.cgImage,
              let texture = try? TextureResource.generate(
                  from: cgImage,
                  options: .init(semantic: .color)
              ) else {
            return false
        }

        let bounds = entity.visualBounds(relativeTo: entity)
        let height = bounds.extents.y
        guard height > 0.0001 else { return false }

        // This USDZ's arms extend above and in front of its head, so the full
        // bounds extrema are not the face. The imported mesh's local vertical
        // direction is inverted after its authoring transforms, placing the
        // head about 24% up from the prepared bounds minimum. Its front also
        // sits slightly behind the model's front-most geometry.
        let faceDiameter = height * 0.15
        let faceCenterY = bounds.min.y + (height * 0.24)
        let faceFrontZ = bounds.center.z + (bounds.extents.z * 0.40)
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
        faceOverlay.position = [
            bounds.center.x,
            faceCenterY,
            faceFrontZ + max(faceDiameter * 0.015, 0.00005)
        ]
        faceOverlay.orientation = simd_quatf(
            angle: .pi / 2,
            axis: [1, 0, 0]
        )
        entity.addChild(faceOverlay)
        return true
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
