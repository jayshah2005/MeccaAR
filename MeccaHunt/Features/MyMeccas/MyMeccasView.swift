import CoreLocation
import SwiftUI

/// Lists the current user's own hidden Meccas and lets them open an AR locator
/// to walk to each one in the real world.
struct MyMeccasView: View {
    @Environment(AppState.self) private var appState
    @Environment(LocationProvider.self) private var location

    @State private var meccas: [Mecca] = []
    @State private var loadState: LoadState = .loading
    @State private var selected: Mecca?
    @State private var pendingDelete: Mecca?
    @State private var deletingIDs: Set<UUID> = []
    @State private var deleteError: String?

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.04, green: 0.18, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                content
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .task {
            location.start()
            await load()
        }
        .fullScreenCover(item: $selected) { mecca in
            MeccaLocatorARView(target: mecca)
        }
        .confirmationDialog(
            "Delete this Mecca?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { mecca in
            Button("Delete “\(mecca.name)”", role: .destructive) {
                Task { await delete(mecca) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently removes it from the map. This can't be undone.")
        }
        .alert(
            "Couldn't delete Mecca",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Button {
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

            Text("My Meccas")
                .font(.headline)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            Spacer()
            ProgressView("Loading your Meccas…")
            Spacer()
        case .failed(let message):
            Spacer()
            ContentUnavailableView(
                "Couldn't load your Meccas",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            Spacer()
        case .loaded where meccas.isEmpty:
            Spacer()
            ContentUnavailableView {
                Label("No Meccas yet", systemImage: "mappin.slash")
            } description: {
                Text("Hide a Mecca to see it here.")
            } actions: {
                Button("Hide a Mecca") { appState.route = .place }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
            }
            Spacer()
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(meccas) { mecca in
                    MyMeccaRow(
                        mecca: mecca,
                        location: location.currentLocation,
                        isDeleting: deletingIDs.contains(mecca.id),
                        onLocate: { selected = mecca },
                        onDelete: { pendingDelete = mecca }
                    )
                }
            }
        }
    }

    private func load() async {
        guard let owner = appState.currentUser else { return }
        loadState = .loading
        do {
            meccas = try await appState.dependencies.meccas.meccasOwned(by: owner.id)
            loadState = .loaded
        } catch {
            loadState = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func delete(_ mecca: Mecca) async {
        guard let owner = appState.currentUser else { return }
        deletingIDs.insert(mecca.id)
        defer { deletingIDs.remove(mecca.id) }
        do {
            try await appState.dependencies.meccas.deleteMecca(id: mecca.id, ownerID: owner.id)
            meccas.removeAll { $0.id == mecca.id }
        } catch {
            deleteError =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct MyMeccaRow: View {
    let mecca: Mecca
    let location: CLLocation?
    let isDeleting: Bool
    let onLocate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onLocate) {
                HStack(spacing: 14) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.mint)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(mecca.name)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Label("Locate", systemImage: "location.north.line.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.mint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                if isDeleting {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(isDeleting)
            .accessibilityLabel("Delete \(mecca.name)")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var subtitle: String {
        guard let location else {
            return "Hidden \(mecca.createdAt.formatted(date: .abbreviated, time: .shortened))"
        }
        let distance = GeoMath.distanceMeters(
            from: location.coordinate,
            to: CLLocationCoordinate2D(latitude: mecca.latitude, longitude: mecca.longitude)
        )
        let altitude = location.verticalAccuracy >= 0 ? location.altitude : nil
        let floor: String = switch GeoMath.floorRelation(
            hunterAltitude: altitude,
            meccaAltitude: mecca.altitude
        ) {
        case .sameFloor: "your floor"
        case .above(let f, _): "\(f) floor\(f == 1 ? "" : "s") up"
        case .below(let f, _): "\(f) floor\(f == 1 ? "" : "s") down"
        }
        return "\(Int(distance.rounded())) m away · \(floor)"
    }
}

#Preview {
    MyMeccasView()
        .environment(AppState(dependencies: .live()))
        .environment(LocationProvider())
}
