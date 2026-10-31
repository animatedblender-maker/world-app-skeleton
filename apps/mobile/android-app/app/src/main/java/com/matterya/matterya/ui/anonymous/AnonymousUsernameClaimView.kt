package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@Composable
fun AnonymousUsernameClaimView(store: AnonymousStore) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    var showConfirm by remember { mutableStateOf(false) }
    val suggested = state.suggestedUsername

    LaunchedEffect(Unit) {
        if (suggested.isBlank()) store.regenerateUsername()
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(MatteryaDimens.pagePadding)
            .padding(top = 24.dp),
    ) {
        Text(
            MatteryaCopy.anonymousClaimTitle,
            fontWeight = FontWeight.SemiBold,
            fontSize = 22.sp,
            color = MatteryaColors.ink,
        )
        Spacer(Modifier.height(12.dp))
        Text(MatteryaCopy.anonymousClaimBody, color = MatteryaColors.inkSecondary, fontSize = 15.sp)
        Spacer(Modifier.height(20.dp))

        Text(
            "Suggested username",
            fontWeight = FontWeight.SemiBold,
            fontSize = 12.sp,
            color = MatteryaColors.inkMuted,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            suggested.ifBlank { "…" },
            fontFamily = FontFamily.Serif,
            fontWeight = FontWeight.Normal,
            fontSize = 26.sp,
            color = MatteryaColors.ink,
            modifier = Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
                .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
                .padding(16.dp),
        )
        Spacer(Modifier.height(10.dp))
        OutlinedButton(
            onClick = { scope.launch { store.regenerateUsername() } },
            enabled = !state.isClaimingUsername,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Regenerate", color = MatteryaColors.ink)
        }

        Spacer(Modifier.height(16.dp))
        Column(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.matteDeep.copy(alpha = 0.65f), RoundedCornerShape(MatteryaDimens.cardRadius))
                .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
                .padding(16.dp),
        ) {
            Text(
                MatteryaCopy.anonymousClaimIrreversible,
                fontWeight = FontWeight.Medium,
                color = MatteryaColors.ink,
                fontSize = 14.sp,
            )
            Spacer(Modifier.height(8.dp))
            Text(MatteryaCopy.anonymousPrivacyBoundary, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
        }

        Spacer(Modifier.height(20.dp))
        Button(
            onClick = { showConfirm = true },
            enabled = !state.isClaimingUsername && suggested.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = MatteryaColors.ink,
                contentColor = MatteryaColors.paper,
            ),
        ) {
            Text(if (state.isClaimingUsername) "Claiming…" else "Confirm username")
        }
        Spacer(Modifier.height(8.dp))
        Text(MatteryaCopy.anonymousClaimGeneratedOnly, color = MatteryaColors.inkMuted, fontSize = 12.sp)
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("Use $suggested?", color = MatteryaColors.ink) },
            text = { Text(MatteryaCopy.anonymousClaimIrreversible, color = MatteryaColors.inkSecondary) },
            confirmButton = {
                TextButton(onClick = {
                    showConfirm = false
                    scope.launch { store.claimUsername() }
                }) {
                    Text("Confirm — can’t change later", color = MatteryaColors.ink)
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) {
                    Text("Cancel", color = MatteryaColors.inkMuted)
                }
            },
            containerColor = MatteryaColors.surface,
        )
    }
}
