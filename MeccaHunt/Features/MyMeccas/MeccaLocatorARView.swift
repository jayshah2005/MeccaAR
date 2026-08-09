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

    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss

    private static let arrivedRadiusMeters = 2.0

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
            LocatorARContainer(placement: placement)
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
        guard let distance = liveDistance else { return "Finding your location…" }
        if distance <= Self.arrivedRadiusMeters {
            return "You've reached it!"
        }
        return "\(Int(distance.rounded())) m away"
    }

    private var subHintText: String {
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
