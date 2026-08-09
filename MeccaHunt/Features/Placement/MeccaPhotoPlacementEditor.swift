import RealityKit
import SwiftUI
import UIKit

struct MeccaPhotoPlacementEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let tintColor: Color
    let pose: MeccaPose
    let onSave: (MeccaPhotoPlacement) -> Void

    @State private var placement: MeccaPhotoPlacement
    @State private var previewAspectRatio: CGFloat = 0.5

    private let modelMargin: CGFloat = 0.065

    init(
        image: UIImage,
        tintColor: Color,
        pose: MeccaPose,
        initialPlacement: MeccaPhotoPlacement,
        onSave: @escaping (MeccaPhotoPlacement) -> Void
    ) {
        self.image = image
        self.tintColor = tintColor
        self.pose = pose
        self.onSave = onSave
        _placement = State(initialValue: initialPlacement.clamped)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Place your face on the Mecca")
                        .font(.headline)
                    Text("Drag the photo onto the head, then tap Done.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                GeometryReader { proxy in
                    let aspect = min(max(previewAspectRatio, 0.35), 0.8)
                    let canvasWidth = min(
                        proxy.size.width,
                        proxy.size.height * aspect
                    )
                    let canvasHeight = canvasWidth / aspect

                    placementCanvas(
                        size: CGSize(width: canvasWidth, height: canvasHeight)
                    )
                    .frame(width: canvasWidth, height: canvasHeight)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }

                HStack {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            placement = .faceDefault
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("Touch or drag to reposition")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Position Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(placement.clamped)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private func placementCanvas(size: CGSize) -> some View {
        let contentWidth = size.width * (1 - modelMargin * 2)
        let contentHeight = size.height * (1 - modelMargin * 2)
        let photoDiameter = size.height * 0.09
        let photoX = size.width * modelMargin
            + CGFloat(placement.horizontal) * contentWidth
        let photoY = size.height * modelMargin
            + CGFloat(1 - placement.vertical) * contentHeight

        return ZStack {
            MeccaFullBodyPreview(
                tintColor: UIColor(tintColor),
                pose: pose,
                aspectRatio: $previewAspectRatio
            )

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: photoDiameter, height: photoDiameter)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.mint, lineWidth: 3)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                }
                .position(x: photoX, y: photoY)
                .allowsHitTesting(false)
        }
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let horizontal = (
                        value.location.x - size.width * modelMargin
                    ) / max(contentWidth, 1)
                    let verticalFromTop = (
                        value.location.y - size.height * modelMargin
                    ) / max(contentHeight, 1)
                    placement = MeccaPhotoPlacement(
                        horizontal: Float(min(max(horizontal, 0), 1)),
                        vertical: Float(1 - min(max(verticalFromTop, 0), 1))
                    )
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mecca photo position editor")
        .accessibilityValue(
            "Horizontal \(Int(placement.horizontal * 100)) percent, vertical \(Int(placement.vertical * 100)) percent"
        )
    }
}

private struct MeccaFullBodyPreview: UIViewRepresentable {
    let tintColor: UIColor
    let pose: MeccaPose
    @Binding var aspectRatio: CGFloat

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

        context.coordinator.loadTask = Task { @MainActor [weak arView] in
            guard let arView else { return }

            let entity = await MeccaEntityFactory.make(pose: pose)
            MeccaEntityFactory.applyColor(tintColor, to: entity)
            MeccaEntityFactory.preparePhotoPlacementPreview(entity)
            entity.scale = SIMD3<Float>(repeating: 10)

            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            let bounds = entity.visualBounds(relativeTo: anchor)
            guard bounds.extents.y > 0.0001 else { return }

            let measuredAspect = CGFloat(bounds.extents.x / bounds.extents.y)
            aspectRatio = min(max(measuredAspect, 0.35), 0.8)

            let fieldOfView: Float = 35
            let halfHeight = bounds.extents.y * 0.58
            let distance = halfHeight
                / tan(fieldOfView * .pi / 360)
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
            light.light.intensity = 2_500
            anchor.addChild(light)
            light.look(
                at: bounds.center,
                from: cameraPosition,
                relativeTo: anchor
            )
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        coordinator.loadTask = nil
    }

    final class Coordinator {
        var loadTask: Task<Void, Never>?
    }
}
