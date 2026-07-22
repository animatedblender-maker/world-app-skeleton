import Foundation

/// Demo / App Store screenshot helper.
/// Keep `isActive == false` for normal app use.
enum ScreenshotMode {
    /// Flip to `true` only when capturing marketing screenshots.
    static let isActive = false

    static var tab: AppTab? { nil }
    static var route: AppDestination? { nil }
    static var searchQuery: String? { nil }

    static let demoProfile = Profile(
        userID: "screenshot_demo_user",
        email: "demo@matterya.app",
        displayName: "Alex Rivera",
        username: "alexrivera",
        avatarURL: "https://api.dicebear.com/7.x/identicon/svg?seed=alexrivera",
        countryName: "Spain",
        countryCode: "ES",
        cityName: "Barcelona",
        bio: "Exploring the world with Matterya.",
        followersCount: 1284,
        followingCount: 312,
        createdAt: ISO8601DateFormatter().string(from: Date()),
        updatedAt: ISO8601DateFormatter().string(from: Date())
    )

    static var demoConversations: [Conversation] {
        let peer = PostAuthor(
            userID: "screenshot_peer",
            displayName: "Sam Chen",
            username: "samchen",
            avatarURL: "https://api.dicebear.com/7.x/identicon/svg?seed=samchen",
            countryName: "Japan",
            countryCode: "JP",
            lastReadAt: nil
        )
        let me = PostAuthor(
            userID: demoProfile.userID,
            displayName: demoProfile.displayName,
            username: demoProfile.username,
            avatarURL: demoProfile.avatarURL,
            countryName: demoProfile.countryName,
            countryCode: demoProfile.countryCode,
            lastReadAt: nil
        )
        let now = ISO8601DateFormatter().string(from: Date())
        let last = Message(
            id: "screenshot_msg_1",
            conversationID: "screenshot_convo_1",
            senderID: peer.userID,
            body: "See you on the globe later!",
            mediaType: nil,
            mediaPath: nil,
            mediaURL: nil,
            mediaName: nil,
            createdAt: now,
            updatedAt: now,
            sender: peer
        )
        return [
            Conversation(
                id: "screenshot_convo_1",
                isDirect: true,
                createdAt: now,
                updatedAt: now,
                lastMessageAt: now,
                members: [me, peer],
                lastMessage: last
            ),
        ]
    }
}
