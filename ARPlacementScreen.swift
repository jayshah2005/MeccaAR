import ARKit
import RealityKit
import SwiftUI

struct ARPlacementScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var placementCount = 0

    var body: some View {
        ZStack {
            ARViewContainer(drawing: model.drawing, placementCount: $placementCount)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        model.mode = .draw
                        model.status = "Edit your drawing, then place it again"
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.65))

                    Spacer()

                    Text("Tap a detected surface")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.65), in: Capsule())
                }
                Spacer()
                VStack(spacing: 10) {
                    Label("\(placementCount) placed", systemImage: "mappin.and.ellipse")
                        .font(.caption.bold())
                    Button("Draw something new", action: model.startOver)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            }
            .padding()
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let drawing: Drawing
    @Binding var placementCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        context.coordinator.arView = view
        view.automaticallyConfigureSession = false
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:))))
        context.coordinator.startSession()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        weak var arView: ARView?
        private var drawings: [String: Drawing] = [:]
        private var renderedAnchors = Set<UUID>()

        init(_ parent: ARViewContainer) {
            self.parent = parent
            if let data = UserDefaults.standard.data(forKey: "savedDrawings"),
               let decoded = try? JSONDecoder().decode([String: Drawing].self, from: data) {
                drawings = decoded
            }
        }

        func startSession() {
            guard let arView else { return }
            arView.session.delegate = self
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.environmentTexturing = .automatic

            if let data = try? Data(contentsOf: worldMapURL),
               let map = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) {
                configuration.initialWorldMap = map
            }
            arView.session.run(configuration)
        }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = recognizer.location(in: arView)
            guard let result = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first else { return }

            let key = UUID().uuidString
            let anchor = ARAnchor(name: "streetsketch:\(key)", transform: result.worldTransform)
            drawings[key] = parent.drawing
            persistDrawings()
            arView.session.add(anchor: anchor)
            parent.placementCount += 1
            saveWorldMap()
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let arView else { return }
            for anchor in anchors {
                guard let name = anchor.name,
                      name.hasPrefix("streetsketch:"),
                      !renderedAnchors.contains(anchor.identifier) else { continue }
                let key = String(name.dropFirst("streetsketch:".count))
                guard let drawing = drawings[key] else { continue }
                renderedAnchors.insert(anchor.identifier)
                let anchorEntity = AnchorEntity(anchor: anchor)
                anchorEntity.addChild(Self.makeDrawingEntity(drawing))
                arView.scene.addAnchor(anchorEntity)
            }
        }

        private static func makeDrawingEntity(_ drawing: Drawing) -> Entity {
            let root = Entity()
            let material = SimpleMaterial(
                color: UIColor(red: CGFloat(drawing.color.red), green: CGFloat(drawing.color.green), blue: CGFloat(drawing.color.blue), alpha: 1),
                isMetallic: false
            )
            let scale: Float = 0.45
            for stroke in drawing.strokes {
                for pair in zip(stroke, stroke.dropFirst()) {
                    let a = SIMD3<Float>((pair.0.x - 0.5) * scale, (0.5 - pair.0.y) * scale, 0)
                    let b = SIMD3<Float>((pair.1.x - 0.5) * scale, (0.5 - pair.1.y) * scale, 0)
                    let delta = b - a
                    let length = simd_length(delta)
                    guard length > 0.001 else { continue }
                    let thickness: Float = 0.012
                    let segment = ModelEntity(
                        mesh: .generateBox(size: SIMD3<Float>(thickness, length, thickness)),
                        materials: [material]
                    )
                    segment.position = (a + b) / 2
                    segment.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
                    root.addChild(segment)
                }
            }
            root.position.z = 0.015
            return root
        }

        private func persistDrawings() {
            if let data = try? JSONEncoder().encode(drawings) {
                UserDefaults.standard.set(data, forKey: "savedDrawings")
            }
        }

        private func saveWorldMap() {
            arView?.session.getCurrentWorldMap { map, _ in
                guard let map,
                      let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) else { return }
                try? data.write(to: self.worldMapURL, options: .atomic)
            }
        }

        private var worldMapURL: URL {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appendingPathComponent("StreetSketchWorldMap.data")
        }
    }
}
