import SwiftUI

/// A quick discovery screen (not a leaderboard) that surfaces the most valuable
/// Meccas around you, so high-point targets are easy to spot and go hunt.
struct NearbyValuableMeccasView: View {
    @Environment(\.dismiss) private var dismiss

    let candidates: [NearbyMecca]
    let hasLocation: Bool
    let onHunt: (Mecca) -> Void

    /// Rank by value first (rarer, longer-hidden Meccas float to the top), then
    /// by how close they are.
    private var ranked: [NearbyMecca] {
        candidates.sorted { lhs, rhs in
            if lhs.mecca.currentPoints != rhs.mecca.currentPoints {
                return lhs.mecca.currentPoints > rhs.mecca.currentPoints
            }
            return lhs.distanceMeters < rhs.distanceMeters
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLocation {
                    ContentUnavailableView(
                        "Finding your location…",
                        systemImage: "location.magnifyingglass",
                        description: Text("We need your location to show what's valuable nearby.")
                    )
                } else if ranked.isEmpty {
                    ContentUnavailableView(
                        "Nothing valuable nearby",
                        systemImage: "sparkle.magnifyingglass",
                        description: Text("Walk around — Meccas are worth more the longer they've hidden.")
                    )
                } else {
                    list
                }
            }
            .background(Color.black)
            .navigationTitle("Valuable Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var list: some View {
        List {
            ForEach(ranked) { candidate in
                NearbyValuableRow(candidate: candidate) {
                    onHunt(candidate.mecca)
                    dismiss()
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
    }
}

// MARK: - Rarity styling (shared by the map markers too)

enum RarityStyle {
    static func color(_ tier: MeccaScoring.Tier) -> Color {
        switch tier {
        case .common: return .mint
        case .uncommon: return .cyan
        case .rare: return .purple
        case .legendary: return .yellow
        }
    }

    static func symbol(_ tier: MeccaScoring.Tier) -> String {
        switch tier {
        case .common: return "circle.fill"
        case .uncommon: return "seal.fill"
        case .rare: return "diamond.fill"
        case .legendary: return "crown.fill"
        }
    }
}

// MARK: - Row

private struct NearbyValuableRow: View {
    let candidate: NearbyMecca
    let onHunt: () -> Void

    private var mecca: Mecca { candidate.mecca }
    private var tier: MeccaScoring.Tier { mecca.rarity }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RarityStyle.color(tier).opacity(0.22))
                    .frame(width: 38, height: 38)
                Image(systemName: RarityStyle.symbol(tier))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(RarityStyle.color(tier))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(mecca.name)
                    .font(.headline)
                Text("\(tier.label) · \(mecca.daysHidden)d hidden · by \(mecca.ownerUsername)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(proximityText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(mecca.currentPoints)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(RarityStyle.color(tier))
                if candidate.isHuntable {
                    Button("Hunt", action: onHunt)
                        .font(.caption.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var proximityText: String {
        let distance = "\(Int(candidate.distanceMeters.rounded())) m away"
        if candidate.isSameFloor {
            return "📍 \(distance)"
        }
        return "📍 \(distance) · \(FloorPresentation.description(candidate.floorRelation))"
    }
}
