package com.matterya.matterya.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Matterya design tokens — mirrors iOS `Theme.swift` exactly.
 * Colors use the same RGB fractions as the Swift source.
 */
object MatteryaColors {
    val paper = Color(red = 0.973f, green = 0.965f, blue = 0.949f)
    val canvas = paper
    val canvasMuted = Color(red = 0.949f, green = 0.941f, blue = 0.925f)
    val canvasDeep = Color(red = 0.929f, green = 0.918f, blue = 0.898f)
    val surface = Color(red = 0.996f, green = 0.992f, blue = 0.984f)
    val surfaceMuted = canvasMuted
    val ink = Color(red = 0.173f, green = 0.157f, blue = 0.145f)
    val inkSecondary = Color(red = 0.420f, green = 0.392f, blue = 0.365f)
    val inkMuted = Color(red = 0.580f, green = 0.545f, blue = 0.510f)
    val accent = Color(red = 0.420f, green = 0.345f, blue = 0.255f)
    val accentBright = Color(red = 0.482f, green = 0.388f, blue = 0.278f)
    val accentSoft = accent.copy(alpha = 0.10f)
    val border = Color(red = 0.867f, green = 0.847f, blue = 0.820f)
    val divider = Color(red = 0.886f, green = 0.871f, blue = 0.847f)
    val landFill = Color(red = 0.910f, green = 0.894f, blue = 0.863f)
    val landSelected = Color(red = 0.878f, green = 0.839f, blue = 0.776f)
    val oceanWash = Color(red = 0.820f, green = 0.878f, blue = 0.922f)
    val reelsAccent = accentBright
    val danger = Color(red = 0.918f, green = 0.000f, blue = 0.043f)
    val like = danger
    val commentBubble = Color(red = 0.941f, green = 0.949f, blue = 0.961f)
    val facebookBlue = Color(red = 0.094f, green = 0.467f, blue = 0.949f)
    val iconFill = Color(red = 0.965f, green = 0.953f, blue = 0.937f)
    val success = Color(red = 0.000f, green = 0.690f, blue = 0.314f)
    val buttonMuted = Color(red = 0.941f, green = 0.941f, blue = 0.941f)
    val globeGlass = Color.White.copy(alpha = 0.94f)
    val globeScrimTop = Color.White.copy(alpha = 0.82f)
    val globeScrimBottom = Color.White.copy(alpha = 0.55f)

    val storyRing = Brush.linearGradient(
        colors = listOf(
            Color(red = 0.985f, green = 0.753f, blue = 0.176f),
            Color(red = 0.918f, green = 0.235f, blue = 0.412f),
            Color(red = 0.525f, green = 0.224f, blue = 0.796f),
        ),
    )
}

object MatteryaDimens {
    val cardRadius = 12.dp
    val controlRadius = 8.dp
    val pagePadding = 16.dp
    val feedGutter = 14.dp
    val feedTextInset = 16.dp
    val cardPadding = 12.dp
    val tabBarHeight = 49.dp
}

/** User-facing names for short vertical videos (not "Reels") — iOS `MatteryaCopy`. */
object MatteryaCopy {
    private const val NBSP = "\u00A0"
    private const val hubsBrand = "Matterya${NBSP}Hubs"

    const val sparks = "Sparks"
    const val spark = "Spark"
    const val matteryaSparks = "Matterya${NBSP}Sparks"
    const val sparksForYou = "Sparks for you"
    const val newSpark = "New spark"
    const val newVideo = "New video"
    const val publishSpark = "Publish spark"
    const val publishVideo = "Publish video"
    const val savedSparks = "Saved sparks"
    const val browseSparks = "Browse Sparks"
    const val watchAllSparks = "Watch all"
    const val sparksFromCountry = "Sparks from"
    const val noSparksYet = "No sparks yet"
    const val noSparksForCountry = "No sparks for"
    const val saveSparksHint = "Save sparks while watching or publish your own."
    const val savedSparksSubtitle = "Sparks you bookmarked"
    const val publishSparkHint = "Vertical video works best"
    const val publishVideoHint = "Shows in feed and $hubsBrand"
    const val matteryaHubs = hubsBrand
    const val continueWatching = "Continue watching"
    const val newOnHubs = "New on $hubsBrand"
    const val watchOnHubs = "Watch on $hubsBrand"
    const val publishedOnHubs = "Published on $hubsBrand"
    const val openingHubs = "Opening $hubsBrand…"
    const val loadingHubs = "Loading $hubsBrand…"
    const val hubsUnavailable = "$hubsBrand unavailable"
    const val exploreHubs = "Explore $hubsBrand"
    const val searchHubs = "Search $hubsBrand"
    const val searchHubsHint = "Find videos and creators on $hubsBrand"
    const val moreOnHubs = "More on $hubsBrand"
    const val yourChannelOnHubs = "Your channel on $hubsBrand"
    const val verifiedHubsChannel = "Verified $hubsBrand channel"
    const val longFormOnHubs = "Long-form on $hubsBrand"
    const val sparksOnHubs = "Short vertical video on $hubsBrand"
    const val hubsPublishHint = "Try another category, follow creators, or publish on $hubsBrand."
    const val hubsLoadError = "Couldn't load $hubsBrand right now. Pull to refresh or check your connection."
    const val hubsNoChannelVideos = "This creator hub has no videos on $hubsBrand yet."
    const val hubsVideoUnavailable = "This video isn't available on $hubsBrand."
    const val postToYourFeed = "Post to the main feed"
    const val shareToYourFeed = "Share to the main feed"
    const val browsingForeignFeed = "Browsing another country"
    const val shareFromForeignHint =
        "Tap share on any post to add it to your home feed. You can only write posts in your own country."
    const val homeCountryOnlyPost = "You can only publish in your home country."
    const val follow = "Follow"
    const val following = "Following"
    const val followers = "followers"
    const val creator = "Creator"
    const val creators = "Creators"
    const val viewCreatorHub = "View creator hub"
    const val shareCreatorHub = "Share creator hub"
    const val aboutThisHub = "About this hub"
    const val featuredCreators = "Featured creators"

