package com.matterya.matterya.ui.profile

import android.Manifest
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.data.auth.AuthService
import com.matterya.matterya.data.location.LocationService
import com.matterya.matterya.data.posts.ProfileService
import com.matterya.matterya.model.Country
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.auth.PremiumTextField
import com.matterya.matterya.ui.components.AvatarView
import kotlinx.coroutines.launch

/**
 * Full profile setup — 1:1 with iOS `ProfileSetupView`:
 * photo · display name · username · auto-detected location · bio · Complete Setup.
 *
 * Location is detected (not free-typed). Save requires display name + detected country.
 */
@Composable
fun ProfileSetupView(
    profile: Profile? = null,
    busy: Boolean = false,
    error: String? = null,
    onSave: (
        displayName: String,
        username: String?,
        countryName: String,
        countryCode: String?,
        cityName: String?,
        bio: String?,
        avatarUrl: String?,
    ) -> Unit = { _, _, _, _, _, _, _ -> },
    onUploadAvatar: (Uri) -> Unit = {},
    externalAvatarUrl: String? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val profileService = remember { ProfileService() }

    var displayName by remember {
        mutableStateOf(
            profile?.displayName.orEmpty().ifBlank {
                AuthService.instance.currentUser?.email
                    ?.substringBefore("@")
                    .orEmpty()
            },
        )
    }
    // Old stub completeProfile saved country into username (positional args bug). Clear that.
    var username by remember {
        mutableStateOf(
            profile?.username?.takeUnless { u ->
                u.equals(profile?.countryName, ignoreCase = true) ||
                    u.equals("Spain", true) || u.equals("Germany", true) ||
                    u.equals("Unknown", true)
            }.orEmpty(),
        )
    }
    var countryName by remember {
        mutableStateOf(
            profile?.countryName?.takeUnless { it == "Unknown" }.orEmpty(),
        )
    }
    var countryCode by remember { mutableStateOf(profile?.countryCode.orEmpty()) }
    var cityName by remember { mutableStateOf(profile?.cityName.orEmpty()) }
    var bio by remember { mutableStateOf(profile?.bio.orEmpty()) }
    var avatarUrl by remember { mutableStateOf(profile?.avatarUrl) }
    var detectingLocation by remember { mutableStateOf(false) }
    var locationStatus by remember { mutableStateOf("") }
    var localError by remember { mutableStateOf<String?>(null) }
    var countries by remember { mutableStateOf<List<Country>>(emptyList()) }
    var showCountryPicker by remember { mutableStateOf(false) }

    LaunchedEffect(externalAvatarUrl) {
        if (!externalAvatarUrl.isNullOrBlank()) avatarUrl = externalAvatarUrl
    }

    LaunchedEffect(profile?.userId) {
        profile?.let { p ->
            if (displayName.isBlank()) displayName = p.displayName.orEmpty()
            if (username.isBlank()) username = p.username.orEmpty()
            if (countryName.isBlank()) {
                countryName = p.countryName?.takeUnless { it == "Unknown" }.orEmpty()
            }
            if (countryCode.isBlank()) countryCode = p.countryCode.orEmpty()
            if (cityName.isBlank()) cityName = p.cityName.orEmpty()
            if (bio.isBlank()) bio = p.bio.orEmpty()
            if (avatarUrl.isNullOrBlank()) avatarUrl = p.avatarUrl
        }
    }

    suspend fun ensureCountries() {
        if (countries.isNotEmpty()) return
        countries = runCatching { profileService.countries() }.getOrDefault(emptyList())
    }

    fun detectLocation() {
        scope.launch {
            detectingLocation = true
            locationStatus = ""
            localError = null
            try {
                val locationService = LocationService.get(context)
                val coord = locationService.currentCoordinate()
                if (coord == null) {
                    locationStatus =
                        "Location unavailable. Pick your country below, or enable Location and try again."
                    showCountryPicker = true
                    ensureCountries()
                    return@launch
                }
                val detected = profileService.detectLocation(coord.first, coord.second)
                countryName = detected.countryName
                countryCode = detected.countryCode
                cityName = detected.cityName.orEmpty()
                locationStatus = "Detected: ${detected.countryName}"
                showCountryPicker = false
            } catch (e: Exception) {
                locationStatus =
                    e.message?.takeIf { it.isNotBlank() }
                        ?: "Could not detect location. Pick your country below."
                showCountryPicker = true
                ensureCountries()
            } finally {
                detectingLocation = false
            }
        }
    }

    // If a previous detection is still spinning after 12s (emulator hang), free the UI.
    LaunchedEffect(detectingLocation) {
        if (!detectingLocation) return@LaunchedEffect
        kotlinx.coroutines.delay(12_000)
        if (detectingLocation) {
            detectingLocation = false
            if (locationStatus.isBlank() && countryName.isBlank()) {
                locationStatus =
                    "Location unavailable. Pick your country below, or enable Location and try again."
                showCountryPicker = true
                ensureCountries()
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        val ok = grants[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            grants[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (ok) detectLocation()
        else {
            locationStatus =
                "Location unavailable. Pick your country below, or enable Location and try again."
            showCountryPicker = true
            scope.launch { ensureCountries() }
        }
    }

    val photoLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
    ) { uri ->
        if (uri != null) onUploadAvatar(uri)
    }

    // Auto-detect on first open (iOS `.task { await detectLocation() }`).
    LaunchedEffect(Unit) {
        val hasPerm = LocationService.get(context).requestAuthorizationIfNeeded()
        if (hasPerm) {
            detectLocation()
        } else {
            permissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
            )
        }
    }

    val hasDetectedLocation =
        countryName.trim().isNotEmpty() && countryName.trim() != "Unknown"
    val canSave = displayName.trim().isNotEmpty() && hasDetectedLocation && !busy && !detectingLocation
    val shownError = localError ?: error
    val seed = profile?.userId
        ?: AuthService.instance.currentUser?.id
        ?: "me"

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 40.dp),
    ) {
        Text(
            "Profile Setup",
            fontFamily = FontFamily.Serif,
            fontSize = 28.sp,
            color = MatteryaColors.ink,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Tell the world who you are and where you call home.",
            color = MatteryaColors.inkMuted,
            fontSize = 15.sp,
        )
        Spacer(Modifier.height(24.dp))

        // ── Profile photo ──────────────────────────────────────────────
        SectionLabel("Profile photo")
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(vertical = 10.dp),
        ) {
            AvatarView(
                url = avatarUrl,
                seed = seed,
                size = 72.dp,
            )
            Spacer(Modifier.width(16.dp))
            Column {
                TextButton(onClick = { photoLauncher.launch("image/*") }) {
                    Text(
                        if (avatarUrl == null) "Upload photo" else "Change photo",
                        color = MatteryaColors.accentBright,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                Text(
                    "Add a photo so people recognize you on Matterya.",
                    fontSize = 12.sp,
                    color = MatteryaColors.inkMuted,
                )
            }
        }
        HorizontalDivider(color = MatteryaColors.divider, thickness = 0.5.dp)
        Spacer(Modifier.height(16.dp))

        // ── Identity ───────────────────────────────────────────────────
        SectionLabel("Identity")
        Spacer(Modifier.height(10.dp))
        PremiumTextField(
            title = "Display name",
            value = displayName,
            onValueChange = { displayName = it },
            imeAction = ImeAction.Next,
        )
        Spacer(Modifier.height(12.dp))
        PremiumTextField(
            title = "Username",
            value = username,
            onValueChange = { username = it.filter { ch -> !ch.isWhitespace() } },
            keyboardType = KeyboardType.Uri,
            imeAction = ImeAction.Next,
        )
        Spacer(Modifier.height(18.dp))
        HorizontalDivider(color = MatteryaColors.divider, thickness = 0.5.dp)
        Spacer(Modifier.height(16.dp))

        // ── Location (detected, not free-typed — matches iOS) ──────────
        SectionLabel("Location")
        Spacer(Modifier.height(10.dp))
        when {
            detectingLocation -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MatteryaColors.accent,
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        "Detecting your location…",
                        fontSize = 14.sp,
                        color = MatteryaColors.inkMuted,
                    )
                }
            }
            hasDetectedLocation && !showCountryPicker -> {
                LabeledValue("Country", countryName)
                if (cityName.isNotBlank()) {
                    Spacer(Modifier.height(6.dp))
                    LabeledValue("City", cityName)
                }
                Spacer(Modifier.height(6.dp))
                Text(
                    "Location is detected automatically and can’t be edited.",
                    fontSize = 12.sp,
                    color = MatteryaColors.inkMuted,
                )
            }
            else -> {
                Text(
                    locationStatus.ifBlank {
                        "We use your device location for your home country."
                    },
                    fontSize = 13.sp,
                    color = MatteryaColors.inkMuted,
                )
                if (showCountryPicker || !hasDetectedLocation) {
                    Spacer(Modifier.height(10.dp))
                    if (countries.isEmpty()) {
                        Text(
                            "Loading countries…",
                            fontSize = 13.sp,
                            color = MatteryaColors.inkMuted,
                        )
                        LaunchedEffect(showCountryPicker) {
                            ensureCountries()
                        }
                    } else {
                        Text(
                            "Choose your home country",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = MatteryaColors.ink,
                        )
                        Spacer(Modifier.height(8.dp))
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            // Popular first for quick pick on emulator / denied GPS.
                            val popular = listOf(
                                "United States", "United Kingdom", "Germany", "Spain",
                                "France", "Japan", "Canada", "Australia", "Brazil", "India",
                            )
                            val ordered = popular.mapNotNull { n ->
                                countries.find { it.name.equals(n, ignoreCase = true) }
                            } + countries.filter { c ->
                                popular.none { it.equals(c.name, ignoreCase = true) }
                            }
                            ordered.take(40).forEach { c ->
                                val selected = countryCode.equals(c.iso, ignoreCase = true) ||
                                    countryName.equals(c.name, ignoreCase = true)
                                Text(
                                    c.name,
                                    fontSize = 13.sp,
                                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                                    color = if (selected) MatteryaColors.surface else MatteryaColors.ink,
                                    modifier = Modifier
                                        .background(
                                            if (selected) MatteryaColors.ink else MatteryaColors.surfaceMuted,
                                            RoundedCornerShape(percent = 50),
                                        )
                                        .clickable {
                                            countryName = c.name
                                            countryCode = c.iso
                                            cityName = ""
                                            locationStatus = "Selected: ${c.name}"
                                            showCountryPicker = false
                                        }
                                        .padding(horizontal = 12.dp, vertical = 8.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        OutlinedButton(
            onClick = {
                val hasPerm = LocationService.get(context).requestAuthorizationIfNeeded()
                if (hasPerm) detectLocation()
                else {
                    permissionLauncher.launch(
                        arrayOf(
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION,
                        ),
                    )
                }
            },
            enabled = !detectingLocation && !busy,
            shape = RoundedCornerShape(MatteryaDimens.controlRadius),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(if (detectingLocation) "Detecting…" else "Detect location again")
        }
        if (hasDetectedLocation) {
            TextButton(onClick = {
                showCountryPicker = true
                scope.launch { ensureCountries() }
            }) {
                Text("Change country", color = MatteryaColors.accentBright, fontSize = 13.sp)
            }
        }
        Spacer(Modifier.height(18.dp))
        HorizontalDivider(color = MatteryaColors.divider, thickness = 0.5.dp)
        Spacer(Modifier.height(16.dp))

        // ── Bio ────────────────────────────────────────────────────────
        SectionLabel("Bio")
        Spacer(Modifier.height(10.dp))
        PremiumTextField(
            title = "Tell the world about you…",
            value = bio,
            onValueChange = { bio = it },
            imeAction = ImeAction.Done,
        )

        if (shownError != null) {
            Spacer(Modifier.height(14.dp))
            Text(shownError, color = MatteryaColors.danger, fontSize = 13.sp)
        }

        Spacer(Modifier.height(28.dp))
        Button(
            onClick = {
                val name = displayName.trim()
                val country = countryName.trim()
                when {
                    name.isEmpty() -> localError = "Display name is required."
                    country.isEmpty() || country == "Unknown" ->
                        localError = "Location is required. Tap Detect location and allow access."
                    else -> {
                        localError = null
                        onSave(
                            name,
                            username.trim().ifBlank { null },
                            country,
                            countryCode.trim().ifBlank { null },
                            cityName.trim().ifBlank { null },
                            bio.trim().ifBlank { null },
                            avatarUrl,
                        )
                    }
                }
            },
            enabled = canSave,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            shape = RoundedCornerShape(MatteryaDimens.controlRadius),
            colors = ButtonDefaults.buttonColors(containerColor = MatteryaColors.accent),
        ) {
            if (busy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = MatteryaColors.surface,
                )
            } else {
                Text("Complete Setup", fontWeight = FontWeight.SemiBold)
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text.uppercase(),
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = MatteryaColors.inkMuted,
        letterSpacing = 0.8.sp,
    )
}

@Composable
private fun LabeledValue(label: String, value: String) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, fontSize = 14.sp, color = MatteryaColors.inkMuted)
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
    }
}

/** Back-compat 2-arg signature used by older call sites. */
@Composable
fun ProfileSetupView(
    busy: Boolean,
    error: String?,
    onContinue: (displayName: String, country: String) -> Unit,
) {
    ProfileSetupView(
        profile = null,
        busy = busy,
        error = error,
        onSave = { displayName, _, countryName, _, _, _, _ ->
            onContinue(displayName, countryName)
        },
    )
}
