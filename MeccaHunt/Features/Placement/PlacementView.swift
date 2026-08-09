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
    @State private var scanCoverageDegrees = 0.0
    @State private var scannedSectors: Set<Int> = []
    @State private var placementStartedAt: Date?
    @State private var placementEnvironment: PlacementEnvironment = .indoorOrWorldMap(
        hasLiDAR: PlacementEnvironment.deviceHasLiDAR
    )
    @State private var geoLocalized = false
    @State private var facePhoto: UIImage?
    @State private var facePhotoRevision = 0
    @State private var isFaceCameraPresented = false

    private var configuration: MeccaPlacementConfiguration {
        let referenceMillimeters = Double(MeccaEntityFactory.referenceHeightMeters * 1_000)
        return MeccaPlacementConfiguration(
            sizeScale: Float(sizeMillimeters / referenceMillimeters),
            xRotationDegrees: Float(xRotationDegrees),
            yRotationDegrees: Float(yRotationDegrees),
            facePhotoRevision: facePhotoRevision,
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
                placeToken: placeToken,
                scanCoverageDegrees: $scanCoverageDegrees,
                scannedSectors: $scannedSectors,
                placementStartedAt: $placementStartedAt,
                usesGeoTracking: placementEnvironment.placementMode == .geo,
                showSceneMesh: placementEnvironment.usesLiDAR,
                geoLocalized: $geoLocalized,
                facePhoto: facePhoto,
                isFaceCameraActive: isFaceCameraPresented
            )
            .ignoresSafeArea()

            Crosshair(active: canPlace)

            if placementCount > 0, placementEnvironment.placementMode == .worldMap {
                ScanCoverageRing(filledSectors: scannedSectors)
                    .frame(width: 72, height: 72)
                    .allowsHitTesting(false)
                    .padding(.top, 96)
            }

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

                    Label(
                        placementEnvironment.placementMode == .geo
                            ? "OUTDOOR GEO"
                            : "PLACE MODE",
                        systemImage: placementEnvironment.placementMode == .geo
                            ? "location.north.circle.fill"
                            : "arkit"
                    )
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(.mint.opacity(0.92), in: Capsule())
                        .foregroundStyle(.black)
                }

                Spacer()

                placeHint

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
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text("Line up the center reticle on a floor, table, or wall. When it turns green, tap anywhere to place your Mecca there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)

                        HStack {
                            Label("\(placementCount) placed", systemImage: "mappin.and.ellipse")
                                .font(.caption.weight(.bold))

                            Spacer()

                            if placementCount > 0 {
                                Button("Clear", systemImage: "trash") {
                                    resetToken += 1
                                    placementCount = 0
                                    scanCoverageDegrees = 0
                                    scannedSectors = []
                                    placementStartedAt = nil
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
                            tintColor: $tintColor,
                            facePhoto: facePhoto,
                            cameraAvailable: UIImagePickerController
                                .isSourceTypeAvailable(.camera),
                            onTakeFacePhoto: {
                                isFaceCameraPresented = true
                            },
                            onRemoveFacePhoto: {
                                facePhoto = nil
                                facePhotoRevision += 1
                            }
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
            placementEnvironment = await PlacementEnvironment.resolve(
                location: location.currentLocation
            )
        }
        .task(id: location.currentLocation?.timestamp) {
            // Re-check when GPS settles, but don't flip modes after a Mecca is placed.
            guard placementCount == 0 else { return }
            placementEnvironment = await PlacementEnvironment.resolve(
                location: location.currentLocation
            )
        }
        .task {
            // Poll ARKit's world-mapping / geo status so we can unlock save.
            while !Task.isCancelled {
                mappingQuality = arSession.currentMappingStatus()
                geoLocalized = arSession.isGeoLocalized
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        .sheet(isPresented: $isFaceCameraPresented) {
            FaceCameraCaptureView(
                isPresented: $isFaceCameraPresented
            ) { image in
                facePhoto = image
                facePhotoRevision += 1
            }
            .ignoresSafeArea()
        }
    }

    private var placeHintText: String {
        if placementCount > 0 {
            return "Tap another spot to move your Mecca"
        }
        return canPlace
            ? "Reticle locked — tap to place your Mecca"
            : "Move your phone slowly to scan a surface…"
    }

    private var placeHint: some View {
        Label(placeHintText, systemImage: canPlace ? "hand.tap.fill" : "viewfinder")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(canPlace ? .black : .white)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                (canPlace ? Color.mint.opacity(0.95) : Color.black.opacity(0.5)),
                in: RoundedRectangle(cornerRadius: 22)
            )
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: canPlace)
            .accessibilityHint(canPlace
                ? "Tap anywhere on the surface to place a Mecca there"
                : "Move your phone to scan a surface before placing")
    }

    /// Hard cap so placement never asks for more than a minute of scanning.
    private static let maxPlacementSeconds: TimeInterval = 60
    /// Orbit sectors (heat map). Filling enough of these unlocks save indoors.
    private static let sectorCount = 8

    private var placementElapsed: TimeInterval {
        guard let placementStartedAt else { return 0 }
        return Date().timeIntervalSince(placementStartedAt)
    }

    private var placementTimedOut: Bool {
        placementCount > 0 && placementElapsed >= Self.maxPlacementSeconds
    }

    /// LiDAR rooms need less orbit; outdoor world-map is medium; plain indoor is most.
    private var requiredSectors: Int {
        if placementEnvironment.usesLiDAR { return 3 }
        return 4
    }

    private var requiredOrbitDegrees: Double {
        if placementEnvironment.usesLiDAR { return 70 }
        return 100
    }

    /// Save unlocks once the spot is captured well enough — or at 60s with a
    /// usable partial map so placement never stalls.
    private var canSave: Bool {
        guard
            !isSaving,
            !alreadyPlacedToday,
            placementCount > 0,
            location.currentLocation != nil
        else { return false }

        switch placementEnvironment.placementMode {
        case .geo:
            return geoLocalized || placementTimedOut
        case .worldMap:
            let coverageReady =
                scannedSectors.count >= requiredSectors
                || scanCoverageDegrees >= requiredOrbitDegrees
            if mappingQuality == .mapped, coverageReady { return true }
            if mappingQuality == .mapped, placementEnvironment.usesLiDAR,
               scannedSectors.count >= 2 {
                return true
            }
            // Time budget: accept a partial but usable map rather than blocking forever.
            if placementTimedOut,
               mappingQuality == .mapped || mappingQuality == .extending {
                return true
            }
            return false
        }
    }

    @ViewBuilder
    private var saveSection: some View {
        if alreadyPlacedToday {
            dailyLimitNote
        } else {
            VStack(spacing: 10) {
                Label(saveInstructionText, systemImage: "dot.viewfinder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                if placementEnvironment.placementMode == .worldMap {
                    mappingQualityLabel
                    if placementCount > 0 {
                        Text(timerLabel)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(placementTimedOut ? .mint : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Label(
                        geoLocalized
                            ? "Outdoor geo lock ready — you can save"
                            : "Look around outdoors until geo tracking locks on",
                        systemImage: geoLocalized
                            ? "checkmark.circle.fill"
                            : "location.north.line"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(geoLocalized ? .mint : .yellow)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !canSave, !isSaving {
                    Label(saveBlockedReason, systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                .tint(canSave ? .mint : .gray)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.55)
            }
        }
    }

    private var saveInstructionText: String {
        switch placementEnvironment.placementMode {
        case .geo:
            return "Outdoors: Apple geo tracking will pin this Mecca to GPS. Place it, wait for the lock, then save — usually under a minute."
        case .worldMap:
            if placementEnvironment.usesLiDAR {
                return "LiDAR is scanning the room. Turn so the ring fills a few sectors, then save. Caps at 60 seconds."
            }
            return "Walk around the Mecca so the ring fills, then save. Caps at 60 seconds so this never takes forever."
        }
    }

    private var timerLabel: String {
        let remaining = max(0, Int(Self.maxPlacementSeconds - placementElapsed))
        if placementTimedOut {
            return "Time budget reached — save with the best map captured."
        }
        return "Scan time left: \(remaining)s"
    }

    private var saveBlockedReason: String {
        if location.currentLocation == nil {
            return "Waiting for GPS — step near a window or outdoors before saving."
        }
        if placementEnvironment.placementMode == .geo {
            return "Keep looking around outside until geo tracking locks (or wait up to 60s)."
        }
        let sectorsLeft = max(0, requiredSectors - scannedSectors.count)
        if sectorsLeft > 0, mappingQuality != .mapped {
            return "Turn slowly to fill the scan ring (\(sectorsLeft) sectors left) and build the AR map."
        }
        if sectorsLeft > 0 {
            return "Turn a bit more to fill the scan ring (\(sectorsLeft) sectors left)."
        }
        switch mappingQuality {
        case .mapped:
            return "Ready to save."
        case .extending:
            return "Almost ready — a bit more scanning helps (auto-unlocks at 60s)."
        default:
            return "Scan the area around the Mecca until the AR map is ready."
        }
    }

    @ViewBuilder
    private var mappingQualityLabel: some View {
        let coverageReady =
            scannedSectors.count >= requiredSectors
            || scanCoverageDegrees >= requiredOrbitDegrees
        let (text, symbol, tint): (String, String, Color) = {
            if mappingQuality == .mapped, coverageReady {
                return ("AR map ready — you can save", "checkmark.circle.fill", .mint)
            }
            if !coverageReady {
                return (
                    "Scan ring \(scannedSectors.count)/\(requiredSectors) sectors",
                    "circle.dotted",
                    .yellow
                )
            }
            switch mappingQuality {
            case .extending:
                return ("Almost ready — keep scanning", "circle.lefthalf.filled", .yellow)
            default:
                return ("Building AR map…", "arkit", .orange)
            }
        }()
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
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
                    : placementEnvironment.placementMode == .geo
                        ? "Saved with outdoor geo tracking — hunters can lock on outside."
                        : "Saved successfully.")
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
        guard canSave, let owner = appState.currentUser else { return }

        let mode = placementEnvironment.placementMode
        if mode == .worldMap {
            let mapReady = mappingQuality == .mapped
                || (placementTimedOut && mappingQuality == .extending)
            guard mapReady else {
                saveError = "Keep scanning until the AR map is ready, then try again."
                return
            }
        }

        let name = "\(owner.username)'s Mecca"
        let notBefore = isDailyLimitExempt
            ? Date.distantFuture
            : Calendar.current.startOfDay(for: Date())

        saveError = nil
        isSaving = true
        didSaveWithMap = false
        Task {
            do {
                switch mode {
                case .geo:
                    try await saveWithGeo(
                        owner: owner,
                        name: name,
                        notBefore: notBefore
                    )
                case .worldMap:
                    try await saveWithWorldMap(
                        owner: owner,
                        name: name,
                        notBefore: notBefore
                    )
                }
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

    private func saveWithGeo(
        owner: User,
        name: String,
        notBefore: Date
    ) async throws {
        saveStatus = "Locking outdoor location…"
        let coordinate: GeoCoordinate
        if let geo = await arSession.captureGeoCoordinate() {
            coordinate = geo
        } else if let fix = await location.captureBestLocation(seconds: 3) {
            coordinate = GeoCoordinate(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                altitude: fix.verticalAccuracy >= 0 ? fix.altitude : nil
            )
        } else {
            saveError = "Couldn't lock an outdoor location. Stay outside with a clear sky view and try again."
            return
        }

        saveStatus = "Saving…"
        let mecca = try await appState.dependencies.meccas.createMecca(
            ownerID: owner.id,
            name: name,
            coordinate: coordinate,
            appearance: appearance,
            placementMode: .geo,
            notBefore: notBefore
        )
        await uploadFacePhotoIfNeeded(meccaID: mecca.id)
        didSaveWithMap = false
        didSave = true
    }

    private func saveWithWorldMap(
        owner: User,
        name: String,
        notBefore: Date
    ) async throws {
        saveStatus = "Capturing AR map — hold still…"
        let minimumPoints = placementTimedOut ? 40 : ARWorldMapArchiver.minimumFeaturePoints
        switch await arSession.captureWorldMap(minimumFeaturePoints: minimumPoints) {
        case .failure(let failure):
            saveError = failure.errorDescription
            return
        case .success(let worldMapData):
            saveStatus = "Locking GPS — hold still…"
            guard let fix = await location.captureBestLocation(seconds: 3) else {
                saveError = "Couldn't get a GPS fix. Try again near a window or outdoors."
                return
            }
            let coordinate = GeoCoordinate(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                altitude: fix.verticalAccuracy >= 0 ? fix.altitude : nil
            )
            saveStatus = "Saving…"
            let mecca = try await appState.dependencies.meccas.createMecca(
                ownerID: owner.id,
                name: name,
                coordinate: coordinate,
                appearance: appearance,
                placementMode: .worldMap,
                notBefore: notBefore
            )
            saveStatus = "Uploading AR map…"
            do {
                try await appState.dependencies.meccas.uploadWorldMap(
                    meccaID: mecca.id,
                    compressedData: worldMapData
                )
                await uploadFacePhotoIfNeeded(meccaID: mecca.id)
                didSaveWithMap = true
                didSave = true
            } catch {
                try? await appState.dependencies.meccas.deleteMecca(
                    id: mecca.id,
                    ownerID: owner.id
                )
                saveError = "Couldn't upload the AR map. Check your connection and try saving again."
            }
        }
    }

    private func uploadFacePhotoIfNeeded(meccaID: UUID) async {
        guard let jpeg = facePhoto?.jpegData(compressionQuality: 0.72) else { return }
        do {
            try await appState.dependencies.meccas.uploadFacePhoto(
                meccaID: meccaID,
                jpegData: jpeg
            )
        } catch {
            // Appearance still saved; face is best-effort so a photo upload
            // glitch doesn't block hiding the Mecca.
        }
    }
}

/// Shared handle to the placement AR session so `PlacementView` can capture the
/// world map / geo location and read mapping quality without owning the `ARView`.
@MainActor
final class PlacementARSession {
    weak var arView: ARView?

    func currentMappingStatus() -> ARFrame.WorldMappingStatus {
        arView?.session.currentFrame?.worldMappingStatus ?? .notAvailable
    }

    var isGeoLocalized: Bool {
        arView?.session.currentFrame?.geoTrackingStatus?.state == .localized
    }

    /// Best-effort geo coordinate for the currently placed Mecca anchor.
    func captureGeoCoordinate() async -> GeoCoordinate? {
        guard
            let session = arView?.session,
            let anchor = session.currentFrame?.anchors.first(where: {
                $0.name == PreciseMeccaARController.anchorName
            })
        else { return nil }

        let point = SIMD3<Float>(
            anchor.transform.columns.3.x,
            anchor.transform.columns.3.y,
            anchor.transform.columns.3.z
        )
        return await withCheckedContinuation { continuation in
            session.getGeoLocation(forPoint: point) { coordinate, altitude, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: GeoCoordinate(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        altitude: altitude
                    )
                )
            }
        }
    }

    /// Asks ARKit for the current world map and returns it archived + compressed.
    /// Fails with a user-facing reason when the map is missing or too sparse.
    func captureWorldMap(
        minimumFeaturePoints: Int = ARWorldMapArchiver.minimumFeaturePoints
    ) async -> Result<Data, CaptureFailure> {
        guard let session = arView?.session else {
            return .failure(.message(
                "AR session isn't ready yet. Keep the camera on the Mecca and try again."
            ))
        }
        return await withCheckedContinuation { continuation in
            session.getCurrentWorldMap { map, error in
                guard let map else {
                    let message = error?.localizedDescription
                        ?? "Couldn't capture the AR map. Keep scanning from more angles, hold still, and try again."
                    continuation.resume(returning: .failure(.message(message)))
                    return
                }
                do {
                    continuation.resume(
                        returning: .success(
                            try ARWorldMapArchiver.encode(
                                map,
                                minimumFeaturePoints: minimumFeaturePoints
                            )
                        )
                    )
                } catch {
                    continuation.resume(
                        returning: .failure(.message(
                            (error as? LocalizedError)?.errorDescription
                                ?? error.localizedDescription
                        ))
                    )
                }
            }
        }
    }

    enum CaptureFailure: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }
}

private struct MeccaPlacementConfiguration: Equatable {
    let sizeScale: Float
    let xRotationDegrees: Float
    let yRotationDegrees: Float
    let facePhotoRevision: Int
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
    let facePhoto: UIImage?
    let cameraAvailable: Bool
    let onTakeFacePhoto: () -> Void
    let onRemoveFacePhoto: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ColorPicker(
                "Mecca color",
                selection: $tintColor,
                supportsOpacity: false
            )
            .font(.subheadline.weight(.semibold))

            FacePhotoControl(
                image: facePhoto,
                cameraAvailable: cameraAvailable,
                onTakePhoto: onTakeFacePhoto,
                onRemovePhoto: onRemoveFacePhoto
            )

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

private struct FacePhotoControl: View {
    let image: UIImage?
    let cameraAvailable: Bool
    let onTakePhoto: () -> Void
    let onRemovePhoto: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.5)))
                }

                Button {
                    onTakePhoto()
                } label: {
                    Label(
                        image == nil ? "Add your face" : "Retake face photo",
                        systemImage: "camera.fill"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(!cameraAvailable)

                if image != nil {
                    Button(role: .destructive) {
                        onRemovePhoto()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Remove face photo")
                }
            }

            Text(
                cameraAvailable
                    ? "Saved with the Mecca — hunters will see this face."
                    : "A physical iPhone camera is required for a face photo."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
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

private struct ScanCoverageRing: View {
    let filledSectors: Set<Int>
    private let sectorCount = 8

    var body: some View {
        ZStack {
            ForEach(0..<sectorCount, id: \.self) { index in
                Circle()
                    .trim(
                        from: CGFloat(index) / CGFloat(sectorCount),
                        to: CGFloat(index + 1) / CGFloat(sectorCount) - 0.012
                    )
                    .stroke(
                        filledSectors.contains(index)
                            ? Color.mint.opacity(0.95)
                            : Color.white.opacity(0.22),
                        style: StrokeStyle(lineWidth: 8, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
            Text("\(filledSectors.count)/\(sectorCount)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.6), radius: 4)
        .accessibilityLabel("Scan coverage \(filledSectors.count) of \(sectorCount) sectors")
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
    @Binding var scanCoverageDegrees: Double
    @Binding var scannedSectors: Set<Int>
    @Binding var placementStartedAt: Date?
    let usesGeoTracking: Bool
    let showSceneMesh: Bool
    @Binding var geoLocalized: Bool
    let facePhoto: UIImage?
    let isFaceCameraActive: Bool

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
        coaching.goal = usesGeoTracking ? .geoTracking : .anyPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        context.coordinator.coachingOverlay = coaching
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
        context.coordinator.setFaceCameraActive(isFaceCameraActive)
        context.coordinator.applyTrackingModeIfNeeded()
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
        private var faceCameraIsActive = false
        /// Last camera yaw (degrees) used to accumulate orbit coverage.
        private var lastYawDegrees: Double?
        private var accumulatedScanDegrees: Double = 0
        private var lastUsesGeoTracking: Bool?
        weak var coachingOverlay: ARCoachingOverlayView?

        init(_ parent: PlacementARView) {
            self.parent = parent
            lastResetToken = parent.resetToken
            lastPlaceToken = parent.placeToken
        }

        func runSession() {
            runSession(resetTracking: true)
        }

        func applyTrackingModeIfNeeded() {
            guard lastUsesGeoTracking != parent.usesGeoTracking else { return }
            // Don't tear down tracking after a Mecca is already placed.
            guard parent.placementCount == 0 else { return }
            runSession(resetTracking: true)
        }

        private func runSession(resetTracking: Bool) {
            guard let arView else { return }
            lastUsesGeoTracking = parent.usesGeoTracking
            coachingOverlay?.goal = parent.usesGeoTracking ? .geoTracking : .anyPlane

            let options: ARSession.RunOptions = resetTracking
                ? [.resetTracking, .removeExistingAnchors]
                : []

            if parent.usesGeoTracking, ARGeoTrackingConfiguration.isSupported {
                let configuration = ARGeoTrackingConfiguration()
                configuration.planeDetection = [.horizontal, .vertical]
                arView.session.run(configuration, options: options)
                // Mesh overlay isn't used outdoors — geo imagery is the signal.
                arView.environment.sceneUnderstanding.options = []
            } else {
                let configuration = ARWorldTrackingConfiguration()
                configuration.planeDetection = [.horizontal, .vertical]
                configuration.environmentTexturing = .automatic
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    configuration.sceneReconstruction = .mesh
                }
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    configuration.frameSemantics.insert(.sceneDepth)
                }
                arView.session.run(configuration, options: options)

                // Soft LiDAR mesh cue indoors so the denser scan is visible without
                // a full RoomPlan flow (which would blow the 60s budget).
                if parent.showSceneMesh {
                    arView.environment.sceneUnderstanding.options = [
                        .occlusion, .receivesLighting, .collision
                    ]
                } else {
                    arView.environment.sceneUnderstanding.options = []
                }
            }
        }

        func setFaceCameraActive(_ isActive: Bool) {
            guard isActive != faceCameraIsActive else { return }
            faceCameraIsActive = isActive

            if isActive {
                arView?.session.pause()
            } else {
                runSession(resetTracking: false)
            }
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

            updateScanCoverage()
        }

        /// Accumulates how far the camera has turned while a Mecca is placed.
        /// Walking around the Mecca builds a denser multi-angle world map and
        /// fills the sector heat ring.
        private func updateScanCoverage() {
            guard parent.placementCount > 0,
                  let frame = arView?.session.currentFrame
            else { return }

            let forward = -SIMD3<Float>(
                frame.camera.transform.columns.2.x,
                0,
                frame.camera.transform.columns.2.z
            )
            guard simd_length(forward) > 0.001 else { return }
            let yaw = Double(atan2(forward.x, -forward.z)) * 180 / .pi

            // 8 sectors around the compass for the heat-map ring.
            let sector = Int(((yaw + 180) / 45).rounded(.down)) % 8
            if !parent.scannedSectors.contains(sector) {
                parent.scannedSectors.insert(sector)
            }

            if let last = lastYawDegrees {
                var delta = yaw - last
                while delta > 180 { delta -= 360 }
                while delta < -180 { delta += 360 }
                accumulatedScanDegrees = min(
                    360,
                    accumulatedScanDegrees + abs(delta)
                )
                if abs(parent.scanCoverageDegrees - accumulatedScanDegrees) >= 1 {
                    parent.scanCoverageDegrees = accumulatedScanDegrees
                }
            }
            lastYawDegrees = yaw
        }

        private func setCanPlace(_ value: Bool) {
            guard value != lastReportedCanPlace else { return }
            lastReportedCanPlace = value
            parent.canPlace = value
            if placedMeccas.isEmpty {
                parent.message = value
                    ? "Surface found — tap the floor to place your Mecca"
                    : "Move your phone slowly to scan a surface"
            }
        }

        /// Tries progressively looser raycast targets so placement works on
        /// mapped planes, their infinite extensions, and rough estimates.
        private func bestSurfaceHit() -> SurfaceHit? {
            guard let arView else { return nil }
            return surfaceHit(at: CGPoint(x: arView.bounds.midX, y: arView.bounds.midY))
        }

        /// Raycasts from a screen point to the nearest surface, trying looser
        /// targets in turn so placement works even on low-texture walls/floors.
        private func surfaceHit(at point: CGPoint) -> SurfaceHit? {
            guard let arView else { return nil }
            let targets: [ARRaycastQuery.Target] = [
                .existingPlaneGeometry,
                .existingPlaneInfinite,
                .estimatedPlane
            ]
            for target in targets {
                if let result = arView.raycast(
                    from: point,
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
            // Always place at the center reticle's hit. It resolves against
            // LiDAR plane geometry first, so it's far more accurate than a
            // raycast from an arbitrary finger location.
            place(at: latestHit)
        }

        func handlePlaceToken(_ token: Int) {
            guard token != lastPlaceToken else { return }
            lastPlaceToken = token
            place(at: latestHit)
        }

        private func place(at hit: SurfaceHit?) {
            guard let arView, let hit else {
                parent.message = "No surface found yet — keep scanning and try again"
                return
            }

            // Only one Mecca can be hidden at a time, so replace any previously
            // placed preview before adding the new one.
            placedMeccas.forEach { $0.anchor.removeFromParent() }
            placedMeccas.removeAll()
            lastYawDegrees = nil
            accumulatedScanDegrees = 0
            parent.scanCoverageDegrees = 0
            parent.scannedSectors = []
            parent.placementStartedAt = Date()

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
            let placementFacePhoto = parent.facePhoto
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
                self.apply(
                    placementConfiguration,
                    facePhoto: placementFacePhoto,
                    shouldUpdateFacePhoto: true,
                    to: placedMecca
                )
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
            lastYawDegrees = nil
            accumulatedScanDegrees = 0
            parent.scanCoverageDegrees = 0
            parent.scannedSectors = []
            parent.placementStartedAt = nil
        }

        func applyConfigurationToLatestMecca() {
            let configuration = parent.configuration
            guard configuration != lastAppliedConfiguration else { return }
            if let latest = placedMeccas.last {
                let facePhotoChanged = configuration.facePhotoRevision
                    != lastAppliedConfiguration?.facePhotoRevision
                apply(
                    configuration,
                    facePhoto: parent.facePhoto,
                    shouldUpdateFacePhoto: facePhotoChanged,
                    to: latest
                )
            }
            lastAppliedConfiguration = configuration
        }

        private func apply(
            _ configuration: MeccaPlacementConfiguration,
            facePhoto: UIImage?,
            shouldUpdateFacePhoto: Bool,
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

            if shouldUpdateFacePhoto {
                let didApplyFacePhoto = MeccaEntityFactory.applyFacePhoto(
                    facePhoto,
                    to: placedMecca.entity
                )
                if facePhoto != nil {
                    parent.message = didApplyFacePhoto
                        ? "Face photo applied — rotate the Mecca to view it"
                        : "Couldn't apply the face photo — please retake it"
                }
            }
        }

        private static func reticleMaterial(valid: Bool) -> UnlitMaterial {
            UnlitMaterial(
                color: (valid ? UIColor.systemGreen : UIColor.systemRed)
                    .withAlphaComponent(0.55)
            )
        }
    }
}
