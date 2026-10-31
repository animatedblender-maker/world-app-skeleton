package com.matterya.matterya.data.auth

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.model.AuthSession
import com.matterya.matterya.model.AuthUser
import com.matterya.matterya.model.RegisterResult
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

private val Context.authDataStore by preferencesDataStore("matterya_auth")

/**
 * Auth — mirrors iOS `AuthService.swift`:
 * - Login / refresh via Supabase auth v1
 * - Signup via Matterya-owned `api.matterya.com/auth/signup`
 * - Session persistence
 */
class AuthService private constructor(private val appContext: Context) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val http = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()
    private val mutex = Mutex()
    private var session: AuthSession? = null

    val isAuthenticated: Boolean get() = session != null
    val currentUser: AuthUser? get() = session?.user
    val currentSession: AuthSession? get() = session

    suspend fun load() {
        // DataStore read can block; never run on Main (caused ANR during bootstrap).
        val raw = withContext(Dispatchers.IO) {
            appContext.authDataStore.data.first()[SESSION_KEY]
        } ?: return
        try {
            session = parseSession(raw)
        } catch (_: Exception) {
            session = null
        }
    }

    fun accessToken(): String? = session?.accessToken

    suspend fun ensureValidTokenOrNull(): String? = try {
        ensureValidToken()
    } catch (_: Exception) {
        null
    }

    suspend fun ensureValidToken(): String = mutex.withLock {
        val s = session ?: throw AuthException("Not signed in.")
        val refreshThreshold = System.currentTimeMillis() / 1000.0 + 60
        if (s.expiresAt >= refreshThreshold) return s.accessToken
        try {
            refreshAccessTokenLocked()
        } catch (e: AuthException) {
            logoutInternal()
            throw AuthException("Your session has expired. Please log in again.")
        }
        return session?.accessToken ?: throw AuthException("Your session has expired. Please log in again.")
    }

    suspend fun login(email: String, password: String) {
        PasswordPolicy.validatePresent(password).getOrElse {
            throw AuthException(it.message ?: "Password cannot be empty.")
        }
        val trimmed = email.trim()
        if (trimmed.isEmpty()) throw AuthException("Email is required. Enter your email address.")
        // Always IO — AppState scope is Main; OkHttp must not run on main.
        val response = withContext(Dispatchers.IO) {
            postAuth(
                "token?grant_type=password",
                buildJsonObject {
                    put("email", trimmed)
                    put("password", password)
                },
            )
        }
        applyAuthResponse(response)
        Log.i(TAG, "login ok user=${session?.user?.id}")
    }

    /**
     * Matterya-owned signup: API creates an unconfirmed user and emails a branded
     * confirmation link. Does **not** establish a session (matches iOS).
     */
    suspend fun register(email: String, password: String): RegisterResult {
        PasswordPolicy.validateStrong(password).getOrElse {
            throw AuthException(it.message ?: PasswordPolicy.REQUIREMENTS_HINT)
        }
        val trimmed = email.trim()
        if (trimmed.isEmpty()) throw AuthException("Email is required. Enter your email address.")

        return withContext(Dispatchers.IO) {
            val body = buildJsonObject {
                put("email", trimmed)
                put("password", password)
            }.toString()
            val req = Request.Builder()
                .url("${AppConfig.apiBaseURL}/auth/signup")
                .post(body.toRequestBody(JSON))
                .header("content-type", "application/json")
                .header("accept", "application/json")
                .build()
            val res = http.newCall(req).execute()
            val raw = res.body?.string().orEmpty()
            val obj = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull()

            if (res.code >= 400) {
                val isExisting = obj?.get("isExistingEmail")?.jsonPrimitive?.booleanOrNull == true ||
                    obj?.get("error")?.jsonPrimitive?.contentOrNull == "EMAIL_EXISTS"
                if (isExisting) return@withContext RegisterResult(needsEmailConfirm = false, isExistingEmail = true)

                val message = obj?.get("message")?.jsonPrimitive?.contentOrNull
                    ?: obj?.get("error")?.jsonPrimitive?.contentOrNull
                    ?: "Signup failed (HTTP ${res.code})."
                if (message.contains(Regex("already|registered|exists", RegexOption.IGNORE_CASE))) {
                    return@withContext RegisterResult(needsEmailConfirm = false, isExistingEmail = true)
                }
                throw AuthException(message)
            }

            // Successful Matterya signup always requires opening the confirmation email.
            RegisterResult(needsEmailConfirm = true, isExistingEmail = false)
        }
    }

    suspend fun resendConfirmation(email: String): String = withContext(Dispatchers.IO) {
        val body = buildJsonObject {
            put("email", email.trim())
        }.toString()
        val req = Request.Builder()
            .url("${AppConfig.apiBaseURL}/auth/resend-confirmation")
            .post(body.toRequestBody(JSON))
            .header("content-type", "application/json")
            .header("accept", "application/json")
            .build()
        val res = http.newCall(req).execute()
        val raw = res.body?.string().orEmpty()
        val obj = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull()
        if (res.code >= 400) {
            throw AuthException(
                obj?.get("message")?.jsonPrimitive?.contentOrNull
                    ?: "Could not resend confirmation email.",
            )
        }
        obj?.get("message")?.jsonPrimitive?.contentOrNull
            ?: "If that email needs confirmation, we sent a new Matterya link."
    }

    suspend fun logout() {
        mutex.withLock { logoutInternal() }
    }

    private suspend fun logoutInternal() {
        session = null
        appContext.authDataStore.edit { it.remove(SESSION_KEY) }
    }

    private suspend fun refreshAccessTokenLocked() {
        val s = session ?: throw AuthException("Session expired.")
        val response = withContext(Dispatchers.IO) {
            postAuth(
                "token?grant_type=refresh_token",
                buildJsonObject { put("refresh_token", s.refreshToken) },
            )
        }
        applyAuthResponse(response)
    }

    private suspend fun applyAuthResponse(obj: JsonObject) {
        val access = obj["access_token"]?.jsonPrimitive?.contentOrNull
            ?: throw AuthException("Invalid email or password.")
        val refresh = obj["refresh_token"]?.jsonPrimitive?.contentOrNull
            ?: throw AuthException("Invalid email or password.")
        // Supabase returns expires_at as integer seconds; accept int/long/double.
        val expiresIn = numberAsDouble(obj["expires_in"]) ?: 3600.0
        val expiresAt = numberAsDouble(obj["expires_at"])
            ?: (System.currentTimeMillis() / 1000.0 + expiresIn)
        val userObj = obj["user"]?.jsonObject
            ?: throw AuthException("Invalid email or password.")
        val userId = userObj["id"]?.jsonPrimitive?.contentOrNull.orEmpty()
        if (userId.isEmpty()) throw AuthException("Invalid email or password.")
        val user = AuthUser(
            id = userId,
            email = userObj["email"]?.jsonPrimitive?.contentOrNull,
        )
        session = AuthSession(access, refresh, expiresAt, user)
        persist()
    }

    private fun numberAsDouble(el: kotlinx.serialization.json.JsonElement?): Double? {
        val p = el?.jsonPrimitive ?: return null
        return p.doubleOrNull
            ?: p.longOrNull?.toDouble()
            ?: p.intOrNull?.toDouble()
            ?: p.contentOrNull?.toDoubleOrNull()
    }

    private suspend fun persist() {
        val s = session ?: return
        val raw = buildJsonObject {
            put("access_token", s.accessToken)
            put("refresh_token", s.refreshToken)
            put("expires_at", s.expiresAt)
            put(
                "user",
                buildJsonObject {
                    put("id", s.user.id)
                    s.user.email?.let { put("email", it) }
                },
            )
        }.toString()
        appContext.authDataStore.edit { it[SESSION_KEY] = raw }
    }

    private fun parseSession(raw: String): AuthSession {
        val obj = json.parseToJsonElement(raw).jsonObject
        val userObj = obj["user"]?.jsonObject
        return AuthSession(
            accessToken = obj["access_token"]?.jsonPrimitive?.contentOrNull
                ?: obj["accessToken"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            refreshToken = obj["refresh_token"]?.jsonPrimitive?.contentOrNull
                ?: obj["refreshToken"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            expiresAt = obj["expires_at"]?.jsonPrimitive?.doubleOrNull
                ?: obj["expiresAt"]?.jsonPrimitive?.doubleOrNull
                ?: 0.0,
            user = AuthUser(
                id = userObj?.get("id")?.jsonPrimitive?.contentOrNull.orEmpty(),
                email = userObj?.get("email")?.jsonPrimitive?.contentOrNull,
            ),
        )
    }

    /** Blocking HTTP — call only from [Dispatchers.IO]. */
    private fun postAuth(path: String, body: JsonObject): JsonObject {
        val req = Request.Builder()
            .url("${AppConfig.supabaseURL}/auth/v1/$path")
            .post(body.toString().toRequestBody(JSON))
            .header("content-type", "application/json")
            .header("apikey", AppConfig.supabaseAnonKey)
            .header("Authorization", "Bearer ${AppConfig.supabaseAnonKey}")
            .build()
        val res = try {
            http.newCall(req).execute()
        } catch (e: Exception) {
            Log.e(TAG, "postAuth network: ${e.message}", e)
            throw AuthException("Network error. Check your connection and try again.")
        }
        val raw = res.body?.string().orEmpty()
        if (!res.isSuccessful) {
            val obj = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull()
            val msg = obj?.get("error_description")?.jsonPrimitive?.contentOrNull
                ?: obj?.get("msg")?.jsonPrimitive?.contentOrNull
                ?: obj?.get("error")?.jsonPrimitive?.contentOrNull
                ?: obj?.get("message")?.jsonPrimitive?.contentOrNull
            val friendly = when {
                msg.isNullOrBlank() -> "Invalid email or password."
                msg.contains("email not confirmed", ignoreCase = true) ->
                    "Confirm your email first — open the Matterya link we sent you, then sign in."
                msg.contains("Invalid login", ignoreCase = true) ->
                    "Invalid email or password."
                else -> msg
            }
            Log.w(TAG, "postAuth HTTP ${res.code}: $raw")
            throw AuthException(friendly)
        }
        return try {
            json.parseToJsonElement(raw).jsonObject
        } catch (e: Exception) {
            Log.e(TAG, "postAuth parse failed: $raw", e)
            throw AuthException("Invalid email or password.")
        }
    }

    companion object {
        private const val TAG = "AuthService"
        private val SESSION_KEY = stringPreferencesKey("worldapp.auth.session")
        private val JSON = "application/json; charset=utf-8".toMediaType()

        @Volatile private var _instance: AuthService? = null
        val instance: AuthService
            get() = _instance
                ?: error("AuthService not initialized. Call AuthService.init(context) first.")

        fun init(context: Context) {
            if (_instance == null) {
                synchronized(this) {
                    if (_instance == null) {
                        _instance = AuthService(context.applicationContext)
                    }
                }
            }
        }
    }
}

class AuthException(message: String) : Exception(message)
