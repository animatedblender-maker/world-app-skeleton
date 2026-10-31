package com.matterya.matterya.model

/**
 * Models package entry — types live in split files mirroring iOS `Models.swift`:
 *
 * - [PostModels] PostVisibility, PostAuthor, PostMediaPayload, CountryPost, SharedPostPreview,
 *   LivingChannel, StoryGroup, StoryViewerContext, ReelsViewerContext, CreateContentSheet,
 *   ArchiveCatalogMedia, list filters
 * - [Markers] LivingChannelMarker, HubChannelPostMarker, SparkShareMarker, HubOriginShareMarker,
 *   PostStoryMarker, HubArchiveIdentity
 * - [ProfileModels] Profile, Country, DetectedLocation, FollowCounts, ProfileLibrarySection
 * - [MessageModels] Message (+ Share/Reply/Reaction), Conversation, CallLogInfo
 * - [ChannelModels] HubChannel, ChannelMember, ChannelMemberRole
 * - [NotificationModels] NotificationItem, ExternalNews*, Ad*
 * - [CommentModels] PostComment
 * - [RelativeTime] RelativeTime
 * - [AuthModels] AuthUser, AuthSession, AppTab, AppDestination, GlobePanel, CountryTab, stats
 * - [ContentSanitizer] ContentSanitizer, DemoPersonNames
 * - [GraphQLTypes] GraphQLPost / Author / Comment / Profile DTOs with toModel (effectiveComments)
 */
