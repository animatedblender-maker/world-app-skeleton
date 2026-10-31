package com.matterya.matterya.ui.auth

import androidx.compose.runtime.Composable
import com.matterya.matterya.ui.profile.ProfileSetupView

/** Back-compat re-exports — prefer [AuthView] / [ProfileSetupView]. */
@Composable
fun AuthScreen(
    busy: Boolean,
    error: String?,
    onLogin: (email: String, password: String) -> Unit,
    onRegister: (email: String, password: String) -> Unit,
) = AuthView(busy, error, onLogin, onRegister)

@Composable
fun ProfileSetupScreen(
    busy: Boolean,
    error: String?,
    onContinue: (displayName: String, country: String) -> Unit,
) = ProfileSetupView(busy, error, onContinue)
