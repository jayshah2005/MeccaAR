import ARKit
import RealityKit
import SwiftUI
import UIKit

struct PlacementView: View {
    @Environment(AppState.self) private var appState
    @State private var placementCount = 0
    @State private var resetToken = 0
    @State private var message = "Move slowly so the camera can find a surface"
    @State private var sizeScale = 0.55
    @State private var rotationDegrees = 0.0
    @State private var pose = MeccaPose.standing
    @State private var tintColor = Color.white

    private var configuration: MeccaPlacementConfiguration {
        MeccaPlacementConfiguration(
            sizeScale: Float(sizeScale),
            rotationDegrees: Float(rotationDegrees),
            pose: pose,
            tint: MeccaTint(color: tintColor)
        )
    }

    var body: some View {
        ZStack {
            PlacementARView(
                placementCount: $placementCount,
                resetToken: resetToken,
                message: $message,
                configuration: configuration
            )
            .ignoresSafeArea()

            Crosshair()

            VStack(spacing: 16) {
                HStack {
                    Button {
                        appState.route = .home
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.68))
                    .accessibilityLabel("Return home")

                    Spacer()

                    Label("PLACE MODE", systemImage: "arkit")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(.mint.opacity(0.92), in: Capsule())
                        .foregroundStyle(.black)
                }

                Spacer()

                VStack(spacing: 10) {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Aim the reticle at a floor, table, wall, or other flat surface, then tap the camera view.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack {
                        Label("\(placementCount) placed", systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.bold))

                        Spacer()

                        if placementCount > 0 {
                            Button("Clear", systemImage: "trash") {
                                resetToken += 1
                                placementCount = 0
                                message = "Cleared — tap a surface to place another Mecca"
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    MeccaPlacementControls(
                        sizeScale: $sizeScale,
                        rotationDegrees: $rotationDegrees,
                        pose: $pose,
                        tintColor: $tintColor
                    )

                    if placementCount > 0 {
                        Text("Controls are editing the most recently placed Mecca.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}

private enum MeccaPose: String, CaseIterable, Identifiable {
    case standing = "Stand"
    case sleeping = "Sleep"

    var id: Self { self }
}

private struct MeccaPlacementConfiguration: Equatable {
    let sizeScale: Float
    let rotationDegrees: Float
    let pose: MeccaPose
    let tint: MeccaTint
}

private struct MeccaTint: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1

        if uiColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) {
            self.red = Double(red)
            self.green = Double(green)
            self.blue = Double(blue)
        } else {
            var white: CGFloat = 1
            uiColor.getWhite(&white, alpha: &alpha)
            self.red = Double(white)
            self.green = Double(white)
            self.blue = Double(white)
        }
    }

    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: 1
        )
    }
}

private struct MeccaPlacementControls: View {
    @Binding var sizeScale: Double
    @Binding var rotationDegrees: Double
    @Binding var pose: MeccaPose
    @Binding var tintColor: Color

    private var approximateHeight: Int {
        Int((36 * sizeScale).rounded())
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Pose", selection: $pose) {
                ForEach(MeccaPose.allCases) { pose in
                    Text(pose.rawValue).tag(pose)
                }
            }
            .pickerStyle(.segmented)

            ColorPicker(
                "Mecca color",
                selection: $tintColor,
                supportsOpacity: false
            )
            .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.caption2)

                Slider(value: $sizeScale, in: 0.25...1.0, step: 0.05)
                    .accessibilityLabel("Mecca size")
                    .accessibilityValue("Approximately \(approximateHeight) centimeters")

                Image(systemName: "person.fill")

                Text("~\(approximateHeight) cm")
                    .font(.caption.monospacedDigit())
                    .frame(width: 48, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Image(systemName: "rotate.left")

                Slider(value: $rotationDegrees, in: 0...360, step: 15)
                    .accessibilityLabel("Mecca rotation")
                    .accessibilityValue("\(Int(rotationDegrees)) degrees")

                Text("\(Int(rotationDegrees))°")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }
}

private struct Crosshair: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
                .frame(width: 34, height: 34)
            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
        }
        .shadow(color: .black.opacity(0.75), radius: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PlacementARView: UIViewRepresentable {
    @Binding var placementCount: Int
    let resetToken: Int
    @Binding var message: String
    let configuration: MeccaPlacementConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.placeMecca(_:))
        )
        arView.addGestureRecognizer(tap)

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
        ])

        context.coordinator.runSession()
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.clearIfNeeded(resetToken: resetToken)
        context.coordinator.applyConfigurationToLatestMecca()
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        arView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PlacementARView
        weak var arView: ARView?

        private struct PlacedMecca {
            let anchor: AnchorEntity
            let entity: Entity
            let surfaceOrientation: simd_quatf
        }

        private var placedMeccas: [PlacedMecca] = []
        private var lastResetToken: Int
        private var lastAppliedConfiguration: MeccaPlacementConfiguration?

        init(_ parent: PlacementARView) {
            self.parent = parent
            lastResetToken = parent.resetToken
        }

        func runSession() {
            guard let arView else { return }

            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.environmentTexturing = .automatic

            arView.session.run(
                configuration,
                options: [.resetTracking, .removeExistingAnchors]
            )
        }

        @objc
        func placeMecca(_: UITapGestureRecognizer) {
            guard let arView else { return }

            let point = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let result = arView.raycast(
                from: point,
                allowing: .estimatedPlane,
                alignment: .any
            ).first else {
                parent.message = "No surface found yet — keep scanning and try again"
                return
            }

            // Keep the character upright in gravity-aligned world space even
            // when the raycast hits a vertical plane. The hit transform's Y
            // axis is still used as the surface normal to avoid wall clipping.
            var anchorTransform = matrix_identity_float4x4
            anchorTransform.columns.3 = result.worldTransform.columns.3
            let surfaceNormal = SIMD3<Float>(
                result.worldTransform.columns.1.x,
                result.worldTransform.columns.1.y,
                result.worldTransform.columns.1.z
            )
            let normalizedNormal = simd_length(surfaceNormal) > 0
                ? simd_normalize(surfaceNormal)
                : SIMD3<Float>(0, 1, 0)

            anchorTransform.columns.3.x += normalizedNormal.x * 0.015
            anchorTransform.columns.3.y += normalizedNormal.y * 0.015
            anchorTransform.columns.3.z += normalizedNormal.z * 0.015

            let anchor = AnchorEntity(world: anchorTransform)
            let surfaceOrientation = Self.orientation(from: result.worldTransform)
            let placementConfiguration = parent.configuration
            parent.message = "Loading Mecca…"

            Task { @MainActor [weak self] in
                guard let self, let arView = self.arView else { return }

                let entity = await MeccaEntityFactory.make()
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)

                let placedMecca = PlacedMecca(
                    anchor: anchor,
                    entity: entity,
                    surfaceOrientation: surfaceOrientation
                )
                self.placedMeccas.append(placedMecca)
                self.apply(placementConfiguration, to: placedMecca)
                self.lastAppliedConfiguration = placementConfiguration

                self.parent.placementCount += 1
                self.parent.message = "Mecca placed in this AR session"
            }
        }

        func clearIfNeeded(resetToken: Int) {
            guard resetToken != lastResetToken else { return }
            placedMeccas.forEach { $0.anchor.removeFromParent() }
            placedMeccas.removeAll()
            lastResetToken = resetToken
            lastAppliedConfiguration = nil
        }

        func applyConfigurationToLatestMecca() {
            let configuration = parent.configuration
            guard configuration != lastAppliedConfiguration else { return }
            if let latest = placedMeccas.last {
                apply(configuration, to: latest)
            }
            lastAppliedConfiguration = configuration
        }

        private func apply(
            _ configuration: MeccaPlacementConfiguration,
            to placedMecca: PlacedMecca
        ) {
            let scale = configuration.sizeScale
            placedMecca.entity.scale = [scale, scale, scale]
            MeccaEntityFactory.applyColor(
                configuration.tint.uiColor,
                to: placedMecca.entity
            )

            let radians = configuration.rotationDegrees * .pi / 180
            switch configuration.pose {
            case .standing:
                placedMecca.entity.orientation = simd_quatf(
                    angle: radians,
                    axis: [0, 1, 0]
                )
            case .sleeping:
                let surfaceSpin = simd_quatf(
                    angle: radians,
                    axis: [0, 1, 0]
                )
                let lieFlat = simd_quatf(
                    angle: .pi / 2,
                    axis: [1, 0, 0]
                )
                placedMecca.entity.orientation =
                    placedMecca.surfaceOrientation * surfaceSpin * lieFlat
            }
        }

        private static func orientation(
            from transform: simd_float4x4
        ) -> simd_quatf {
            let rotation = simd_float3x3(
                SIMD3<Float>(
                    transform.columns.0.x,
                    transform.columns.0.y,
                    transform.columns.0.z
                ),
                SIMD3<Float>(
                    transform.columns.1.x,
                    transform.columns.1.y,
                    transform.columns.1.z
                ),
                SIMD3<Float>(
                    transform.columns.2.x,
                    transform.columns.2.y,
                    transform.columns.2.z
                )
            )
            return simd_quatf(rotation)
        }
    }
}
