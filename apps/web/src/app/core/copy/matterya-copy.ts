/** User-facing copy — mirrors iOS `MatteryaCopy` in Theme.swift exactly. */
const NBSP = '\u00A0';
const hubsBrand = `Matterya${NBSP}Hubs`;
const masqueradeBrand = `Matterya${NBSP}Masquerade`;

export const MatteryaCopy = {
  sparks: 'Sparks',
  spark: 'Spark',
  matteryaSparks: `Matterya${NBSP}Sparks`,
  sparksForYou: 'Sparks for you',
  newSpark: 'New spark',
  newVideo: 'New video',
  publishSpark: 'Publish spark',
  publishVideo: 'Publish video',
  savedSparks: 'Saved sparks',
  browseSparks: 'Browse Sparks',
  watchAllSparks: 'Watch all',
  sparksFromCountry: 'Sparks from',
  noSparksYet: 'No sparks yet',
  noSparksForCountry: 'No sparks for',
  saveSparksHint: 'Save sparks while watching or publish your own.',
  savedSparksSubtitle: 'Sparks you bookmarked',
  publishSparkHint: 'Vertical video works best',
  publishVideoHint: `Shows in feed and ${hubsBrand}`,
  matteryaHubs: hubsBrand,
  continueWatching: 'Continue watching',
  newOnHubs: `New on ${hubsBrand}`,
  watchOnHubs: `Watch on ${hubsBrand}`,
  publishedOnHubs: `Published on ${hubsBrand}`,
  openingHubs: `Opening ${hubsBrand}…`,
  loadingHubs: `Loading ${hubsBrand}…`,
  hubsUnavailable: `${hubsBrand} unavailable`,
  exploreHubs: `Explore ${hubsBrand}`,
  searchHubs: `Search ${hubsBrand}`,
  searchHubsHint: `Find videos and creators on ${hubsBrand}`,
  moreOnHubs: `More on ${hubsBrand}`,
  yourChannelOnHubs: `Your channel on ${hubsBrand}`,
  verifiedHubsChannel: `Verified ${hubsBrand} channel`,
  longFormOnHubs: `Long-form on ${hubsBrand}`,
  sparksOnHubs: `Short vertical video on ${hubsBrand}`,
  hubsPublishHint: `Follow creators or publish on ${hubsBrand}.`,
  hubsLoadError: `Couldn't load ${hubsBrand} right now. Pull to refresh or check your connection.`,
  hubsNoChannelVideos: `This creator hub has no videos on ${hubsBrand} yet.`,
  hubsVideoUnavailable: `This video isn't available on ${hubsBrand}.`,
  postToYourFeed: 'Post to the main feed',
  shareToYourFeed: 'Share to the main feed',
  browsingForeignFeed: 'Browsing another country',
  shareFromForeignHint:
    'Tap share on any post to add it to your home feed. You can only write posts in your own country.',
  homeCountryOnlyPost: 'You can only publish in your home country.',
  follow: 'Follow',
  following: 'Following',
  followers: 'followers',
  creator: 'Creator',
  creators: 'Creators',
  viewCreatorHub: 'View creator hub',
  shareCreatorHub: 'Share creator hub',
  aboutThisHub: 'About this hub',
  featuredCreators: 'Featured creators',

  // Masquerade (Anonymous mode) — UI name is Masquerade
  anonymous: 'Masquerade',
  matteryaMasquerade: masqueradeBrand,
  anonymousModeChip: 'Anonymous mode',
  anonymousTagline: 'Leave your identity outside.',
  anonymousWildeQuote: '“Give him a mask, and he will tell you the truth.”',
  anonymousWildeAttribution: '— Oscar Wilde, 1891',
  anonymousPrivacyBoundary:
    'Your Masquerade name is public inside Spaces. Other members can’t see your Matterya profile. Matterya may link identities for safety and legal compliance.',
  anonymousUnder18Title: 'Adults only',
  anonymousUnder18Body:
    'Masquerade is only available to people 18 and older. No posts, Spaces, or search are shown until age eligibility is confirmed.',
  anonymousMissingBirthdateTitle: 'Birthday needed',
  anonymousMissingBirthdateBody:
    'Add your birthday in Matterya profile settings before entering Masquerade.',
  anonymousAgeGateHint: 'Return to Matterya from the tab bar anytime.',
  anonymousAttestTitle: 'Confirm you’re 18+',
  anonymousAttestBody:
    'Before entering Masquerade, confirm you are at least 18 years old. Private Space content stays hidden until you do.',
  anonymousAttestFinePrint:
    'False confirmation may result in account restrictions. Age assurance may be re-checked over time.',
  anonymousClaimTitle: 'Choose your Masquerade name',
  anonymousClaimBody:
    'You’ll get one persistent username for all Spaces. It’s separate from your Matterya profile.',
  anonymousClaimIrreversible: 'Usernames can’t be changed later. Pick carefully.',
  anonymousClaimGeneratedOnly:
    'v1 usernames are generated for you — custom real-name handles aren’t allowed.',
  anonymousWelcomeLetterTitle: 'Welcome to Masquerade',
  anonymousWelcomeLetterBody: `**Well, look who wandered in.**

Welcome to Masquerade.

It's a little different on this side of Matterya, isn't it?

Out there, the world knows your name, your face, and perhaps the person you've spent years becoming. But in here, none of that matters.

There's something rather fascinating about strangers behind masks. The stories they carry, the secrets they keep, and the things that only come to light when nobody knows who's speaking.

We all have a side of ourselves the world rarely gets to meet. Perhaps you'll find yours here. Or perhaps you'll discover something entirely unexpected in someone else's shadows.

We've given you a new name. What you do with it is entirely up to you.

Now, go on. Have a look around, find a room that catches your interest, and see where the conversations take you.

Just remember, not everything hidden is meant to be feared.

**Enjoy the Masquerade.**

**Matterya Team**`,
  anonymousSpacesOnboardingTitle: 'Find a few Spaces',
  anonymousSpacesOnboardingBody:
    'Join rooms that look interesting. You can always find more later — or skip for now.',
  anonymousNoSpaces: 'No Spaces yet',
  anonymousNoSpacesBody: 'Create a free Space or pull to refresh when more appear.',
  anonymousNoJoinedSpaces: 'No joined Spaces',
  anonymousNoJoinedSpacesBody: 'Join a free Space to see it here.',
  anonymousPaidComingSoonTitle: 'Paid Spaces coming soon',
  anonymousPaidComingSoonBody:
    'Paid memberships aren’t live yet. You can browse labels, but joining paid Spaces stays disabled.',
  anonymousPaidJoinDisabled: 'Paid join isn’t available yet. Billing will unlock this Space later.',
  anonymousSpaceMissing: 'Space unavailable',
  anonymousSpaceMissingBody: 'This Space may be private, removed, or temporarily unavailable.',
  anonymousSpaceEmptyPosts: 'No posts yet. Seed a thoughtful first conversation.',
  anonymousFeedEmptyTitle: 'Nothing in your feed',
  anonymousFeedEmptyBody: 'Pull to refresh — free Spaces show up here automatically.',
  anonymousFeedWakeTitle: 'Still waking up',
  anonymousFeedWakeBody:
    'Masquerade timed out on the first try. Pull to refresh — posts are already live.',
  anonymousNoComments: 'No comments yet.',
  anonymousComposerPrivacyNudge:
    'Don’t share real names, contact info, or anything that links to your Matterya profile.',
  anonymousMeHint:
    'This identity is only for Masquerade. Your ordinary Matterya avatar and name never appear here.',
  anonymousExportPlaceholder: 'Masquerade data export will open a request flow soon.',
  anonymousDeletePlaceholder: 'Masquerade deletion requests will open a support flow soon.',
  anonymousSearchTitle: 'Search Masquerade',
  anonymousSearchHint: 'Find people, Spaces, and posts across Masquerade.',
  anonymousSearchEmptyTitle: 'No matches',
  anonymousSearchEmptyBody: 'Try another keyword. Private Spaces won’t appear in search.',
  anonymousNotificationsTitle: 'No Masquerade notifications yet',
  anonymousNotificationsBody:
    'Replies, mentions, and Space updates land only here — never mixed with Matterya notifications or Inbox.',
  anonymousMessagesInboxTitle: 'No Masquerade messages yet',
  anonymousMessagesInboxBody:
    'Masquerade Inbox is anonymous-only. Official Matterya notes appear here — never your normal Matterya chats.',
  anonymousInboxPrivacyNote:
    'Lock-screen and push copy won’t reveal Space titles to unauthorized recipients.',
  anonymousModPlaceholderBody:
    'Moderator queue, removals, and sanctions will appear here. Platform policy still outranks Space rules.',
  anonymousSuspendedTitle: 'Masquerade suspended',
  anonymousSuspendedBody:
    'Your Masquerade access is restricted. Contact support if you believe this is a mistake.',
  anonymousOfflineTitle: 'Masquerade isn’t live yet',
  anonymousOfflineBody:
    'The Masquerade API isn’t reachable on this build. After the server migration and Manual Deploy, pull to try again.',
  anonymousCreateMenuTitle: 'Create in Masquerade',
  anonymousCreateSpace: 'Create a Space',
  anonymousCreatePost: 'New post in a Space',

  personsHubTitle(displayName?: string | null, username?: string | null): string {
    const raw = (displayName ?? '').trim();
    const firstFromName = raw.split(/\s+/).filter(Boolean)[0];
    const handle = (username ?? '').trim();
    const name = firstFromName || (handle || null);
    if (!name) return 'Their hub';
    if (name.toLowerCase().endsWith('s')) return `${name}' hub`;
    return `${name}'s hub`;
  },
} as const;
