import SwiftUI

/// Ranks every player by total points earned from hunts.
struct LeaderboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [LeaderboardEntry] = []
    @State private var loadState: LoadState = .loading

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    ProgressView("Loading scores…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView(
                        "Couldn't load leaderboard",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                case .loaded where entries.allSatisfy { $0.points == 0 }:
                    ContentUnavailableView(
                        "No hunts yet",
                        systemImage: "trophy",
                        description: Text("Be the first to find a Mecca and score points.")
                    )
                case .loaded:
                    list
                }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var list: some View {
        List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                LeaderboardRow(
                    rank: index + 1,
                    entry: entry,
                    isCurrentUser: entry.id == appState.currentUser?.id
                )
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
    }

    private func load() async {
        loadState = .loading
        do {
            entries = try await appState.dependencies.meccas.leaderboard()
            loadState = .loaded
        } catch {
            loadState = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 14) {
            rankBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.username)
                        .font(.headline)
                    if isCurrentUser {
                        Text("YOU")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.mint)
                    }
                }
                Text("\(entry.finds) find\(entry.finds == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(entry.points)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.mint)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var rankBadge: some View {
        let medal: Color? = switch rank {
        case 1: .yellow
        case 2: Color(white: 0.75)
        case 3: Color(red: 0.80, green: 0.50, blue: 0.20)
        default: nil
        }

        ZStack {
            Circle()
                .fill(medal ?? Color.white.opacity(0.12))
                .frame(width: 34, height: 34)
            if let medal {
                Image(systemName: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(medal == .yellow ? .black : .white)
            } else {
                Text("\(rank)")
                    .font(.subheadline.weight(.bold))
            }
        }
    }
}

#Preview {
    LeaderboardView()
        .environment(AppState(dependencies: .live()))
}
