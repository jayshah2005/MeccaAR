import ARKit
import CoreLocation
import RealityKit
import SwiftUI
import UIKit

/// One AR room session containing every currently huntable Mecca. A selected
/// mapped Mecca is created only after exact world-map relocalization, so it
/// never jumps from a GPS estimate to its saved position.
struct RoomHuntARView: View {
    let targets: [Mecca]
    let preloadedPrimaryWorldMap: ARWorldMap?
    let onClaimed: () async -> Void

    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var tappedMeccaID: UUID?
    @State private var removedMeccaIDs: Set<UUID> = []
    @State private var isCleared = false
    @State private var claimState: ClaimState = .searching
    @State private var primaryWorldMap: ARWorldMap?
    @State private var didAttemptWorldMapLoad = false
    @State private var primaryWorldMapUnavailable = false
    @State private var preciseState: PreciseMeccaARController.State = .initializing

    init(
        targets: [Mecca],
        preloadedPrimaryWorldMap: ARWorldMap? = nil,
        onClaimed: @escaping () async -> Void
    ) {
        self.targets = targets
        self.preloadedPrimaryWorldMap = preloadedPrimaryWorldMap
        self.onClaimed = onClaimed
        _primaryWorldMap = State(initialValue: preloadedPrimaryWorldMap)
    }

    private enum ClaimState: Equatable {
        case searching
        case claiming(Mecca)
        case claimed(Mecca)
        case failed(String)
    }

    private var visibleTargets: [Mecca] {
        guard !isCleared else { return [] }
        return targets.filter { !removedMeccaIDs.contains($0.id) }
    }

    private var placements: [RoomHuntPlacement] {
        guard let origin = location.currentLocation?.coordinate else { return [] }
        let activeTargets = visibleTargets
        let midpoint = Double(activeTargets.count - 1) / 2

        return activeTargets.enumerated().map { index, mecca in
            let coordinate = CLLocationCoordinate2D(
                latitude: mecca.latitude,
                longitude: mecca.longitude
            )
            return RoomHuntPlacement(
                id: mecca.id,
                bearingDegrees: GeoMath.bearingDegrees(from: origin, to: coordinate),
                distanceMeters: GeoMath.distanceMeters(from: origin, to: coordinate),
                // GPS positions placed in the same room can be identical. A
                // small deterministic spread keeps every model independently
                // visible and tappable without changing its general direction.
                lateralOffsetMeters: (Double(index) - midpoint) * 0.45,
                headingDegrees: currentHeading,
                appearance: mecca.appearance
            )
        }
    }

    private var currentHeading: Double? {
        location.heading.flatMap { reading in
            if reading.trueHeading >= 0 { return reading.trueHeading }
            if reading.magneticHeading >= 0 { return reading.magneticHeading }
            return nil
        }
    }

    private var reservePrimaryForExactMap: Bool {
        guard targets.first?.hasWorldMap == true else { return false }
        return !primaryWorldMapUnavailable
    }

    var body: some View {
        ZStack {
            RoomHuntARContainer(
                placements: placements,
                removedMeccaIDs: removedMeccaIDs,
                isCleared: isCleared,
                primaryMeccaID: targets.first?.id,
                primaryWorldMap: primaryWorldMap,
                reservePrimaryForExactMap: reservePrimaryForExactMap,
                preciseState: $preciseState,
                tappedMeccaID: $tappedMeccaID
            )
            .ignoresSafeArea()

            RoomHuntCrosshair()

            VStack {
                topBar
                Spacer()
                hintPanel
            }
            .padding()

            if case .claimed(let mecca) = claimState {
                successOverlay(for: mecca)
            }
        }
        .preferredColorScheme(.dark)
        .task { await MeccaEntityFactory.preload() }
        .task { await loadPrimaryWorldMapIfNeeded() }
        .onChange(of: tappedMeccaID) { _, meccaID in
            if let meccaID { claim(meccaID) }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.65))

            Spacer()

