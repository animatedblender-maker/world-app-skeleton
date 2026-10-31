package com.matterya.matterya.ui.ads

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.AdCampaign
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens

/** iOS `AdsView` — campaign list + create entry points. */
@Composable
fun AdsView(
    campaigns: List<AdCampaign> = emptyList(),
    isLoading: Boolean = false,
    errorMessage: String? = null,
    onBack: () -> Unit = {},
    onCreate: () -> Unit = {},
    onOpenCampaign: (AdCampaign) -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.paper),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(MatteryaColors.surface)
                .padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = MatteryaColors.ink)
            }
            Spacer(Modifier.weight(1f))
            Text("Ads Manager", fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onCreate) {
                Icon(Icons.Default.Add, contentDescription = "Create", tint = MatteryaColors.ink)
            }
        }

        when {
            isLoading && campaigns.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MatteryaColors.accent)
                }
            }
            errorMessage != null && campaigns.isEmpty() -> {
                Text(errorMessage, color = MatteryaColors.danger, modifier = Modifier.padding(24.dp))
            }
            campaigns.isEmpty() -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        Icons.Default.Campaign,
                        contentDescription = null,
                        tint = MatteryaColors.accentBright,
                        modifier = Modifier.size(48.dp),
                    )
                    Spacer(Modifier.height(16.dp))
                    Text("No campaigns yet", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Create a campaign to run preroll ads across Matterya Hubs and Sparks.",
                        color = MatteryaColors.inkMuted,
                        fontSize = 14.sp,
                    )
                    Spacer(Modifier.height(20.dp))
                    TextButton(
                        onClick = onCreate,
                        modifier = Modifier
                            .background(MatteryaColors.ink, RoundedCornerShape(MatteryaDimens.controlRadius))
                            .padding(horizontal = 8.dp),
                    ) {
                        Text("Create campaign", color = MatteryaColors.paper, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            else -> {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(campaigns, key = { it.id }) { campaign ->
                        CampaignRow(campaign) { onOpenCampaign(campaign) }
                    }
                }
            }
        }
    }
}

@Composable
private fun CampaignRow(campaign: AdCampaign, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = MatteryaDimens.pagePadding, vertical = 8.dp)
            .background(MatteryaColors.surface, RoundedCornerShape(MatteryaDimens.cardRadius))
            .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(MatteryaDimens.cardRadius))
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                campaign.name.ifBlank { "Untitled campaign" },
                fontWeight = FontWeight.SemiBold,
                color = MatteryaColors.ink,
                modifier = Modifier.weight(1f),
            )
            StatusChip(campaign.status)
        }
        Spacer(Modifier.height(6.dp))
        Text(
            "Placement · ${campaign.placement}",
            fontSize = 12.sp,
            color = MatteryaColors.inkMuted,
        )
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Metric("Impressions", campaign.impressionCount)
            Metric("Clicks", campaign.clickCount)
            Metric("Creatives", campaign.creatives.size)
        }
    }
}

@Composable
private fun StatusChip(status: String) {
    val color = when (status.lowercase()) {
        "active", "running" -> MatteryaColors.success
        "paused" -> MatteryaColors.inkMuted
        else -> MatteryaColors.accent
    }
    Text(
        status.replaceFirstChar { it.uppercase() },
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}

@Composable
private fun Metric(label: String, value: Int) {
    Column {
        Text("$value", fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink, fontSize = 14.sp)
        Text(label, fontSize = 11.sp, color = MatteryaColors.inkMuted)
    }
}
