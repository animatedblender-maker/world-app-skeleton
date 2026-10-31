package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.AnonymousSpaceFilter
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@Composable
fun AnonymousSpacesOnboardingView(store: AnonymousStore) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        store.loadSpaces(AnonymousSpaceFilter.ForYou, force = true)
        store.loadSpaces(AnonymousSpaceFilter.Popular, force = true)
    }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(MatteryaDimens.pagePadding).padding(top = 16.dp)) {
            Text(MatteryaCopy.anonymousSpacesOnboardingTitle, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, color = MatteryaColors.ink)
            Spacer(Modifier.height(8.dp))
            Text(MatteryaCopy.anonymousSpacesOnboardingBody, color = MatteryaColors.inkSecondary, fontSize = 14.sp)
        }
        LazyColumn(Modifier.weight(1f)) {
            items(state.spacesOnboardingCandidates, key = { it.id }) { space ->
                AnonymousSpaceRow(
                    space = space,
                    joined = store.isJoined(space),
                    busy = store.isMembershipBusy(space.id),
                    onOpen = { store.pushSpace(space.slug) },
                    onToggleJoin = {
                        scope.launch {
                            if (store.isJoined(space)) {
                                // Onboarding only joins; leave is rare here.
                            } else {
                                store.joinSpace(space)
                            }
                        }
                    },
                )
            }
        }
        Column(Modifier.padding(MatteryaDimens.pagePadding)) {
            Button(
                onClick = { store.completeSpacesOnboarding() },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MatteryaColors.accent),
            ) { Text("Enter Masquerade") }
            TextButton(onClick = { store.completeSpacesOnboarding() }, modifier = Modifier.fillMaxWidth()) {
                Text("Skip for now", color = MatteryaColors.inkMuted)
            }
        }
    }
}
