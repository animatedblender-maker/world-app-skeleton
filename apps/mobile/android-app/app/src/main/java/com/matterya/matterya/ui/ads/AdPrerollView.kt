package com.matterya.matterya.ui.ads

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.AdSlot
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.ui.components.VideoPlayerView
import kotlinx.coroutines.delay

/**
 * iOS `AdPrerollView` — sponsored preroll with skip countdown.
 * When no ad slot is provided, completes immediately (graceful no-fill).
 */
@Composable
fun AdPrerollView(
    placement: String,
    countryCode: String? = null,
    contentCountryCode: String? = null,
    postId: String? = null,
    adSlot: AdSlot? = null,
    onComplete: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var isLoading by remember { mutableStateOf(adSlot == null) }
    var skipReady by remember { mutableStateOf(false) }
    var skipSecondsLeft by remember { mutableIntStateOf(adSlot?.skipAfterSeconds ?: 5) }
    val uriHandler = LocalUriHandler.current

    LaunchedEffect(placement, adSlot) {
        if (adSlot == null) {
            // No fill — don't block content
            delay(200)
            onComplete()
            return@LaunchedEffect
        }
        isLoading = false
        skipSecondsLeft = adSlot.skipAfterSeconds.coerceAtLeast(0)
        while (skipSecondsLeft > 0) {
            delay(1000)
            skipSecondsLeft -= 1
        }
        skipReady = true
    }

    Box(
        modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        when {
            isLoading -> {
                CircularProgressIndicator(
                    Modifier.align(Alignment.Center),
                    color = Color.White,
                )
            }
            adSlot != null -> {
                VideoPlayerView(
                    url = adSlot.creative.mediaUrl,
                    adsEnabled = false,
                    isActive = true,
                    loops = false,
                    showsControls = false,
                    fillsFrame = true,
                    modifier = Modifier.fillMaxSize(),
                    onViewed = { /* impression logged by service */ },
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                listOf(
                                    Color.Black.copy(alpha = 0.35f),
                                    Color.Transparent,
                                    Color.Black.copy(alpha = 0.55f),
                                ),
                            ),
                        ),
                )
                Column(Modifier.fillMaxSize()) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "Sponsored",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            modifier = Modifier
                                .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(50))
                                .padding(horizontal = 12.dp, vertical = 6.dp),
                        )
                        Spacer(Modifier.weight(1f))
                        if (skipReady) {
                            TextButton(onClick = onComplete) {
                                Text(
                                    "Skip",
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White,
                                    modifier = Modifier
                                        .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(50))
                                        .padding(horizontal = 8.dp, vertical = 2.dp),
                                )
                            }
                        } else if (skipSecondsLeft > 0) {
                            Text(
                                "Skip in ${skipSecondsLeft}s",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White.copy(alpha = 0.9f),
                                modifier = Modifier
                                    .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(50))
                                    .padding(horizontal = 12.dp, vertical = 6.dp),
                            )
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(20.dp)
                            .padding(bottom = 28.dp),
                    ) {
                        adSlot.creative.title?.takeIf { it.isNotEmpty() }?.let {
                            Text(it, fontWeight = FontWeight.Bold, color = Color.White, fontSize = 18.sp)
                            Spacer(Modifier.height(6.dp))
                        }
                        adSlot.creative.body?.takeIf { it.isNotEmpty() }?.let {
                            Text(it, color = Color.White.copy(alpha = 0.92f), fontSize = 14.sp, maxLines = 3)
                            Spacer(Modifier.height(10.dp))
                        }
                        adSlot.creative.clickUrl?.takeIf { it.isNotEmpty() }?.let { url ->
                            TextButton(
                                onClick = {
                                    runCatching { uriHandler.openUri(url) }
                                },
                                modifier = Modifier
                                    .background(MatteryaColors.facebookBlue, RoundedCornerShape(MatteryaDimens.controlRadius)),
                            ) {
                                Text(
                                    adSlot.creative.ctaLabel ?: "Learn more",
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
