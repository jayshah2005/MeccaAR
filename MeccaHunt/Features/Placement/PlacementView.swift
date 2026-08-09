import ARKit
import RealityKit
import SwiftUI
import UIKit

struct PlacementView: View {
    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location
    @State private var placementCount = 0
    @State private var resetToken = 0
    @State private var message = "Move slowly so the camera can find a surface"
    @State private var sizeMillimeters = 25.0
    @State private var xRotationDegrees = 0.0
    @State private var yRotationDegrees = 0.0
    @State private var tintColor = Color.white
    @State private var isToolbarMinimized = false
    @State private var meccaName = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var didSave = false
    @State private var alreadyPlacedToday = false

    private var configuration: MeccaPlacementConfiguration {
        let referenceMillimeters = Double(MeccaEntityFactory.referenceHeightMeters * 1_000)
        return MeccaPlacementConfiguration(
            sizeScale: Float(sizeMillimeters / referenceMillimeters),
            xRotationDegrees: Float(xRotationDegrees),
            yRotationDegrees: Float(yRotationDegrees),
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
                        location.stop()
                        appState.route = .map
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.68))
                    .accessibilityLabel("Return to map")

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
                    HStack(spacing: 12) {
                        if isToolbarMinimized {
                            Label(
                                "\(placementCount) placed",
                                systemImage: "mappin.and.ellipse"
                            )
                            .font(.caption.weight(.bold))
                        } else {
                            Text(message)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isToolbarMinimized.toggle()
                            }
                        } label: {
                            Image(
                                systemName: isToolbarMinimized
                                    ? "chevron.up"
                                    : "chevron.down"
                            )
                            .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(
                            isToolbarMinimized
                                ? "Expand placement toolbar"
                                : "Minimize placement toolbar"
                        )
                    }

                    if !isToolbarMinimized {
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
                            sizeMillimeters: $sizeMillimeters,
                            xRotationDegrees: $xRotationDegrees,
                            yRotationDegrees: $yRotationDegrees,
                            tintColor: $tintColor
                        )

                        if placementCount > 0 {
                            Text("Controls are editing the most recently placed Mecca.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Divider()

                            saveSection
                        } else if alreadyPlacedToday {
                            Divider()
                            dailyLimitNote
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding()

            if didSave {
                savedOverlay
            }
        }
        .preferredColorScheme(.dark)
        .task {
            location.start()
            await checkDailyLimit()
        }
    }

