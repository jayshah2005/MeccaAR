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

    private enum ClaimState: Equatable {
        case searching
        case claiming
        case claimed
        case failed(String)
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
            HuntARContainer(placement: placement, didTapMecca: $didTapMecca)
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
        .onChange(of: didTapMecca) { _, tapped in
            if tapped { claim() }
        }
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
        guard let distance = liveDistance else {
            return "Finding your location…"
        }
        if distance <= HuntTuning.hintUntilMeters {
            return "It's right here — look around and tap it!"
        }
        return "\(Int(distance.rounded())) m away"
    }

    private var subHintText: String {
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

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.mint)
                Text("Mecca hunted!")
                    .font(.largeTitle.bold())
                Text("+\(HuntTuning.awardedPoints) points for finding \(target.name).")
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
                _ = try await appState.dependencies.meccas.claim(
                    meccaID: target.id,
                    hunterID: hunterID,
                    awardedPoints: HuntTuning.awardedPoints
                )
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

