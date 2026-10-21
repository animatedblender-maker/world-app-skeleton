import Foundation

extension Notification.Name {
    static let conversationMessagesDidChange = Notification.Name("conversationMessagesDidChange")
    static let incomingCallPush = Notification.Name("incomingCallPush")
    static let authTokenDidRefresh = Notification.Name("authTokenDidRefresh")
    static let socialNotificationsDidChange = Notification.Name("socialNotificationsDidChange")
    static let userPostsDidChange = Notification.Name("userPostsDidChange")
    /// User deleted a post — feed, profile, caches must drop it (userInfo: `postID`).
    static let userPostDidDelete = Notification.Name("userPostDidDelete")
    static let pushDeepLinkRequested = Notification.Name("pushDeepLinkRequested")
    /// Sync export of the live feed player into SparkWarmPool before Sparks/Hubs claim.
    /// userInfo: `postIDs` ([String]). Delivered synchronously on the posting thread.
    static let matteryaExportPlaybackForHandoff = Notification.Name("matterya.exportPlaybackForHandoff")
    /// Frame0PosterCache gained signed posters — userInfo: `postIDs` ([String]).
    /// Strip/feed cells observe this because the cache itself is not SwiftUI state.
    static let frame0PostersDidUpdate = Notification.Name("frame0PostersDidUpdate")
    /// ScrollBudget cleared fling — Home feed drains queued load-more that skipped mid-fling.
    static let scrollBudgetDidSettle = Notification.Name("matterya.scrollBudget.didSettle")
}