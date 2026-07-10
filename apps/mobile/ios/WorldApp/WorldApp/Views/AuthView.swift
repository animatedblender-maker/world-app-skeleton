import SwiftUI

struct AuthView: View {
    @Environment(AppState.self) private var appState

    @State private var activeTab: AuthTab = .login
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    enum AuthTab {
        case login, register
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)

                    Text(AppConfig.appName)
                        .font(.system(size: 42, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)

                    VStack(spacing: 14) {
                        PremiumTextField(title: "Email", text: $email, keyboard: .emailAddress)
                        PremiumTextField(title: "Password", text: $password, isSecure: true)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let infoMessage {
                            Text(infoMessage)
                                .font(.footnote)
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: submit) {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Text(busy ? "Please wait…" : (activeTab == .login ? "Log In" : "Sign Up"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || email.isEmpty || password.count < 6)
                    }
                    .padding(.horizontal, 32)

                    VStack(spacing: 16) {
                        Theme.divider.frame(height: 0.5)
                        HStack(spacing: 4) {
                            Text(activeTab == .login ? "Don't have an account?" : "Have an account?")
                                .foregroundStyle(Theme.inkMuted)
                            Button(activeTab == .login ? "Sign up" : "Log in") {
                                activeTab = activeTab == .login ? .register : .login
                                errorMessage = nil
                                infoMessage = nil
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 32)

                    if activeTab == .register {
                        Text("If email confirmation is enabled, check your inbox after registering.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
            }
        }
    }

    private func submit() {
        busy = true
        errorMessage = nil
        infoMessage = nil

        Task {
            defer { busy = false }
            do {
                if activeTab == .login {
                    try await AuthService.shared.login(email: email, password: password)
                    await appState.onAuthenticated()
                } else {
                    let result = try await AuthService.shared.register(email: email, password: password)
                    if result.isExistingEmail {
                        errorMessage = "This email is already registered."
                    } else if result.needsEmailConfirm {
                        infoMessage = "Account created. Check your email to confirm, then log in."
                    } else {
                        await appState.onAuthenticated()
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}