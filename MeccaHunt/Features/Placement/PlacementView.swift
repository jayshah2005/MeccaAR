import ARKit
import Combine
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
    @State private var didSaveWithMap = false
    @State private var alreadyPlacedToday = false
    @State private var saveStatus = "Save to map"
    @State private var arSession = PlacementARSession()
    @State private var mappingQuality: ARFrame.WorldMappingStatus = .notAvailable
    @State private var canPlace = false
    @State private var placeToken = 0

    private var configuration: MeccaPlacementConfiguration {
        let referenceMillimeters = Double(MeccaEntityFactory.referenceHeightMeters * 1_000)
        return MeccaPlacementConfiguration(
            sizeScale: Float(sizeMillimeters / referenceMillimeters),
            xRotationDegrees: Float(xRotationDegrees),
            yRotationDegrees: Float(yRotationDegrees),
            tint: MeccaTint(color: tintColor)
        )
    }

    /// The persisted appearance for the Mecca being saved, so it renders with
    /// the same color, size, and rotation for everyone who finds it.
    private var appearance: MeccaAppearance {
        let tint = MeccaTint(color: tintColor)
        return MeccaAppearance(
            sizeMillimeters: sizeMillimeters,
            xRotationDegrees: xRotationDegrees,
            yRotationDegrees: yRotationDegrees,
            red: tint.red,
            green: tint.green,
            blue: tint.blue
        )
    }

    var body: some View {
        ZStack {
            PlacementARView(
                placementCount: $placementCount,
                resetToken: resetToken,
                message: $message,
                configuration: configuration,
                session: arSession,
                canPlace: $canPlace,
                placeToken: placeToken
            )
            .ignoresSafeArea()

            Crosshair(active: canPlace)

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

                placeButton

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
                        Text("Point the reticle at a floor, table, or wall. When it turns green, tap Place Mecca.")
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
                .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 20))
            }
            .padding()

            if didSave {
                savedOverlay
            }
        }
        .preferredColorScheme(.dark)
        .task { await MeccaEntityFactory.preload() }
        .task {
            location.start()
            await checkDailyLimit()
        }
        .task {
            // Poll ARKit's world-mapping status so we can tell the user when the
            // captured area is rich enough for precise relocalization.
            while !Task.isCancelled {
                mappingQuality = arSession.currentMappingStatus()
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }

    private var placeButton: some View {
        Button {
            placeToken += 1
        } label: {
            Label(canPlace ? "Place Mecca" : "Scanning for a surface…",
                  systemImage: canPlace ? "plus.viewfinder" : "viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(canPlace ? .mint : .gray)
        .disabled(!canPlace)
        .opacity(canPlace ? 1 : 0.55)
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.2), value: canPlace)
        .accessibilityHint(canPlace
            ? "Places a Mecca where the reticle is pointing"
            : "Move your phone to scan a surface before placing")
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
                    "Slowly look around the Mecca from a few angles first, then keep still and save. This records a precise AR map of the spot.",
                    systemImage: "arkit"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                mappingQualityLabel

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Button(action: save) {
                    HStack {
                        if isSaving { ProgressView().tint(.black) }
                        Text(isSaving ? saveStatus : "Save to map")
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
    private var mappingQualityLabel: some View {
        let (text, symbol, tint): (String, String, Color) = switch mappingQuality {
        case .mapped:
            ("AR map ready — precise find enabled", "checkmark.circle.fill", .mint)
        case .extending:
            ("Good AR coverage — a bit more helps", "circle.lefthalf.filled", .yellow)
        default:
            ("Look around the Mecca to build the AR map", "arkit", .orange)
        }
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
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
                Text(didSaveWithMap
                    ? "Saved with a precise AR map — hunters can lock onto its exact spot."
                    : "Saved with GPS only. Look around next time to enable centimeter-accurate finding.")
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
        didSaveWithMap = false
        Task {
            // Capture the AR world map first, while the user is still holding the
            // phone at the Mecca. This is what enables centimeter-accurate finding.
            saveStatus = "Capturing AR map — hold still…"
            let worldMapData = await arSession.captureWorldMap()

            // Sample GPS for a few seconds too, as a coarse gate so hunters know
            // when they're close enough to start scanning.
            saveStatus = "Locking GPS — hold still…"
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
                saveStatus = "Saving…"
                let mecca = try await appState.dependencies.meccas.createMecca(
                    ownerID: owner.id,
                    name: name,
                    coordinate: coordinate,
                    appearance: appearance,
                    notBefore: notBefore
                )
                if let worldMapData {
                    saveStatus = "Uploading AR map…"
                    do {
                        try await appState.dependencies.meccas.uploadWorldMap(
                            meccaID: mecca.id,
                            compressedData: worldMapData
                        )
                        didSaveWithMap = true
                    } catch {
                        // The Mecca is saved with GPS; precise map upload is a
                        // best-effort bonus, so don't fail the whole save.
                        didSaveWithMap = false
                    }
                }
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

/// Shared handle to the placement AR session so `PlacementView` can capture the
/// world map and read mapping quality without owning the `ARView` directly.
@MainActor
final class PlacementARSession {
    weak var arView: ARView?

    func currentMappingStatus() -> ARFrame.WorldMappingStatus {
        arView?.session.currentFrame?.worldMappingStatus ?? .notAvailable
    }

    /// Asks ARKit for the current world map and returns it archived + compressed,
    /// or nil if a usable map isn't available yet.
    func captureWorldMap() async -> Data? {
        guard let session = arView?.session else { return nil }
        return await withCheckedContinuation { continuation in
            session.getCurrentWorldMap { map, _ in
                guard let map else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: try? ARWorldMapArchiver.encode(map))
            }
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
    var active: Bool = false

    var body: some View {
        let color: Color = active ? .green : .white
        ZStack {
            Circle()
                .stroke(color.opacity(0.95), lineWidth: 2)
                .frame(width: 34, height: 34)
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
        }
        .shadow(color: .black.opacity(0.75), radius: 3)
        .animation(.easeInOut(duration: 0.2), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PlacementARView: UIViewRepresentable {
    @Binding var placementCount: Int
    let resetToken: Int
    @Binding var message: String
    let configuration: MeccaPlacementConfiguration
    let session: PlacementARSession
    @Binding var canPlace: Bool
    let placeToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView
        session.arView = arView

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
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
        context.coordinator.beginTracking()
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.clearIfNeeded(resetToken: resetToken)
        context.coordinator.applyConfigurationToLatestMecca()
        context.coordinator.handlePlaceToken(placeToken)
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        coordinator.tearDown()
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

        private struct SurfaceHit {
            let transform: simd_float4x4
            let normal: SIMD3<Float>
        }

        private var placedMeccas: [PlacedMecca] = []
        private var lastResetToken: Int
        private var lastAppliedConfiguration: MeccaPlacementConfiguration?
        /// The session-tracked anchor persisted into the world map for precise
        /// relocalization. Only the most recent placement is kept.
        private var persistedAnchor: ARAnchor?

        // Live placement feedback.
        private var updateSubscription: (any Cancellable)?
        private var reticleAnchor: AnchorEntity?
        private var reticle: ModelEntity?
        private var latestHit: SurfaceHit?
        private var lastReportedCanPlace = false
        private var lastPlaceToken = 0

        init(_ parent: PlacementARView) {
            self.parent = parent
            lastResetToken = parent.resetToken
            lastPlaceToken = parent.placeToken
        }

        func runSession() {
            guard let arView else { return }

            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.environmentTexturing = .automatic
            // LiDAR devices get a full scene mesh, which makes surface detection
            // (and therefore placement) far more reliable, even on low-texture
            // walls and floors.
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
            }

            arView.session.run(
                configuration,
                options: [.resetTracking, .removeExistingAnchors]
            )
        }

        /// Builds the placement reticle and starts a per-frame loop that raycasts
        /// from the screen center to show where a Mecca would land.
        func beginTracking() {
            guard let arView else { return }

            let reticle = ModelEntity(
                mesh: .generatePlane(width: 0.09, depth: 0.09, cornerRadius: 0.045),
                materials: [Self.reticleMaterial(valid: true)]
            )
            reticle.isEnabled = false
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(reticle)
            arView.scene.addAnchor(anchor)
            self.reticle = reticle
            self.reticleAnchor = anchor

            updateSubscription = arView.scene.subscribe(
                to: SceneEvents.Update.self
            ) { [weak self] _ in
                self?.refreshReticle()
            }
        }

        func tearDown() {
            updateSubscription?.cancel()
            updateSubscription = nil
        }

        private func refreshReticle() {
            guard let arView, let reticle else { return }

            if let hit = bestSurfaceHit() {
                latestHit = hit
                // Orient the flat reticle so its up (+Y) matches the surface.
                let rotation = simd_quatf(from: [0, 1, 0], to: hit.normal)
                let position = SIMD3<Float>(
                    hit.transform.columns.3.x,
                    hit.transform.columns.3.y,
                    hit.transform.columns.3.z
                )
                reticleAnchor?.transform = Transform(
                    scale: SIMD3<Float>(repeating: 1),
                    rotation: rotation,
                    translation: position
                )
                reticle.isEnabled = true
                setCanPlace(true)
            } else {
                latestHit = nil
                reticle.isEnabled = false
                setCanPlace(false)
            }
        }

        private func setCanPlace(_ value: Bool) {
            guard value != lastReportedCanPlace else { return }
            lastReportedCanPlace = value
            parent.canPlace = value
            if placedMeccas.isEmpty {
                parent.message = value
                    ? "Surface found — tap Place Mecca"
                    : "Move your phone slowly to scan a surface"
            }
        }

        /// Tries progressively looser raycast targets so placement works on
        /// mapped planes, their infinite extensions, and rough estimates.
        private func bestSurfaceHit() -> SurfaceHit? {
            guard let arView else { return nil }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let targets: [ARRaycastQuery.Target] = [
                .existingPlaneGeometry,
                .existingPlaneInfinite,
                .estimatedPlane
            ]
            for target in targets {
                if let result = arView.raycast(
                    from: center,
                    allowing: target,
                    alignment: .any
                ).first {
                    let normal = SIMD3<Float>(
                        result.worldTransform.columns.1.x,
                        result.worldTransform.columns.1.y,
                        result.worldTransform.columns.1.z
                    )
                    let normalized = simd_length(normal) > 0
                        ? simd_normalize(normal)
                        : SIMD3<Float>(0, 1, 0)
                    return SurfaceHit(transform: result.worldTransform, normal: normalized)
                }
            }
            return nil
        }

        @objc
        func handleTap(_: UITapGestureRecognizer) {
            place()
        }

        func handlePlaceToken(_ token: Int) {
            guard token != lastPlaceToken else { return }
            lastPlaceToken = token
            place()
        }

        private func place() {
            guard let arView, let hit = latestHit else {
                parent.message = "No surface found yet — keep scanning and try again"
                return
            }

            // Only one Mecca can be hidden at a time, so replace any previously
            // placed preview before adding the new one.
            placedMeccas.forEach { $0.anchor.removeFromParent() }
            placedMeccas.removeAll()

            // Keep the character upright in gravity-aligned world space even
            // when the surface is a wall. The surface normal is still used to
            // lift the anchor slightly off the surface to avoid clipping.
            var anchorTransform = matrix_identity_float4x4
            anchorTransform.columns.3 = hit.transform.columns.3
            anchorTransform.columns.3.x += hit.normal.x * 0.015
            anchorTransform.columns.3.y += hit.normal.y * 0.015
            anchorTransform.columns.3.z += hit.normal.z * 0.015

            let anchor = AnchorEntity(world: anchorTransform)
            let placementConfiguration = parent.configuration
            parent.message = "Loading Mecca…"

            // Persist a named session anchor at the same spot so it is captured
            // in the world map and can be relocalized later to the exact cm.
            if let existing = persistedAnchor {
                arView.session.remove(anchor: existing)
            }
            let worldAnchor = ARAnchor(
                name: PreciseMeccaARController.anchorName,
                transform: anchorTransform
            )
            arView.session.add(anchor: worldAnchor)
            persistedAnchor = worldAnchor

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

                self.parent.placementCount = 1
                self.parent.message = "Mecca placed — adjust it below or save it"
            }
        }

        func clearIfNeeded(resetToken: Int) {
            guard resetToken != lastResetToken else { return }
            placedMeccas.forEach { $0.anchor.removeFromParent() }
            placedMeccas.removeAll()
            if let existing = persistedAnchor {
                arView?.session.remove(anchor: existing)
                persistedAnchor = nil
            }
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

        private static func reticleMaterial(valid: Bool) -> UnlitMaterial {
            UnlitMaterial(
                color: (valid ? UIColor.systemGreen : UIColor.systemRed)
                    .withAlphaComponent(0.55)
            )
        }
    }
}
