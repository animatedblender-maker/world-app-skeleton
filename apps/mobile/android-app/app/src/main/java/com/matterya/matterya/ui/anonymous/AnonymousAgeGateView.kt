package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

enum class AnonymousAgeGateMode { Under18, Attest, MissingBirthdate }

@Composable
fun AnonymousAgeGateView(
    mode: AnonymousAgeGateMode,
    store: AnonymousStore,
) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    val title = when (mode) {
        AnonymousAgeGateMode.Under18 -> MatteryaCopy.anonymousUnder18Title
        AnonymousAgeGateMode.MissingBirthdate -> MatteryaCopy.anonymousMissingBirthdateTitle
        AnonymousAgeGateMode.Attest -> MatteryaCopy.anonymousAttestTitle
    }
    val body = when (mode) {
        AnonymousAgeGateMode.Under18 -> MatteryaCopy.anonymousUnder18Body
        AnonymousAgeGateMode.MissingBirthdate -> MatteryaCopy.anonymousMissingBirthdateBody
        AnonymousAgeGateMode.Attest -> MatteryaCopy.anonymousAttestBody
    }
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(MatteryaDimens.pagePadding)
            .padding(top = 24.dp),
    ) {
        Icon(
            if (mode == AnonymousAgeGateMode.Attest) Icons.Default.VerifiedUser else Icons.Default.Shield,
            contentDescription = null,
            tint = MatteryaColors.inkMuted,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )
        Spacer(Modifier.height(20.dp))
        Text(title, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, color = MatteryaColors.ink)
        Spacer(Modifier.height(12.dp))
        Text(body, color = MatteryaColors.inkSecondary, fontSize = 15.sp)
        Spacer(Modifier.height(16.dp))
        AnonymousPrivacyCard()
        Spacer(Modifier.height(20.dp))
        if (mode == AnonymousAgeGateMode.Attest) {
            Button(
                onClick = { scope.launch { store.attest() } },
                enabled = !state.isAttesting,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MatteryaColors.accent),
            ) {
                Text(if (state.isAttesting) "Confirming…" else "I confirm I am 18 or older")
            }
            Spacer(Modifier.height(8.dp))
            Text(MatteryaCopy.anonymousAttestFinePrint, color = MatteryaColors.inkMuted, fontSize = 12.sp)
        } else {
            Text(MatteryaCopy.anonymousAgeGateHint, color = MatteryaColors.inkMuted, fontSize = 12.sp)
        }
    }
}
