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
    @State private var savedCapturePercentage = 0
    @State private var alreadyPlacedToday = false
    @State private var saveStatus = "Save to map"
    @State private var arSession = PlacementARSession()
    @State private var environmentScan = PlacementARSession.EnvironmentScanSnapshot.empty
    @State private var isScanReviewPresented = false
    @State private var canPlace = false
    @State private var placeToken = 0
    @State private var facePhoto: UIImage?
    @State private var pendingFacePhoto: UIImage?
    @State private var facePhotoPlacement = MeccaPhotoPlacement.initial
    @State private var facePhotoRevision = 0
    @State private var isFaceCameraPresented = false
    @State private var isFaceEditorPresented = false

    private var configuration: MeccaPlacementConfiguration {
        let referenceMillimeters = Double(MeccaEntityFactory.referenceHeightMeters * 1_000)
        return MeccaPlacementConfiguration(
            sizeScale: Float(sizeMillimeters / referenceMillimeters),
            xRotationDegrees: Float(xRotationDegrees),
            yRotationDegrees: Float(yRotationDegrees),
            facePhotoPlacement: facePhotoPlacement,
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

    private var environmentScanIsReady: Bool {
        guard environmentScan.directionalProgress >= 1,
              environmentScan.parallaxProgress >= 1
        else { return false }
        return environmentScan.mappingStatus == .mapped
    }

    private var capturePercentage: Int {
        Int((environmentScan.roomCaptureProgress * 100).rounded())
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
                facePhoto: facePhoto,
                isFaceCameraActive: isFaceCameraPresented || isFaceEditorPresented
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
                        ScrollView(.vertical) {
                            toolbarScrollableContent
                                .padding(.trailing, 4)
                        }
                        .scrollIndicators(.visible)
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(
                            maxHeight: min(
                                UIScreen.main.bounds.height * 0.45,
                                430
                            )
                        )

                        if placementCount > 0 && !alreadyPlacedToday {
                            Divider()
                            reviewAndSaveButton
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

            if isScanReviewPresented && !didSave {
                scanReviewOverlay
            }
        }
        .preferredColorScheme(.dark)
        .task { await MeccaEntityFactory.preload() }
        .task {
            location.start()
            await checkDailyLimit()
        }
        .task {
            // Sample the viewing direction slowly enough that turning the phone
            // through every direction is a real scan rather than a quick spin.
            while !Task.isCancelled {
                environmentScan = arSession.environmentScanSnapshot()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .sheet(
            isPresented: $isFaceCameraPresented,
            onDismiss: {
                if pendingFacePhoto != nil {
                    isFaceEditorPresented = true
                }
            }
        ) {
            FaceCameraCaptureView(
                isPresented: $isFaceCameraPresented
            ) { image in
                pendingFacePhoto = image
            }
            .ignoresSafeArea()
        }
        .sheet(
            isPresented: $isFaceEditorPresented,
            onDismiss: {
                pendingFacePhoto = nil
            }
        ) {
            if let editorImage = pendingFacePhoto ?? facePhoto {
                MeccaPhotoPlacementEditor(
                    image: editorImage,
                    tintColor: tintColor,
                    initialPlacement: facePhotoPlacement
                ) { placement in
                    facePhoto = editorImage
                    facePhotoPlacement = placement
                    facePhotoRevision += 1
                    pendingFacePhoto = nil
                }
            }
        }
    }

    private var toolbarScrollableContent: some View {
        VStack(spacing: 12) {
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
                tintColor: $tintColor,
                facePhoto: facePhoto,
                cameraAvailable: UIImagePickerController
                    .isSourceTypeAvailable(.camera),
                onTakeFacePhoto: {
                    pendingFacePhoto = nil
                    isFaceCameraPresented = true
                },
                onPositionFacePhoto: {
                    isFaceEditorPresented = true
                },
                onRemoveFacePhoto: {
                    facePhoto = nil
                    pendingFacePhoto = nil
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
                    scanInstruction,
                    systemImage: environmentScanIsReady
                        ? "checkmark.circle.fill"
                        : "figure.walk.motion"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(environmentScanIsReady ? .mint : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 7) {
                    HStack {
                        Label("360° room captured", systemImage: "camera.metering.matrix")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Text("\(capturePercentage)%")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(capturePercentage == 100 ? .mint : .yellow)
                    }
                    ProgressView(value: environmentScan.roomCaptureProgress)
                        .tint(capturePercentage == 100 ? .mint : .yellow)
                        .scaleEffect(y: 1.5)
                }
                .padding(10)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))

                mappingQualityLabel

                ScanPassProgress(
                    title: "1. Phone level",
                    systemImage: "iphone",
                    progress: environmentScan.levelProgress
                )
                ScanPassProgress(
                    title: "2. Tilt toward floor",
                    systemImage: "arrow.down.forward",
                    progress: environmentScan.downwardProgress
                )
                ScanPassProgress(
                    title: "3. Tilt toward ceiling",
                    systemImage: "arrow.up.forward",
                    progress: environmentScan.upwardProgress
                )
                ScanPassProgress(
                    title: "Move at least 0.5 m",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    progress: environmentScan.parallaxProgress
                )

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

            }
        }
    }

    private var reviewAndSaveButton: some View {
        Button {
            isScanReviewPresented = true
        } label: {
            HStack {
                Image(systemName: capturePercentage == 100
                    ? "checkmark.circle.fill"
                    : "viewfinder.circle")
                Text("Save Mecca at \(capturePercentage)%")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.borderedProminent)
        .tint(capturePercentage == 100 ? .mint : .yellow)
        .disabled(location.currentLocation == nil)
        .accessibilityHint(
            "Shows the predicted mapped space before final confirmation."
        )
    }

    @ViewBuilder
    private var mappingQualityLabel: some View {
        let (text, symbol, tint): (String, String, Color) = switch environmentScan.mappingStatus {
        case .mapped where environmentScanIsReady:
            ("Room capture ready for review", "checkmark.circle.fill", .mint)
        case .mapped:
            ("AR map is usable — save now or keep scanning for better coverage",
             "checkmark.circle", .yellow)
        case .extending:
            ("Partial AR map available — more scanning should improve hunter relocalization",
             "circle.lefthalf.filled", .yellow)
        default:
            ("Very early capture — saving may fail until ARKit has enough room features",
             "arkit", .orange)
        }
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scanInstruction: String {
        if environmentScan.isTurningTooFast {
            return "Slow down. Rotate at roughly walking speed and pause briefly on corners, furniture, doors, and windows so ARKit can record sharp visual features."
        }
        if environmentScan.levelProgress < 1 {
            return "Pass 1 of 3: hold the phone upright at chest height. Walk a small circle around the Mecca while turning slowly; keep furniture and wall details in frame."
        }
        if environmentScan.downwardProgress < 1 {
            return "Pass 2 of 3: tilt the phone about 25° toward the floor and make another slow turn. Capture the floor-to-wall edges around the room."
        }
        if environmentScan.upwardProgress < 1 {
            return "Pass 3 of 3: tilt about 25° upward and turn slowly again. Capture upper walls, doors, windows, and the ceiling edge."
        }
        if environmentScan.parallaxProgress < 1 {
            return "Directional passes complete. Take a few slow side steps around the Mecca to add depth; avoid pointing at blank walls only."
        }
        if !environmentScanIsReady {
            return "Coverage is complete, but ARKit needs more visual detail. Move slowly near textured furniture, corners, posters, or door frames."
        }
        return "Capture complete. Review the detected room outline and scan path before committing the Mecca."
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
                    ? "Saved with \(savedCapturePercentage)% room coverage. More coverage generally makes exact relocalization easier for hunters."
                    : "The required 360° AR map could not be saved.")
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

    private var scanReviewOverlay: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Predicted mapped space")
                            .font(.title2.bold())
                        Text("\(capturePercentage)% captured · Mecca shown at its saved anchor")
                            .font(.caption)
                            .foregroundStyle(capturePercentage == 100 ? .mint : .yellow)
                    }
                    Spacer()
                    Button {
                        isScanReviewPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Close scan review")
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)

                ScrollView(.vertical) {
                    VStack(spacing: 18) {
                        RoomCaptureOutline(snapshot: environmentScan)
                            .frame(height: 310)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))

                        Label(
                            environmentScan.surfaceCount > 0
                                ? "Solid mint shapes are detected horizontal surfaces and bright lines are walls. The orange marker is the Mecca's exact saved position."
                                : "No plane outline was detected. The feature map may still relocalize, but scanning corners, furniture, and wall edges will improve reliability.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let saveError {
                            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .scrollIndicators(.visible)

                Divider()

                HStack(spacing: 12) {
                    Button("Scan more", systemImage: "arrow.triangle.2.circlepath") {
                        isScanReviewPresented = false
                    }
                    .buttonStyle(.bordered)

                    Button(action: save) {
                        HStack {
                            if isSaving { ProgressView().tint(.black) }
                            Text(isSaving
                                ? saveStatus
                                : "Confirm Save at \(capturePercentage)%")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .disabled(isSaving)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }
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
        let chosenCapturePercentage = capturePercentage

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
            guard let worldMapData = await arSession.captureWorldMap() else {
                saveError = "The 360° AR map could not be captured. Keep scanning slowly and try again."
                isSaving = false
                return
            }

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
                _ = try await appState.dependencies.meccas.createMappedMecca(
                    ownerID: owner.id,
                    name: name,
                    coordinate: coordinate,
                    appearance: appearance,
                    notBefore: notBefore,
                    worldMapData: worldMapData
                )
                didSaveWithMap = true
                savedCapturePercentage = chosenCapturePercentage
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
    struct SurfaceOutline: Identifiable, Equatable {
        enum Kind: Equatable {
            case floorOrTable
            case wall
        }

        let id: UUID
        let kind: Kind
        let points: [SIMD2<Float>]
    }

    struct EnvironmentScanSnapshot {
        let levelProgress: Double
        let downwardProgress: Double
        let upwardProgress: Double
        let parallaxProgress: Double
        let mappingStatus: ARFrame.WorldMappingStatus
        let featurePointCount: Int
        let surfaces: [SurfaceOutline]
        let cameraPath: [SIMD2<Float>]
        let meccaPosition: SIMD2<Float>?
        let maximumDisplacementMeters: Double
        let isTurningTooFast: Bool

        static let empty = EnvironmentScanSnapshot(
            levelProgress: 0,
            downwardProgress: 0,
            upwardProgress: 0,
            parallaxProgress: 0,
            mappingStatus: .notAvailable,
            featurePointCount: 0,
            surfaces: [],
            cameraPath: [],
            meccaPosition: nil,
            maximumDisplacementMeters: 0,
            isTurningTooFast: false
        )

        var directionalProgress: Double {
            min(levelProgress, downwardProgress, upwardProgress)
        }

        /// Overall 360° coverage across all 72 directional sectors. Movement
        /// and ARKit mapping quality are reported separately because this is the
        /// percentage the user explicitly chooses to save.
        var roomCaptureProgress: Double {
            (levelProgress + downwardProgress + upwardProgress) / 3
        }

        var surfaceCount: Int { surfaces.count }
    }

    private enum ScanBand: CaseIterable {
        case level
        case downward
        case upward
    }

    /// Each pitch pass must cover twenty-four 15° sectors. Frames are sampled
    /// directly from AR rather than by the SwiftUI timer, reducing UI latency.
    private static let environmentSectorCount = 24
    private static let requiredMovementMeters: Float = 0.5
    private static let minimumSampleInterval = 0.12
    private static let maximumAngularSpeedRadiansPerSecond = 0.9
    private static let stableObservationsPerSector = 3
    private static let minimumFeaturePointsPerObservation = 30

    weak var arView: ARView?
    private var isScanningEnvironment = false
    private var observedSectors: [ScanBand: Set<Int>] = [:]
    private var sectorEvidence: [ScanBand: [Int: Int]] = [:]
    private var scanOrigin: SIMD3<Float>?
    private var meccaWorldTransform: simd_float4x4?
    private var meccaWorldPosition: SIMD2<Float>?
    private var maximumDisplacement: Float = 0
    private var cameraPath: [SIMD2<Float>] = []
    private var maximumFeaturePointCount = 0
    private var previousYaw: Double?
    private var previousFrameTimestamp: TimeInterval?
    private var lastSectorSampleTimestamp: TimeInterval?
    private var lastFastTurnTimestamp: TimeInterval?

    func beginEnvironmentScan(meccaTransform: simd_float4x4) {
        observedSectors = Dictionary(
            uniqueKeysWithValues: ScanBand.allCases.map { ($0, Set<Int>()) }
        )
        sectorEvidence = Dictionary(
            uniqueKeysWithValues: ScanBand.allCases.map { ($0, [:]) }
        )
        let camera = arView?.session.currentFrame?.camera.transform.columns.3
        scanOrigin = camera.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        let mecca = meccaTransform.columns.3
        meccaWorldTransform = meccaTransform
        meccaWorldPosition = [mecca.x, mecca.z]
        maximumDisplacement = 0
        cameraPath.removeAll()
        maximumFeaturePointCount = 0
        previousYaw = nil
        previousFrameTimestamp = nil
        lastSectorSampleTimestamp = nil
        lastFastTurnTimestamp = nil
        isScanningEnvironment = true
        arView?.debugOptions = [.showFeaturePoints, .showSceneUnderstanding]
    }

    func resetEnvironmentScan() {
        observedSectors.removeAll()
        sectorEvidence.removeAll()
        scanOrigin = nil
        meccaWorldTransform = nil
        meccaWorldPosition = nil
        maximumDisplacement = 0
        cameraPath.removeAll()
        maximumFeaturePointCount = 0
        previousYaw = nil
        previousFrameTimestamp = nil
        lastSectorSampleTimestamp = nil
        lastFastTurnTimestamp = nil
        isScanningEnvironment = false
        arView?.debugOptions = []
    }

    /// Called from RealityKit's per-frame update. Coverage is accepted only
    /// during normal tracking and a controlled turn; a blurry fast spin does
    /// not fill sectors.
    func recordEnvironmentScanFrame() {
        guard
            isScanningEnvironment,
            let frame = arView?.session.currentFrame,
            case .normal = frame.camera.trackingState
        else { return }

        let transform = frame.camera.transform
        let visibleFeatureCount = frame.rawFeaturePoints?.points.count ?? 0
        maximumFeaturePointCount = max(
            maximumFeaturePointCount,
            visibleFeatureCount
        )
        let position4 = transform.columns.3
        let position = SIMD3<Float>(position4.x, position4.y, position4.z)
        recordMovement(position)

        let forward3 = SIMD3<Float>(
            -transform.columns.2.x,
            -transform.columns.2.y,
            -transform.columns.2.z
        )
        let horizontalForward = SIMD2<Float>(forward3.x, forward3.z)
        guard simd_length(horizontalForward) > 0.25 else { return }

        var yaw = atan2(Double(horizontalForward.x), Double(horizontalForward.y))
        if yaw < 0 { yaw += 2 * .pi }
        let timestamp = frame.timestamp

        defer {
            previousYaw = yaw
            previousFrameTimestamp = timestamp
        }

        guard let previousYaw, let previousFrameTimestamp else { return }
        let elapsed = timestamp - previousFrameTimestamp
        guard elapsed > 0 else { return }
        var yawDelta = abs(yaw - previousYaw)
        yawDelta = min(yawDelta, 2 * .pi - yawDelta)
        let angularSpeed = yawDelta / elapsed
        if angularSpeed > Self.maximumAngularSpeedRadiansPerSecond {
            lastFastTurnTimestamp = timestamp
            return
        }
        guard timestamp - (lastSectorSampleTimestamp ?? 0) >= Self.minimumSampleInterval else {
            return
        }

        let band: ScanBand?
        if forward3.y < -0.28 {
            band = .downward
        } else if forward3.y > 0.28 {
            band = .upward
        } else if abs(forward3.y) < 0.20 {
            band = .level
        } else {
            band = nil
        }
        guard let band else { return }
        guard visibleFeatureCount >= Self.minimumFeaturePointsPerObservation else { return }

        let sectorWidth = 2 * Double.pi / Double(Self.environmentSectorCount)
        let sector = min(Int(yaw / sectorWidth), Self.environmentSectorCount - 1)
        let evidence = (sectorEvidence[band]?[sector] ?? 0) + 1
        sectorEvidence[band, default: [:]][sector] = evidence
        if evidence >= Self.stableObservationsPerSector {
            observedSectors[band, default: []].insert(sector)
        }
        lastSectorSampleTimestamp = timestamp
    }

    func environmentScanSnapshot() -> EnvironmentScanSnapshot {
        guard let frame = arView?.session.currentFrame else {
            return .empty
        }
        return EnvironmentScanSnapshot(
            levelProgress: progress(for: .level),
            downwardProgress: progress(for: .downward),
            upwardProgress: progress(for: .upward),
            parallaxProgress: min(
                Double(maximumDisplacement / Self.requiredMovementMeters),
                1
            ),
            mappingStatus: frame.worldMappingStatus,
            featurePointCount: maximumFeaturePointCount,
            surfaces: surfaceOutlines(from: frame),
            cameraPath: cameraPath,
            meccaPosition: meccaWorldPosition,
            maximumDisplacementMeters: Double(maximumDisplacement),
            isTurningTooFast: lastFastTurnTimestamp.map {
                frame.timestamp - $0 < 1
            } ?? false
        )
    }

    private func progress(for band: ScanBand) -> Double {
        Double(observedSectors[band]?.count ?? 0)
            / Double(Self.environmentSectorCount)
    }

    private func recordMovement(_ position: SIMD3<Float>) {
        if scanOrigin == nil { scanOrigin = position }
        if let scanOrigin {
            let horizontalDelta = SIMD2<Float>(
                position.x - scanOrigin.x,
                position.z - scanOrigin.z
            )
            maximumDisplacement = max(maximumDisplacement, simd_length(horizontalDelta))
        }

        let point = SIMD2<Float>(position.x, position.z)
        if let last = cameraPath.last, simd_distance(last, point) < 0.06 { return }
        cameraPath.append(point)
        if cameraPath.count > 240 {
            cameraPath.removeFirst(cameraPath.count - 240)
        }
    }

    private func surfaceOutlines(from frame: ARFrame) -> [SurfaceOutline] {
        frame.anchors.compactMap { anchor in
            guard let plane = anchor as? ARPlaneAnchor else { return nil }
            let center = plane.center
            let halfWidth = plane.extent.x / 2

            switch plane.alignment {
            case .horizontal:
                let halfDepth = plane.extent.z / 2
                let corners: [SIMD3<Float>] = [
                    [center.x - halfWidth, center.y, center.z - halfDepth],
                    [center.x + halfWidth, center.y, center.z - halfDepth],
                    [center.x + halfWidth, center.y, center.z + halfDepth],
                    [center.x - halfWidth, center.y, center.z + halfDepth]
                ]
                return SurfaceOutline(
                    id: plane.identifier,
                    kind: .floorOrTable,
                    points: corners.map { worldPoint($0, using: plane.transform) }
                )
            case .vertical:
                let ends: [SIMD3<Float>] = [
                    [center.x - halfWidth, center.y, center.z],
                    [center.x + halfWidth, center.y, center.z]
                ]
                return SurfaceOutline(
                    id: plane.identifier,
                    kind: .wall,
                    points: ends.map { worldPoint($0, using: plane.transform) }
                )
            @unknown default:
                return nil
            }
        }
    }

    private func worldPoint(
        _ point: SIMD3<Float>,
        using transform: simd_float4x4
    ) -> SIMD2<Float> {
        let world = transform * SIMD4<Float>(point.x, point.y, point.z, 1)
        return [world.x, world.z]
    }

    /// Asks ARKit for the current world map and returns it archived + compressed,
    /// or nil if a usable map isn't available yet.
    func captureWorldMap() async -> Data? {
        guard let session = arView?.session else { return nil }
        let exactMeccaTransform = meccaWorldTransform
        return await withCheckedContinuation { continuation in
            session.getCurrentWorldMap { map, _ in
                guard let map else {
                    continuation.resume(returning: nil)
                    return
                }
                // Be explicit even if ARKit already included the live session
                // anchor. This guarantees the archived map has exactly one
                // named Mecca anchor at the placement transform.
                var anchors = map.anchors.filter {
                    $0.name != PreciseMeccaARController.anchorName
                }
                if let exactMeccaTransform {
                    anchors.append(
                        ARAnchor(
                            name: PreciseMeccaARController.anchorName,
                            transform: exactMeccaTransform
                        )
                    )
                }
                map.anchors = anchors
                continuation.resume(returning: try? ARWorldMapArchiver.encode(map))
            }
        }
    }
}

private struct MeccaPlacementConfiguration: Equatable {
    let sizeScale: Float
    let xRotationDegrees: Float
    let yRotationDegrees: Float
    let facePhotoPlacement: MeccaPhotoPlacement
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
    let onPositionFacePhoto: () -> Void
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
                onPositionPhoto: onPositionFacePhoto,
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
    let onPositionPhoto: () -> Void
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

            if image != nil {
                Button {
                    onPositionPhoto()
                } label: {
                    Label("Position photo on Mecca", systemImage: "move.3d")
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .foregroundStyle(.black)
            }

            Text(
                cameraAvailable
                    ? "After capture, drag the photo anywhere on the Mecca. It stays in this AR session."
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

private struct ScanPassProgress: View {
    let title: String
    let systemImage: String
    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: progress >= 1 ? "checkmark.circle.fill" : systemImage)
                .foregroundStyle(progress >= 1 ? .mint : .yellow)
                .frame(width: 22)
            ProgressView(value: progress)
                .tint(progress >= 1 ? .mint : .yellow)
            Text("\(Int((progress * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(width: 112, alignment: .leading)
        }
    }
}

private struct RoomCaptureOutline: View {
    let snapshot: PlacementARSession.EnvironmentScanSnapshot

    private var allPoints: [SIMD2<Float>] {
        snapshot.surfaces.flatMap(\.points)
            + [snapshot.meccaPosition].compactMap { $0 }
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let points = allPoints
                let rawMinimumX = points.map(\.x).min() ?? -0.5
                let rawMaximumX = points.map(\.x).max() ?? 0.5
                let rawMinimumZ = points.map(\.y).min() ?? -0.5
                let rawMaximumZ = points.map(\.y).max() ?? 0.5
                let spanX = max(rawMaximumX - rawMinimumX, 1)
                let spanZ = max(rawMaximumZ - rawMinimumZ, 1)
                let minimumX = (rawMinimumX + rawMaximumX - spanX) / 2
                let minimumZ = (rawMinimumZ + rawMaximumZ - spanZ) / 2
                let scale = min(
                    (size.width - 36) / CGFloat(spanX),
                    (size.height - 36) / CGFloat(spanZ)
                )
                let contentWidth = CGFloat(spanX) * scale
                let contentHeight = CGFloat(spanZ) * scale
                let xInset = (size.width - contentWidth) / 2
                let yInset = (size.height - contentHeight) / 2
                let project: (SIMD2<Float>) -> CGPoint = { point in
                    CGPoint(
                        x: xInset + CGFloat(point.x - minimumX) * scale,
                        y: size.height - yInset - CGFloat(point.y - minimumZ) * scale
                    )
                }

                for surface in snapshot.surfaces {
                    guard let first = surface.points.first else { continue }
                    var path = Path()
                    path.move(to: project(first))
                    for point in surface.points.dropFirst() {
                        path.addLine(to: project(point))
                    }
                    switch surface.kind {
                    case .floorOrTable:
                        path.closeSubpath()
                        context.fill(path, with: .color(.mint.opacity(0.16)))
                        context.stroke(path, with: .color(.mint.opacity(0.75)), lineWidth: 1.5)
                    case .wall:
                        context.stroke(path, with: .color(.mint), lineWidth: 3)
                    }
                }

                if let mecca = snapshot.meccaPosition {
                    let center = project(mecca)
                    let marker = Path(ellipseIn: CGRect(
                        x: center.x - 7,
                        y: center.y - 7,
                        width: 14,
                        height: 14
                    ))
                    context.fill(marker, with: .color(.orange))
                    context.stroke(marker, with: .color(.white), lineWidth: 2)
                }
            }

            if snapshot.surfaces.isEmpty {
                Text("Keep scanning room edges to build an outline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(50)
            }

        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
        context.coordinator.setFaceCameraActive(isFaceCameraActive)
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

        init(_ parent: PlacementARView) {
            self.parent = parent
            lastResetToken = parent.resetToken
            lastPlaceToken = parent.placeToken
        }

        func runSession() {
            runSession(resetTracking: true)
        }

        private func runSession(resetTracking: Bool) {
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

            let options: ARSession.RunOptions = resetTracking
                ? [.resetTracking, .removeExistingAnchors]
                : []
            arView.session.run(configuration, options: options)
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
            parent.session.recordEnvironmentScanFrame()

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
            parent.session.beginEnvironmentScan(meccaTransform: anchorTransform)

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
                self.parent.message = "Mecca placed — slowly scan a full 360° around it"
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
            parent.session.resetEnvironmentScan()
            lastResetToken = resetToken
            lastAppliedConfiguration = nil
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
                    placement: configuration.facePhotoPlacement,
                    to: placedMecca.entity
                )
                if facePhoto != nil {
                    parent.message = didApplyFacePhoto
                        ? "Photo applied at your selected position"
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
