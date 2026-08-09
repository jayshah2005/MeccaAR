import SwiftUI

/// Hunt owns its own screen and will contain map discovery, relocalization,
/// targeting, and scoring as those capabilities are implemented.
struct HuntView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.10, green: 0.08, blue: 0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button {
                        appState.route = .home
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.68))
                    .accessibilityLabel("Return home")

                    Spacer()
                }

                Spacer()

                Image(systemName: "scope")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.mint)

                Text("Hunt mode is next")
                    .font(.largeTitle.bold())

                Text("Map discovery, nearby-Mecca loading, targeting, and scoring will live in this feature—not in the home or placement screens.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    HuntView()
        .environment(AppState())
}
