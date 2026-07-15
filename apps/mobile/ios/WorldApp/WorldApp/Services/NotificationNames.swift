import Foundation

extension Notification.Name {
    static let conversationMessagesDidChange = Notification.Name("conversationMessagesDidChange")
    static let incomingCallPush = Notification.Name("incomingCallPush")
    static let authTokenDidRefresh = Notification.Name("authTokenDidRefresh")
    static let socialNotificationsDidChange = Notification.Name("socialNotificationsDidChange")
    static let userPostsDidChange = Notification.Name("userPostsDidChange")
    static let postRealtimeInsert = Notification.Name("postRealtimeInsert")
    static let postRealtimeDelete = Notification.Name("postRealtimeDelete")
    static let pushDeepLinkRequested = Notification.Name("pushDeepLinkRequested")
}