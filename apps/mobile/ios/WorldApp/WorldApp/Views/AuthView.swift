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
                        Text("After sign up, Matterya emails you a confirmation link. Open it, then log in.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    if activeTab == .login, infoMessage != nil {
                        Button("Resend confirmation email") {
                            Task { await resendConfirm() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .disabled(busy || email.isEmpty)
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
                        errorMessage = "This email is already registered. Log in or reset your password."
                        activeTab = .login
                    } else if result.needsEmailConfirm {
                        activeTab = .login
                        infoMessage = "We sent a Matterya confirmation email. Open the link to activate your account, then log in."
                    } else {
                        await appState.onAuthenticated()
                    }
                }
            } catch {
                let msg = error.localizedDescription
                if msg.localizedCaseInsensitiveContains("email not confirmed")
                    || msg.localizedCaseInsensitiveContains("not confirmed") {
                    infoMessage = "Confirm your email first — check your Matterya confirmation message, or resend below."
                    errorMessage = nil
                } else {
                    errorMessage = msg
                }
            }
        }
    }

    private func resendConfirm() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            infoMessage = try await AuthService.shared.resendConfirmation(email: email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}