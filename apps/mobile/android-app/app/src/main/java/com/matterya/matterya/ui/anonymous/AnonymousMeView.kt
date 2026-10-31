package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore

@Composable
fun AnonymousMeView(store: AnonymousStore) {
    val state by store.state.collectAsState()
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas)
            .verticalScroll(rememberScrollState())
            .padding(MatteryaDimens.pagePadding),
    ) {
        Text("Your mask", fontWeight = FontWeight.SemiBold, fontSize = 13.sp, color = MatteryaColors.inkMuted)
        Spacer(Modifier.height(8.dp))
        Text(
            "@${state.displayUsername.ifBlank { "…" }}",
            fontWeight = FontWeight.Bold,
            fontSize = 28.sp,
            color = MatteryaColors.ink,
        )
        Spacer(Modifier.height(12.dp))
        Text(MatteryaCopy.anonymousMeHint, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
        Spacer(Modifier.height(16.dp))
        AnonymousPrivacyCard()
        Spacer(Modifier.height(24.dp))
        TextButton(onClick = { /* placeholder */ }, modifier = Modifier.fillMaxWidth()) {
            Text(MatteryaCopy.anonymousExportPlaceholder, color = MatteryaColors.inkMuted)
        }
        TextButton(onClick = { /* placeholder */ }, modifier = Modifier.fillMaxWidth()) {
            Text(MatteryaCopy.anonymousDeletePlaceholder, color = MatteryaColors.danger)
        }
    }
}
