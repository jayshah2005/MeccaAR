import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.04, green: 0.18, blue: 0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    Spacer()

                    Text("MECCA HUNT")
                        .font(.caption.weight(.bold))
                        .tracking(4)
                        .foregroundStyle(.mint)

                    Text("Hide here.\nHunt out there.")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.75)

                    Text("Place a Mecca on a real surface, or get ready for the upcoming hunt mode.")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    HomeAction(
                        title: "Hide a Mecca",
                        detail: "Open the camera and tap a surface",
                        symbol: "arkit",
                        badge: "READY"
                    ) {
                        appState.route = .place
                    }

                    HomeAction(
                        title: "Hunt nearby",
                        detail: "Map discovery and hunting come next",
                        symbol: "scope",
                        badge: "PLANNED"
                    ) {
                        appState.route = .hunt
                    }

                    Label("Local AR placement enabled", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(24)
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct HomeAction: View {
    let title: String
    let detail: String
    let symbol: String
    let badge: String
    let action: (() -> Void)?

    init(
        title: String,
        detail: String,
        symbol: String,
        badge: String,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.badge = badge
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
                .opacity(0.7)
        }
    }

    private var content: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.mint)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HomeView()
        .environment(AppState())
}
