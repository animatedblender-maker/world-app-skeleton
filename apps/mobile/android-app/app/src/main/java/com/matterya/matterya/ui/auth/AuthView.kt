package com.matterya.matterya.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.config.AppConfig
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens

/**
 * Login / register — mirrors iOS `AuthView`.
 * Uses [BasicTextField] (not Material TextField) so emulator / soft-keyboard input stays stable
 * under recomposition.
 */
@Composable
fun AuthView(
    busy: Boolean,
    error: String?,
    onLogin: (email: String, password: String) -> Unit,
    onRegister: (email: String, password: String) -> Unit,
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var signup by remember { mutableStateOf(false) }
    var localError by remember { mutableStateOf<String?>(null) }

    val emailFocus = remember { FocusRequester() }
    val passwordFocus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current

    // Request keyboard on first open (helps emulator soft-IME).
    LaunchedEffect(Unit) {
        emailFocus.requestFocus()
        keyboard?.show()
    }

    fun submit() {
        localError = null
        val trimmed = email.trim()
        if (trimmed.isEmpty()) {
            localError = "Email is required. Enter your email address."
            return
        }
        if (!trimmed.contains("@")) {
            localError = "Enter a valid email address (for example you@example.com)."
            return
        }
        if (password.isEmpty()) {
            localError = "Password is required."
            return
        }
        keyboard?.hide()
        if (signup) onRegister(trimmed, password) else onLogin(trimmed, password)
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas)
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(48.dp))
        Text(
            AppConfig.appName,
            fontFamily = FontFamily.Serif,
            fontSize = 42.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.ink,
        )
        Spacer(Modifier.height(32.dp))

        PremiumTextField(
            title = "Email",
            value = email,
            onValueChange = { email = it },
            keyboardType = KeyboardType.Email,
            imeAction = ImeAction.Next,
            onImeAction = { passwordFocus.requestFocus() },
            focusRequester = emailFocus,
            enabled = !busy,
        )
        Spacer(Modifier.height(14.dp))
        PremiumTextField(
            title = "Password",
            value = password,
            onValueChange = { password = it },
            isSecure = true,
            keyboardType = KeyboardType.Password,
            imeAction = ImeAction.Done,
            onImeAction = { submit() },
            focusRequester = passwordFocus,
            enabled = !busy,
        )

        val displayError = localError ?: error
        if (displayError != null) {
            Spacer(Modifier.height(10.dp))
            Text(
                displayError,
                color = MatteryaColors.danger,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Spacer(Modifier.height(16.dp))
        Button(
            onClick = { submit() },
            enabled = !busy,
            modifier = Modifier
                .fillMaxWidth()
                .height(46.dp),
            shape = RoundedCornerShape(MatteryaDimens.controlRadius),
            colors = ButtonDefaults.buttonColors(containerColor = MatteryaColors.accent),
        ) {
            if (busy) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp)
            } else {
                Text(
                    if (signup) "Sign Up" else "Log In",
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                )
            }
        }

        Spacer(Modifier.height(24.dp))
        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
        Spacer(Modifier.height(16.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                if (signup) "Have an account?" else "Don't have an account?",
                color = MatteryaColors.inkMuted,
                fontSize = 14.sp,
            )
            TextButton(
                onClick = {
                    signup = !signup
                    localError = null
                },
                enabled = !busy,
            ) {
                Text(
                    if (signup) "Log in" else "Sign up",
                    color = MatteryaColors.accent,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
        Spacer(Modifier.height(40.dp))
    }
}

@Composable
fun PremiumTextField(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    isSecure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Default,
    onImeAction: (() -> Unit)? = null,
    focusRequester: FocusRequester? = null,
    enabled: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    Column(Modifier.fillMaxWidth()) {
        Text(
            title,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = MatteryaColors.inkMuted,
        )
        Spacer(Modifier.height(6.dp))
        Box(
            Modifier
                .fillMaxWidth()
                .height(48.dp)
                .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.controlRadius))
                .background(MatteryaColors.canvasMuted, RoundedCornerShape(MatteryaDimens.controlRadius))
                .padding(horizontal = 14.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                singleLine = true,
                textStyle = TextStyle(
                    color = MatteryaColors.ink,
                    fontSize = 16.sp,
                ),
                cursorBrush = SolidColor(MatteryaColors.accent),
                visualTransformation = if (isSecure) {
                    PasswordVisualTransformation()
                } else {
                    VisualTransformation.None
                },
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = keyboardType,
                    imeAction = imeAction,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { onImeAction?.invoke() },
                    onDone = { onImeAction?.invoke() },
                ),
                interactionSource = interaction,
                modifier = Modifier
                    .fillMaxWidth()
                    .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier),
            )
        }
    }
}

