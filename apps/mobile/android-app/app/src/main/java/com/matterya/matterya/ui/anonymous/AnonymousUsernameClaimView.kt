package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
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
    LaunchedEffect(Unit) {
        if (state.suggestedUsername.isBlank()) store.regenerateUsername()
    }
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(MatteryaDimens.pagePadding)
            .padding(top = 24.dp),
    ) {
        Text(MatteryaCopy.anonymousClaimTitle, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, color = MatteryaColors.ink)
        Spacer(Modifier.height(12.dp))
        Text(MatteryaCopy.anonymousClaimBody, color = MatteryaColors.inkSecondary, fontSize = 15.sp)
        Spacer(Modifier.height(24.dp))
        Text(
            "@${state.suggestedUsername.ifBlank { "…" }}",
            fontWeight = FontWeight.Bold,
            fontSize = 28.sp,
            color = MatteryaColors.ink,
        )
        Spacer(Modifier.height(8.dp))
        Text(MatteryaCopy.anonymousClaimIrreversible, color = MatteryaColors.inkMuted, fontSize = 13.sp)
        Spacer(Modifier.height(4.dp))
        Text(MatteryaCopy.anonymousClaimGeneratedOnly, color = MatteryaColors.inkMuted, fontSize = 13.sp)
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = { scope.launch { store.claimUsername() } },
            enabled = !state.isClaimingUsername && state.suggestedUsername.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = MatteryaColors.accent),
        ) {
            Text(if (state.isClaimingUsername) "Claiming…" else "Claim this name")
        }
        Spacer(Modifier.height(8.dp))
        OutlinedButton(
            onClick = { scope.launch { store.regenerateUsername() } },
            enabled = !state.isClaimingUsername,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Suggest another", color = MatteryaColors.ink)
        }
        Spacer(Modifier.height(16.dp))
        AnonymousPrivacyCard()
    }
}
