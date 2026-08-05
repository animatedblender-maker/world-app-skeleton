import Foundation

/// Matterya strong password policy — keep in sync with API `password-policy.ts`.
enum PasswordPolicy {
    static let minLength = 8
    static let maxLength = 128

    static let requirementsHint =
        "Use at least 8 characters with uppercase, lowercase, a number, and a symbol character (!@#$%…)."

    private static let commonPasswords: Set<String> = [
        "password", "password1", "password12", "password123",
        "12345678", "123456789", "1234567890",
        "qwerty123", "qwertyui", "letmein1", "welcome1",
        "admin123", "iloveyou", "monkey12", "abc12345",
        "passw0rd", "matterya", "matterya1",
    ]

    enum Failure: LocalizedError {
        case empty(String)
        case weak(String)

        var errorDescription: String? {
            switch self {
            case .empty(let message), .weak(let message): message
            }
        }
    }

    /// Signup / password reset — full strength.
    static func validateStrong(_ password: String) -> Result<Void, Failure> {
        if password.isEmpty || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.empty("Password cannot be empty. Choose a strong password to continue."))
        }
        if password.count < minLength {
            return .failure(.weak(
                "Password is too short. Use at least \(minLength) characters, including uppercase, lowercase, a number, and a symbol character."
            ))
        }
        if password.count > maxLength {
            return .failure(.weak("Password is too long. Use at most \(maxLength) characters."))
        }
        if password.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return .failure(.weak("Password cannot contain spaces. Use letters, numbers, and symbols only."))
        }
        if password.range(of: "[a-z]", options: .regularExpression) == nil {
            return .failure(.weak("Password must include at least one lowercase letter (a–z)."))
        }
        if password.range(of: "[A-Z]", options: .regularExpression) == nil {
            return .failure(.weak("Password must include at least one uppercase letter (A–Z)."))
        }
        if password.range(of: "[0-9]", options: .regularExpression) == nil {
            return .failure(.weak("Password must include at least one number (0–9)."))
        }
        if password.range(of: "[^A-Za-z0-9]", options: .regularExpression) == nil {
            return .failure(.weak(
                "Password must include at least one special character (for example ! @ # $ % & *)."
            ))
        }
        if commonPasswords.contains(password.lowercased()) {
            return .failure(.weak("That password is too common. Choose something unique that only you would use."))
        }
        if let first = password.first, password.allSatisfy({ $0 == first }) {
            return .failure(.weak("Password cannot be the same character repeated. Mix letters, numbers, and symbols."))
        }
        return .success(())
    }

    /// Login — empty only.
    static func validatePresent(_ password: String) -> Result<Void, Failure> {
        if password.isEmpty || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.empty("Password cannot be empty. Enter your password to log in."))
        }
        return .success(())
    }

    static func isStrong(_ password: String) -> Bool {
        if case .success = validateStrong(password) { return true }
        return false
    }
}
