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

                Text("Pick a name\nto start hunting.")
                    .font(.system(size: 44, weight: .black, design: .rounded))
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

                Spacer()
            }
            .padding(24)
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
