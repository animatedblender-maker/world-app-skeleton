package com.matterya.matterya.ui.settings

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens

/**
 * iOS `BlockedAccountsView` — list + unblock.
 */
@Composable
fun BlockedAccountsView(
    blocked: List<com.matterya.matterya.data.social.BlockedAccount> = emptyList(),
    onUnblock: (String) -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas)
            .verticalScroll(rememberScrollState())
            .padding(bottom = 40.dp),
    ) {
        Text(
            "Blocked",
            fontWeight = FontWeight.SemiBold,
            fontSize = 22.sp,
            color = MatteryaColors.ink,
            modifier = Modifier.padding(MatteryaDimens.pagePadding),
        )
        if (blocked.isEmpty()) {
            Text(
                "No blocked accounts",
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding),
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "People you block won't appear in your feed. Block someone from their post menu or profile.",
                fontSize = 14.sp,
                color = MatteryaColors.inkMuted,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding),
            )
        } else {
            blocked.forEach { account ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(MatteryaColors.surface)
                        .padding(horizontal = MatteryaDimens.pagePadding, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(account.label, fontWeight = FontWeight.Medium, color = MatteryaColors.ink)
                        account.username?.let {
                            Text("@$it", fontSize = 12.sp, color = MatteryaColors.inkMuted)
                        }
                    }
                    TextButton(onClick = { onUnblock(account.userId) }) {
                        Text("Unblock", fontWeight = FontWeight.SemiBold, color = MatteryaColors.accentBright)
                    }
                }
                HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
            }
        }
    }
}

/**
 * iOS `SettingsView` — Account, Account control, Notifications, Calling, Privacy, Support.
 */
