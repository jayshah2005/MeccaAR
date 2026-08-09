import SwiftUI

/// Username-only sign in. Entering a username creates the account on first use
/// or resumes the existing one, then hands control to the map.
struct LoginView: View {
    @Environment(AppState.self) private var appState

    @State private var username = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        trimmedUsername.count >= 2 && !isSubmitting
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // Show the full artwork, anchored to the top so most of it stays
            // visible above the sign-in controls.
            Image("LoginBackground")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            // Fade the artwork into black behind the controls so the text and
            // fields stay legible.
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.75),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 340)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("MECCA HUNT")
                    .font(.caption.weight(.bold))
                    .tracking(4)
                    .foregroundStyle(.mint)

                Text("Pick a name\nto start hunting.")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.75)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .padding()
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                        .font(.title3.weight(.semibold))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    Button(action: submit) {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.black)
                            }
                            Text(isSubmitting ? "Signing in…" : "Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .disabled(!canSubmit)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        guard canSubmit else { return }
        let name = trimmedUsername
        errorMessage = nil
        isSubmitting = true

        Task {
            do {
                let user = try await appState.dependencies.auth.signIn(username: name)
                appState.completeSignIn(user)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState(dependencies: .live()))
}
