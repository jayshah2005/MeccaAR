import RealityKit
import UIKit

enum MeccaEntityFactory {
    static func make() -> Entity {
        let root = Entity()
        root.name = "mecca"

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
        root.addChild(head)

        addBox(
            to: root,
            size: [0.12, 0.16, 0.06],
            position: [0, 0.205, 0],
            material: white
        )

        addLimb(
            to: root,
            position: [-0.085, 0.205, 0],
            angle: 0.12,
            material: white
        )
        addLimb(
            to: root,
            position: [0.085, 0.205, 0],
            angle: -0.12,
            material: white
        )

        addBox(
            to: root,
            size: [0.045, 0.135, 0.05],
            position: [-0.033, 0.0675, 0],
            material: white
        )
        addBox(
            to: root,
            size: [0.045, 0.135, 0.05],
            position: [0.033, 0.0675, 0],
            material: white
        )

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
}
