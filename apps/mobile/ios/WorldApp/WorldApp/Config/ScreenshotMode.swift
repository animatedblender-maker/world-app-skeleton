import Foundation

/// Demo / App Store screenshot helper.
/// Code default stays inactive. Simulator captures: launch with
/// `-UIScreenshotMode` and optional `-UIScreenshotTab feed|anonymous|hubs|messages|profile`.
enum ScreenshotMode {
    /// Active only when launched with `-UIScreenshotMode` (keeps Release clean).
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-UIScreenshotMode")
    }

    static var tab: AppTab? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-UIScreenshotTab"),
              args.indices.contains(idx + 1),
              let tab = AppTab(rawValue: args[idx + 1]) else { return nil }
        return tab
    }

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
        birthdate: "1996-04-12",
        followersCount: 1284,
        followingCount: 312,
        messagePrivacy: "everyone",
        accountStatus: "active",
        deactivatedAt: nil,
        deletedAt: nil,
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
                isRequest: false,
                requestStatus: nil,
                members: [me, peer],
                lastMessage: last
            ),
        ]
    }
}
