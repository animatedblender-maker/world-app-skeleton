import Foundation

extension Notification.Name {
    static let conversationMessagesDidChange = Notification.Name("conversationMessagesDidChange")
    static let incomingCallPush = Notification.Name("incomingCallPush")
    static let authTokenDidRefresh = Notification.Name("authTokenDidRefresh")
    static let socialNotificationsDidChange = Notification.Name("socialNotificationsDidChange")
    static let userPostsDidChange = Notification.Name("userPostsDidChange")
}