            Label("\(visibleTargets.count) NEARBY", systemImage: "scope")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.mint.opacity(0.92), in: Capsule())
                .foregroundStyle(.black)

            Button(role: .destructive) { clearAll() } label: {
                Label("Clear", systemImage: "trash")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.82))
            .disabled(isCleared || visibleTargets.isEmpty)
            .accessibilityLabel("Clear all Meccas from this AR view")
        }
    }

    private var hintPanel: some View {
        VStack(spacing: 8) {
            Text(hintTitle)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            if case .claiming(let mecca) = claimState {
                HStack(spacing: 8) {
                    ProgressView().tint(.mint)
                    Text("Claiming \(mecca.name)…")
                }
                .font(.footnote.weight(.semibold))
            } else if case .failed(let message) = claimState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text(hintDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var hintTitle: String {
        if isCleared { return "All Meccas cleared" }
        if location.currentLocation == nil { return "Finding your location…" }
        if visibleTargets.isEmpty { return "Room cleared!" }
        if reservePrimaryForExactMap,
           primaryWorldMap != nil,
           preciseState != .located {
            return "Recognizing the saved room…"
        }
        return "Look around — every nearby Mecca is placed"
    }

    private var hintDetail: String {
        if isCleared { return "This only clears the current AR view. Saved Meccas are unchanged." }
        if location.currentLocation == nil { return "AR placement starts as soon as a location fix is available." }
        if primaryWorldMap != nil {
            switch preciseState {
            case .located:
                return "The selected Mecca is locked to its saved 360° room scan. Tap any Mecca to hunt it."
            case .approximating, .initializing, .relocalizing:
                return "Look around the scanned space. The selected Mecca will appear once at its exact saved spot and will not move."
            }
        }
        return "Meccas stay fixed at their first coordinate-based AR position. Tap any one to hunt it."
    }

    private func loadPrimaryWorldMapIfNeeded() async {
        guard
            primaryWorldMap == nil,
            !didAttemptWorldMapLoad,
            let primary = targets.first,
            primary.hasWorldMap
        else { return }

        didAttemptWorldMapLoad = true
        do {
            guard let data = try await appState.dependencies.meccas.worldMap(for: primary.id) else {
                primaryWorldMapUnavailable = true
                return
            }
            primaryWorldMap = try ARWorldMapArchiver.decode(data)
        } catch {
            // Coordinate placement remains visible if a legacy map is missing
            // or corrupt; newly created Meccas require an atomic map upload.
            primaryWorldMapUnavailable = true
        }
    }

    private func successOverlay(for mecca: Mecca) -> some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.mint)
                Text("Mecca hunted!")
                    .font(.largeTitle.bold())
                Text("+\(HuntTuning.awardedPoints) points for finding \(mecca.name).")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(visibleTargets.isEmpty ? "Done" : "Keep hunting") {
                    if visibleTargets.isEmpty {
                        dismiss()
                    } else {
                        claimState = .searching
                    }
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(.mint)
            }
            .padding(32)
        }
    }

    private func clearAll() {
        isCleared = true
        tappedMeccaID = nil
        claimState = .searching
    }

    private func claim(_ meccaID: UUID) {
        switch claimState {
        case .searching, .failed(_):
            break
        case .claiming(_), .claimed(_):
            tappedMeccaID = nil
            return
        }

        guard
            let target = visibleTargets.first(where: { $0.id == meccaID }),
            let hunterID = appState.currentUser?.id
        else {
            tappedMeccaID = nil
            return
        }

        claimState = .claiming(target)
        Task {
            do {
                _ = try await appState.dependencies.meccas.claim(
                    meccaID: target.id,
                    hunterID: hunterID,
                    awardedPoints: HuntTuning.awardedPoints
                )
                removedMeccaIDs.insert(target.id)
                tappedMeccaID = nil
                await onClaimed()
                claimState = .claimed(target)
            } catch {
                claimState = .failed(
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
                tappedMeccaID = nil
            }
        }
    }
}

private struct RoomHuntPlacement: Equatable, Identifiable {
    let id: UUID
    let bearingDegrees: Double
    let distanceMeters: Double
    let lateralOffsetMeters: Double
    let headingDegrees: Double?
    let appearance: MeccaAppearance
}

