import SwiftUI

/// Hunter leaderboard ranked by points earned over a chosen time window.
struct LeaderboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var period: LeaderboardPeriod = .week
    @State private var entries: [LeaderboardEntry] = []
    @State private var loadState: LoadState = .loading

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Period", selection: $period) {
                    ForEach(LeaderboardPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                content
            }
            .background(Color.black)
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: period) { await load() }
    }

    @ViewBuilder
    private var content: some View {
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
        case .loaded where entries.isEmpty:
            ContentUnavailableView(
                "No hunts \(periodNoun)",
                systemImage: "trophy",
                description: Text("Find a Mecca to score points.")
            )
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HunterRow(
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

    private var periodNoun: String {
        switch period {
        case .week: return "this week"
        case .month: return "this month"
        case .year: return "this year"
        case .allTime: return "yet"
        }
    }

    private func load() async {
        loadState = .loading
        do {
            entries = try await appState.dependencies.meccas
                .hunterLeaderboard(period: period)
            loadState = .loaded
        } catch {
            loadState = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}

private struct HunterRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 14) {
            RankBadge(rank: rank)

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
}

struct RankBadge: View {
    let rank: Int

    var body: some View {
        let medal: Color? = switch rank {
        case 1: .yellow
        case 2: Color(white: 0.82)
        case 3: Color(red: 0.90, green: 0.60, blue: 0.30)
        default: nil
        }

        ZStack {
            Circle()
                .fill(medal ?? Color.white.opacity(0.12))
                .frame(width: 34, height: 34)
            if let medal {
                Image(systemName: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(medal == .yellow ? .black : .black.opacity(0.85))
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
