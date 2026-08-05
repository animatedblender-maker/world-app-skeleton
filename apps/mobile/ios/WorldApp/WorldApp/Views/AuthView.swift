import SwiftUI

struct AuthView: View {
    @Environment(AppState.self) private var appState

    @State private var activeTab: AuthTab = .login
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var successPopup: String?

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
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
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
                        .disabled(busy)
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

                    if activeTab == .login, infoMessage != nil {
                        Button("Resend confirmation email") {
                            Task { await resendConfirm() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if let successPopup {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accent)
                    Text(successPopup)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(24)
                .frame(maxWidth: 300)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                .padding(.horizontal, 32)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: successPopup)
        .animation(.easeOut(duration: 0.15), value: errorMessage)
    }

    private func submit() {
        errorMessage = nil
        infoMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty {
            errorMessage = "Email is required. Enter your email address."
            return
        }
        if !isValidEmail(trimmedEmail) {
            errorMessage = "Enter a valid email address (for example you@example.com)."
            return
        }

        if activeTab == .login {
            if case .failure(let failure) = PasswordPolicy.validatePresent(password) {
                errorMessage = failure.errorDescription
                return
            }
        } else {
            if case .failure(let failure) = PasswordPolicy.validateStrong(password) {
                errorMessage = failure.errorDescription
                return
            }
        }

        busy = true

        Task {
            defer { busy = false }
            do {
                if activeTab == .login {
                    try await AuthService.shared.login(email: trimmedEmail, password: password)
                    await appState.onAuthenticated()
                } else {
                    let result = try await AuthService.shared.register(
                        email: trimmedEmail,
                        password: password
                    )
                    if result.isExistingEmail {
                        errorMessage = "This email is already registered. Log in or reset your password."
                        activeTab = .login
                    } else if result.needsEmailConfirm {
                        activeTab = .login
                        await presentSuccessPopup(
                            "We sent you a confirmation email. Open the link to activate your account, then log in."
                        )
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
                    // Always show server/client validation in red.
                    errorMessage = msg
                }
            }
        }
    }

    @MainActor
    private func presentSuccessPopup(_ message: String) async {
        successPopup = message
        appState.showToast(message, style: .success, durationSeconds: 5)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if successPopup == message {
            successPopup = nil
        }
    }

    private func resendConfirm() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            errorMessage = "Email is required. Enter your email address."
            return
        }
        if !isValidEmail(trimmedEmail) {
            errorMessage = "Enter a valid email address (for example you@example.com)."
            return
        }
        do {
            let msg = try await AuthService.shared.resendConfirmation(email: trimmedEmail)
            await presentSuccessPopup(msg)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        // Practical email shape check (not full RFC).
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
