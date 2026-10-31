package com.matterya.matterya.ui.components

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.theme.MatteryaColors

/**
 * Collapsed body text with See more / See less — mirrors iOS `ExpandableBodyText`.
 *
 * Defaults match iOS: body ~15sp, inkSecondary, 3-line collapse, caption See more/less.
 */
@Composable
fun ExpandableBodyText(
    text: String,
    modifier: Modifier = Modifier,
    collapsedLineLimit: Int = 3,
    fontSize: TextUnit = 15.sp,
    color: Color = MatteryaColors.inkSecondary,
    /** Approximate iOS body lineSpacing 4pt → ~21sp line height at 15sp. */
    lineHeight: TextUnit = 21.sp,
    moreTitle: String = "See more",
    lessTitle: String = "See less",
) {
    var expanded by remember(text) { mutableStateOf(false) }
    var isTruncated by remember(text) { mutableStateOf(false) }

    Column(
        modifier
            .fillMaxWidth()
            .animateContentSize(),
    ) {
        Text(
            text = text,
            color = color,
            fontSize = fontSize,
            lineHeight = lineHeight,
            maxLines = if (expanded) Int.MAX_VALUE else collapsedLineLimit,
            modifier = Modifier.fillMaxWidth(),
            onTextLayout = { layout: TextLayoutResult ->
                if (!expanded) {
                    isTruncated = layout.hasVisualOverflow
                }
            },
        )
        if (isTruncated || expanded) {
            Text(
                text = if (expanded) lessTitle else moreTitle,
                color = MatteryaColors.accentBright,
                fontSize = 12.sp, // caption
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .padding(top = 6.dp)
                    .clickable { expanded = !expanded },
            )
        }
    }
}
