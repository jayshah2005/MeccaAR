import ARKit
import CoreLocation
import RealityKit
import SwiftUI
import UIKit

/// Full-screen AR experience for hunting a specific Mecca. The target is placed
/// in the compass direction of its stored GPS coordinate; distance hints guide
/// the hunter until they're within `hintUntilMeters`, after which they must find
/// and tap it themselves. Tapping it claims it (never your own Mecca).
struct HuntARView: View {
    let target: Mecca
    let onClaimed: () async -> Void

    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var didTapMecca = false
    @State private var claimState: ClaimState = .searching
    @State private var mapLoad: MapLoad = .idle
    @State private var preciseState: PreciseMeccaARController.State = .relocalizing
    @State private var geoState: GeoMeccaARController.State = .localizing
    @State private var awardedPoints = 0
    @State private var facePhoto: UIImage?

    private enum ClaimState: Equatable {
        case searching
        case claiming
        case claimed
        case failed(String)
    }

    /// Whether the precise, world-map-based hunt is available and loading.
    private enum MapLoad {
        case idle
        case loading
        case ready(ARWorldMap)
        case geo
        case gpsFallback
    }

    private var isPreciseMode: Bool {
        if case .ready = mapLoad { return true }
        return false
    }

    private var isGeoMode: Bool {
        if case .geo = mapLoad { return true }
        return false
    }

