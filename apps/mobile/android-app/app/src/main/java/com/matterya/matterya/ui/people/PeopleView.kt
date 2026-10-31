package com.matterya.matterya.ui.people

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.matterya.matterya.model.Profile
import com.matterya.matterya.theme.MatteryaColors
import com.matterya.matterya.ui.components.AvatarView
import com.matterya.matterya.ui.components.FollowButton

/** iOS `PeopleView` — list rows with avatar, @user · country, Follow chip, Load more. */
@Composable
fun PeopleView(
    people: List<Profile> = emptyList(),
    isLoading: Boolean = false,
    loadingMore: Boolean = false,
    hasMore: Boolean = false,
    errorMessage: String? = null,
    currentUserId: String? = null,
    isFollowing: (String) -> Boolean = { false },
    onOpenProfile: (Profile) -> Unit = {},
    onFollow: (Profile) -> Unit = {},
    onFollowToggle: (suspend (String) -> Unit)? = null,
    onLoadMore: () -> Unit = {},
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MatteryaColors.canvas),
    ) {
        Text(
            "People",
            fontWeight = FontWeight.SemiBold,
            fontSize = 17.sp,
            color = MatteryaColors.ink,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        )
        when {
            isLoading && people.isEmpty() -> {
                CircularProgressIndicator(
                    Modifier
                        .padding(40.dp)
                        .align(Alignment.CenterHorizontally),
                    color = MatteryaColors.accentBright,
                )
                Text(
                    "Loading people…",
                    color = MatteryaColors.inkMuted,
                    fontSize = 14.sp,
                    modifier = Modifier.align(Alignment.CenterHorizontally),
                )
            }
            errorMessage != null && people.isEmpty() -> {
                EmptyBlock(
                    title = "People unavailable",
                    subtitle = errorMessage,
                )
            }
            people.isEmpty() -> {
                EmptyBlock(
                    title = "No people yet",
                    subtitle = "Check back soon for new members.",
                )
            }
            else -> {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(people, key = { it.userId }) { person ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .background(MatteryaColors.surface)
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Row(
                                Modifier
                                    .weight(1f)
                                    .clickable { onOpenProfile(person) },
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                AvatarView(url = person.avatarUrl, seed = person.userId, size = 44.dp)
                                Spacer(Modifier.width(12.dp))
                                Column {
                                    Text(
                                        person.displayName ?: person.username ?: "Member",
                                        fontWeight = FontWeight.SemiBold,
                                        fontSize = 14.sp,
                                        color = MatteryaColors.ink,
                                    )
                                    Text(
                                        "@${person.username ?: "user"} · ${person.countryName.orEmpty()}",
                                        fontSize = 12.sp,
                                        color = MatteryaColors.inkMuted,
                                    )
                                }
                            }
                            if (person.userId != currentUserId && !person.isDemoUser) {
                                FollowButton(
                                    userId = person.userId,
                                    isFollowing = isFollowing(person.userId),
                                    isSelf = false,
                                    onToggle = {
                                        if (onFollowToggle != null) {
                                            onFollowToggle(person.userId)
                                        } else {
                                            onFollow(person)
                                        }
                                    },
                                )
                            }
                        }
                        HorizontalDivider(thickness = 0.5.dp, color = MatteryaColors.divider)
                    }
                    if (hasMore) {
                        item {
                            TextButton(
                                onClick = onLoadMore,
                                enabled = !loadingMore,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                            ) {
                                Text(
                                    if (loadingMore) "Loading…" else "Load more",
                                    color = MatteryaColors.accentBright,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyBlock(title: String, subtitle: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, fontWeight = FontWeight.SemiBold, color = MatteryaColors.ink)
        Spacer(Modifier.padding(top = 8.dp))
        Text(subtitle, color = MatteryaColors.inkMuted, fontSize = 14.sp)
    }
}
