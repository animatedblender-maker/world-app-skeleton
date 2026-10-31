package com.matterya.matterya.ui.letters

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens

data class LetterThreadItem(
    val id: String,
    val peerName: String,
    val preview: String = "",
    val destinationCountry: String = "",
    val isInFlight: Boolean = false,
    val isPenFriend: Boolean = false,
)

/** iOS `LettersStripView` — feed strip replacing Moments. */
@Composable
fun LettersStripView(
    remainingToday: Int = 5,
    inFlight: List<LetterThreadItem> = emptyList(),
    penFriends: List<LetterThreadItem> = emptyList(),
    onWrite: () -> Unit = {},
    onInbox: () -> Unit = {},
    onOpenThread: (LetterThreadItem) -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(
                Brush.verticalGradient(
                    listOf(MatteryaColors.oceanWash.copy(alpha = 0.10f), Color.Transparent),
                ),
            )
            .padding(vertical = 8.dp),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Mail, null, tint = MatteryaColors.oceanWash, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                "Letters",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.inkMuted,
                letterSpacing = 0.6.sp,
            )
            Spacer(Modifier.weight(1f))
            Text(
                "$remainingToday/5 left",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (remainingToday == 0) MatteryaColors.inkMuted else MatteryaColors.accentBright,
                modifier = Modifier
                    .background(MatteryaColors.surface, RoundedCornerShape(50))
                    .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(50))
                    .padding(horizontal = 8.dp, vertical = 3.dp),
            )
        }
        Spacer(Modifier.height(10.dp))
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            LetterChipCard(
                label = "New letter",
                icon = Icons.Default.Edit,
                subtitle = if (remainingToday > 0) "Write" else "Full",
                dimmed = remainingToday == 0,
                onClick = onWrite,
            )
            LetterChipCard(
                label = "Inbox",
                icon = Icons.Default.MailOutline,
                subtitle = "Open",
                onClick = onInbox,
            )
            inFlight.take(6).forEach { t ->
                LetterChipCard(
                    label = t.destinationCountry.ifEmpty { t.peerName },
                    icon = Icons.Default.Mail,
                    subtitle = "In flight",
                    onClick = { onOpenThread(t) },
                )
            }
            penFriends.take(4).forEach { t ->
                LetterChipCard(
                    label = t.peerName,
                    icon = Icons.Default.MailOutline,
                    subtitle = "Pen friend",
                    onClick = { onOpenThread(t) },
                )
            }
        }
    }
}

@Composable
private fun LetterChipCard(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    subtitle: String,
    dimmed: Boolean = false,
    onClick: () -> Unit,
) {
    Column(
        Modifier
            .clickable(onClick = onClick)
            .then(if (dimmed) Modifier else Modifier),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(92.dp)
                .background(
                    Brush.linearGradient(
                        listOf(
                            Color(0.96f, 0.93f, 0.88f),
                            Color(0.90f, 0.86f, 0.78f),
                        ),
                    ),
                    RoundedCornerShape(14.dp),
                )
                .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(14.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(icon, null, tint = MatteryaColors.accent)
                Spacer(Modifier.height(6.dp))
                Text(subtitle, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = MatteryaColors.inkSecondary)
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = MatteryaColors.inkSecondary, maxLines = 1)
    }
}

/** Letters inbox / compose host screens. */
@Composable
fun LettersInboxView(
    threads: List<LetterThreadItem> = emptyList(),
    remainingToday: Int = 5,
    onBack: () -> Unit = {},
    onWrite: () -> Unit = {},
    onOpenThread: (LetterThreadItem) -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = MatteryaColors.ink)
            }
            Text("Letters", fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onWrite, enabled = remainingToday > 0) {
                Text("Write", color = MatteryaColors.accent)
            }
        }
        if (threads.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No letters yet. Write one across the world.", color = MatteryaColors.inkMuted)
            }
        } else {
            LazyColumn {
                items(threads, key = { it.id }) { t ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onOpenThread(t) }
                            .padding(16.dp),
                    ) {
                        Icon(Icons.Default.Mail, null, tint = MatteryaColors.accentBright)
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text(t.peerName, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                            Text(t.preview, fontSize = 13.sp, color = MatteryaColors.inkMuted, maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun LetterComposeView(
    remainingToday: Int = 5,
    onCancel: () -> Unit = {},
    onSend: (body: String, destinationCountry: String) -> Unit = { _, _ -> },
) {
    var body by remember { mutableStateOf("") }
    var destination by remember { mutableStateOf("") }
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper)
            .padding(MatteryaDimens.pagePadding),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onCancel) { Text("Cancel", color = MatteryaColors.inkSecondary) }
            Spacer(Modifier.weight(1f))
            Text("Write a letter", fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            TextButton(
                onClick = { onSend(body.trim(), destination.trim()) },
                enabled = body.isNotBlank() && remainingToday > 0,
            ) {
                Text("Send", color = MatteryaColors.accent)
            }
        }
        Spacer(Modifier.height(12.dp))
        Text("$remainingToday of 5 letters left today", fontSize = 12.sp, color = MatteryaColors.inkMuted)
        Spacer(Modifier.height(12.dp))
        TextField(
            value = destination,
            onValueChange = { destination = it },
            placeholder = { Text("Destination country (optional)") },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(12.dp))
        TextField(
            value = body,
            onValueChange = { body = it },
            placeholder = { Text("Dear stranger…") },
            modifier = Modifier
                .fillMaxWidth()
                .height(220.dp),
        )
    }
}
