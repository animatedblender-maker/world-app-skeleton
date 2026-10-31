package com.matterya.matterya.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.ui.auth.AuthView
import com.matterya.matterya.ui.profile.ProfileSetupView
import com.matterya.matterya.ui.shell.MainTabView
import com.matterya.matterya.viewmodel.AppUiState
import com.matterya.matterya.viewmodel.AppViewModel
import kotlinx.coroutines.launch

/**
 * Root auth gate — mirrors iOS `RootView`.
 *
 * **No AnimatedContent** on the auth gate: animated transitions remount the login
 * fields and drop keyboard focus / swallow key events (especially on emulator).
 */
@Composable
fun RootView(
    state: AppUiState,
    vm: AppViewModel,
) {
    when {
        state.bootstrapping -> SplashScreen("Loading…")
        !state.authenticated -> AuthView(
            busy = state.authBusy,
            error = state.authError,
            onLogin = vm::login,
            onRegister = vm::register,
        )
        state.needsProfileSetup -> {
            // iOS ProfileSetupView — full form (photo, username, auto location, bio).
            val scope = rememberCoroutineScope()
            var avatarOverride by remember { mutableStateOf<String?>(null) }
            var avatarBusy by remember { mutableStateOf(false) }
            var avatarError by remember { mutableStateOf<String?>(null) }
            ProfileSetupView(
                profile = state.profile,
                busy = state.authBusy || avatarBusy,
                error = avatarError ?: state.authError,
                externalAvatarUrl = avatarOverride ?: state.profile?.avatarUrl,
                onUploadAvatar = { uri ->
                    scope.launch {
                        avatarBusy = true
                        avatarError = null
                        runCatching { vm.uploadAvatarAndApply(uri) }
                            .onSuccess { p ->
                                avatarOverride = p.avatarUrl
                            }
                            .onFailure {
                                avatarError = "Avatar upload failed: ${it.message ?: "try another image"}"
                            }
                        avatarBusy = false
                    }
                },
                onSave = { name, username, country, code, city, bio, avatar ->
                    vm.completeProfile(
                        displayName = name,
                        username = username,
                        countryName = country,
                        countryCode = code,
                        cityName = city,
                        bio = bio,
                        avatarUrl = avatar ?: avatarOverride,
                    )
                },
            )
        }
        !state.sessionReady -> SplashScreen("Loading Matterya…")
        else -> MainTabView(state = state, vm = vm)
    }
}

@Composable
fun SplashScreen(label: String) {
    Box(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                AppConfig.appName,
                fontFamily = FontFamily.Serif,
                fontSize = 32.sp,
                color = MatteryaColors.ink,
            )
            Spacer(Modifier.height(16.dp))
            Text(label, color = MatteryaColors.inkMuted, fontSize = 14.sp)
            Spacer(Modifier.height(16.dp))
            CircularProgressIndicator(color = MatteryaColors.accent)
        }
    }
}