    // MARK: Masquerade (Anonymous mode)
    private const val masqueradeBrand = "Matterya${NBSP}Masquerade"
    const val anonymous = "Masquerade"
    const val matteryaMasquerade = masqueradeBrand
    const val anonymousModeChip = "Anonymous mode"
    const val anonymousTagline = "Leave your identity outside."
    const val anonymousWildeQuote =
        "“Give him a mask, and he will tell you the truth.”"
    const val anonymousWildeAttribution = "— Oscar Wilde, 1891"
    const val anonymousPrivacyBoundary =
        "Your Masquerade name is public inside Spaces. Other members can’t see your Matterya profile. Matterya may link identities for safety and legal compliance."
    const val anonymousUnder18Title = "Adults only"
    const val anonymousUnder18Body =
        "Masquerade is only available to people 18 and older. No posts, Spaces, or search are shown until age eligibility is confirmed."
    const val anonymousMissingBirthdateTitle = "Birthday needed"
    const val anonymousMissingBirthdateBody =
        "Add your birthday in Matterya profile settings before entering Masquerade."
    const val anonymousAgeGateHint = "Return to Matterya from the tab bar anytime."
    const val anonymousAttestTitle = "Confirm you’re 18+"
    const val anonymousAttestBody =
        "Before entering Masquerade, confirm you are at least 18 years old. Private Space content stays hidden until you do."
    const val anonymousAttestFinePrint =
        "False confirmation may result in account restrictions. Age assurance may be re-checked over time."
    const val anonymousClaimTitle = "Choose your Masquerade name"
    const val anonymousClaimBody =
        "You’ll get one persistent username for all Spaces. It’s separate from your Matterya profile."
    const val anonymousClaimIrreversible =
        "Usernames can’t be changed later. Pick carefully."
    const val anonymousClaimGeneratedOnly =
        "v1 usernames are generated for you — custom real-name handles aren’t allowed."
    const val anonymousWelcomeLetterTitle = "Welcome to Masquerade"
    val anonymousWelcomeLetterBody = """
**Well, look who wandered in.**

Welcome to Masquerade.

It's a little different on this side of Matterya, isn't it?

Out there, the world knows your name, your face, and perhaps the person you've spent years becoming. But in here, none of that matters.

There's something rather fascinating about strangers behind masks. The stories they carry, the secrets they keep, and the things that only come to light when nobody knows who's speaking.

We all have a side of ourselves the world rarely gets to meet. Perhaps you'll find yours here. Or perhaps you'll discover something entirely unexpected in someone else's shadows.

We've given you a new name. What you do with it is entirely up to you.

Now, go on. Have a look around, find a room that catches your interest, and see where the conversations take you.

Just remember, not everything hidden is meant to be feared.

**Enjoy the Masquerade.**

**Matterya Team**
""".trimIndent()
    const val anonymousSpacesOnboardingTitle = "Find a few Spaces"
    const val anonymousSpacesOnboardingBody =
        "Join rooms that look interesting. You can always find more later — or skip for now."
    const val anonymousNoSpaces = "No Spaces yet"
    const val anonymousNoSpacesBody = "Create a free Space or pull to refresh when more appear."
    const val anonymousNoJoinedSpaces = "No joined Spaces"
    const val anonymousNoJoinedSpacesBody = "Join a free Space to see it here."
    const val anonymousPaidComingSoonTitle = "Paid Spaces coming soon"
    const val anonymousPaidComingSoonBody =
        "Paid memberships aren’t live yet. You can browse labels, but joining paid Spaces stays disabled."
    const val anonymousPaidJoinDisabled =
        "Paid join isn’t available yet. Billing will unlock this Space later."
    const val anonymousSpaceMissing = "Space unavailable"
    const val anonymousSpaceMissingBody =
        "This Space may be private, removed, or temporarily unavailable."
    const val anonymousSpaceEmptyPosts =
        "No posts yet. Seed a thoughtful first conversation."
    const val anonymousFeedEmptyTitle = "Nothing in your feed"
    const val anonymousFeedEmptyBody =
        "Pull to refresh — free Spaces show up here automatically."
    const val anonymousFeedWakeTitle = "Still waking up"
    const val anonymousFeedWakeBody =
        "Masquerade timed out on the first try. Pull to refresh — posts are already live."
    const val anonymousNoComments = "No comments yet."
    const val anonymousComposerPrivacyNudge =
        "Don’t share real names, contact info, or anything that links to your Matterya profile."
    const val anonymousMeHint =
        "This identity is only for Masquerade. Your ordinary Matterya avatar and name never appear here."
    const val anonymousExportPlaceholder =
        "Masquerade data export will open a request flow soon."
    const val anonymousDeletePlaceholder =
        "Masquerade deletion requests will open a support flow soon."
    const val anonymousSearchTitle = "Search Masquerade"
    const val anonymousSearchHint = "Find people, Spaces, and posts across Masquerade."
    const val anonymousSearchEmptyTitle = "No matches"
    const val anonymousSearchEmptyBody =
        "Try another keyword. Private Spaces won’t appear in search."
    const val anonymousNotificationsTitle = "No Masquerade notifications yet"
    const val anonymousNotificationsBody =
        "Replies, mentions, and Space updates land only here — never mixed with Matterya notifications or Inbox."
    const val anonymousMessagesInboxTitle = "No Masquerade messages yet"
    const val anonymousMessagesInboxBody =
        "Masquerade Inbox is anonymous-only. Official Matterya notes appear here — never your normal Matterya chats."
    const val anonymousInboxPrivacyNote =
        "Lock-screen and push copy won’t reveal Space titles to unauthorized recipients."
    const val anonymousModPlaceholderBody =
        "Moderator queue, removals, and sanctions will appear here. Platform policy still outranks Space rules."
    const val anonymousSuspendedTitle = "Masquerade suspended"
    const val anonymousSuspendedBody =
        "Your Masquerade access is restricted. Contact support if you believe this is a mistake."
    const val anonymousOfflineTitle = "Masquerade isn’t live yet"
    const val anonymousOfflineBody =
        "The Masquerade API isn’t reachable on this build. After the server migration and Manual Deploy, pull to try again."
    const val anonymousCreateMenuTitle = "Create in Masquerade"
    const val anonymousCreateSpace = "Create a Space"
    const val anonymousCreatePost = "New post in a Space"
}

