import Combine
import RealityKit
import UIKit

@MainActor
enum MeccaEntityFactory {
    /// Scale 1 is a 30 mm character; the placement default of 0.5 is 15 mm.
    static let referenceHeightMeters: Float = 0.03
    private static var cachedTemplate: Entity?

    static func make() async -> Entity {
        if let cachedTemplate {
            return cachedTemplate.clone(recursive: true)
        }

        let template: Entity
        do {
            let imported = try await loadImportedModel()
            template = prepare(imported)
        } catch {
            template = makeProceduralFallback()
        }

        cachedTemplate = template
        return template.clone(recursive: true)
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

    static func applyColor(_ color: UIColor, to entity: Entity) {
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
