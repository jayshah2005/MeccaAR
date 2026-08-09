import ARKit
import CoreLocation
import RealityKit
import SwiftUI
import UIKit

/// Full-screen AR view that points the user toward one of their own Meccas in
/// the real world. Unlike hunting, there is no claiming — it's purely for
/// finding your own hidden Mecca again.
struct MeccaLocatorARView: View {
    let target: Mecca

    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var mapLoad: MapLoad = .idle
    @State private var preciseState: PreciseMeccaARController.State = .relocalizing
    @State private var geoState: GeoMeccaARController.State = .localizing
    @State private var facePhoto: UIImage?

    private static let arrivedRadiusMeters = 2.0

    fileprivate static var guideFreezeMeters: Double { arrivedRadiusMeters }

    /// Whether the precise, world-map-based locate is available and loading.
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

    private var placement: LocatorPlacement? {
        guard let origin = location.currentLocation?.coordinate else { return nil }
        return LocatorPlacement(
            bearingDegrees: GeoMath.bearingDegrees(from: origin, to: targetCoordinate),
            distanceMeters: GeoMath.distanceMeters(from: origin, to: targetCoordinate)
        )
    }

    var body: some View {
        ZStack {
            arLayer
                .ignoresSafeArea()

            LocatorCrosshair()

            VStack {
                topBar
                Spacer()
                hintPanel
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .task { await MeccaEntityFactory.preload() }
        .task { await loadWorldMap() }
    }

    @ViewBuilder
    private var arLayer: some View {
        switch mapLoad {
        case .ready(let map):
            LocatorPreciseARContainer(
                worldMap: map,
                appearance: target.appearance,
                facePhoto: facePhoto,
                placement: placement,
                deviceHeadingDegrees: location.heading?.trueHeading
                    ?? location.heading?.magneticHeading,
                state: $preciseState
            )
        case .geo:
            LocatorGeoARContainer(
                coordinate: targetCoordinate,
                altitude: target.altitude,
                appearance: target.appearance,
                facePhoto: facePhoto,
                placement: placement,
                deviceHeadingDegrees: location.heading?.trueHeading
                    ?? location.heading?.magneticHeading,
                state: $geoState
            )
        case .idle, .loading, .gpsFallback:
            LocatorARContainer(
                placement: placement,
                appearance: target.appearance,
                facePhoto: facePhoto
            )
        }
    }

    private func loadWorldMap() async {
        // Load the face first so geo/precise containers start with it applied.
        await loadFacePhoto()
        if target.placementMode == .geo {
            mapLoad = .geo
            return
        }
        guard target.hasWorldMap, case .idle = mapLoad else {
            if !target.hasWorldMap { mapLoad = .gpsFallback }
            return
        }
        mapLoad = .loading
        do {
            guard let data = try await appState.dependencies.meccas.worldMap(for: target.id) else {
                mapLoad = .gpsFallback
                return
            }
            let map = try ARWorldMapArchiver.decode(data)
            if ARWorldMapArchiver.containsMeccaAnchor(map) {
                mapLoad = .ready(map)
            } else {
                mapLoad = .gpsFallback
            }
        } catch {
            mapLoad = .gpsFallback
        }
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

            Label("LOCATE", systemImage: "location.north.line.fill")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.mint.opacity(0.92), in: Capsule())
                .foregroundStyle(.black)
        }
    }

    private var hintPanel: some View {
        VStack(spacing: 8) {
            Text(target.name)
                .font(.headline)
            Text(hintText)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subHintText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
                ? "Found it — outdoor geo lock"
                : "Look around outdoors to lock geo tracking"
        }
        if isPreciseMode {
            return preciseState == .located
                ? "Found it — it's pinned exactly here"
                : "Scan the area to lock on"
        }
        guard let distance = liveDistance else { return "Finding your location…" }
        if distance <= Self.arrivedRadiusMeters {
            return "You've reached it!"
        }
        return "\(Int(distance.rounded())) m away"
    }

    private var subHintText: String {
        if isGeoMode {
            return geoState == .located
                ? "Your Mecca is pinned with outdoor geo tracking."
                : "Stay outside with a clear street view until geo tracking locks on."
        }
        if isPreciseMode {
            return preciseState == .located
                ? "Your Mecca is shown at its exact real-world spot."
                : "Slowly pan your phone across the area where you hid it until it locks on (centimeter-accurate)."
        }
        guard let distance = liveDistance else {
            return "Move outside for a better GPS fix."
        }
        if distance <= Self.arrivedRadiusMeters {
            return "Your Mecca should be right in front of you."
        }
        let accuracy = location.horizontalAccuracy.map { " GPS ±\(Int($0.rounded())) m." } ?? ""
        return "Follow the reticle direction to reach your Mecca.\(accuracy)"
    }
}

/// Direction and distance from the user to their Mecca.
struct LocatorPlacement: Equatable {
    let bearingDegrees: Double
    let distanceMeters: Double
}

private struct LocatorCrosshair: View {
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

private struct LocatorARContainer: UIViewRepresentable {
    let placement: LocatorPlacement?
    let appearance: MeccaAppearance
    let facePhoto: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView
        context.coordinator.runSession()
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        if let placement {
            context.coordinator.placer.update(
                bearingDegrees: placement.bearingDegrees,
                distanceMeters: placement.distanceMeters,
                freezeWithinMeters: 2.5,
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
        weak var arView: ARView?
        let placer = ARMeccaPlacer()

        func runSession() {
            guard let arView else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.worldAlignment = .gravityAndHeading
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }
}

/// Precise locate container: relocalizes against the Mecca's stored world map and
/// renders it at its exact physical spot. While scanning to lock on, a
/// camera-relative GPS guide Mecca points toward the right area.
private struct LocatorPreciseARContainer: UIViewRepresentable {
    let worldMap: ARWorldMap
    let appearance: MeccaAppearance
    let facePhoto: UIImage?
    let placement: LocatorPlacement?
    let deviceHeadingDegrees: Double?
    @Binding var state: PreciseMeccaARController.State

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView
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
        context.coordinator.controller.updateFacePhoto(facePhoto)
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
            freezeWithinMeters: MeccaLocatorARView.guideFreezeMeters,
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
        var parent: LocatorPreciseARContainer
        weak var arView: ARView?
        let controller = PreciseMeccaARController()
        let guide = ARMeccaPlacer()

        init(_ parent: LocatorPreciseARContainer) {
            self.parent = parent
        }
    }
}

private struct LocatorGeoARContainer: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let appearance: MeccaAppearance
    let facePhoto: UIImage?
    let placement: LocatorPlacement?
    let deviceHeadingDegrees: Double?
    @Binding var state: GeoMeccaARController.State

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView
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
        context.coordinator.controller.updateFacePhoto(facePhoto)
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
            freezeWithinMeters: MeccaLocatorARView.guideFreezeMeters,
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
        var parent: LocatorGeoARContainer
        weak var arView: ARView?
        let controller = GeoMeccaARController()
        let guide = ARMeccaPlacer()

        init(_ parent: LocatorGeoARContainer) {
            self.parent = parent
        }
    }
}
