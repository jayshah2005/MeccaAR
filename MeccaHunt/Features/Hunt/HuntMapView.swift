import CoreLocation
import MapKit
import SwiftUI

/// The app's main page: a live map of every hidden Mecca. Nearby Meccas can be
/// hunted; groups in the same room collapse into a single point.
struct HuntMapView: View {
    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location

    @State private var model: HuntViewModel?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCluster: MeccaCluster?
    @State private var huntTarget: Mecca?
    @State private var showLeaderboard = false

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
        .task {
            if model == nil {
                model = HuntViewModel(repository: appState.dependencies.meccas)
            }
            location.start()
            await reload()
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
    }

    // MARK: Map

    private var mapLayer: some View {
        Map(position: $camera) {
            UserAnnotation()

            ForEach(model?.clusters ?? []) { cluster in
                Annotation(clusterTitle(cluster), coordinate: cluster.coordinate) {
                    ClusterMarker(cluster: cluster, currentUserID: appState.currentUser?.id)
                        .onTapGesture { selectedCluster = cluster }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    private func clusterTitle(_ cluster: MeccaCluster) -> String {
        cluster.isGroup ? "\(cluster.count) Meccas" : cluster.representative.name
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.currentUser?.username ?? "hunter")
                    .font(.headline)
                Text("\(model?.meccas.count ?? 0) Meccas hidden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

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

            Button(role: .destructive) {
                location.stop()
                appState.signOut()
            } label: {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.6))
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
                HuntableRow(candidate: candidate) { huntTarget = candidate.mecca }
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

    private func reload() async {
        guard let model, let userID = appState.currentUser?.id else { return }
        await model.load(hunterID: userID)
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

private struct ClusterMarker: View {
    let cluster: MeccaCluster
    let currentUserID: UUID?

    private var allMine: Bool {
        currentUserID != nil && cluster.meccas.allSatisfy { $0.ownerID == currentUserID }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(allMine ? Color.blue : Color.mint)
                .frame(width: cluster.isGroup ? 40 : 30, height: cluster.isGroup ? 40 : 30)
                .shadow(radius: 3)

            if cluster.isGroup {
                Text("\(cluster.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.black)
            } else {
                Image(systemName: allMine ? "person.fill" : "mappin")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
            }
        }
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