    private var targetCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
    }

    private var liveDistance: Double? {
        location.currentLocation.map {
            GeoMath.distanceMeters(from: $0.coordinate, to: targetCoordinate)
        }
    }

    private var placement: HuntPlacement? {
        guard let origin = location.currentLocation?.coordinate else { return nil }
        return HuntPlacement(
            bearingDegrees: GeoMath.bearingDegrees(from: origin, to: targetCoordinate),
            distanceMeters: GeoMath.distanceMeters(from: origin, to: targetCoordinate)
        )
    }

    var body: some View {
        ZStack {
            arLayer
                .ignoresSafeArea()

            Crosshair()

            VStack {
                topBar
                Spacer()
                hintPanel
            }
            .padding()

            if claimState == .claimed {
                successOverlay
            }
        }
        .preferredColorScheme(.dark)
        .task { await MeccaEntityFactory.preload() }
        .task { await loadWorldMap() }
        .onChange(of: didTapMecca) { _, tapped in
            if tapped { claim() }
        }
    }

    @ViewBuilder
    private var arLayer: some View {
        switch mapLoad {
        case .ready(let map):
            HuntPreciseARContainer(
                worldMap: map,
                appearance: target.appearance,
                facePhoto: facePhoto,
                placement: placement,
                deviceHeadingDegrees: location.heading?.trueHeading
                    ?? location.heading?.magneticHeading,
                didTapMecca: $didTapMecca,
                state: $preciseState
            )
        case .geo:
            HuntGeoARContainer(
                coordinate: targetCoordinate,
                altitude: target.altitude,
                appearance: target.appearance,
                facePhoto: facePhoto,
                placement: placement,
                deviceHeadingDegrees: location.heading?.trueHeading
                    ?? location.heading?.magneticHeading,
                didTapMecca: $didTapMecca,
                state: $geoState
            )
        case .idle, .loading, .gpsFallback:
            HuntARContainer(
                placement: placement,
                appearance: target.appearance,
                facePhoto: facePhoto,
                didTapMecca: $didTapMecca
            )
        }
    }

    private func loadWorldMap() async {
        async let faceTask: Void = loadFacePhoto()
        if target.placementMode == .geo {
            mapLoad = .geo
            await faceTask
            return
        }
        guard target.hasWorldMap, case .idle = mapLoad else {
            if !target.hasWorldMap { mapLoad = .gpsFallback }
            await faceTask
            return
        }
        mapLoad = .loading
        do {
            guard let data = try await appState.dependencies.meccas.worldMap(for: target.id) else {
                mapLoad = .gpsFallback
                await faceTask
                return
            }
            mapLoad = .ready(try ARWorldMapArchiver.decode(data))
        } catch {
            mapLoad = .gpsFallback
        }
        await faceTask
    }

    private func loadFacePhoto() async {
        guard target.hasFacePhoto else { return }
        guard let data = try? await appState.dependencies.meccas.facePhoto(for: target.id),
              let image = UIImage(data: data)
        else { return }
        facePhoto = image
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.65))

            Spacer()

            Label("HUNTING", systemImage: "scope")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.mint.opacity(0.92), in: Capsule())
                .foregroundStyle(.black)
        }
    }

    @ViewBuilder
    private var hintPanel: some View {
        VStack(spacing: 8) {
            Text(target.name)
                .font(.headline)

            Text(hintText)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            if case .failed(let message) = claimState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if claimState == .claiming {
                ProgressView().tint(.mint)
            } else {
                Text(subHintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var hintText: String {
        if case .loading = mapLoad {
            return "Loading precise AR map…"
        }
        if isGeoMode {
            return geoState == .located
                ? "Locked on — tap the Mecca!"
                : "Look around outdoors to lock geo tracking"
        }
        if isPreciseMode {
            if preciseState == .located {
                return "Locked on — tap the Mecca!"
            }
            if let distance = liveDistance, distance > HuntTuning.hintUntilMeters {
                return "Walk \(Int(distance.rounded())) m \(compassDirection), then scan"
            }
            return "Scan the area to lock on"
        }
        guard let distance = liveDistance else {
            return "Finding your location…"
        }
        if distance <= HuntTuning.hintUntilMeters {
            return "It's right here — look around and tap it!"
        }
        return "\(Int(distance.rounded())) m away"
    }

    private var subHintText: String {
        if isGeoMode {
            return geoState == .located
                ? "Pinned with outdoor geo tracking."
                : "Stay outside with a clear view of the street — Apple geo tracking will lock on."
        }
        if isPreciseMode {
            if preciseState == .located {
                return "This Mecca is pinned to its exact real-world spot."
            }
            if let distance = liveDistance, distance > HuntTuning.hintUntilMeters {
                return "Head to where it was hidden, then slowly pan your phone across the area to lock on.\(accuracySuffix)"
            }
            return "Slowly pan your phone across the area where it was hidden until it locks on (centimeter-accurate)."
        }
        guard let distance = liveDistance else {
            return "Move outside for a better GPS fix."
        }
        if distance <= HuntTuning.hintUntilMeters {
            return "No more hints. Scan the space with your camera to spot the Mecca."
        }
        return "Walk toward the reticle direction. Hints stop at \(Int(HuntTuning.hintUntilMeters)) m.\(accuracySuffix)"
    }

    private var accuracySuffix: String {
        guard let accuracy = location.horizontalAccuracy else { return "" }
        return " GPS ±\(Int(accuracy.rounded())) m."
    }

    /// Rough compass word for the direction to the target, for guiding the
    /// hunter toward the mapped area during precise relocalization.
    private var compassDirection: String {
        guard let bearing = placement?.bearingDegrees else { return "toward it" }
        let directions = [
            "north", "northeast", "east", "southeast",
            "south", "southwest", "west", "northwest"
        ]
        let index = Int((bearing / 45).rounded()) % directions.count
        return directions[index]
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.mint)
                Text("Mecca hunted!")
                    .font(.largeTitle.bold())
                Text("+\(awardedPoints) points for finding \(target.name).")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") {
                    Task {
                        await onClaimed()
                        dismiss()
                    }
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(.mint)
            }
            .padding(32)
        }
    }

    private func claim() {
        guard claimState == .searching, let hunterID = appState.currentUser?.id else { return }
        claimState = .claiming
        Task {
            do {
                let claim = try await appState.dependencies.meccas.claim(
                    meccaID: target.id,
                    hunterID: hunterID
                )
                awardedPoints = claim.awardedPoints
                claimState = .claimed
            } catch {
                claimState = .failed(
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
                didTapMecca = false
            }
        }
    }
}

/// The direction and distance from the hunter to the target, used to place the
/// AR entity relative to the compass-aligned world origin.
struct HuntPlacement: Equatable {
    let bearingDegrees: Double
    let distanceMeters: Double
}

private struct Crosshair: View {
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.9), lineWidth: 2).frame(width: 34, height: 34)
            Circle().fill(.white).frame(width: 4, height: 4)
        }
        .shadow(color: .black.opacity(0.75), radius: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HuntARContainer: UIViewRepresentable {
    let placement: HuntPlacement?
    let appearance: MeccaAppearance
    let facePhoto: UIImage?
    @Binding var didTapMecca: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        context.coordinator.runSession()
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.parent = self
        if let placement {
            context.coordinator.placer.update(
                bearingDegrees: placement.bearingDegrees,
                distanceMeters: placement.distanceMeters,
                freezeWithinMeters: HuntTuning.hintUntilMeters,
                appearance: appearance,
                facePhoto: facePhoto,
                in: arView
            )
        }
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        arView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: HuntARContainer
        weak var arView: ARView?
        let placer = ARMeccaPlacer()

        init(_ parent: HuntARContainer) {
            self.parent = parent
        }

        func runSession() {
            guard let arView else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.worldAlignment = .gravityAndHeading
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        @objc
        func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = recognizer.location(in: arView)
            guard let tapped = arView.entity(at: point) else { return }

            if placer.contains(tapped) {
                parent.didTapMecca = true
            }
        }
    }
}

