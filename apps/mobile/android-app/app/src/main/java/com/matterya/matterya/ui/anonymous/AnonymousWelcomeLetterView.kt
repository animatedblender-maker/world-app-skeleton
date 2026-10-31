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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.theme.MatteryaCopy
import com.matterya.matterya.theme.MatteryaDimens
import com.matterya.matterya.viewmodel.AnonymousStore

@Composable
fun AnonymousWelcomeLetterView(store: AnonymousStore) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(MatteryaDimens.pagePadding)
            .padding(top = 24.dp),
    ) {
        Text(
            MatteryaCopy.anonymousWelcomeLetterTitle,
            fontFamily = FontFamily.Serif,
            fontWeight = FontWeight.SemiBold,
            fontSize = 24.sp,
            color = MatteryaColors.ink,
        )
        Spacer(Modifier.height(16.dp))
        Text(
            MatteryaCopy.anonymousWelcomeLetterBody,
            color = MatteryaColors.inkSecondary,
            fontSize = 15.sp,
            lineHeight = 22.sp,
        )
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = { store.completeWelcomeLetter() },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = MatteryaColors.accent),
        ) {
            Text("Continue")
        }
    }
}