@Composable
fun SettingsView(
    profile: Profile?,
    appVersion: String = "1.0.0 (1)",
    pushEnabled: Boolean = false,
    alertTokenStatus: String = "—",
    alertServerStatus: String = "—",
    pushRoutesStatus: String = "—",
    apnsStatus: String = "—",
    serverTokenSummary: String = "",
    registrationSummary: String = "",
    statusMessage: String? = null,
    isRequestingPush: Boolean = false,
    isSendingTest: Boolean = false,
    isRefreshingPush: Boolean = false,
    voipTokenStatus: String = "—",
    voipServerStatus: String = "—",
    signalingStatus: String = "—",
    incomingCallsReady: Boolean = false,
    pushEnvironmentLabel: String = "",
    callingSummary: String = "",
    isRefreshingCalling: Boolean = false,
    /** CallKit → TelecomCallManager surface line. */
    telecomStatus: String = "—",
    /** Apple Music → NowPlayingService / MediaSession surface line. */
    nowPlayingStatus: String = "—",
    blockedCount: Int = 0,
    onEditProfile: () -> Unit = {},
    onLogout: () -> Unit = {},
    onDeactivate: () -> Unit = {},
    onDelete: (confirmation: String) -> Unit = {},
    onPushToggle: (Boolean) -> Unit = {},
    onSendTestPush: () -> Unit = {},
    onRefreshPush: () -> Unit = {},
    onRefreshCalling: () -> Unit = {},
    onOpenBlocked: () -> Unit = {},
    onOpenPrivacy: () -> Unit = {},
    onOpenHelp: () -> Unit = {},
) {
    val context = LocalContext.current
    var accountSheet by remember { mutableStateOf<AccountSheet?>(null) }
    var deleteConfirmation by remember { mutableStateOf("") }
    var accountError by remember { mutableStateOf<String?>(null) }
    var privacyOpen by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas)
            .verticalScroll(rememberScrollState())
            .padding(bottom = 40.dp),
    ) {
        Text(
            "Settings",
            fontWeight = FontWeight.SemiBold,
            fontSize = 22.sp,
            color = MatteryaColors.ink,
            modifier = Modifier.padding(MatteryaDimens.pagePadding),
        )

        SectionHeader("Account")
        if (profile != null) {
            SettingsRow("Name", profile.displayName ?: profile.username ?: "Member")
            profile.username?.let { SettingsRow("Username", "@$it") }
            profile.countryName?.let { SettingsRow("Home country", it) }
        }
        SettingsAction("Edit profile", onClick = onEditProfile)

        Spacer(Modifier.height(12.dp))
        SectionHeader("Account control")
        SettingsAction(
            title = "Deactivate account",
            subtitle = "Hide your profile and pause activity. You can sign in again anytime to reactivate.",
            chevron = true,
            onClick = {
                accountError = null
                accountSheet = AccountSheet.Deactivate
            },
        )
        SettingsAction(
            title = "Delete account",
            subtitle = "Permanently delete your account, profile, and posts. This cannot be undone.",
            danger = true,
            chevron = true,
            onClick = {
                deleteConfirmation = ""
                accountError = null
                accountSheet = AccountSheet.Delete
            },
        )
        accountError?.let {
            Text(
                it,
                fontSize = 12.sp,
                color = MatteryaColors.danger,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 6.dp),
            )
        }
        FooterText("Deactivate is temporary. Delete removes your Matterya identity and content for good.")

        Spacer(Modifier.height(12.dp))
        SectionHeader("Notifications")
        SettingsToggleRow(
            title = "Incoming calls & alerts",
            checked = pushEnabled,
            onCheckedChange = { enabled ->
                if (enabled) {
                    onPushToggle(true)
                } else {
                    // Mirror iOS: open system settings to disable
                    runCatching {
                        context.startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                            },
                        )
                    }
                    onPushToggle(false)
                }
            },
        )
        if (isRequestingPush) {
            Text(
                "Requesting permission…",
                fontSize = 13.sp,
                color = MatteryaColors.inkMuted,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
            )
        }
        StatusRow("Alert token", alertTokenStatus, alertTokenStatus == "Received")
        StatusRow("Server registration", alertServerStatus, alertServerStatus == "Registered")
        StatusRow("Push API routes", pushRoutesStatus, pushRoutesStatus == "Deployed")
        StatusRow("Server APNs", apnsStatus, apnsStatus == "Configured")
        if (serverTokenSummary.isNotBlank()) {
            SettingsRow("Devices on server", serverTokenSummary)
        }
        if (registrationSummary.isNotBlank()) {
            Text(
                registrationSummary,
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
            )
        }
        SettingsAction(
            title = if (isSendingTest) "Sending test…" else "Send test notification",
            enabled = !isSendingTest && pushEnabled,
            onClick = onSendTestPush,
        )
        SettingsAction(
            title = if (isRefreshingPush) "Refreshing…" else "Refresh push status",
            enabled = !isRefreshingPush,
            onClick = onRefreshPush,
        )
        statusMessage?.let {
            Text(
                it,
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
            )
        }
        FooterText(
            "Android uses FCM high-priority channels for calls and alerts. " +
                "Enable notifications in system Settings if the toggle stays off.",
        )

        Spacer(Modifier.height(12.dp))
        SectionHeader("Calling")
        StatusRow("VoIP token", voipTokenStatus, voipTokenStatus == "Received")
        StatusRow("Server registration", voipServerStatus, voipServerStatus == "Registered")
        StatusRow("Call signaling", signalingStatus, signalingStatus == "Connected")
        StatusRow(
            "Incoming calls",
            if (incomingCallsReady) "Ready" else "Not ready",
            incomingCallsReady,
        )
        // CallKit → TelecomCallManager (always referenced — not a missing service gap).
        SettingsRow("Telecom (CallKit)", telecomStatus)
        if (pushEnvironmentLabel.isNotBlank()) {
            SettingsRow("Push environment", pushEnvironmentLabel)
        }
        if (callingSummary.isNotBlank()) {
            Text(
                callingSummary,
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
            )
        }
        SettingsAction(
            title = if (isRefreshingCalling) "Refreshing…" else "Refresh calling status",
            enabled = !isRefreshingCalling,
            onClick = onRefreshCalling,
        )
        FooterText(
            "Incoming calls when Matterya is closed require push registration and a real device. " +
                "If Server registration stays red, calls cannot ring off-app. " +
                "TelecomCallManager is the Android CallKit surface.",
        )

        Spacer(Modifier.height(12.dp))
        SectionHeader("Media")
        // Apple Music → NowPlayingService (MediaSession).
        SettingsRow("Now Playing", nowPlayingStatus)
        FooterText(
            "NowPlayingService mirrors iOS AppleMusicNowPlayingService via Android MediaSession. " +
                "Share what you're listening to from Connected.",
        )

        Spacer(Modifier.height(12.dp))
        SectionHeader("Privacy")
        SettingsAction(
            title = "Blocked accounts",
            subtitle = if (blockedCount > 0) "$blockedCount blocked" else null,
            chevron = true,
            onClick = onOpenBlocked,
        )
        SettingsAction(
            title = "Data & privacy",
            chevron = true,
            onClick = {
                privacyOpen = true
                onOpenPrivacy()
            },
        )

        Spacer(Modifier.height(12.dp))
        SectionHeader("Support")
        SettingsRow("App", "Matterya")
        SettingsRow("Version", appVersion)
        SettingsAction(
            title = "Help center",
            chevron = true,
            onClick = {
                onOpenHelp()
                runCatching {
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("https://matterya.com")),
                    )
                }
            },
        )

        Spacer(Modifier.height(20.dp))
        SettingsAction("Log out", danger = true, onClick = onLogout)
    }

    when (val sheet = accountSheet) {
        AccountSheet.Deactivate -> AccountConfirmDialog(
            title = "Deactivate account?",
            body = "Your profile will be hidden and you will be signed out. Sign in again anytime to reactivate.",
            confirmLabel = "Deactivate",
            error = accountError,
            onCancel = { accountSheet = null },
            onConfirm = {
                accountSheet = null
                onDeactivate()
            },
        )
        AccountSheet.Delete -> AccountDeleteDialog(
            username = profile?.username,
            confirmation = deleteConfirmation,
            onConfirmationChange = { deleteConfirmation = it },
            error = accountError,
            onCancel = { accountSheet = null },
            onConfirm = {
                val text = deleteConfirmation.trim()
                if (text.isEmpty()) {
                    accountError = "Enter DELETE or your username to confirm."
                } else {
                    accountSheet = null
                    onDelete(text)
                }
            },
        )
        null -> Unit
    }

    if (privacyOpen) {
        PrivacyInfoDialog(onDismiss = { privacyOpen = false })
    }
}

