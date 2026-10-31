package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.AnonymousSpaceFilter
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore

@Composable
fun AnonymousMeView(store: AnonymousStore) {
    val state by store.state.collectAsState()
    var toast by remember { mutableStateOf<String?>(null) }
    val joined = state.spacesByFilter[AnonymousSpaceFilter.Joined].orEmpty()
    val blockedCount = state.blockedProfileIds.size

    LaunchedEffect(Unit) {
        store.loadSpaces(AnonymousSpaceFilter.Joined, force = false)
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas)
            .verticalScroll(rememberScrollState())
            .padding(MatteryaDimens.pagePadding)
            .padding(bottom = 28.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
                .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
                .padding(16.dp),
        ) {
            Text(
                "Masquerade identity",
                fontWeight = FontWeight.SemiBold,
                fontSize = 12.sp,
                color = MatteryaColors.inkMuted,
            )
            Spacer(Modifier.height(10.dp))
            Text(
                "@${state.displayUsername.ifBlank { "…" }}",
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Normal,
                fontSize = 28.sp,
                color = MatteryaColors.ink,
                modifier = Modifier.clickable(enabled = state.displayUsername.isNotBlank()) {
                    store.pushProfile(state.displayUsername)
                },
            )
            Spacer(Modifier.height(10.dp))
            Text(MatteryaCopy.anonymousMeHint, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
        }

        Spacer(Modifier.height(22.dp))
        SectionLabel("Spaces")
        Spacer(Modifier.height(10.dp))
        if (joined.isEmpty()) {
            Text(
                MatteryaCopy.anonymousNoJoinedSpacesBody,
                color = MatteryaColors.inkMuted,
                fontSize = 14.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MatteryaColors.surface, RoundedCornerShape(14.dp))
                    .border(0.5.dp, MatteryaColors.border.copy(alpha = 0.85f), RoundedCornerShape(14.dp))
                    .padding(14.dp),
            )
        } else {
            joined.take(12).forEach { space ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(bottom = 8.dp)
                        .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
                        .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
                        .clickable { store.pushSpace(space.slug) }
                        .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(space.title, fontWeight = FontWeight.Medium, color = MatteryaColors.ink)
                        Text(
                            "${space.memberCount ?: 0} members · ${space.postCount ?: 0} posts",
                            color = MatteryaColors.inkMuted,
                            fontSize = 12.sp,
                        )
                    }
                    if (space.isPaid) {
                        Text(
                            "Paid",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = MatteryaColors.ink,
                            modifier = Modifier
                                .background(MatteryaColors.matteDeep, RoundedCornerShape(50))
                                .padding(horizontal = 7.dp, vertical = 3.dp),
                        )
                    }
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = MatteryaColors.inkMuted,
                    )
                }
            }
        }

        Spacer(Modifier.height(22.dp))
        SectionLabel("Safety")
        Spacer(Modifier.height(10.dp))
        SettingsCard(
            title = "Blocked profiles",
            subtitle = if (blockedCount == 0) {
                "No blocked Anonymous profiles"
            } else {
                "$blockedCount blocked"
            },
        )
        Spacer(Modifier.height(8.dp))
        SettingsCard(
            title = "Username",
            subtitle = "Immutable. Exceptional renames are handled by trust & safety only.",
        )

        Spacer(Modifier.height(22.dp))
        SectionLabel("Data")
        Spacer(Modifier.height(10.dp))
        SettingsCard(
            title = "Request data export",
            subtitle = null,
            onClick = { toast = MatteryaCopy.anonymousExportPlaceholder },
        )
        Spacer(Modifier.height(8.dp))
        SettingsCard(
            title = "Request Anonymous deletion",
            subtitle = null,
            destructive = true,
            onClick = { toast = MatteryaCopy.anonymousDeletePlaceholder },
        )

        Spacer(Modifier.height(16.dp))
        Text(
            MatteryaCopy.anonymousPrivacyBoundary,
            color = MatteryaColors.inkMuted,
            fontSize = 12.sp,
            modifier = Modifier.padding(horizontal = 4.dp),
        )

        toast?.let { msg ->
            Spacer(Modifier.height(12.dp))
            Text(msg, color = MatteryaColors.inkSecondary, fontSize = 13.sp)
        }
    }
}

@Composable
private fun SectionLabel(title: String) {
    Text(
        title.uppercase(),
        fontWeight = FontWeight.SemiBold,
        fontSize = 12.sp,
        color = MatteryaColors.inkMuted,
    )
}

@Composable
private fun SettingsCard(
    title: String,
    subtitle: String?,
    destructive: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(14.dp),
    ) {
        Text(
            title,
            fontWeight = FontWeight.Medium,
            color = if (destructive) MatteryaColors.danger else MatteryaColors.ink,
        )
        if (!subtitle.isNullOrBlank()) {
            Spacer(Modifier.height(4.dp))
            Text(subtitle, color = MatteryaColors.inkMuted, fontSize = 12.sp)
        }
    }
}