    @ViewBuilder
    private var saveSection: some View {
        if alreadyPlacedToday {
            dailyLimitNote
        } else {
            VStack(spacing: 10) {
                TextField("Name this Mecca", text: $meccaName)
                    .textInputAutocapitalization(.words)
                    .padding(10)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                Label(
                    "Hold your phone right where the Mecca is and keep still while saving — this records its exact spot.",
                    systemImage: "hand.raised.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                accuracyLabel

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Button(action: save) {
                    HStack {
                        if isSaving { ProgressView().tint(.black) }
                        Text(isSaving ? "Locking GPS — hold still…" : "Save to map")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .disabled(isSaving || location.currentLocation == nil)
            }
        }
    }

    @ViewBuilder
    private var accuracyLabel: some View {
        if let accuracy = location.horizontalAccuracy {
            let tint: Color = accuracy <= 10 ? .mint : (accuracy <= 25 ? .yellow : .orange)
            Label("GPS accuracy ±\(Int(accuracy.rounded())) m", systemImage: "dot.scope")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label("Waiting for GPS fix…", systemImage: "location.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dailyLimitNote: some View {
        Label(
            "You've already hidden a Mecca today. Come back tomorrow!",
            systemImage: "clock.badge.exclamationmark"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savedOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.mint)
                Text("Mecca hidden!")
                    .font(.largeTitle.bold())
                Text("It's now on the map for other hunters to find.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Back to map") {
                    location.stop()
                    appState.route = .map
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(.mint)
            }
            .padding(32)
        }
    }

    /// Usernames that are allowed to hide unlimited Meccas per day.
    private static let dailyLimitExemptUsernames: Set<String> = ["jay", "loic"]

    private var isDailyLimitExempt: Bool {
        guard let name = appState.currentUser?.username.lowercased() else { return false }
        return Self.dailyLimitExemptUsernames.contains(name)
    }

    private func checkDailyLimit() async {
        guard let owner = appState.currentUser else { return }
        if isDailyLimitExempt {
            alreadyPlacedToday = false
            return
        }
        let dayStart = Calendar.current.startOfDay(for: Date())
        if let last = try? await appState.dependencies.meccas.lastPlacement(ownerID: owner.id) {
            alreadyPlacedToday = last >= dayStart
            if alreadyPlacedToday {
                message = "You've already hidden a Mecca today."
            }
        }
    }

    private func save() {
        guard !isSaving, !alreadyPlacedToday, let owner = appState.currentUser else { return }

        let trimmed = meccaName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "\(owner.username)'s Mecca" : trimmed
        // Exempt users pass a future cutoff so the "already placed since" guard
        // never matches, allowing unlimited placements.
        let notBefore = isDailyLimitExempt
            ? Date.distantFuture
            : Calendar.current.startOfDay(for: Date())

        saveError = nil
        isSaving = true
        Task {
            // Sample GPS for a few seconds and average the best fixes so the
            // recorded coordinate is as precise as possible.
            guard let fix = await location.captureBestLocation(seconds: 4) else {
                saveError = "Couldn't get a GPS fix. Try again near a window or outdoors."
                isSaving = false
                return
            }
            let altitude = fix.verticalAccuracy >= 0 ? fix.altitude : nil
            let coordinate = GeoCoordinate(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                altitude: altitude
            )
            do {
                _ = try await appState.dependencies.meccas.createMecca(
                    ownerID: owner.id,
                    name: name,
                    coordinate: coordinate,
                    notBefore: notBefore
                )
                didSave = true
            } catch MeccaRepositoryError.dailyLimitReached {
                alreadyPlacedToday = true
                saveError = MeccaRepositoryError.dailyLimitReached.errorDescription
            } catch {
                saveError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct MeccaPlacementConfiguration: Equatable {
    let sizeScale: Float
    let xRotationDegrees: Float
    let yRotationDegrees: Float
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
    @Binding var sizeMillimeters: Double
    @Binding var xRotationDegrees: Double
    @Binding var yRotationDegrees: Double
    @Binding var tintColor: Color

    var body: some View {
        VStack(spacing: 12) {
            ColorPicker(
                "Mecca color",
                selection: $tintColor,
                supportsOpacity: false
            )
            .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.caption2)

                Slider(value: $sizeMillimeters, in: 20...35, step: 1)
                    .accessibilityLabel("Mecca size")
                    .accessibilityValue(
                        "\(Int(sizeMillimeters.rounded())) millimeters"
                    )

                Image(systemName: "person.fill")

                Text("~\(Int(sizeMillimeters.rounded())) mm")
                    .font(.caption.monospacedDigit())
                    .frame(width: 48, alignment: .trailing)
            }
            AxisRotationControl(
                axisName: "Y",
                degrees: $yRotationDegrees
            )

            AxisRotationControl(
                axisName: "X",
                degrees: $xRotationDegrees
            )
        }
    }
}

private struct AxisRotationControl: View {
    let axisName: String
    @Binding var degrees: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(axisName)-axis rotation")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(Int(degrees))°")
                    .font(.caption.monospacedDigit())
            }

            HStack(spacing: 10) {
                Button {
                    rotate(by: -90)
                } label: {
                    Image(systemName: "rotate.left")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    "Rotate Mecca negative 90 degrees on \(axisName) axis"
                )

                Slider(value: $degrees, in: 0...360, step: 15)
                    .accessibilityLabel("Mecca \(axisName)-axis rotation")
                    .accessibilityValue("\(Int(degrees)) degrees")

                Button {
                    rotate(by: 90)
                } label: {
                    Image(systemName: "rotate.right")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(
                    "Rotate Mecca positive 90 degrees on \(axisName) axis"
                )
            }
        }
    }

    private func rotate(by adjustment: Double) {
        let rotated = (degrees + adjustment)
            .truncatingRemainder(dividingBy: 360)
        degrees = rotated >= 0 ? rotated : rotated + 360
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
            let placementConfiguration = parent.configuration
            parent.message = "Loading Mecca…"

            Task { @MainActor [weak self] in
                guard let self, let arView = self.arView else { return }

                let entity = await MeccaEntityFactory.make()
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)

                let placedMecca = PlacedMecca(
                    anchor: anchor,
                    entity: entity
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

            let xRadians = configuration.xRotationDegrees * .pi / 180
            let yRadians = configuration.yRotationDegrees * .pi / 180
            let xRotation = simd_quatf(angle: xRadians, axis: [1, 0, 0])
            let yRotation = simd_quatf(angle: yRadians, axis: [0, 1, 0])
            placedMecca.entity.orientation = yRotation * xRotation
        }
    }
}
