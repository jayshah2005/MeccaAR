import ARKit
import CoreLocation
import RealityKit
import UIKit

/// Outdoor centimeter-class placement via Apple's geo localization imagery.
/// Adds an `ARGeoAnchor` at the Mecca's lat/long (and altitude when known) and
/// bakes the entity once geo tracking reports `.localized`.
@MainActor
final class GeoMeccaARController: NSObject, ARSessionDelegate,
    ARCoachingOverlayViewDelegate {
    static let anchorName = "mecca"

    enum State: Equatable {
        case initializing
        case localizing
        case located
    }

    var onStateChange: ((State) -> Void)?

    private weak var arView: ARView?
    private var meccaEntity: Entity?
    private var appearance: MeccaAppearance = .default
    private var facePhoto: UIImage?
    private var coachingOverlay: ARCoachingOverlayView?
    private var geoAnchor: ARGeoAnchor?
    private var placed = false

    func start(
        coordinate: CLLocationCoordinate2D,
        altitude: Double?,
        appearance: MeccaAppearance,
        facePhoto: UIImage? = nil,
        in arView: ARView
    ) {
        self.arView = arView
        self.appearance = appearance
        self.facePhoto = facePhoto
        arView.session.delegate = self

        let configuration = ARGeoTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )

        let anchor: ARGeoAnchor
        if let altitude {
            anchor = ARGeoAnchor(
                name: Self.anchorName,
                coordinate: coordinate,
                altitude: altitude
            )
        } else {
            anchor = ARGeoAnchor(name: Self.anchorName, coordinate: coordinate)
        }
        geoAnchor = anchor
        arView.session.add(anchor: anchor)

        installCoachingOverlay(in: arView)
        onStateChange?(.localizing)
    }

    func contains(_ entity: Entity) -> Bool {
        guard let meccaEntity else { return false }
        return entity == meccaEntity || entity.isDescendant(of: meccaEntity)
    }

    private func installCoachingOverlay(in arView: ARView) {
        guard coachingOverlay == nil else { return }
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.delegate = self
        coaching.goal = .geoTracking
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
        ])
        coachingOverlay = coaching
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        placeIfReady(using: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        placeIfReady(using: anchors)
    }

    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
        switch geoTrackingStatus.state {
        case .localized:
            placeIfReady(using: session.currentFrame?.anchors ?? [])
            onStateChange?(placed ? .located : .localizing)
        case .localizing, .initializing:
            if !placed { onStateChange?(.localizing) }
        case .notAvailable:
            if !placed { onStateChange?(.initializing) }
        @unknown default:
            if !placed { onStateChange?(.localizing) }
        }
    }

    private func placeIfReady(using anchors: [ARAnchor]) {
        guard
            !placed,
            let arView,
            let geoAnchor,
            let live = anchors.first(where: { $0.identifier == geoAnchor.identifier })
                ?? anchors.compactMap({ $0 as? ARGeoAnchor }).first(where: {
                    $0.name == Self.anchorName
                }),
            arView.session.currentFrame?.geoTrackingStatus?.state == .localized
        else { return }

        placed = true
        coachingOverlay?.setActive(false, animated: true)

        let anchorEntity = AnchorEntity(anchor: live)
        arView.scene.addAnchor(anchorEntity)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let entity = await MeccaEntityFactory.make()
            MeccaEntityFactory.apply(self.appearance, to: entity)
            if let facePhoto = self.facePhoto {
                _ = MeccaEntityFactory.applyFacePhoto(facePhoto, to: entity)
            }
            anchorEntity.addChild(entity)
            self.meccaEntity = entity
            self.onStateChange?(.located)
        }
    }

    func coachingOverlayViewWillActivate(_ overlayView: ARCoachingOverlayView) {
        if !placed { onStateChange?(.localizing) }
    }

    func coachingOverlayViewDidDeactivate(_ overlayView: ARCoachingOverlayView) {
        if let anchors = arView?.session.currentFrame?.anchors {
            placeIfReady(using: anchors)
        }
    }

    /// Applies a face photo that arrived after `start` (async download).
    func updateFacePhoto(_ image: UIImage?) {
        facePhoto = image
        guard let meccaEntity else { return }
        _ = MeccaEntityFactory.applyFacePhoto(image, to: meccaEntity)
    }
}
