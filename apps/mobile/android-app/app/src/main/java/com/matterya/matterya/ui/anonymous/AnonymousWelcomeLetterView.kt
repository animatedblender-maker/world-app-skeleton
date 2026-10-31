package com.matterya.matterya.ui.anonymous

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore

@Composable
fun AnonymousWelcomeLetterView(store: AnonymousStore) {
    Column(Modifier.fillMaxSize().background(MatteryaColors.canvas)) {
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 28.dp, bottom = 24.dp),
        ) {
            Text(
                MatteryaCopy.anonymousWelcomeLetterTitle,
                fontWeight = FontWeight.SemiBold,
                fontSize = 22.sp,
                color = MatteryaColors.ink,
            )
            Spacer(Modifier.height(16.dp))
            WelcomeLetterBody(MatteryaCopy.anonymousWelcomeLetterBody)
            Spacer(Modifier.height(16.dp))
            Text(
                MatteryaCopy.anonymousWildeQuote,
                fontFamily = FontFamily.Serif,
                fontStyle = FontStyle.Italic,
                color = MatteryaColors.inkSecondary,
                fontSize = 15.sp,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                MatteryaCopy.anonymousWildeAttribution,
                color = MatteryaColors.inkMuted,
                fontSize = 12.sp,
            )
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(MatteryaColors.divider),
        )
        Button(
            onClick = { store.completeWelcomeLetter() },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = MatteryaDimens.pagePadding)
                .padding(top = 12.dp, bottom = 24.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = MatteryaColors.ink,
                contentColor = MatteryaColors.paper,
            ),
        ) {
            Text("Continue")
        }
    }
}

/** Minimal `**bold**` markdown for the Masquerade welcome letter. */
@Composable
private fun WelcomeLetterBody(raw: String) {
    val annotated = buildAnnotatedString {
        var i = 0
        while (i < raw.length) {
            if (raw.startsWith("**", i)) {
                val end = raw.indexOf("**", i + 2)
                if (end >= 0) {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = MatteryaColors.ink)) {
                        append(raw.substring(i + 2, end))
                    }
                    i = end + 2
                    continue
                }
            }
            append(raw[i])
            i++
        }
    }
    Text(
        annotated,
        color = MatteryaColors.inkSecondary,
        fontSize = 15.sp,
        lineHeight = 22.sp,
    )
}
