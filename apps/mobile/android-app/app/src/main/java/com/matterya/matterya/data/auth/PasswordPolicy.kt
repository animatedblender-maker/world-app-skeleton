package com.matterya.matterya.data.auth

/**
 * Matterya strong password policy — mirrors iOS `PasswordPolicy.swift`
 * and API `password-policy.ts`.
 */
object PasswordPolicy {
    const val MIN_LENGTH = 8
    const val MAX_LENGTH = 128

    const val REQUIREMENTS_HINT =
        "Use at least 8 characters with uppercase, lowercase, a number, and a symbol character (!@#$%…)."

    private val commonPasswords = setOf(
        "password", "password1", "password12", "password123",
        "12345678", "123456789", "1234567890",
        "qwerty123", "qwertyui", "letmein1", "welcome1",
        "admin123", "iloveyou", "monkey12", "abc12345",
        "passw0rd", "matterya", "matterya1",
    )

    sealed class Failure(message: String) : Exception(message) {
        class Empty(message: String) : Failure(message)
        class Weak(message: String) : Failure(message)
    }

    /** Signup / password reset — full strength. */
    fun validateStrong(password: String): Result<Unit> {
        if (password.isEmpty() || password.trim().isEmpty()) {
            return Result.failure(
                Failure.Empty("Password cannot be empty. Choose a strong password to continue."),
            )
        }
        if (password.length < MIN_LENGTH) {
            return Result.failure(
                Failure.Weak(
                    "Password is too short. Use at least $MIN_LENGTH characters, including uppercase, lowercase, a number, and a symbol character.",
                ),
            )
        }
        if (password.length > MAX_LENGTH) {
            return Result.failure(
                Failure.Weak("Password is too long. Use at most $MAX_LENGTH characters."),
            )
        }
        if (password.any { it.isWhitespace() }) {
            return Result.failure(
                Failure.Weak("Password cannot contain spaces. Use letters, numbers, and symbols only."),
            )
        }
        if (!password.any { it in 'a'..'z' }) {
            return Result.failure(
                Failure.Weak("Password must include at least one lowercase letter (a–z)."),
            )
        }
        if (!password.any { it in 'A'..'Z' }) {
            return Result.failure(
                Failure.Weak("Password must include at least one uppercase letter (A–Z)."),
            )
        }
        if (!password.any { it in '0'..'9' }) {
            return Result.failure(
                Failure.Weak("Password must include at least one number (0–9)."),
            )
        }
        if (password.all { it.isLetterOrDigit() }) {
            return Result.failure(
                Failure.Weak(
                    "Password must include at least one special character (for example ! @ # $ % & *).",
                ),
            )
        }
        if (commonPasswords.contains(password.lowercase())) {
            return Result.failure(
                Failure.Weak("That password is too common. Choose something unique that only you would use."),
            )
        }
        if (password.all { it == password.first() }) {
            return Result.failure(
                Failure.Weak("Password cannot be the same character repeated. Mix letters, numbers, and symbols."),
            )
        }
        return Result.success(Unit)
    }

    /** Login — empty only. */
    fun validatePresent(password: String): Result<Unit> {
        if (password.isEmpty() || password.trim().isEmpty()) {
            return Result.failure(
                Failure.Empty("Password cannot be empty. Enter your password to log in."),
            )
        }
        return Result.success(Unit)
    }

    fun isStrong(password: String): Boolean = validateStrong(password).isSuccess
}
