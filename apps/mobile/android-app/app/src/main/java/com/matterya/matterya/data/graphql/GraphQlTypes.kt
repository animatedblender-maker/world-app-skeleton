package com.matterya.matterya.data.graphql

/**
 * GraphQL DTO helpers — Android decodes GraphQL JSON directly into
 * `com.matterya.matterya.model` types via kotlinx.serialization.
 *
 * Field selections live in [GqlOps] (copied from iOS PostsService /
 * ProfileService / MessagesService / ChannelsService / FollowService /
 * NotificationsService).
 *
 * iOS counterpart: `GraphQLTypes.swift` (`GraphQLPost`, `GraphQLComment`,
 * `GraphQLProfile`, `GraphQLAuthor`, …). On Android those map 1:1 to:
 * - CountryPost / PostComment / Profile / PostAuthor
 * - Conversation / Message
 * - HubChannel / ChannelMember
 * - NotificationItem
 */
object GraphQlTypes {
    /** No-op marker for mutations that return only a scalar / empty payload. */
    const val EMPTY = "EmptyMutation"
}