private val ColorScheme = lightColorScheme(
    primary = MatteryaColors.accent,
    onPrimary = Color.White,
    secondary = MatteryaColors.accentBright,
    background = MatteryaColors.paper,
    surface = MatteryaColors.surface,
    onBackground = MatteryaColors.ink,
    onSurface = MatteryaColors.ink,
    error = MatteryaColors.danger,
)

@Composable
fun MatteryaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = ColorScheme,
        content = content,
    )
}

/** Paper screen background modifier (iOS `screenBackground()`). */
fun Modifier.screenBackground(): Modifier =
    this.background(MatteryaColors.paper)

fun Modifier.premiumCard(inset: Dp = MatteryaDimens.cardPadding): Modifier =
    this
        .padding(inset)
        .background(MatteryaColors.surface)

fun Modifier.glassSurface(cornerRadius: Dp = MatteryaDimens.controlRadius): Modifier =
    this
        .padding(12.dp)
        .background(MatteryaColors.globeGlass, RoundedCornerShape(cornerRadius))
        .border(0.5.dp, MatteryaColors.border, RoundedCornerShape(cornerRadius))

fun Modifier.instagramButton(): Modifier =
    this
        .fillMaxWidth()
        .padding(vertical = 7.dp)
        .background(MatteryaColors.buttonMuted, RoundedCornerShape(MatteryaDimens.controlRadius))

fun Modifier.elegantButton(outlined: Boolean = false): Modifier {
    val shape = RoundedCornerShape(MatteryaDimens.controlRadius)
    return if (outlined) {
        this
            .fillMaxWidth()
            .padding(vertical = 10.dp)
            .border(0.5.dp, MatteryaColors.border, shape)
    } else {
        this
            .fillMaxWidth()
            .padding(vertical = 10.dp)
            .background(MatteryaColors.ink, shape)
    }
}
