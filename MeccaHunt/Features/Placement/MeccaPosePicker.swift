import RealityKit
import SwiftUI
import UIKit

/// Horizontal carousel of live 3D pose thumbnails so players pick by look,
/// not by opaque pose numbers.
struct MeccaPosePicker: View {
    @Binding var pose: MeccaPose
    var tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pose")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(pose.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MeccaPose.allCases) { candidate in
                        PoseThumbnailCard(
                            pose: candidate,
                            tintColor: tintColor,
                            isSelected: candidate == pose
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                pose = candidate
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mecca pose")
    }
}

private struct PoseThumbnailCard: View {
    let pose: MeccaPose
    let tintColor: Color
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                MeccaPoseThumbnail(
                    pose: pose,
                    tintColor: UIColor(tintColor)
                )
                .frame(width: 72, height: 96)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.mint : Color.white.opacity(0.18),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .shadow(
                    color: isSelected ? .mint.opacity(0.35) : .clear,
                    radius: 6,
                    y: 2
                )

                Text(pose.displayName)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .mint : .secondary)
                    .lineLimit(1)
                    .frame(width: 76)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pose.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Compact non-AR RealityKit preview of a single pose for the picker strip.
struct MeccaPoseThumbnail: UIViewRepresentable {
    let pose: MeccaPose
    let tintColor: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        arView.isUserInteractionEnabled = false
        arView.environment.background = .color(.clear)
        context.coordinator.hostPose = pose
        context.coordinator.reload(in: arView, pose: pose, tint: tintColor)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if context.coordinator.hostPose != pose {
            context.coordinator.hostPose = pose
            context.coordinator.reload(in: uiView, pose: pose, tint: tintColor)
            return
        }
        context.coordinator.applyTint(tintColor)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    final class Coordinator {
        var hostPose: MeccaPose?
        var loadTask: Task<Void, Never>?
        private weak var meccaEntity: Entity?

        func cancel() {
            loadTask?.cancel()
            loadTask = nil
            meccaEntity = nil
        }

        @MainActor
        func applyTint(_ tint: UIColor) {
            guard let meccaEntity else { return }
            MeccaEntityFactory.applyColor(tint, to: meccaEntity)
        }

        @MainActor
        func reload(in arView: ARView, pose: MeccaPose, tint: UIColor) {
            loadTask?.cancel()
            arView.scene.anchors.removeAll()
            meccaEntity = nil

            loadTask = Task { @MainActor [weak self, weak arView] in
                guard let self, let arView else { return }
                let entity = await MeccaEntityFactory.make(pose: pose)
                guard !Task.isCancelled, self.hostPose == pose else { return }

                MeccaEntityFactory.applyColor(tint, to: entity)
                MeccaEntityFactory.preparePhotoPlacementPreview(entity)
                entity.scale = SIMD3<Float>(repeating: 8)

                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)
                self.meccaEntity = entity

                let bounds = entity.visualBounds(relativeTo: anchor)
                guard bounds.extents.y > 0.0001 else { return }

                let fieldOfView: Float = 32
                let halfHeight = bounds.extents.y * 0.62
                let distance = halfHeight / tan(fieldOfView * .pi / 360)
                    + bounds.extents.z / 2
                let cameraPosition = SIMD3<Float>(
                    bounds.center.x,
                    bounds.center.y,
                    bounds.max.z + distance
                )

                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = fieldOfView
                anchor.addChild(camera)
                camera.look(
                    at: bounds.center,
                    from: cameraPosition,
                    relativeTo: anchor
                )

                let light = DirectionalLight()
                light.light.intensity = 2_400
                anchor.addChild(light)
                light.look(
                    at: bounds.center,
                    from: cameraPosition,
                    relativeTo: anchor
                )
            }
        }
    }
}
