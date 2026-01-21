// apps/api/src/graphql/typeDefs.ts
export const typeDefs = `#graphql
  type LatLng {
    lat: Float!
    lng: Float!
  }

  type Country {
    id: ID!
    name: String!
    iso: String!
    continent: String!
    lat: Float!
    lng: Float!
    center: LatLng!
  }

  # ✅ Match your frontend query shape:
  # query { countries { countries { ... } } }
  type CountriesResult {
    countries: [Country!]!
  }

  type Profile {
    user_id: ID!
    email: String
    display_name: String
    username: String
    avatar_url: String
    country_name: String!
    country_code: String
    city_name: String
    bio: String
    created_at: String
    updated_at: String
  }

  # ✅ This is what Query.me returns (not Profile)
  type MeUser {
    id: ID!
    email: String
    role: String
  }

  type DetectedLocation {
    countryCode: String!
    countryName: String!
    cityName: String
    source: String!
  }

  type PostAuthor {
    user_id: ID!
    display_name: String
    username: String
    avatar_url: String
    country_name: String
    country_code: String
  }

  type NotificationActor {
    user_id: ID!
    display_name: String
    username: String
    avatar_url: String
  }

  type Post {
    id: ID!
    author_id: ID!
    category_id: ID!
    country_name: String!
    country_code: String
    city_name: String
    title: String
    body: String!
    media_type: String!
    media_url: String
    thumb_url: String
    visibility: String!
    like_count: Int!
    comment_count: Int!
    liked_by_me: Boolean!
    created_at: String!
    updated_at: String!
    author: PostAuthor
  }

  type PostComment {
    id: ID!
    post_id: ID!
    parent_id: ID
    author_id: ID!
    body: String!
    like_count: Int!
    liked_by_me: Boolean!
    created_at: String!
    updated_at: String!
    author: PostAuthor
  }

  type PostLike {
    user_id: ID!
    created_at: String!
    user: PostAuthor
  }

  type Notification {
    id: ID!
    user_id: ID!
    actor_id: ID
    type: String!
    entity_type: String
    entity_id: ID
    read_at: String
    created_at: String!
    actor: NotificationActor
  }

  type Message {
    id: ID!
    conversation_id: ID!
    sender_id: ID!
    body: String!
    created_at: String!
    sender: PostAuthor
  }

  type Conversation {
    id: ID!
    is_direct: Boolean!
    created_at: String!
    updated_at: String!
    last_message_at: String
    members: [PostAuthor!]!
    last_message: Message
  }

  input CreatePostInput {
    title: String
    body: String!
    country_name: String!
    country_code: String!
    city_name: String
    visibility: String
    media_type: String
    media_url: String
    thumb_url: String
  }

  input UpdatePostInput {
    title: String
    body: String
    visibility: String
  }

  type FollowCounts {
    followers: Int!
    following: Int!
  }

  input UpdateProfileInput {
    display_name: String
    username: String
    avatar_url: String
    country_name: String
    country_code: String
    city_name: String
    bio: String
  }

  # ----------------------------
  # Presence / Stats (NEW)
  # ----------------------------

  type GlobalStats {
    totalUsers: Int!
    onlineNow: Int!
    ttlSeconds: Int!
    computedAt: String!
  }

  type CountryStats {
    iso: String!
    name: String
    totalUsers: Int!
    onlineNow: Int!
    ttlSeconds: Int!
    computedAt: String!
  }

  type HeartbeatResult {
    ok: Boolean!
    ttlSeconds: Int!
    lastSeen: String!
  }

  type Query {
    # Countries
    countries: CountriesResult!
    countryByIso(iso: String!): Country

    # Auth info
    me: MeUser
    privatePing: String

    # Profile
    meProfile: Profile
    profileById(user_id: ID!): Profile
    profileByUsername(username: String!): Profile
    searchProfiles(query: String!, limit: Int): [Profile!]!

    # Presence stats
    globalStats: GlobalStats!
    countryStats(iso: String!): CountryStats!

    # Posts / social
    postsByCountry(country_code: String!, limit: Int): [Post!]!
    postsByAuthor(user_id: ID!, limit: Int): [Post!]!
    postById(post_id: ID!): Post
    commentsByPost(post_id: ID!, limit: Int, before: String): [PostComment!]!
    postLikes(post_id: ID!, limit: Int): [PostLike!]!
    followCounts(user_id: ID!): FollowCounts!
    followingIds: [ID!]!
    isFollowing(user_id: ID!): Boolean!

    # Messaging
    conversations(limit: Int): [Conversation!]!
    conversationById(conversation_id: ID!): Conversation
    messagesByConversation(conversation_id: ID!, limit: Int, before: String): [Message!]!
    messagesUnreadCount: Int!

    # Notifications
    notifications(limit: Int, before: String): [Notification!]!
    notificationsUnreadCount: Int!
  }

  type Mutation {
    detectLocation(lat: Float!, lng: Float!): DetectedLocation!
    updateProfile(input: UpdateProfileInput!): Profile!

    # Presence mutations
    heartbeat(iso: String): HeartbeatResult!
    setOffline: Boolean!

    # Posts / social
    createPost(input: CreatePostInput!): Post!
    updatePost(post_id: ID!, input: UpdatePostInput!): Post!
    deletePost(post_id: ID!): Boolean!
    likePost(post_id: ID!): Post!
    unlikePost(post_id: ID!): Post!
    addComment(post_id: ID!, body: String!, parent_id: ID): PostComment!
    likeComment(comment_id: ID!): PostComment!
    unlikeComment(comment_id: ID!): PostComment!
    reportPost(post_id: ID!, reason: String!): Boolean!
    followUser(target_id: ID!): Boolean!
    unfollowUser(target_id: ID!): Boolean!

    # Messaging
    startConversation(target_id: ID!): Conversation!
    sendMessage(conversation_id: ID!, body: String!): Message!

    # Notifications
    markNotificationRead(id: ID!): Boolean!
    markAllNotificationsRead: Int!
  }
`;
