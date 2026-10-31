package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.matterya.matterya.model.AnonymousCreateSpaceInput
import com.matterya.matterya.model.AnonymousSpaceAdmission
import com.matterya.matterya.model.AnonymousSpaceVisibility
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore
import kotlinx.coroutines.launch

@Composable
fun AnonymousCreateSpaceView(
    store: AnonymousStore,
    onBack: () -> Unit,
    onCreated: (String) -> Unit,
) {
    var title by remember { mutableStateOf("") }
    var slug by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(Modifier.fillMaxSize().background(MatteryaColors.paper)) {
        Row(
            Modifier.fillMaxWidth().background(MatteryaColors.surface).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = MatteryaColors.ink)
            }
            Text(MatteryaCopy.anonymousCreateSpace, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        }
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(MatteryaDimens.pagePadding),
        ) {
            OutlinedTextField(
                value = title,
                onValueChange = { next ->
                    val previousSlug = slugify(title)
                    title = next
                    if (slug.isBlank() || slug == previousSlug) {
                        slug = slugify(next)
                    }
                },
                label = { Text("Title") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = slug,
                onValueChange = { slug = slugify(it) },
                label = { Text("Slug") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text("Description") },
                modifier = Modifier.fillMaxWidth().height(120.dp),
            )
            Spacer(Modifier.height(8.dp))
            Text(MatteryaCopy.anonymousPaidComingSoonBody, color = MatteryaColors.inkMuted)
            Spacer(Modifier.height(20.dp))
            Button(
                onClick = {
                    scope.launch {
                        busy = true
                        val created = store.createSpace(
                            AnonymousCreateSpaceInput(
                                slug = slug.trim(),
                                title = title.trim(),
                                description = description.trim(),
                                visibility = AnonymousSpaceVisibility.AdultPublic.rawValue,
                                admission = AnonymousSpaceAdmission.Free.rawValue,
                            ),
                        )
                        busy = false
                        if (created != null) onCreated(created.slug)
                    }
                },
                enabled = !busy && title.isNotBlank() && slug.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MatteryaColors.accent),
            ) {
                Text(if (busy) "Creating…" else "Create free Space")
            }
        }
    }
}

private fun slugify(raw: String): String =
    raw.lowercase()
        .replace(Regex("[^a-z0-9]+"), "-")
        .trim('-')
        .take(48)
