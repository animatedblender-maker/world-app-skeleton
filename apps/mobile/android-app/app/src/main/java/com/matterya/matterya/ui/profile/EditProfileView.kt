package com.matterya.matterya.ui.profile

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.LivingChannelMarker
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.AvatarView

/**
 * iOS `EditProfileView` — Avatar, Identity, Location (detect-only), Bio, Save Profile.
 */
@Composable
fun EditProfileView(
    profile: Profile?,
    busy: Boolean = false,
    uploadingAvatar: Boolean = false,
    detectingLocation: Boolean = false,
    locationStatus: String = "",
    error: String? = null,
    successMessage: String? = null,
    countryName: String = profile?.countryName.orEmpty(),
    countryCode: String = profile?.countryCode.orEmpty(),
    cityName: String = profile?.cityName.orEmpty(),
    avatarUrlOverride: String? = null,
    onChangeAvatar: () -> Unit = {},
    onPickAvatarUri: (android.net.Uri) -> Unit = {},
    onDetectLocation: () -> Unit = {},
    onSave: (
        displayName: String,
        username: String,
        bio: String,
        countryName: String,
        countryCode: String,
        cityName: String,
    ) -> Unit = { _, _, _, _, _, _ -> },
) {
    var name by remember(profile?.userId) { mutableStateOf(profile?.displayName.orEmpty()) }
    var username by remember(profile?.userId) { mutableStateOf(profile?.username.orEmpty()) }
    var bio by remember(profile?.userId) {
        mutableStateOf(runCatching { LivingChannelMarker.displayBio(profile?.bio) }.getOrDefault(""))
    }
    val safeCountryName = countryName.trim()
    val safeCountryCode = countryCode.trim()
    val safeCityName = cityName.trim()
    val hasDetectedLocation = safeCountryName.isNotBlank() &&
        !safeCountryName.equals("Unknown", ignoreCase = true)
    val fieldShape = RoundedCornerShape(MatteryaDimens.controlRadius)
    val avatarUrl = avatarUrlOverride?.takeIf { it.isNotBlank() } ?: profile?.avatarUrl

    val avatarPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
    ) { uri ->
        if (uri != null) onPickAvatarUri(uri)
    }

    LaunchedEffect(profile?.userId, profile?.displayName, profile?.username, profile?.bio) {
        val p = profile ?: return@LaunchedEffect
        if (name.isEmpty()) {
            name = p.displayName.orEmpty()
            username = p.username.orEmpty()
            bio = runCatching { LivingChannelMarker.displayBio(p.bio) }.getOrDefault("")
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas)
            .verticalScroll(rememberScrollState())
            .padding(bottom = 32.dp),
    ) {
        Text(
            "Edit Profile",
            fontWeight = FontWeight.SemiBold,
            fontSize = 17.sp,
            color = MatteryaColors.ink,
            modifier = Modifier.padding(MatteryaDimens.pagePadding),
        )

        SectionTitle("Avatar")
        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface)
                .padding(MatteryaDimens.pagePadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AvatarView(
                url = avatarUrl,
                seed = profile?.userId ?: "me",
                size = 64.dp,
            )
            Spacer(Modifier.width(16.dp))
            Column {
                OutlinedButton(
                    onClick = {
                        onChangeAvatar()
                        avatarPicker.launch("image/*")
                    },
                    enabled = !busy && !uploadingAvatar,
                ) {
                    if (uploadingAvatar) {
                        CircularProgressIndicator(
                            Modifier.size(14.dp),
                            strokeWidth = 2.dp,
                            color = MatteryaColors.accentBright,
                        )
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(
                        if (uploadingAvatar) "Uploading…" else "Change avatar",
                        fontWeight = FontWeight.SemiBold,
                        color = MatteryaColors.accentBright,
                    )
                }
                Spacer(Modifier.height(6.dp))
                Text(
                    if (uploadingAvatar) {
                        "Please wait — photo is uploading…"
                    } else {
                        "Pick a photo from your library."
                    },
                    fontSize = 12.sp,
                    color = MatteryaColors.inkMuted,
                )
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)

        SectionTitle("Identity")
        LabeledField("Display name") {
            TextField(
                value = name,
                onValueChange = { name = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .border(0.5.dp, MatteryaColors.border, fieldShape),
                singleLine = true,
                colors = fieldColors(),
            )
        }
        LabeledField("Username") {
            TextField(
                value = username,
                onValueChange = { username = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .border(0.5.dp, MatteryaColors.border, fieldShape),
                singleLine = true,
                colors = fieldColors(),
            )
        }

        SectionTitle("Location")
        Column(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface)
                .padding(MatteryaDimens.pagePadding),
        ) {
            when {
                detectingLocation -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(
                            Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = MatteryaColors.accentBright,
                        )
                        Spacer(Modifier.width(10.dp))
                        Text("Detecting your location…", fontSize = 14.sp, color = MatteryaColors.inkMuted)
                    }
                }
                hasDetectedLocation -> {
                    Text("Country", fontSize = 12.sp, color = MatteryaColors.inkMuted)
                    Text(safeCountryName, fontSize = 15.sp, color = MatteryaColors.ink)
                    if (safeCityName.isNotBlank()) {
                        Spacer(Modifier.height(8.dp))
                        Text("City", fontSize = 12.sp, color = MatteryaColors.inkMuted)
                        Text(safeCityName, fontSize = 15.sp, color = MatteryaColors.ink)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Location is detected automatically and can’t be edited.",
                        fontSize = 12.sp,
                        color = MatteryaColors.inkMuted,
                    )
                }
                else -> {
                    Text(
                        locationStatus.ifBlank {
                            "Tap below to detect your location from this device."
                        },
                        fontSize = 13.sp,
                        color = MatteryaColors.inkMuted,
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedButton(
                onClick = onDetectLocation,
                enabled = !detectingLocation && !busy && !uploadingAvatar,
            ) {
                Text(
                    if (detectingLocation) "Detecting…" else "Detect location again",
                    color = MatteryaColors.accentBright,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)

        SectionTitle("Bio")
        LabeledField("Bio") {
            TextField(
                value = bio,
                onValueChange = { bio = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp)
                    .border(0.5.dp, MatteryaColors.border, fieldShape),
                colors = fieldColors(),
            )
        }

        error?.let {
            Text(
                it,
                color = MatteryaColors.danger,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
            )
        }
        successMessage?.let {
            Text(
                it,
                color = MatteryaColors.success,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp),
            )
        }

        Spacer(Modifier.height(16.dp))
        Button(
            onClick = {
                val trimmedName = name.trim()
                if (trimmedName.isEmpty()) return@Button
                onSave(
                    trimmedName,
                    username.trim(),
                    bio.trim(),
                    safeCountryName,
                    safeCountryCode,
                    safeCityName,
                )
            },
            enabled = !busy && !uploadingAvatar && name.trim().isNotEmpty(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding)
                .height(48.dp),
            shape = RoundedCornerShape(MatteryaDimens.controlRadius),
            colors = ButtonDefaults.buttonColors(containerColor = MatteryaColors.accentBright),
        ) {
            if (busy) {
                CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
            }
            Text(
                if (busy) "Saving…" else "Save Profile",
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
            )
        }
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        title,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        color = MatteryaColors.inkMuted,
        modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 10.dp),
    )
}

@Composable
private fun LabeledField(label: String, content: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 10.dp),
    ) {
        Text(label, fontSize = 12.sp, color = MatteryaColors.inkMuted)
        Spacer(Modifier.height(6.dp))
        content()
    }
    HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
}

@Composable
private fun fieldColors() = TextFieldDefaults.colors(
    focusedContainerColor = MatteryaColors.surface,
    unfocusedContainerColor = MatteryaColors.surface,
    focusedIndicatorColor = Color.Transparent,
    unfocusedIndicatorColor = Color.Transparent,
    cursorColor = MatteryaColors.accentBright,
)