private enum class AccountSheet { Deactivate, Delete }

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        color = MatteryaColors.inkMuted,
        modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
    )
}

@Composable
private fun FooterText(text: String) {
    Text(
        text,
        fontSize = 12.sp,
        color = MatteryaColors.inkMuted,
        modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
    )
}

@Composable
private fun SettingsRow(label: String, value: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = MatteryaColors.ink, fontSize = 15.sp, modifier = Modifier.weight(1f))
        Text(value, color = MatteryaColors.inkMuted, fontSize = 15.sp)
    }
    HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
}

@Composable
private fun StatusRow(label: String, value: String, positive: Boolean) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = MatteryaColors.ink, fontSize = 15.sp, modifier = Modifier.weight(1f))
        Text(
            value,
            fontWeight = FontWeight.SemiBold,
            fontSize = 14.sp,
            color = if (positive) MatteryaColors.success else MatteryaColors.inkMuted,
        )
    }
    HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
}

@Composable
private fun SettingsToggleRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = MatteryaColors.ink, fontSize = 15.sp, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = MatteryaColors.accentBright,
            ),
        )
    }
    HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
}

@Composable
private fun SettingsAction(
    title: String,
    subtitle: String? = null,
    danger: Boolean = false,
    chevron: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                color = when {
                    !enabled -> MatteryaColors.inkMuted
                    danger -> MatteryaColors.danger
                    else -> MatteryaColors.ink
                },
                fontSize = 15.sp,
            )
            if (subtitle != null) {
                Spacer(Modifier.height(4.dp))
                Text(subtitle, fontSize = 12.sp, color = MatteryaColors.inkMuted)
            }
        }
        if (chevron) {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MatteryaColors.inkMuted,
            )
        }
    }
    HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
}