private struct RoomHuntCrosshair: View {
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

private struct RoomHuntARContainer: UIViewRepresentable {
    let placements: [RoomHuntPlacement]
    let removedMeccaIDs: Set<UUID>
    let isCleared: Bool
    let primaryMeccaID: UUID?
    let primaryWorldMap: ARWorldMap?
    let reservePrimaryForExactMap: Bool
    @Binding var preciseState: PreciseMeccaARController.State
    @Binding var tappedMeccaID: UUID?

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
        context.coordinator.sync(
            placements: placements,
            removedMeccaIDs: removedMeccaIDs,
            isCleared: isCleared,
            in: arView
        )
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        coordinator.clearAll()
        arView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: RoomHuntARContainer
        weak var arView: ARView?
        private var placers: [UUID: ARMeccaPlacer] = [:]
        private var preciseController: PreciseMeccaARController?
        private var hasActivatedPrimaryWorldMap = false
        private var hasCleared = false

        init(_ parent: RoomHuntARContainer) {
            self.parent = parent
        }

        func runSession() {
            guard let arView else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.worldAlignment = .gravityAndHeading
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        func sync(
            placements: [RoomHuntPlacement],
            removedMeccaIDs: Set<UUID>,
            isCleared: Bool,
            in arView: ARView
        ) {
            for id in removedMeccaIDs {
                placers.removeValue(forKey: id)?.clear()
                if id == parent.primaryMeccaID {
                    preciseController?.clear()
                    preciseController = nil
                }
            }

            if isCleared {
                clearAll()
                hasCleared = true
                return
            }
            guard !hasCleared else { return }

            if let worldMap = parent.primaryWorldMap,
               !hasActivatedPrimaryWorldMap,
               let primaryID = parent.primaryMeccaID,
               let primary = placements.first(where: { $0.id == primaryID }) {
                activatePrimaryWorldMap(
                    worldMap,
                    primary: primary,
                    in: arView
                )
            }

            for placement in placements
            where placers[placement.id] == nil
                && (!(hasActivatedPrimaryWorldMap || parent.reservePrimaryForExactMap)
                    || placement.id != parent.primaryMeccaID) {
                let placer = ARMeccaPlacer()
                placers[placement.id] = placer
                placer.update(
                    bearingDegrees: placement.bearingDegrees,
                    distanceMeters: placement.distanceMeters,
                    freezeWithinMeters: .greatestFiniteMagnitude,
                    lateralOffsetMeters: placement.lateralOffsetMeters,
                    headingDegrees: hasActivatedPrimaryWorldMap
                        ? placement.headingDegrees
                        : nil,
                    appearance: placement.appearance,
                    in: arView
                )
            }
        }

        private func activatePrimaryWorldMap(
            _ worldMap: ARWorldMap,
            primary: RoomHuntPlacement,
            in arView: ARView
        ) {
            // Loading an initialWorldMap resets the AR coordinate system. Clear
            // coordinate anchors first, then immediately recreate the other
            // room Meccas in the new session so none wait on plane detection.
            for placer in placers.values { placer.clear() }
            placers.removeAll()

            let controller = PreciseMeccaARController()
            controller.onStateChange = { [weak self] state in
                self?.parent.preciseState = state
            }
            preciseController = controller
            hasActivatedPrimaryWorldMap = true
            controller.start(
                worldMap: worldMap,
                appearance: primary.appearance,
                fallbackPlacement: nil,
                in: arView
            )
        }

        func clearAll() {
            for placer in placers.values { placer.clear() }
            placers.removeAll()
            preciseController?.clear()
            preciseController = nil
        }

        @objc
        func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = recognizer.location(in: arView)
            guard let tapped = arView.entity(at: point) else { return }

            if preciseController?.contains(tapped) == true,
               let primaryMeccaID = parent.primaryMeccaID {
                parent.tappedMeccaID = primaryMeccaID
                return
            }
            if let match = placers.first(where: { $0.value.contains(tapped) }) {
                parent.tappedMeccaID = match.key
            }
        }
    }
}
