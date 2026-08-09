import ARKit
import CoreLocation
import MapKit
import SwiftUI

private struct HuntRoomSession: Identifiable {
    let id = UUID()
    let targets: [Mecca]
    let primaryWorldMap: ARWorldMap?
}

/// The app's main page: a live map of every hidden Mecca. Nearby Meccas can be
/// hunted; groups in the same room collapse into a single point.
struct HuntMapView: View {
    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location

    @State private var model: HuntViewModel?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCluster: MeccaCluster?
    @State private var huntTarget: Mecca?
    @State private var huntRoom: HuntRoomSession?
    @State private var preloadedWorldMaps: [UUID: ARWorldMap] = [:]
    @State private var attemptedWorldMapLoads: Set<UUID> = []
    @State private var showLeaderboard = false
    @State private var showValuableNearby = false
    @State private var myPoints = 0
    @State private var showDeleteAccount = false
    @State private var accountError: String?
    @State private var didCenterOnUser = false

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea()

            topBar

            VStack {
                Spacer()
                bottomStack
            }
            .padding()
        }
        .id(appState.currentUser?.id)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLeaderboard) {
            LeaderboardView()
        }
        .sheet(isPresented: $showValuableNearby) {
            NearbyValuableMeccasView(
                candidates: valuableNearby,
                hasLocation: location.currentLocation != nil,
                onHunt: { openHunt(for: $0) },
                onShowLocation: { showLocation(of: $0) }
            )
            .presentationDetents([.medium, .large])
        }
        .task { await MeccaEntityFactory.preload() }
        .task {
            if model == nil {
                model = HuntViewModel(repository: appState.dependencies.meccas)
            }
            location.start()
            await reload()
            centerOnUserIfNeeded()
        }
        .onChange(of: location.currentLocation?.timestamp) { _, _ in
            centerOnUserIfNeeded()
        }
        .task(id: huntableWorldMapIDs) {
            await preloadNearbyWorldMaps()
        }
        .sheet(item: $selectedCluster) { cluster in
            ClusterDetailSheet(
                cluster: cluster,
                currentUserID: appState.currentUser?.id,
                location: location.currentLocation
            )
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $huntTarget) { target in
            HuntARView(target: target) {
                await reload()
            }
        }
        .fullScreenCover(item: $huntRoom) { room in
            RoomHuntARView(
                targets: room.targets,
                preloadedPrimaryWorldMap: room.primaryWorldMap
            ) {
                await reload()
            }
        }
        .confirmationDialog(
            "Delete account?",
            isPresented: $showDeleteAccount,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, the Meccas you've hidden, and your scores. This can't be undone.")
        }
        .alert(
            "Couldn't delete account",
            isPresented: Binding(
                get: { accountError != nil },
                set: { if !$0 { accountError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { accountError = nil }
        } message: {
            Text(accountError ?? "")
        }
    }

    private func deleteAccount() {
        Task {
            do {
                location.stop()
                try await appState.deleteAccount()
            } catch {
                accountError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    // MARK: Map

    private var mapLayer: some View {
        Map(position: $camera) {
            // System blue puck plus our labeled GPS marker so "you" stay
            // visible next to Mecca pins.
            UserAnnotation()

            if let userLocation = location.currentLocation {
                MapCircle(
                    center: userLocation.coordinate,
                    radius: max(userLocation.horizontalAccuracy, 12)
                )
                .foregroundStyle(Color.mint.opacity(0.14))
                .stroke(Color.mint.opacity(0.55), lineWidth: 1.5)

                Annotation(
                    "You",
                    coordinate: userLocation.coordinate,
                    anchor: .center
                ) {
                    YouAreHereMarker(
                        headingDegrees: location.heading.flatMap { reading in
                            if reading.trueHeading >= 0 { return reading.trueHeading }
                            if reading.magneticHeading >= 0 { return reading.magneticHeading }
                            return nil
                        }
                    )
                }
            }

            ForEach(model?.clusters ?? []) { cluster in
                Annotation(
                    clusterTitle(cluster),
                    coordinate: cluster.coordinate,
                    anchor: .bottom
                ) {
                    ClusterMarker(cluster: cluster, currentUserID: appState.currentUser?.id)
                        .onTapGesture { selectedCluster = cluster }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        // MapKit always draws Apple Maps + Legal; cover that strip so it does
        // not sit on top of the hunt UI.
        .overlay(alignment: .bottomLeading) {
            Color.black
                .frame(width: 150, height: 40)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// First GPS fix centers the map so Meccas and the user appear together.
    private func centerOnUserIfNeeded() {
        guard !didCenterOnUser, let userLocation = location.currentLocation else { return }
        didCenterOnUser = true
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = .region(
                MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: 900,
                    longitudinalMeters: 900
                )
            )
        }
    }

    private func clusterTitle(_ cluster: MeccaCluster) -> String {
        cluster.isGroup ? "\(cluster.count) Meccas" : cluster.representative.name
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.currentUser?.username ?? "hunter")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(myPoints) point\(myPoints == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.mint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())

            Button {
                showValuableNearby = true
            } label: {
                Label("Valuable Mecca nearby", systemImage: "figure.stand")
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.6))
            .accessibilityLabel("Valuable Mecca nearby")

            Button {
                showLeaderboard = true
            } label: {
                Label("Leaderboard", systemImage: "trophy.fill")
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.6))
            .accessibilityLabel("Leaderboard")

            Menu {
                Button {
                    location.stop()
                    appState.signOut()
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive) {
                    showDeleteAccount = true
                } label: {
                    Label("Delete account", systemImage: "trash")
                }
            } label: {
                Label("Account", systemImage: "person.crop.circle")
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.6))
            .accessibilityLabel("Account options")
        }
        .padding(.horizontal)
    }

    // MARK: Bottom stack

    @ViewBuilder
    private var bottomStack: some View {
        if let model {
            switch model.loadState {
            case .failed(let message):
                banner(message, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            case .loading where model.meccas.isEmpty:
                banner("Loading Meccas…", systemImage: "arrow.triangle.2.circlepath", tint: .mint)
            default:
                proximityContent(model)
            }
        }

        actionButtons
    }

    @ViewBuilder
    private func proximityContent(_ model: HuntViewModel) -> some View {
        let userID = appState.currentUser?.id
        let huntable = userID.map { model.huntable(from: location.currentLocation, currentUserID: $0) } ?? []
        let offFloor = userID.map { model.offFloor(from: location.currentLocation, currentUserID: $0) } ?? []

        VStack(spacing: 10) {
            ForEach(huntable) { candidate in
                HuntableRow(candidate: candidate) {
                    openHunt(for: candidate.mecca)
                }
            }

            ForEach(offFloor) { candidate in
                OffFloorRow(candidate: candidate)
            }

            if huntable.isEmpty && offFloor.isEmpty {
                banner(
                    location.currentLocation == nil
                        ? "Finding your location…"
                        : "Walk closer to a Mecca to hunt it (within \(Int(HuntTuning.huntRadiusMeters)) m).",
                    systemImage: "figure.walk",
                    tint: .secondary
                )
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                appState.route = .myMeccas
            } label: {
                Label("My Meccas", systemImage: "list.bullet")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button {
                location.stop()
                appState.route = .place
            } label: {
                Label("Hide a Mecca", systemImage: "arkit")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
        }
    }

    private func banner(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint == .secondary ? .secondary : tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Meccas around the hunter (excluding their own), for the "valuable nearby"
    /// discovery screen.
    private var valuableNearby: [NearbyMecca] {
        guard let model, let userID = appState.currentUser?.id else { return [] }
        return model
            .nearby(from: location.currentLocation, currentUserID: userID)
            .filter { !$0.isMine && !$0.mecca.claimedByMe }
    }

    private func reload() async {
        guard let model, let userID = appState.currentUser?.id else { return }
        await model.load(hunterID: userID)
        await loadMyPoints(userID: userID)
    }

    private func openHunt(for primary: Mecca) {
        let others = currentHuntableCandidates
            .map(\.mecca)
            .filter { $0.id != primary.id }
        // Hybrid: one nearby Mecca uses the single-target path (geo/map/GPS
        // fallbacks). Two or more open a shared room session.
        if others.isEmpty {
            huntTarget = primary
            return
        }
        huntRoom = HuntRoomSession(
            targets: [primary] + others,
            primaryWorldMap: preloadedWorldMaps[primary.id]
        )
    }

    /// Fly the map to a Mecca from the valuable-nearby list and open its pin.
    private func showLocation(of mecca: Mecca) {
        showValuableNearby = false
        let coordinate = CLLocationCoordinate2D(
            latitude: mecca.latitude,
            longitude: mecca.longitude
        )
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 450,
                    longitudinalMeters: 450
                )
            )
        }
        if let cluster = model?.clusters.first(where: {
            $0.meccas.contains(where: { $0.id == mecca.id })
        }) {
            // Let the sheet dismiss before presenting cluster details.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                selectedCluster = cluster
            }
        }
    }

    private func loadMyPoints(userID: UUID) async {
        guard let entries = try? await appState.dependencies.meccas.overallLeaderboard() else {
            return
        }
        myPoints = entries.first(where: { $0.id == userID })?.points ?? 0
    }

    private var currentHuntableCandidates: [NearbyMecca] {
        guard
            let model,
            let userID = appState.currentUser?.id
        else { return [] }
        return model.huntable(
            from: location.currentLocation,
            currentUserID: userID
        )
    }

    private var huntableWorldMapIDs: [UUID] {
        currentHuntableCandidates
            .map(\.mecca)
            .filter(\.hasWorldMap)
            .map(\.id)
    }

    /// Download maps while the hunter is merely in range, before they open the
    /// camera. ARKit still needs live visual recognition, but network transfer
    /// and decompression are no longer part of the apparent-generation delay.
    private func preloadNearbyWorldMaps() async {
        for mecca in currentHuntableCandidates.map(\.mecca)
        where mecca.hasWorldMap
            && preloadedWorldMaps[mecca.id] == nil
            && !attemptedWorldMapLoads.contains(mecca.id) {
            attemptedWorldMapLoads.insert(mecca.id)
            do {
                guard let data = try await appState.dependencies.meccas.worldMap(for: mecca.id) else {
                    continue
                }
                preloadedWorldMaps[mecca.id] = try ARWorldMapArchiver.decode(data)
            } catch {
                // Room hunt retains the stable coordinate fallback for legacy
                // records whose map cannot be downloaded or decoded.
            }
        }
    }
}

// MARK: - Rows

private struct HuntableRow: View {
    let candidate: NearbyMecca
    let onHunt: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.title3)
                .foregroundStyle(.mint)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.mecca.name)
                    .font(.headline)
                Text("by \(candidate.mecca.ownerUsername) · \(Int(candidate.distanceMeters)) m away")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Hunt", action: onHunt)
                .font(.subheadline.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(.mint)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct OffFloorRow: View {
    let candidate: NearbyMecca

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: FloorPresentation.symbol(candidate.floorRelation))
                .font(.title3)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.mecca.name)
                    .font(.headline)
                Text(FloorPresentation.description(candidate.floorRelation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Map marker

/// GPS “you are here” marker shown with Mecca pins. Arrow rotates with compass
/// heading when available.
private struct YouAreHereMarker: View {
    let headingDegrees: Double?

    var body: some View {
        ZStack {
            Circle()
                .fill(.mint.opacity(0.25))
                .frame(width: 44, height: 44)

            Circle()
                .fill(.mint)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(.white, lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

            if let headingDegrees {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: -16)
                    .rotationEffect(.degrees(headingDegrees))
            }
        }
        .accessibilityLabel("Your GPS location")
    }
}

/// An upside-down teardrop map pin whose color signals rarity and whose head
/// shows the Mecca itself (a figure tinted with the Mecca's own color), so a
/// hunter can see what they're looking for at a glance. Its tip points at the
/// coordinate (the annotation is bottom-anchored).
private struct ClusterMarker: View {
    let cluster: MeccaCluster
    let currentUserID: UUID?

    private var allMine: Bool {
        currentUserID != nil && cluster.meccas.allSatisfy { $0.ownerID == currentUserID }
    }

    /// Rarest Mecca in the cluster drives the styling, so rarer (older) Meccas
    /// stand out on the map.
    private var topTier: MeccaScoring.Tier {
        cluster.meccas.map(\.rarity).max(by: { $0.rawValue < $1.rawValue }) ?? .common
    }

    private var meccaColor: Color {
        let appearance = cluster.representative.appearance
        return Color(
            red: appearance.red,
            green: appearance.green,
            blue: appearance.blue
        )
    }

    /// Ink that stays readable on top of the Mecca's color.
    private var meccaInk: Color {
        let a = cluster.representative.appearance
        let luminance = 0.299 * a.red + 0.587 * a.green + 0.114 * a.blue
        return luminance > 0.6 ? .black : .white
    }

    var body: some View {
        let tierColor = RarityStyle.color(topTier)
        let isLegendary = topTier == .legendary
        let isRarePlus = topTier.rawValue >= MeccaScoring.Tier.rare.rawValue
        let width: CGFloat = (cluster.isGroup ? 46 : 40) + (isLegendary ? 8 : isRarePlus ? 4 : 0)
        let height = width * 1.32
        let headDiameter = width * 0.66

        ZStack(alignment: .top) {
            if isRarePlus {
                PinShape()
                    .fill(tierColor.opacity(0.45))
                    .frame(width: width + 12, height: height + 12)
                    .blur(radius: 6)
            }

            PinShape()
                .fill(allMine ? Color.blue : tierColor)
                .overlay(
                    PinShape().stroke(.white.opacity(0.95), lineWidth: isLegendary ? 2.5 : 1.5)
                )
                .frame(width: width, height: height)
                .shadow(radius: 3)

            // Logo sits inside the circular head, centered at width/2 from top.
            ZStack {
                Circle()
                    .fill(cluster.isGroup ? Color.white : meccaColor)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                    .frame(width: headDiameter, height: headDiameter)
                head(headDiameter: headDiameter)
            }
            .frame(width: width, height: width)
        }
        .frame(width: width + 12, height: height + 12, alignment: .top)
    }

    @ViewBuilder
    private func head(headDiameter: CGFloat) -> some View {
        if cluster.isGroup {
            Text("\(cluster.count)")
                .font(.system(size: headDiameter * 0.5, weight: .black))
                .foregroundStyle(.black)
        } else {
            Image(systemName: "figure.stand")
                .font(.system(size: headDiameter * 0.64, weight: .bold))
                .foregroundStyle(meccaInk)
        }
    }
}

/// A classic downward map-pin outline: a circular head with a pointed tip at the
/// bottom center.
private struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let radius = width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)

        var path = Path()
        path.move(to: tip)
        path.addQuadCurve(
            to: CGPoint(x: center.x - radius, y: center.y),
            control: CGPoint(x: center.x - radius, y: rect.maxY * 0.62)
        )
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addQuadCurve(
            to: tip,
            control: CGPoint(x: center.x + radius, y: rect.maxY * 0.62)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Floor text

enum FloorPresentation {
    static func symbol(_ relation: GeoMath.FloorRelation) -> String {
        switch relation {
        case .sameFloor: return "mappin"
        case .above: return "arrow.up.circle.fill"
        case .below: return "arrow.down.circle.fill"
        }
    }

    static func description(_ relation: GeoMath.FloorRelation) -> String {
        switch relation {
        case .sameFloor:
            return "On your floor"
        case .above(let floors, let meters):
            return "≈\(floors) floor\(floors == 1 ? "" : "s") above you (~\(Int(meters)) m up)"
        case .below(let floors, let meters):
            return "≈\(floors) floor\(floors == 1 ? "" : "s") below you (~\(Int(meters)) m down)"
        }
    }
}

// MARK: - Cluster detail sheet

private struct ClusterDetailSheet: View {
    let cluster: MeccaCluster
    let currentUserID: UUID?
    let location: CLLocation?

    var body: some View {
        NavigationStack {
            List(cluster.meccas) { mecca in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mecca.name).font(.headline)
                        if mecca.ownerID == currentUserID {
                            Text("YOURS")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.blue)
                        }
                        if mecca.claimedByMe {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.mint)
                        }
                    }
                    Text("by \(mecca.ownerUsername) · claimed \(mecca.claimCount)×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(distanceAndFloor(for: mecca))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(cluster.isGroup ? "\(cluster.count) Meccas here" : "Mecca")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func distanceAndFloor(for mecca: Mecca) -> String {
        guard let location else { return "Location unknown" }
        let distance = GeoMath.distanceMeters(
            from: location.coordinate,
            to: CLLocationCoordinate2D(latitude: mecca.latitude, longitude: mecca.longitude)
        )
        let altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        let relation = GeoMath.floorRelation(hunterAltitude: altitude, meccaAltitude: mecca.altitude)
        return "\(Int(distance)) m away · \(FloorPresentation.description(relation))"
    }
}

#Preview {
    HuntMapView()
        .environment(AppState(dependencies: .live()))
        .environment(LocationProvider())
}
