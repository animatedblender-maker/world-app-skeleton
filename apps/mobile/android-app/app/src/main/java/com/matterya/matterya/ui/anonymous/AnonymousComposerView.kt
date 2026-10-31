package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@Composable
fun AnonymousComposerView(
    store: AnonymousStore,
    spaceId: String,
    spaceTitle: String,
    onBack: () -> Unit,
    onPublished: () -> Unit,
) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().background(MatteryaColors.paper)) {
        MasqueradePushChrome(
            title = "New post",
            onBack = onBack,
            trailing = {
                Button(
                    onClick = {
                        scope.launch {
                            busy = true
                            val post = store.publishPost(spaceId)
                            busy = false
                            if (post != null) onPublished()
                        }
                    },
                    enabled = !busy && (state.composerBody.isNotBlank() || state.composerTitle.isNotBlank()),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MatteryaColors.ink,
                        contentColor = MatteryaColors.paper,
                    ),
                ) {
                    Text(if (busy) "…" else "Post")
                }
            },
        )
        Text(
            spaceTitle,
            color = MatteryaColors.inkMuted,
            fontSize = 12.sp,
            modifier = Modifier.padding(horizontal = MatteryaDimens.pagePadding, vertical = 4.dp),
        )
        Column(Modifier.padding(MatteryaDimens.pagePadding)) {
            Text(MatteryaCopy.anonymousComposerPrivacyNudge, color = MatteryaColors.inkMuted, fontSize = 12.sp)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = state.composerTitle,
                onValueChange = { store.setComposerTitle(it) },
                label = { Text("Title (optional)") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = state.composerBody,
                onValueChange = { store.setComposerBody(it) },
                label = { Text("Body") },
                modifier = Modifier.fillMaxWidth().height(200.dp),
            )
        }
    }
}