/// Precise hunt container: relocalizes against the Mecca's stored world map and
/// renders it at its exact physical spot. While still scanning to lock on, a
/// camera-relative GPS guide Mecca points the hunter toward the right area.
private struct HuntPreciseARContainer: UIViewRepresentable {
    let worldMap: ARWorldMap
    let appearance: MeccaAppearance
    let facePhoto: UIImage?
    let placement: HuntPlacement?
    let deviceHeadingDegrees: Double?
    @Binding var didTapMecca: Bool
    @Binding var state: PreciseMeccaARController.State

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        context.coordinator.controller.onStateChange = { newState in
            context.coordinator.parent.state = newState
            if newState == .located {
                context.coordinator.guide.clear()
            }
        }
        context.coordinator.controller.start(
            worldMap: worldMap,
            appearance: appearance,
            facePhoto: facePhoto,
            in: arView
        )
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.parent = self
        guard
            context.coordinator.parent.state != .located,
            let placement,
            let heading = deviceHeadingDegrees,
            heading >= 0
        else { return }

        context.coordinator.guide.updateCameraRelative(
            targetBearingDegrees: placement.bearingDegrees,
            deviceHeadingDegrees: heading,
            distanceMeters: placement.distanceMeters,
            freezeWithinMeters: HuntTuning.hintUntilMeters,
            appearance: appearance,
            facePhoto: facePhoto,
            in: arView
        )
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        arView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: HuntPreciseARContainer
        weak var arView: ARView?
        let controller = PreciseMeccaARController()
        let guide = ARMeccaPlacer()

        init(_ parent: HuntPreciseARContainer) {
            self.parent = parent
        }

        @objc
        func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = recognizer.location(in: arView)
            guard let tapped = arView.entity(at: point) else { return }
            // Only the precise (baked) Mecca counts as a claim — the GPS guide
            // is just directional help while scanning.
            if controller.contains(tapped) {
                parent.didTapMecca = true
            }
        }
    }
}

/// Outdoor hunt container using Apple geo tracking + an ARGeoAnchor.
private struct HuntGeoARContainer: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let appearance: MeccaAppearance
    let facePhoto: UIImage?
    let placement: HuntPlacement?
    let deviceHeadingDegrees: Double?
    @Binding var didTapMecca: Bool
    @Binding var state: GeoMeccaARController.State

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        context.coordinator.controller.onStateChange = { newState in
            context.coordinator.parent.state = newState
            if newState == .located {
                context.coordinator.guide.clear()
            }
        }
        context.coordinator.controller.start(
            coordinate: coordinate,
            altitude: altitude,
            appearance: appearance,
            facePhoto: facePhoto,
            in: arView
        )
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.parent = self
        guard
            context.coordinator.parent.state != .located,
            let placement,
            let heading = deviceHeadingDegrees,
            heading >= 0
        else { return }

        context.coordinator.guide.updateCameraRelative(
            targetBearingDegrees: placement.bearingDegrees,
            deviceHeadingDegrees: heading,
            distanceMeters: placement.distanceMeters,
            freezeWithinMeters: HuntTuning.hintUntilMeters,
            appearance: appearance,
            facePhoto: facePhoto,
            in: arView
        )
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        arView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: HuntGeoARContainer
        weak var arView: ARView?
        let controller = GeoMeccaARController()
        let guide = ARMeccaPlacer()

        init(_ parent: HuntGeoARContainer) {
            self.parent = parent
        }

        @objc
        func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = recognizer.location(in: arView)
            guard let tapped = arView.entity(at: point) else { return }
            if controller.contains(tapped) {
                parent.didTapMecca = true
            }
        }
    }
}