@Composable
private fun AccountConfirmDialog(
    title: String,
    body: String,
    confirmLabel: String,
    error: String?,
    onCancel: () -> Unit,
    onConfirm: () -> Unit,
) {
    Dialog(onDismissRequest = onCancel) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(MatteryaColors.surface)
                .padding(20.dp),
        ) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp, color = MatteryaColors.ink)
            Spacer(Modifier.height(10.dp))
            Text(body, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
            error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = MatteryaColors.danger, fontSize = 12.sp)
            }
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onCancel) {
                    Text("Cancel", color = MatteryaColors.inkMuted)
                }
                Spacer(Modifier.width(8.dp))
                TextButton(onClick = onConfirm) {
                    Text(confirmLabel, color = MatteryaColors.danger, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun AccountDeleteDialog(
    username: String?,
    confirmation: String,
    onConfirmationChange: (String) -> Unit,
    error: String?,
    onCancel: () -> Unit,
    onConfirm: () -> Unit,
) {
    val handle = username?.let { "@$it" } ?: "your username"
    Dialog(onDismissRequest = onCancel) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(MatteryaColors.surface)
                .padding(20.dp),
        ) {
            Text(
                "Delete account permanently?",
                fontWeight = FontWeight.Bold,
                fontSize = 18.sp,
                color = MatteryaColors.ink,
            )
            Spacer(Modifier.height(10.dp))
            Text(
                "This cannot be undone. Posts, profile, and login will be removed.",
                color = MatteryaColors.inkSecondary,
                fontSize = 14.sp,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Type DELETE or $handle to confirm.",
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
            )
            Spacer(Modifier.height(10.dp))
            TextField(
                value = confirmation,
                onValueChange = onConfirmationChange,
                placeholder = { Text("DELETE or username") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(MatteryaColors.surfaceMuted),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MatteryaColors.surfaceMuted,
                    unfocusedContainerColor = MatteryaColors.surfaceMuted,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                ),
            )
            error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = MatteryaColors.danger, fontSize = 12.sp)
            }
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onCancel) {
                    Text("Cancel", color = MatteryaColors.inkMuted)
                }
                Spacer(Modifier.width(8.dp))
                TextButton(
                    onClick = onConfirm,
                    enabled = confirmation.trim().isNotEmpty(),
                ) {
                    Text("Delete forever", color = MatteryaColors.danger, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun PrivacyInfoDialog(onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(MatteryaColors.surface)
                .padding(20.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            Text("Privacy", fontWeight = FontWeight.Bold, fontSize = 18.sp, color = MatteryaColors.ink)
            Spacer(Modifier.height(14.dp))
            Text("Your data", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            Spacer(Modifier.height(6.dp))
            Text(
                "Matterya stores your profile, posts, and messages on our servers so you can use the app across devices. We do not sell your personal data.",
                color = MatteryaColors.inkSecondary,
                fontSize = 14.sp,
            )
            Spacer(Modifier.height(14.dp))
            Text("Calls", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            Spacer(Modifier.height(6.dp))
            Text(
                "Voice and video calls use encrypted real-time channels. Call activity may be logged in your conversation history.",
                color = MatteryaColors.inkSecondary,
                fontSize = 14.sp,
            )
            Spacer(Modifier.height(16.dp))
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text("Done", color = MatteryaColors.accentBright, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
