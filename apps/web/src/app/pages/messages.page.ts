import { ChangeDetectorRef, Component, ElementRef, NgZone, OnDestroy, OnInit, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { AuthService } from '../core/services/auth.service';
import { MessagesService } from '../core/services/messages.service';
import { MediaService } from '../core/services/media.service';
import { NotificationsService, type NotificationItem } from '../core/services/notifications.service';
import { PushService } from '../core/services/push.service';
import { CallService, type CallSignal } from '../core/services/call.service';
import { Conversation, Message } from '../core/models/messages.model';
import { PostAuthor } from '../core/models/post.model';
import { VideoPlayerComponent } from '../components/video-player.component';
import { environment } from '../../envirnoments/envirnoment';
import { BottomTabsComponent } from '../components/bottom-tabs.component';

@Component({
  selector: 'app-messages-page',
  standalone: true,
  imports: [CommonModule, FormsModule, VideoPlayerComponent, BottomTabsComponent],
  template: `
    <div class="wrap">
      <div class="card">
        <div class="layout" [class.thread-only]="mobileThreadOnly">
          <aside class="panel">
            <!-- iOS MessagesView top bar -->
            <div class="panel-title">
              <button class="panel-icon-btn" type="button" (click)="goBack()" aria-label="Back">
                <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8">
                  <path d="M15 5l-7 7 7 7" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </button>
              <span class="panel-heading">Messages</span>
              <button class="panel-icon-btn" type="button" (click)="goPeople()" aria-label="New message">
                <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.7">
                  <path d="M5 19l1.5-5.5L16.5 3.5a2.1 2.1 0 0 1 3 3L9.5 16.5 4 18z" stroke-linejoin="round"/>
                  <path d="M13.5 6.5l4 4" stroke-linecap="round"/>
                </svg>
              </button>
            </div>
            <div class="status" *ngIf="loadingConversations">Loading conversations…</div>
            <div class="status error" *ngIf="conversationError">{{ conversationError }}</div>
            <div class="status empty" *ngIf="!loadingConversations && !conversations.length">
              No conversations yet. Start chatting from a profile.
            </div>
            <button
              class="conversation"
              type="button"
              *ngFor="let convo of conversations"
              [class.active]="convo.id === activeConversationId"
              [class.unread]="isConversationUnread(convo)"
              (click)="selectConversation(convo, true)"
            >
              <div class="avatar">
                <img
                  *ngIf="otherMember(convo)?.avatar_url"
                  [src]="otherMember(convo)?.avatar_url"
                  alt=""
                />
                <div class="initials" *ngIf="!otherMember(convo)?.avatar_url">
                  {{ initialsFor(otherMember(convo)) }}
                </div>
              </div>
              <div class="meta">
                <div class="name-row">
                  <div class="name">{{ displayNameFor(otherMember(convo)) }}</div>
                  <div class="time">{{ formatTime(convo.last_message_at || convo.updated_at) }}</div>
                </div>
                <div class="snippet">{{ conversationSnippet(convo) }}</div>
              </div>
              <span class="conversation-unread" *ngIf="isConversationUnread(convo)" aria-hidden="true"></span>
            </button>
          </aside>

          <section class="thread" *ngIf="activeConversation || !isNarrow">
            <div class="thread-header" *ngIf="activeConversation; else emptyThread">
              <button
                class="thread-back"
                type="button"
                *ngIf="mobileThreadOnly"
                (click)="showConversationList()"
                aria-label="Back to chats"
              >
                <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8">
                  <path d="M15 5l-7 7 7 7" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </button>
              <div class="avatar large">
                <img
                  *ngIf="otherMember(activeConversation)?.avatar_url"
                  [src]="otherMember(activeConversation)?.avatar_url"
                  alt=""
                />
                <div class="initials" *ngIf="!otherMember(activeConversation)?.avatar_url">
                  {{ initialsFor(otherMember(activeConversation)) }}
                </div>
              </div>
              <div class="thread-meta">
                <div class="thread-name">{{ displayNameFor(otherMember(activeConversation)) }}</div>
                <div
                  class="thread-sub"
                  *ngIf="displayHandleFor(otherMember(activeConversation)) as handle"
                >
                  {{ handle }}
                </div>
              </div>
              <div class="thread-actions">
                <button
                  class="call-btn"
                  type="button"
                  [disabled]="!canStartCall()"
                  (click)="startCall('audio')"
                  aria-label="Voice call"
                >
                  <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
                    <path d="M6.6 3.8c.5-.5 1.3-.5 1.8 0l1.7 1.7c.5.5.5 1.2.1 1.7l-1 1.3c.8 1.6 2 2.9 3.6 3.6l1.3-1c.5-.4 1.2-.4 1.7.1l1.7 1.7c.5.5.5 1.3 0 1.8l-1.1 1.1c-.5.5-1.2.7-1.9.5-3.3-.9-6.1-3.7-7-7-.2-.7 0-1.4.5-1.9l1.1-1.1z"/>
                  </svg>
                </button>
                <button
                  class="call-btn"
                  type="button"
                  [disabled]="!canStartCall()"
                  (click)="startCall('video')"
                  aria-label="Video call"
                >
                  <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
                    <path d="M4 7.5A2.5 2.5 0 0 1 6.5 5h7A2.5 2.5 0 0 1 16 7.5v9a2.5 2.5 0 0 1-2.5 2.5h-7A2.5 2.5 0 0 1 4 16.5v-9z"/>
                    <path d="M17 10.2l3.2-2.1a.8.8 0 0 1 1.3.7v6.4a.8.8 0 0 1-1.3.7L17 13.8v-3.6z"/>
                  </svg>
                </button>
              </div>
            </div>

            <ng-template #emptyThread>
              <div class="thread-empty">
                <div class="thread-empty-icon" aria-hidden="true">💬</div>
                <div class="thread-empty-title">Your messages</div>
                <div class="thread-empty-sub">Select a conversation to start chatting.</div>
              </div>
            </ng-template>

            <div class="messages" *ngIf="activeConversation">
              <div class="status" *ngIf="loadingMessages">Loading messages…</div>
              <div class="status error" *ngIf="messageError">{{ messageError }}</div>
              <div class="message-list" *ngIf="!loadingMessages" #messageList>
                <ng-container *ngFor="let message of messages; let i = index; trackBy: trackMessageById">
                  <ng-container *ngIf="!isReactionMessage(message)">
                    <div class="message-day" *ngIf="showDaySeparatorVisible(i)">
                      {{ formatDayLabel(message.created_at) }}
                    </div>

                    <!-- iOS call log pill -->
                    <div
                      class="call-log-row"
                      *ngIf="isCallLogMessage(message); else chatBubble"
                      [attr.id]="'msg-' + message.id"
                    >
                      <span class="call-log-line"></span>
                      <span class="call-log-pill">{{ messageText(message) }}</span>
                      <span class="call-log-line"></span>
                      <div class="call-log-time">{{ formatTimestamp(message.created_at) }}</div>
                    </div>

                    <ng-template #chatBubble>
                      <!-- iOS MessageBubble: no per-message avatar, stacked content -->
                      <div
                        class="message"
                        [class.me]="message.sender_id === meId"
                        [attr.id]="'msg-' + message.id"
                      >
                        <div class="bubble-col">
                          <div
                            class="reply-preview"
                            *ngIf="replyPreview(message) as reply"
                            (click)="scrollToMessage(reply.id)"
                          >
                            <div class="reply-meta">Replying to {{ reply.name }}</div>
                            <div class="reply-text">{{ reply.text }}</div>
                          </div>

                          <div class="message-media" *ngIf="message.media_type && message.media_url">
                            <img
                              *ngIf="message.media_type === 'image'"
                              [src]="message.media_url"
                              alt=""
                              (click)="openImageLightbox(message.media_url)"
                            />
                            <app-video-player
                              *ngIf="message.media_type === 'video'"
                              [src]="message.media_url"
                            ></app-video-player>
                          </div>

                          <div class="bubble" *ngIf="messageText(message) as text">
                            <div class="body">{{ text }}</div>
                          </div>

                          <div class="reaction-strip" *ngIf="messageLikeCount(message) > 0">
                            <span class="reaction-chip">❤️ {{ messageLikeCount(message) }}</span>
                          </div>

                          <div class="message-meta">
                            <span class="message-time">{{ formatTimestamp(message.created_at) }}</span>
                            <span class="message-edited" *ngIf="isEdited(message)">Edited</span>
                            <span class="message-read" *ngIf="isLastReadOwn(message)">Read</span>
                          </div>

                          <div class="message-tools" *ngIf="!isEditing(message)">
                            <button type="button" class="tool" (click)="startReply(message)">Reply</button>
                            <button
                              type="button"
                              class="tool"
                              [class.on]="isMessageLikedByMe(message)"
                              (click)="toggleMessageLike(message)"
                            >
                              {{ isMessageLikedByMe(message) ? 'Liked' : 'Like' }}
                            </button>
                            <button
                              type="button"
                              class="tool"
                              *ngIf="message.sender_id === meId"
                              (click)="startEditMessage(message)"
                            >
                              Edit
                            </button>
                            <button
                              type="button"
                              class="tool danger"
                              *ngIf="message.sender_id === meId"
                              (click)="deleteMessage(message)"
                            >
                              Unsend
                            </button>
                          </div>

                          <div class="message-edit" *ngIf="isEditing(message)">
                            <textarea class="message-edit-input" [(ngModel)]="editingDraft" rows="2"></textarea>
                            <div class="message-edit-actions">
                              <button type="button" class="ghost" (click)="cancelEditMessage()">Cancel</button>
                              <button type="button" class="save" (click)="saveEditMessage(message)" [disabled]="editBusy">
                                {{ editBusy ? 'Saving…' : 'Save' }}
                              </button>
                            </div>
                          </div>
                        </div>
                      </div>
                    </ng-template>
                  </ng-container>
                </ng-container>
              </div>
            </div>

            <!-- iOS composerBar: photo + field + paperplane circle -->
            <form class="composer" *ngIf="activeConversation" (ngSubmit)="sendMessage()">
              <div class="composer-reply" *ngIf="replyingTo">
                <div class="composer-reply-bar" aria-hidden="true"></div>
                <div class="composer-reply-copy">
                  <div class="composer-reply-title">
                    Replying to {{ displayNameFor(senderInfo(replyingTo)) }}
                  </div>
                  <div class="composer-reply-text">{{ replySnippet(replyingTo) }}</div>
                </div>
                <button type="button" class="composer-reply-close" (click)="cancelReply()">Cancel</button>
              </div>
              <div class="composer-preview" *ngIf="messageMediaPreview">
                <img *ngIf="messageMediaType === 'image'" [src]="messageMediaPreview" alt="" />
                <video
                  *ngIf="messageMediaType === 'video'"
                  [src]="messageMediaPreview"
                  muted
                  playsinline
                ></video>
                <button class="composer-clear" type="button" (click)="clearMedia()">Remove</button>
              </div>
              <div class="composer-row">
                <input
                  #mediaInput
                  type="file"
                  accept="image/png,image/jpeg,image/webp,video/mp4,video/webm,video/quicktime"
                  hidden
                  (change)="onMediaSelected($event)"
                />
                <button class="composer-attach" type="button" (click)="triggerMediaPicker()" aria-label="Add photo">
                  <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.7">
                    <rect x="3.5" y="5.5" width="17" height="13" rx="2.2"/>
                    <circle cx="9" cy="10.5" r="1.6"/>
                    <path d="M7.5 16.5l3.2-3.4 2.4 2.2 3.1-3.6 3.3 4.8" stroke-linecap="round" stroke-linejoin="round"/>
                  </svg>
                </button>
                <textarea
                  #messageInput
                  class="composer-input"
                  name="message"
                  [(ngModel)]="messageDraft"
                  [placeholder]="replyingTo ? 'Write a reply…' : 'Message…'"
                  maxlength="2000"
                  rows="1"
                  (input)="onMessageInput($event)"
                ></textarea>
                <button
                  class="composer-send"
                  type="submit"
                  [disabled]="messageBusy || !canSendMessage()"
                  aria-label="Send"
                >
                  <svg *ngIf="!messageBusy" viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
                    <path d="M3.4 20.6 21 12 3.4 3.4l.1 6.7L15 12 3.5 13.9z"/>
                  </svg>
                  <span *ngIf="messageBusy" class="send-busy">…</span>
                </button>
              </div>
              <div class="status error" *ngIf="messageMediaError">{{ messageMediaError }}</div>
            </form>
          </section>
        </div>
      </div>
    </div>
    <app-bottom-tabs *ngIf="!activeConversation"></app-bottom-tabs>

    <div class="lightbox" *ngIf="lightboxUrl" (click)="closeImageLightbox()">
      <div class="lightbox-card" (click)="$event.stopPropagation()">
        <div class="lightbox-frame">
          <button class="lightbox-close" type="button" (click)="closeImageLightbox()">x</button>
          <img [src]="lightboxUrl" alt="Preview" />
        </div>
      </div>
    </div>

    <div class="call-overlay" *ngIf="callUiOpen">
      <div class="call-card" [class.video]="callType === 'video'" (click)="$event.stopPropagation()">
        <div class="call-top">
          <img class="call-logo" src="/logo.png" alt="Matterya" />
          <div>
            <div class="call-title">{{ callTitle() }}</div>
            <div class="call-sub">{{ callStatusText() }}</div>
          </div>
          <div class="call-timer">{{ callTimerLabel() }}</div>
        </div>
        <div class="call-body">
          <video
            #remoteVideo
            class="call-remote"
            autoplay
            playsinline
            *ngIf="callType === 'video'"
          ></video>
          <div class="call-avatar" [class.speaking]="callSpeaking" *ngIf="callType !== 'video'">
            <img *ngIf="callPeerAvatar()" [src]="callPeerAvatar()" alt="avatar" />
            <div class="initials" *ngIf="!callPeerAvatar()">
              {{ initialsFor(callPeer()) }}
            </div>
          </div>
          <video
            #localVideo
            class="call-local"
            autoplay
            muted
            playsinline
            *ngIf="callType === 'video'"
          ></video>
        </div>
        <div class="call-controls">
          <ng-container *ngIf="callIncoming; else activeControls">
            <button class="call-action accept" type="button" (click)="acceptCall()">Accept</button>
            <button class="call-action end" type="button" (click)="declineCall()">Decline</button>
          </ng-container>
          <ng-template #activeControls>
            <button class="call-action ghost" type="button" (click)="toggleMute()">
              {{ callMuted ? 'Unmute' : 'Mute' }}
            </button>
            <button
              class="call-action ghost"
              type="button"
              *ngIf="callType === 'video'"
              (click)="toggleCamera()"
            >
              {{ callCameraOff ? 'Camera on' : 'Camera off' }}
            </button>
            <button class="call-action end" type="button" (click)="endCall()">End</button>
          </ng-template>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
    :host{
      display:block;
      min-height:100svh;
      height:100svh;
      position:relative;
      color:var(--m-ink, #2c2825);
      background:var(--m-paper, #f8f6f2);
    }
    .wrap{
      min-height:100%;
      height:100%;
      position:relative;
      padding:0 0 var(--tabs-safe, 64px);
      box-sizing:border-box;
      display:flex;
      flex-direction:column;
      background:var(--m-paper, #f8f6f2);
    }
    .card{
      position:relative;
      z-index:1;
      width:100%;
      height:100%;
      max-width:none;
      margin:0;
      background:var(--m-paper, #f8f6f2);
      border-radius:0;
      padding:0;
      border:0;
      box-shadow:none;
      backdrop-filter:none;
      color:var(--m-ink, #2c2825);
      flex:1;
      box-sizing:border-box;
      display:flex;
      flex-direction:column;
      min-height:0;
      overflow:hidden;
    }
    .layout{
      display:grid;
      grid-template-columns:320px 1fr;
      gap:0;
      align-items:stretch;
      flex:1;
      min-height:0;
    }
    .layout.thread-only .panel{
      display:none;
    }
    /* Desktop: NEVER hide the conversation list when a chat is open */
    @media (min-width: 901px){
      .layout.thread-only .panel{
        display:flex !important;
      }
    }
    .panel{
      display:flex;
      flex-direction:column;
      gap:4px;
      background:var(--m-paper, #f8f6f2);
      border-radius:0;
      padding:0 0 8px;
      border:0;
      border-right:0.5px solid var(--m-divider, #e2ded8);
      min-height:0;
      overflow:auto;
    }
    .panel-title{
      position:sticky;
      top:0;
      z-index:2;
      min-height:44px;
      padding:0 8px;
      display:grid;
      grid-template-columns:44px 1fr 44px;
      align-items:center;
      gap:4px;
      background:var(--m-surface, #fefdfb);
      border-bottom:0.5px solid var(--m-divider, #e2ded8);
    }
    .panel-heading{
      text-align:center;
      font-size:17px;
      font-weight:650;
      color:var(--m-ink, #2c2825);
    }
    .panel-icon-btn{
      width:44px;
      height:44px;
      border:0;
      background:transparent;
      color:var(--m-ink, #2c2825);
      display:grid;
      place-items:center;
      cursor:pointer;
      border-radius:12px;
      padding:0;
    }
    .panel-icon-btn:hover{ background:rgba(44,40,37,0.05); }
    .status{
      font-size:14px;
      color:var(--m-ink-muted, #948b82);
      padding:16px 16px 8px;
    }
    .status.error{ color:var(--m-danger, #ea000b); }
    .status.empty{ text-align:center; padding:40px 20px; line-height:1.45; }
    .conversation{
      display:flex;
      align-items:center;
      gap:12px;
      padding:10px 14px;
      margin:0 6px;
      border-radius:14px;
      border:0;
      background:transparent;
      cursor:pointer;
      text-align:left;
      color:inherit;
      width:calc(100% - 12px);
      box-sizing:border-box;
    }
    .conversation:hover{ background:rgba(44,40,37,0.04); }
    .conversation.active{ background:var(--m-surface, #fefdfb); box-shadow:inset 0 0 0 0.5px var(--m-border, #ddd8d1); }
    .conversation.unread .name{ font-weight:750; }
    .conversation.unread .snippet{ color:var(--m-ink, #2c2825); opacity:0.85; }
    .conversation-unread{
      width:9px;
      height:9px;
      border-radius:999px;
      background:var(--m-danger, #ea000b);
      flex:0 0 auto;
    }
    .avatar{
      width:48px;
      height:48px;
      border-radius:50%;
      overflow:hidden;
      background:var(--m-canvas-muted, #f2f0ec);
      display:flex;
      align-items:center;
      justify-content:center;
      font-weight:700;
      font-size:13px;
      color:var(--m-ink-secondary, #6b645d);
      flex-shrink:0;
    }
    .avatar img{ width:100%; height:100%; object-fit:cover; }
    .avatar.large{ width:40px; height:40px; font-size:12px; }
    .meta{ flex:1; min-width:0; }
    .name-row{
      display:flex;
      align-items:baseline;
      justify-content:space-between;
      gap:10px;
    }
    .name{
      font-weight:650;
      font-size:15px;
      color:var(--m-ink, #2c2825);
      white-space:nowrap;
      overflow:hidden;
      text-overflow:ellipsis;
    }
    .snippet{
      margin-top:3px;
      font-size:13px;
      color:var(--m-ink-muted, #948b82);
      white-space:nowrap;
      overflow:hidden;
      text-overflow:ellipsis;
    }
    .time{
      font-size:11px;
      color:var(--m-ink-muted, #948b82);
      white-space:nowrap;
      flex-shrink:0;
    }
    .thread{
      display:flex;
      flex-direction:column;
      border-radius:0;
      border:0;
      background:var(--m-paper, #f8f6f2);
      min-height:0;
      overflow:hidden;
    }
    .thread-back{
      border:0;
      background:transparent;
      color:var(--m-ink, #2c2825);
      width:40px;
      height:40px;
      border-radius:12px;
      display:grid;
      place-items:center;
      cursor:pointer;
      padding:0;
      flex-shrink:0;
    }
    .thread-header{
      display:flex;
      align-items:center;
      gap:10px;
      padding:8px 12px;
      min-height:52px;
      border-bottom:0.5px solid var(--m-divider, #e2ded8);
      background:var(--m-canvas, #f8f6f2);
      min-width:0;
    }
    .thread-meta{ min-width:0; flex:1; }
    .thread-name{
      font-weight:650;
      font-size:16px;
      color:var(--m-ink, #2c2825);
      white-space:nowrap;
      overflow:hidden;
      text-overflow:ellipsis;
    }
    .thread-sub{
      font-size:12px;
      color:var(--m-ink-muted, #948b82);
      white-space:nowrap;
      overflow:hidden;
      text-overflow:ellipsis;
    }
    .thread-actions{
      margin-left:auto;
      display:flex;
      gap:4px;
      flex-shrink:0;
    }
    .call-btn{
      width:40px;
      height:40px;
      border-radius:12px;
      border:0;
      background:transparent;
      color:var(--m-ink, #2c2825);
      cursor:pointer;
      display:grid;
      place-items:center;
      padding:0;
    }
    .call-btn:hover{ background:rgba(44,40,37,0.05); }
    .call-btn:disabled{ opacity:0.4; cursor:not-allowed; }
    .thread-empty{
      flex:1;
      display:flex;
      flex-direction:column;
      align-items:center;
      justify-content:center;
      gap:6px;
      padding:40px 24px;
      text-align:center;
      color:var(--m-ink-muted, #948b82);
    }
    .thread-empty-icon{ font-size:36px; line-height:1; margin-bottom:8px; opacity:0.7; }
    .thread-empty-title{ font-size:17px; font-weight:650; color:var(--m-ink, #2c2825); }
    .thread-empty-sub{ font-size:14px; }
    .messages{
      flex:1;
      display:flex;
      flex-direction:column;
      min-height:0;
      overflow:hidden;
    }
    .message-list{
      flex:1;
      padding:16px;
      display:flex;
      flex-direction:column;
      gap:10px;
      overflow-y:auto;
      min-height:0;
      background:var(--m-paper, #f8f6f2);
    }
    .message-day{
      align-self:center;
      font-size:12px;
      font-weight:650;
      color:var(--m-ink-muted, #948b82);
      background:var(--m-canvas-muted, #f2f0ec);
      border:0.5px solid var(--m-border, #ddd8d1);
      border-radius:999px;
      padding:5px 12px;
      margin:6px 0;
    }
    /* —— iOS MessageBubble —— */
    .message{
      display:flex;
      width:100%;
      justify-content:flex-start;
    }
    .message.me{ justify-content:flex-end; }
    .bubble-col{
      display:flex;
      flex-direction:column;
      align-items:flex-start;
      gap:4px;
      max-width:min(78%, 340px);
      min-width:0;
    }
    .message.me .bubble-col{ align-items:flex-end; }
    .bubble{
      max-width:100%;
      background:var(--m-surface, #fefdfb);
      border:0.5px solid var(--m-border, #ddd8d1);
      border-radius:18px;
      padding:10px 14px;
      font-size:15px;
      line-height:1.4;
      color:var(--m-ink, #2c2825);
    }
    .message.me .bubble{
      background:var(--m-accent-bright, #7b6347);
      border-color:transparent;
      color:#fff;
    }
    .body{
      white-space:pre-wrap;
      word-break:break-word;
    }
    .call-log-row{
      display:flex;
      flex-wrap:wrap;
      align-items:center;
      justify-content:center;
      gap:10px;
      width:100%;
      padding:8px 0;
    }
    .call-log-line{
      flex:1;
      height:0.5px;
      background:var(--m-border, #ddd8d1);
      min-width:24px;
    }
    .call-log-pill{
      font-size:12px;
      font-weight:650;
      color:var(--m-ink-muted, #948b82);
      background:var(--m-canvas-muted, #f2f0ec);
      border-radius:999px;
      padding:6px 12px;
      max-width:70%;
      text-align:center;
    }
    .call-log-time{
      width:100%;
      text-align:center;
      font-size:11px;
      color:var(--m-ink-muted, #948b82);
    }
    .message-media{
      display:flex;
      flex-direction:column;
      gap:6px;
      max-width:220px;
    }
    .message.me .message-media{ align-items:flex-end; }
    .message-media img{
      display:block;
      width:100%;
      max-height:280px;
      min-height:120px;
      object-fit:cover;
      border-radius:14px;
      cursor:pointer;
      background:#0c0a09;
    }
    .message-media app-video-player{
      width:220px;
      max-width:100%;
      border-radius:12px;
      overflow:hidden;
      background:#000;
    }
    .message-media app-video-player ::ng-deep .video-shell{ max-height:none; }
    .message-media app-video-player ::ng-deep video{
      width:100%;
      height:100%;
      object-fit:contain;
    }
    .reaction-strip{ display:flex; gap:6px; }
    .reaction-chip{
      font-size:12px;
      padding:4px 8px;
      border-radius:999px;
      background:var(--m-canvas-muted, #f2f0ec);
      color:var(--m-ink, #2c2825);
    }
    .message-meta{
      display:flex;
      align-items:center;
      gap:6px;
      font-size:11px;
      color:var(--m-ink-muted, #948b82);
      padding:0 2px;
    }
    .message-time{ font-size:11px; }
    .message-edited{ font-weight:650; }
    .message-read{
      font-weight:500;
      color:var(--m-ink-muted, #948b82);
    }
    .message-tools{
      display:flex;
      flex-wrap:wrap;
      gap:10px;
      padding:0 2px;
      opacity:0.85;
    }
    .message-tools .tool{
      border:0;
      background:transparent;
      padding:0;
      font-size:12px;
      font-weight:650;
      color:var(--m-ink-muted, #948b82);
      cursor:pointer;
    }
    .message-tools .tool.on{ color:var(--m-ink, #2c2825); }
    .message-tools .tool.danger{ color:var(--m-danger, #ea000b); }
    .reply-preview{
      width:100%;
      max-width:220px;
      box-sizing:border-box;
      padding:8px 12px 8px 14px;
      border-radius:12px;
      background:var(--m-canvas-muted, #f2f0ec);
      position:relative;
      cursor:pointer;
    }
    .reply-preview::before{
      content:'';
      position:absolute;
      left:0;
      top:6px;
      bottom:6px;
      width:3px;
      border-radius:2px;
      background:var(--m-accent, #6b5841);
    }
    .reply-meta{
      font-size:11px;
      font-weight:650;
      color:var(--m-ink-muted, #948b82);
    }
    .reply-text{
      margin-top:2px;
      font-size:13px;
      color:var(--m-ink-secondary, #6b645d);
      display:-webkit-box;
      -webkit-line-clamp:2;
      -webkit-box-orient:vertical;
      overflow:hidden;
    }
    .message-edit{
      width:100%;
      display:flex;
      flex-direction:column;
      gap:8px;
    }
    .message-edit-input{
      width:100%;
      border-radius:12px;
      border:0.5px solid var(--m-border, #ddd8d1);
      padding:10px 12px;
      font:inherit;
      font-size:14px;
      resize:vertical;
      min-height:60px;
      background:var(--m-surface, #fefdfb);
      color:var(--m-ink, #2c2825);
      box-sizing:border-box;
    }
    .message-edit-actions{
      display:flex;
      justify-content:flex-end;
      gap:10px;
    }
    .message-edit-actions .ghost{
      border:0;
      background:none;
      font-size:13px;
      font-weight:650;
      color:var(--m-ink-muted, #948b82);
      cursor:pointer;
    }
    .message-edit-actions .save{
      border:0;
      border-radius:999px;
      padding:8px 14px;
      background:var(--m-accent-bright, #7b6347);
      color:#fff;
      font-size:13px;
      font-weight:650;
      cursor:pointer;
    }
    .message-highlight .bubble{
      box-shadow:0 0 0 2px color-mix(in srgb, var(--m-accent-bright, #7b6347) 45%, transparent);
    }
    @media (max-width: 600px){
      .message-media app-video-player ::ng-deep .video-shell{ max-height:240px; }
      .message-media app-video-player ::ng-deep video{ max-height:240px; }
    }
    /* —— iOS composerBar —— */
    .composer{
      position:sticky;
      bottom:0;
      z-index:5;
      display:flex;
      flex-direction:column;
      gap:10px;
      padding:12px 16px;
      border-top:0.5px solid var(--m-border, #ddd8d1);
      background:var(--m-surface, #fefdfb);
      padding-bottom:calc(12px + env(safe-area-inset-bottom));
    }
    .composer-reply{
      display:flex;
      align-items:flex-start;
      gap:10px;
      padding:0 2px;
    }
    .composer-reply-bar{
      width:2px;
      align-self:stretch;
      border-radius:1px;
      background:color-mix(in srgb, var(--m-accent, #6b5841) 45%, transparent);
      flex-shrink:0;
    }
    .composer-reply-copy{ flex:1; min-width:0; }
    .composer-reply-title{
      font-size:12px;
      font-weight:650;
      color:var(--m-ink, #2c2825);
    }
    .composer-reply-text{
      margin-top:2px;
      font-size:12px;
      color:var(--m-ink-secondary, #6b645d);
      white-space:nowrap;
      overflow:hidden;
      text-overflow:ellipsis;
    }
    .composer-reply-close{
      border:0;
      background:transparent;
      color:var(--m-accent, #6b5841);
      font-size:12px;
      font-weight:650;
      cursor:pointer;
      padding:0;
      flex-shrink:0;
    }
    .composer-row{
      display:flex;
      gap:10px;
      align-items:flex-end;
    }
    .composer-attach{
      width:36px;
      height:36px;
      border:0;
      border-radius:10px;
      background:transparent;
      color:var(--m-accent-bright, #7b6347);
      cursor:pointer;
      display:grid;
      place-items:center;
      flex-shrink:0;
      padding:0;
    }
    .composer-input{
      flex:1;
      min-width:0;
      border:0.5px solid var(--m-border, #ddd8d1);
      border-radius:8px;
      padding:12px;
      font-size:15px;
      font-family:inherit;
      background:var(--m-surface, #fefdfb);
      color:var(--m-ink, #2c2825);
      min-height:44px;
      max-height:120px;
      line-height:1.35;
      resize:none;
      overflow-y:auto;
      box-sizing:border-box;
    }
    .composer-send{
      width:44px;
      height:44px;
      min-width:44px;
      border:0;
      border-radius:999px;
      padding:0;
      background:var(--m-accent-bright, #7b6347);
      color:#fff;
      cursor:pointer;
      display:grid;
      place-items:center;
      flex-shrink:0;
    }
    .composer-send:disabled{
      background:var(--m-ink-muted, #948b82);
      opacity:0.85;
      cursor:not-allowed;
    }
    .send-busy{ font-size:16px; line-height:1; }
    .composer-preview{
      display:flex;
      align-items:center;
      gap:12px;
      background:var(--m-canvas-muted, #f2f0ec);
      border:0.5px solid var(--m-border, #ddd8d1);
      border-radius:12px;
      padding:8px;
    }
    .composer-preview img,
    .composer-preview video{
      width:120px;
      height:80px;
      object-fit:cover;
      border-radius:10px;
      background:#000;
    }
    .composer-clear{
      border:0;
      background:none;
      color:var(--m-danger, #ea000b);
      font-weight:650;
      font-size:14px;
      cursor:pointer;
    }
    .lightbox{
      position:fixed;
      inset:0;
      background:rgba(5,10,18,0.7);
      backdrop-filter:blur(6px);
      display:grid;
      place-items:center;
      z-index:100;
    }
    .lightbox-card{
      position:relative;
      max-width:min(92vw, 780px);
      max-height:80vh;
      background:rgba(255,255,255,0.95);
      border-radius:18px;
      padding:12px;
      box-shadow:0 20px 50px rgba(0,0,0,0.25);
    }
    .lightbox-frame{
      position:relative;
    }
    .lightbox-card img{
      width:100%;
      height:auto;
      max-height:70vh;
      display:block;
      border-radius:12px;
    }
    .lightbox-close{
      position:absolute;
      top:6px;
      right:6px;
      width:30px;
      height:30px;
      border-radius:50%;
      border:1px solid rgba(7,20,40,0.2);
      background:white;
      cursor:pointer;
      font-weight:800;
    }
    .call-overlay{
      position:fixed;
      inset:0;
      background:rgba(5,10,18,0.75);
      backdrop-filter:blur(10px);
      display:grid;
      place-items:center;
      z-index:120;
      padding:calc(16px + env(safe-area-inset-top)) 16px calc(16px + env(safe-area-inset-bottom));
    }
    .call-card{
      width:min(92vw, 520px);
      height:min(86svh, 680px);
      max-height:calc(100svh - 32px - env(safe-area-inset-top) - env(safe-area-inset-bottom));
      background:rgba(8,16,28,0.96);
      border-radius:24px;
      padding:18px;
      display:flex;
      flex-direction:column;
      color:#e8f1ff;
      box-shadow:0 24px 60px rgba(0,0,0,0.35);
      box-sizing:border-box;
    }
    .call-card.video{
      width:min(96vw, 720px);
      height:min(90svh, 720px);
    }
    .call-top{
      display:flex;
      align-items:center;
      gap:12px;
      margin-bottom:12px;
    }
    .call-logo{
      width:32px;
      height:32px;
      border-radius:10px;
      object-fit:cover;
      background:rgba(255,255,255,0.08);
    }
    .call-title{
      font-weight:700;
      font-size:16px;
    }
    .call-sub{
      font-size:12px;
      opacity:0.7;
    }
    .call-timer{
      margin-left:auto;
      font-size:12px;
      letter-spacing:0.12em;
      text-transform:uppercase;
      color:rgba(255,255,255,0.7);
    }
    .call-body{
      flex:1;
      position:relative;
      display:flex;
      align-items:center;
      justify-content:center;
      border-radius:18px;
      background:rgba(0,0,0,0.2);
      overflow:hidden;
    }
    .call-remote{
      width:100%;
      height:100%;
      object-fit:cover;
      background:#000;
    }
    .call-local{
      position:absolute;
      width:130px;
      height:96px;
      bottom:12px;
      right:12px;
      border-radius:12px;
      border:1px solid rgba(255,255,255,0.25);
      background:#000;
      object-fit:cover;
    }
    .call-avatar{
      width:120px;
      height:120px;
      border-radius:50%;
      display:grid;
      place-items:center;
      background:rgba(255,255,255,0.08);
      overflow:hidden;
      border:1px solid rgba(255,255,255,0.08);
      box-shadow:0 0 0 rgba(0,0,0,0);
      transition: box-shadow 200ms ease, transform 200ms ease;
    }
    .call-avatar.speaking{
      box-shadow:
        0 0 0 6px rgba(0,155,220,0.18),
        0 0 18px rgba(0,155,220,0.45);
      transform:scale(1.03);
    }
    .call-avatar img{
      width:100%;
      height:100%;
      object-fit:cover;
    }
    .call-controls{
      margin-top:14px;
      display:flex;
      gap:10px;
      justify-content:center;
      flex-wrap:wrap;
    }
    .call-action{
      border:0;
      border-radius:18px;
      padding:10px 16px;
      background:rgba(255,255,255,0.12);
      color:#eef6ff;
      font-weight:600;
      cursor:pointer;
    }
    .call-action.ghost{
      background:rgba(255,255,255,0.08);
    }
    .call-action.accept{
      background:#2f9d66;
      color:#fff;
    }
    .call-action.end{
      background:#d84c4c;
      color:#fff;
    }
    @media (min-width: 901px){
      :host{ height:100svh; }
      .wrap{
        padding:0;
        height:100%;
        background:var(--m-paper, #f8f6f2);
      }
      .card{ height:100%; }
      .layout{
        grid-template-columns:minmax(300px, 32vw) minmax(0, 1fr);
        max-width:none;
        width:100%;
        margin:0;
        border:0;
        background:var(--m-paper, #f8f6f2);
        height:100%;
      }
      .panel{
        border-right:0.5px solid var(--m-divider, #e2ded8);
        background:var(--m-paper, #f8f6f2);
        padding:0 0 12px;
        gap:2px;
      }
      .thread{ background:var(--m-paper, #f8f6f2); min-height:0; }
      .thread-header{
        background:var(--m-canvas, #f8f6f2);
        border-bottom:0.5px solid var(--m-divider, #e2ded8);
        padding:8px 16px;
        min-height:52px;
      }
      .message-list{ padding:16px 20px 20px; gap:12px; }
      .bubble-col{ max-width:min(62%, 420px); }
      .composer{ padding:12px 20px calc(12px + env(safe-area-inset-bottom)); }
    }
    @media (max-width: 900px){
      .wrap{ padding:0; }
      .layout{
        grid-template-columns:1fr;
        height:100%;
        gap:0;
      }
      .panel{
        max-height:none;
        overflow:auto;
        border-right:0;
      }
      .layout.thread-only .panel{ display:none; }
      .layout.thread-only{ height:100%; }
      .thread{ min-height:0; height:100%; }
      .messages, .message-list{ min-height:0; }
    }
    @media (max-width: 600px){
      .wrap{ padding:0; }
      .card{ padding:0; }
      .bubble-col{ max-width:min(86%, 340px); }
      .composer-send{
        width:44px;
        min-width:44px;
        height:44px;
      }
      .call-card{
        height:min(80svh, 600px);
        max-height:calc(100svh - 32px - env(safe-area-inset-top) - env(safe-area-inset-bottom));
      }
      .call-local{
        width:96px;
        height:72px;
      }
      .thread-actions{
        align-items:center;
        gap:6px;
      }
      .thread-header{
        flex-wrap:nowrap;
        align-items:center;
      }
      .thread-meta{
        min-width:0;
      }
      .thread-name{
        font-size:14px;
      }
    }
    `
  ],
})
export class MessagesPageComponent implements OnInit, OnDestroy {
  @ViewChild('mediaInput') mediaInput?: ElementRef<HTMLInputElement>;
  @ViewChild('messageInput') messageInput?: ElementRef<HTMLTextAreaElement>;
  @ViewChild('messageList') messageList?: ElementRef<HTMLDivElement>;
  @ViewChild('remoteVideo') remoteVideo?: ElementRef<HTMLVideoElement>;
  @ViewChild('localVideo') localVideo?: ElementRef<HTMLVideoElement>;
  conversations: Conversation[] = [];
  messages: Message[] = [];
  activeConversation: Conversation | null = null;
  activeConversationId: string | null = null;
  loadingConversations = false;
  loadingMessages = false;
  conversationError = '';
  messageError = '';
  messageDraft = '';
  messageBusy = false;
  messageMediaFile: File | null = null;
  messageMediaPreview = '';
  messageMediaType: 'image' | 'video' | null = null;
  messageMediaError = '';
  replyingTo: Message | null = null;
  lightboxUrl: string | null = null;
  meId: string | null = null;
  editingMessageId: string | null = null;
  editingDraft = '';
  editBusy = false;
  private pendingConversation: Conversation | null = null;
  private routeSub?: Subscription;
  private pendingSub?: Subscription;
  private callSignalSub?: Subscription;
  private callConnectedSub?: Subscription;
  private pollTimer: number | null = null;
  mobileThreadOnly = false;
  isNarrow = false;
  unreadConversationIds = new Set<string>();
  private messageNotifications: NotificationItem[] = [];
  callActive = false;
  callConnecting = false;
  callIncoming = false;
  callType: 'audio' | 'video' | null = null;
  callConversationId: string | null = null;
  callMuted = false;
  callCameraOff = false;
  callError = '';
  private callFromId: string | null = null;
  private incomingOffer:
    | {
        conversationId: string;
        from: string;
        callType: 'audio' | 'video';
        callId?: string | null;
        roomName?: string | null;
      }
    | null =
      null;
  private wsConnected = false;
  private localStream?: MediaStream;
  private remoteStream?: MediaStream;
  private livekitRoom?: any;
  private livekitLocalTracks: any[] = [];
  private livekitLoadPromise: Promise<void> | null = null;
  private livekitModule: any | null = null;
  private pendingCallType: 'audio' | 'video' | null = null;
  private pendingCallFrom: string | null = null;
  private pendingCallConversationId: string | null = null;
  private pendingCallId: string | null = null;
  private pendingCallRoom: string | null = null;
  private pendingCallAutoAccept = false;
  private awaitingOffer = false;
  private callSessionId: string | null = null;
  private callRoomName: string | null = null;
  private liveKitConnectGeneration = 0;
  private readonly callLogPrefix = '__call__|';
  private audioContext?: AudioContext;
  private audioAnalyser?: AnalyserNode;
  private audioData?: Uint8Array<ArrayBuffer>;
  private speakingRafId: number | null = null;
  callSpeaking = false;
  callTimerSeconds = 0;
  private callTimerId: number | null = null;
  private callDisconnectTimer: number | null = null;
  private callStartAt: number | null = null;
  private callLogSent = false;
  private destroyed = false;
  private readonly REACTION_PREFIX = '__react__|';
  private readonly REPLY_PREFIX = '__reply__|';
  private reactionsByMessage = new Map<string, { count: number; likedByMe: boolean }>();

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private auth: AuthService,
    private messagesService: MessagesService,
    private mediaService: MediaService,
    private notificationsService: NotificationsService,
    private push: PushService,
    private callService: CallService,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    this.updateViewportFlag();
    if (typeof window !== 'undefined') {
      window.addEventListener('resize', this.onViewportResize);
    }
    void this.push.syncIfGranted();
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;
    this.forceUi();
    this.wsConnected = this.callService.connected;
    this.callSignalSub = this.callService.signals$.subscribe((msg) => {
      void this.handleSignalMessage(msg);
    });
    this.callConnectedSub = this.callService.connected$.subscribe((connected) => {
      this.wsConnected = connected;
      this.forceUi();
    });

    const stashed = this.messagesService.getPendingConversation();
    const navState = (this.router.getCurrentNavigation()?.extras.state ?? history.state) as
      | { convo?: Conversation }
      | null;
    const pending = stashed ?? navState?.convo ?? null;
    if (pending) {
      this.pendingConversation = pending;
      this.activeConversation = pending;
      this.activeConversationId = pending.id;
      this.upsertConversation(pending);
      this.enterThreadView();
      this.forceUi();
      void this.loadMessages(pending.id, false);
    }

    this.routeSub = this.route.queryParamMap.subscribe((params) => {
      const convoId = params.get('c');
      const callParam = params.get('call');
      const fromParam = params.get('from');
      const callIdParam = params.get('callId');
      const roomParam = params.get('room');
      const acceptParam = params.get('accept');
      if (convoId && callParam) {
        this.pendingCallType = callParam === 'video' ? 'video' : 'audio';
        this.pendingCallFrom = fromParam;
        this.pendingCallConversationId = convoId;
        this.pendingCallId = callIdParam;
        this.pendingCallRoom = roomParam;
        this.pendingCallAutoAccept = acceptParam === '1';
      }
      if (!convoId) return;
      if (convoId !== this.activeConversationId) {
        void this.activateConversationById(convoId).then(() => this.maybeShowCallFromParams());
        return;
      }
      if (!this.messages.length) {
        void this.loadMessages(convoId, false);
      }
      this.maybeShowCallFromParams();
    });

    this.pendingSub = this.messagesService.pendingConversation$.subscribe((convo) => {
      if (!convo) return;
      this.pendingConversation = convo;
      this.activeConversation = convo;
      this.activeConversationId = convo.id;
      this.upsertConversation(convo);
      this.enterThreadView();
      this.forceUi();
      void this.loadMessages(convo.id, false);
    });

    await this.loadConversations();
    await this.refreshUnreadConversations();
    this.startPolling();
  }

  ngOnDestroy(): void {
    this.destroyed = true;
    if (typeof window !== 'undefined') {
      window.removeEventListener('resize', this.onViewportResize);
    }
    this.routeSub?.unsubscribe();
    this.pendingSub?.unsubscribe();
    this.callSignalSub?.unsubscribe();
    this.callConnectedSub?.unsubscribe();
    if (this.pollTimer) {
      window.clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    this.cleanupCall();
    this.clearMedia();
  }

  private onViewportResize = (): void => {
    this.updateViewportFlag();
    this.forceUi();
  };

  async loadConversations(selectId?: string | null): Promise<void> {
    this.loadingConversations = true;
    this.conversationError = '';
    this.forceUi();

    try {
      const serverConvos = await this.messagesService.listConversations();
      const pending = this.pendingConversation;
      const serverHasPending =
        !!pending && serverConvos.some((item) => item.id === pending.id);
      const merged = [...serverConvos];
      const seen = new Set(merged.map((item) => item.id));

      if (pending && !seen.has(pending.id)) {
        merged.unshift(pending);
        seen.add(pending.id);
      }

      if (this.activeConversation && !seen.has(this.activeConversation.id)) {
        merged.unshift(this.activeConversation);
        seen.add(this.activeConversation.id);
      }

      this.conversations = merged;

      if (serverHasPending) {
        this.pendingConversation = null;
        this.messagesService.clearPendingConversation();
      }
      const targetId = selectId ?? this.activeConversationId;
      if (targetId) {
        let convo = this.conversations.find((item) => item.id === targetId) ?? null;
        if (convo) {
          this.activeConversation = convo;
          this.activeConversationId = convo.id;
        } else if (this.pendingConversation?.id === targetId) {
          this.activeConversation = this.pendingConversation;
          this.activeConversationId = targetId;
        } else {
          const fetched = await this.fetchConversationById(targetId);
          if (fetched) {
            this.upsertConversation(fetched);
            this.activeConversation = fetched;
            this.activeConversationId = fetched.id;
            convo = fetched;
          }
        }
      }
      if (
        this.activeConversationId &&
        (!this.messages.length || this.messages[0]?.conversation_id !== this.activeConversationId)
      ) {
        void this.loadMessages(this.activeConversationId, true);
      }
    } catch (e: any) {
      this.conversationError = e?.message ?? String(e);
    } finally {
      this.loadingConversations = false;
      this.forceUi();
    }
  }

  private startPolling(): void {
    if (this.pollTimer) return;
    this.pollTimer = window.setInterval(() => {
      void this.loadConversations();
      void this.refreshUnreadConversations();
      if (this.activeConversationId) {
        void this.loadMessages(this.activeConversationId, true);
      }
    }, 6000);
  }

  get callUiOpen(): boolean {
    return this.callActive || this.callConnecting || this.callIncoming || !!this.callError;
  }

  canStartCall(): boolean {
    return !!(
      this.activeConversationId &&
      this.wsConnected &&
      !this.callActive &&
      !this.callConnecting &&
      !this.callIncoming
    );
  }

  callPeer(): PostAuthor | null {
    if (!this.activeConversation) return null;
    if (this.callFromId) {
      return (
        this.activeConversation.members.find((member) => member.user_id === this.callFromId) ??
        this.otherMember(this.activeConversation)
      );
    }
    return this.otherMember(this.activeConversation);
  }

  callPeerAvatar(): string {
    return this.callPeer()?.avatar_url ?? '';
  }

  callTitle(): string {
    const peer = this.callPeer();
    const name = peer ? this.displayNameFor(peer) : 'Member';
    const kind = this.callType === 'video' ? 'Video call' : 'Voice call';
    return `${kind} · ${name}`;
  }

  callStatusText(): string {
    if (this.callError) return this.callError;
    if (this.callIncoming) {
      return this.incomingOffer ? 'Incoming call' : 'Tap accept to call back';
    }
    if (this.callConnecting) return 'Connecting...';
    if (this.callActive) return 'In call';
    return '';
  }

  callTimerLabel(): string {
    if (!this.callStartAt) return '00:00';
    return this.formatDuration(this.callTimerSeconds);
  }

  private markCallActive(): void {
    if (!this.callStartAt) {
      this.callStartAt = Date.now();
    }
    this.startCallTimer();
  }

  private getCallLogMeta(): {
    conversationId: string | null;
    kind: 'audio' | 'video' | null;
    startedAt: number | null;
  } {
    return {
      conversationId: this.callConversationId,
      kind: this.callType,
      startedAt: this.callStartAt,
    };
  }

  private maybeShowCallFromParams(): void {
    if (!this.pendingCallType || !this.pendingCallConversationId) return;
    if (this.pendingCallConversationId !== this.activeConversationId) return;
    if (this.callActive || this.callConnecting || this.callIncoming) return;
    this.callType = this.pendingCallType;
    this.callConversationId = this.pendingCallConversationId;
    this.callFromId = this.pendingCallFrom;
    this.callSessionId = this.pendingCallId;
    this.callRoomName =
      this.pendingCallRoom ||
      (this.pendingCallId
        ? `call_${this.pendingCallConversationId}_${this.pendingCallId}`
        : this.pendingCallFrom
          ? `call_${this.pendingCallConversationId}_${this.pendingCallFrom}`
          : null);
    this.callError = '';
    const autoAccept = this.pendingCallAutoAccept;
    this.pendingCallType = null;
    this.pendingCallFrom = null;
    this.pendingCallConversationId = null;
    this.pendingCallId = null;
    this.pendingCallRoom = null;
    this.pendingCallAutoAccept = false;
    this.clearCallParams();

    if (autoAccept && this.callRoomName && this.callType) {
      this.incomingOffer = {
        conversationId: this.callConversationId,
        from: this.callFromId || '',
        callType: this.callType,
        callId: this.callSessionId,
        roomName: this.callRoomName,
      };
      void this.acceptCall();
      return;
    }

    this.callIncoming = true;
    this.callConnecting = false;
    this.callActive = false;
    this.forceUi();
  }

  private clearCallParams(): void {
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { call: null, from: null, callId: null, room: null, accept: null },
      queryParamsHandling: 'merge',
    });
  }

  private newCallSessionId(): string {
    try {
      return crypto.randomUUID();
    } catch {
      return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    }
  }

  private resolveCallRoomName(offer: {
    conversationId: string;
    from: string;
    callId?: string | null;
    roomName?: string | null;
  }): string {
    const explicit =
      typeof offer.roomName === 'string' ? offer.roomName.trim() : '';
    if (explicit) return explicit;
    if (this.callRoomName) return this.callRoomName;
    if (offer.callId) return `call_${offer.conversationId}_${offer.callId}`;
    // Prefer shared call session id over "from" so caller/callee join the same room.
    if (this.callSessionId) return `call_${offer.conversationId}_${this.callSessionId}`;
    return `call_${offer.conversationId}_${offer.from}`;
  }

  async startCall(type: 'audio' | 'video'): Promise<void> {
    if (!this.activeConversationId) {
      this.callError = 'Open a conversation first.';
      this.forceUi();
      return;
    }
    if (!this.wsConnected) {
      this.callError = 'Connecting to call service… try again in a moment.';
      this.forceUi();
      this.callService.reconnect();
      return;
    }
    if (!this.canStartCall()) return;
    if (this.callActive || this.callConnecting || this.callIncoming) {
      this.cleanupCall();
    }
    this.callType = type;
    this.callConversationId = this.activeConversationId;
    this.callSessionId = this.newCallSessionId();
    this.callRoomName = `call_${this.callConversationId}_${this.callSessionId}`;
    this.callConnecting = true;
    this.callIncoming = false;
    this.callActive = false;
    this.callFromId = this.meId;
    this.callError = '';
    this.callStartAt = null;
    this.callLogSent = false;
    this.forceUi();
    try {
      // Announce first so the peer has roomName/callId before we finish joining.
      this.sendSignal('call-offer', this.callConversationId, {
        callType: type,
        callId: this.callSessionId,
        roomName: this.callRoomName,
      });
      await this.ensureLiveKitConnected(type, this.callRoomName);
      this.callConnecting = true;
      this.forceUi();
    } catch (e: any) {
      this.callError = e?.message ?? 'Call failed.';
      this.callConnecting = false;
      this.callActive = false;
      this.forceUi();
    }
  }

  async acceptCall(): Promise<void> {
    if (!this.incomingOffer) {
      const type = this.callType ?? 'audio';
      if (this.callConversationId && this.activeConversationId !== this.callConversationId) {
        await this.activateConversationById(this.callConversationId);
      }
      if (this.callConversationId) {
        this.callConnecting = true;
        this.callIncoming = false;
        this.callActive = false;
        this.callError = '';
        this.callSessionId = null;
        this.awaitingOffer = true;
        this.sendSignal('call-accept', this.callConversationId, { callType: type, to: this.callFromId });
      }
      this.callService.clearIncomingCall();
      this.forceUi();
      return;
    }
    const offer = this.incomingOffer;
    this.callConversationId = offer.conversationId;
    this.callType = offer.callType;
    this.callFromId = offer.from;
    this.callSessionId = offer.callId ?? this.callSessionId;
    this.callIncoming = false;
    this.callConnecting = true;
    this.callActive = false;
    this.callError = '';
    this.callService.clearIncomingCall();
    this.callStartAt = null;
    this.callLogSent = false;
    this.awaitingOffer = false;
    this.forceUi();
    try {
      const roomName = this.resolveCallRoomName(offer);
      this.callRoomName = roomName;
      await this.ensureLiveKitConnected(offer.callType, roomName);
      this.sendSignal('call-accept', offer.conversationId, {
        callType: offer.callType,
        roomName,
      });
      this.incomingOffer = null;
    } catch (e: any) {
      this.callError = e?.message ?? 'Call failed.';
      this.callConnecting = false;
      this.callActive = false;
      this.forceUi();
    }
  }

  declineCall(): void {
    if (!this.incomingOffer) return;
    this.sendSignal('call-decline', this.incomingOffer.conversationId);
    this.callService.clearIncomingCall();
    this.cleanupCall();
  }

  toggleMute(): void {
    const next = !this.callMuted;
    if (this.livekitRoom) {
      void this.livekitRoom.localParticipant.setMicrophoneEnabled(!next);
    } else if (this.localStream) {
      this.localStream.getAudioTracks().forEach((track) => {
        track.enabled = !next;
      });
    }
    this.callMuted = next;
    this.forceUi();
  }

  toggleCamera(): void {
    const next = !this.callCameraOff;
    if (this.livekitRoom) {
      void this.livekitRoom.localParticipant.setCameraEnabled(!next);
    } else if (this.localStream) {
      this.localStream.getVideoTracks().forEach((track) => {
        track.enabled = !next;
      });
    }
    this.callCameraOff = next;
    this.forceUi();
  }

  endCall(): void {
    const meta = this.getCallLogMeta();
    const status = this.callActive || this.callStartAt ? 'ended' : 'missed';
    void this.sendCallLog(status, meta);
    this.cleanupCall(true, true);
  }

  private async sendCallLog(
    status: 'ended' | 'missed',
    meta: { conversationId: string | null; kind: 'audio' | 'video' | null; startedAt: number | null }
  ): Promise<void> {
    if (this.callLogSent) return;
    const conversationId = meta.conversationId;
    if (!conversationId) return;
    const kind: 'audio' | 'video' = meta.kind === 'video' ? 'video' : 'audio';
    const durationSeconds = meta.startedAt ? Math.round((Date.now() - meta.startedAt) / 1000) : 0;
    const body = this.buildCallLogBody(status, kind, durationSeconds);
    try {
      const sent = await this.messagesService.sendMessage(conversationId, body);
      if (sent) {
        this.messages = [...this.messages, sent];
        this.bumpConversation(sent);
        this.scrollToBottom();
        this.forceUi();
      }
    } catch {}
    this.callLogSent = true;
  }

  private sendSignal(type: string, conversationId: string | null, payload?: Record<string, any>): void {
    this.callService.sendSignal(type, conversationId, {
      from: this.meId,
      ...(this.callSessionId ? { callId: this.callSessionId } : {}),
      ...(payload ?? {}),
    });
  }

  private async handleSignalMessage(msg: CallSignal): Promise<void> {
    const type = String(msg?.type ?? '');
    const conversationId = String(msg?.conversationId ?? '');
    const from = String(msg?.from ?? '');
    const msgCallId = typeof (msg as any)?.callId === 'string' ? String((msg as any).callId) : '';
    const callIdMatches = this.callSessionId ? msgCallId === this.callSessionId : true;
    if (!type || !conversationId || !from || from === this.meId) return;

    if (type === 'call-offer') {
      const expectingOffer = this.awaitingOffer && conversationId === this.callConversationId;
      if (
        !expectingOffer &&
        (this.callActive ||
          this.callIncoming ||
          (this.callConnecting && this.callFromId && this.callFromId !== from))
      ) {
        this.sendSignal('call-busy', conversationId, { callId: msgCallId });
        return;
      }
      if (!expectingOffer && this.callConnecting && this.callFromId === this.meId) {
        this.cleanupCall(false);
      }
      const callType = msg.callType === 'video' ? 'video' : 'audio';
      const callId = msgCallId || null;
      if (callId) {
        this.callSessionId = callId;
      }
      const roomName = this.resolveCallRoomName({
        conversationId,
        from,
        callId,
        roomName:
          typeof (msg as any)?.roomName === 'string'
            ? String((msg as any).roomName)
            : null,
      });
      this.incomingOffer = { conversationId, from, callType, callId, roomName };
      this.awaitingOffer = false;
      if (this.callConnecting && (this.callFromId === from || expectingOffer)) {
        this.callIncoming = false;
        await this.acceptCall();
        return;
      }
      this.callConversationId = conversationId;
      this.callType = callType;
      this.callFromId = from;
      this.callIncoming = true;
      this.callConnecting = false;
      this.callActive = false;
      this.callStartAt = null;
      this.callLogSent = false;
      this.callService.clearIncomingCall();
      this.forceUi();
      if (conversationId !== this.activeConversationId) {
        await this.activateConversationById(conversationId);
      }
      return;
    }

    if (type === 'call-accept') {
      if (this.callFromId !== this.meId || !this.callConversationId) return;
      if (conversationId !== this.callConversationId) return;
      try {
        const callType = msg.callType === 'video' ? 'video' : (this.callType ?? 'audio');
        this.callType = callType;
        const roomName = this.resolveCallRoomName({
          conversationId,
          from,
          callId: msgCallId || this.callSessionId,
          roomName:
            typeof (msg as any)?.roomName === 'string'
              ? String((msg as any).roomName)
              : this.callRoomName,
        });
        this.callRoomName = roomName;
        await this.ensureLiveKitConnected(callType, roomName);
      } catch {}
      return;
    }

    if (conversationId !== this.callConversationId) return;

    if (type === 'call-decline' || type === 'call-busy') {
      if (!callIdMatches) return;
      if (this.callFromId === this.meId) {
        void this.sendCallLog('missed', this.getCallLogMeta());
      }
      this.cleanupCall();
      return;
    }

    if (type === 'call-end') {
      if (!callIdMatches) return;
      this.cleanupCall();
    }
  }

    private async ensureLiveKitConnected(callType: 'audio' | 'video', roomName: string): Promise<void> {
      if (this.livekitRoom && this.livekitRoom.name === roomName) return;
      await this.disconnectLiveKit();
      this.callMuted = false;
      this.callCameraOff = callType !== 'video';

      const urlBase = environment.livekitUrl;
      if (!urlBase) throw new Error('LiveKit URL not configured.');

      await this.ensureLiveKitLoaded();
      const LiveKit = this.livekitModule || (window as any).LiveKit;
      if (!LiveKit) throw new Error('LiveKit not loaded.');
    const { Room, RoomEvent, createLocalTracks } = LiveKit;

    let lastError: unknown = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await this.disconnectLiveKit();
        await new Promise((resolve) => setTimeout(resolve, 600));
      }

      const tokenInfo = await this.fetchLiveKitToken(roomName, attempt);
      const url = tokenInfo.url || urlBase;

    const room = new Room({ adaptiveStream: true, dynacast: true });
    this.livekitRoom = room;
    this.remoteStream = new MediaStream();

    room.on(RoomEvent.TrackSubscribed, (track: any) => {
      const mediaTrack = (track as any)?.mediaStreamTrack as MediaStreamTrack | undefined;
      if (!mediaTrack) return;
      if (!this.remoteStream) this.remoteStream = new MediaStream();
      if (!this.remoteStream.getTracks().some((t) => t.id === mediaTrack.id)) {
        this.remoteStream.addTrack(mediaTrack);
      }
      this.attachRemoteStream();
      if (!this.callActive) {
        this.callActive = true;
        this.callConnecting = false;
        this.markCallActive();
        this.clearDisconnectTimer();
        this.forceUi();
      }
    });

    room.on(RoomEvent.TrackUnsubscribed, (track: any) => {
      const mediaTrack = (track as any)?.mediaStreamTrack as MediaStreamTrack | undefined;
      if (!mediaTrack || !this.remoteStream) return;
      this.remoteStream.removeTrack(mediaTrack);
    });

    room.on(RoomEvent.ParticipantConnected, () => {
      if (!this.callActive) {
        this.callActive = true;
        this.callConnecting = false;
        this.markCallActive();
        this.clearDisconnectTimer();
        this.forceUi();
      }
    });

    room.on(RoomEvent.ParticipantDisconnected, () => {
      if (this.callActive) {
        this.startDisconnectTimer();
      }
    });

    room.on(RoomEvent.Disconnected, () => {
      if (!this.destroyed) {
        this.callError = this.callError || 'Call disconnected.';
        this.cleanupCall(false);
        this.forceUi();
      }
    });

    try {
      await room.connect(url, tokenInfo.token);
      this.callConnecting = true;
      this.callError = '';

      const tracks = await createLocalTracks({
        audio: true,
        video: callType === 'video',
      });
      this.livekitLocalTracks = tracks;
      this.localStream = new MediaStream();
      for (const track of tracks) {
        const mediaTrack = (track as any)?.mediaStreamTrack as MediaStreamTrack | undefined;
        if (mediaTrack) this.localStream.addTrack(mediaTrack);
        await room.localParticipant.publishTrack(track);
      }
      this.startVoiceDetection();
      this.forceUi();
      requestAnimationFrame(() => {
        this.attachLocalStream();
      });
      return;
    } catch (e) {
      lastError = e;
      try {
        room.removeAllListeners();
        await room.disconnect();
      } catch {}
      this.livekitRoom = undefined;
    }
    }

    throw lastError instanceof Error ? lastError : new Error('Could not join call room.');
  }

  private liveKitConnectInstance(attempt: number): string {
    this.liveKitConnectGeneration += 1;
    const base = this.callSessionId ?? `${Date.now()}`;
    return `${base}-${this.liveKitConnectGeneration}-${attempt}`;
  }

  private async fetchLiveKitToken(roomName: string, attempt = 0): Promise<{ token: string; url: string }> {
    const token = await this.auth.getAccessToken();
    if (!token) throw new Error('Missing auth token.');
    const res = await fetch(`${environment.apiBaseUrl}/livekit/token`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        room: roomName,
        instance: this.liveKitConnectInstance(attempt),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const msg = typeof data?.error === 'string' ? data.error : 'LiveKit auth failed.';
      throw new Error(msg);
    }
    const url = typeof data?.url === 'string' ? data.url : environment.livekitUrl;
    const lkToken = typeof data?.token === 'string' ? data.token : '';
    if (!lkToken) throw new Error('Missing LiveKit token.');
    return { token: lkToken, url: url ?? '' };
  } 

  private async disconnectLiveKit(): Promise<void> {
    if (this.livekitRoom) {
      try {
        this.livekitRoom.removeAllListeners();
        await this.livekitRoom.disconnect(true);
      } catch {}
      this.livekitRoom = undefined;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    if (this.livekitLocalTracks.length) {
      for (const track of this.livekitLocalTracks) {
        try {
          track.stop();
        } catch {}
      }
      this.livekitLocalTracks = [];
    }
  }

  private attachLocalStream(): void {
    if (!this.localStream || this.callType !== 'video') return;
    const video = this.localVideo?.nativeElement;
    if (!video) return;
    video.srcObject = this.localStream;
    void video.play().catch(() => {});
  }

  private remoteAudio?: HTMLAudioElement;

  private attachRemoteStream(): void {
    if (!this.remoteStream) return;
    if (this.callType === 'video') {
      const video = this.remoteVideo?.nativeElement;
      if (!video) return;
      video.srcObject = this.remoteStream;
      void video.play().catch(() => {});
      return;
    }
    if (!this.remoteAudio) {
      this.remoteAudio = new Audio();
      this.remoteAudio.autoplay = true;
    }
    this.remoteAudio.srcObject = this.remoteStream as unknown as MediaStream;
    void this.remoteAudio.play().catch(() => {});
  }

  private cleanupCall(resetError = true, notifyRemote = false): void {
    if (notifyRemote && this.callConversationId) {
      this.sendSignal('call-end', this.callConversationId);
    }
    if (resetError) this.callError = '';
    this.callActive = false;
    this.callConnecting = false;
    this.callIncoming = false;
    this.callType = null;
    this.callConversationId = null;
    this.callMuted = false;
    this.callCameraOff = false;
    this.callFromId = null;
    this.incomingOffer = null;
    this.callStartAt = null;
    this.callLogSent = false;
    this.callSpeaking = false;
    this.callTimerSeconds = 0;
    this.awaitingOffer = false;
    this.callSessionId = null;
    this.callRoomName = null;
    this.liveKitConnectGeneration = 0;
    this.stopCallTimer();
    this.clearDisconnectTimer();
    this.stopVoiceDetection();

    void this.disconnectLiveKit();

    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
      this.localStream = undefined;
    }
    if (this.remoteStream) {
      this.remoteStream.getTracks().forEach((track) => track.stop());
      this.remoteStream = undefined;
    }
    if (this.localVideo?.nativeElement) {
      this.localVideo.nativeElement.srcObject = null;
    }
    if (this.remoteVideo?.nativeElement) {
      this.remoteVideo.nativeElement.srcObject = null;
    }
    if (this.remoteAudio) {
      this.remoteAudio.srcObject = null;
    }
    this.forceUi();
  }

  private startCallTimer(): void {
    if (this.callTimerId) return;
    this.callTimerId = window.setInterval(() => {
      if (!this.callStartAt) {
        this.callTimerSeconds = 0;
      } else {
        this.callTimerSeconds = Math.max(0, Math.floor((Date.now() - this.callStartAt) / 1000));
      }
      this.forceUi();
    }, 1000);
  }

  private stopCallTimer(): void {
    if (!this.callTimerId) return;
    window.clearInterval(this.callTimerId);
    this.callTimerId = null;
  }

  private startDisconnectTimer(): void {
    if (this.callDisconnectTimer) return;
    this.callDisconnectTimer = window.setTimeout(() => {
      if (this.callActive) {
        if (this.callConversationId) {
          this.sendSignal('call-end', this.callConversationId);
        }
        this.cleanupCall();
      } else if (this.callConnecting) {
        this.cleanupCall();
      }
    }, 8000);
  }

  private clearDisconnectTimer(): void {
    if (!this.callDisconnectTimer) return;
    window.clearTimeout(this.callDisconnectTimer);
    this.callDisconnectTimer = null;
  }

  private startVoiceDetection(): void {
    if (!this.localStream || this.audioContext) return;
    const AudioCtx = (window as any).AudioContext || (window as any).webkitAudioContext;
    if (!AudioCtx) return;
    try {
      this.audioContext = new AudioCtx();
      const context = this.audioContext;
      if (!context) return;
      const source = context.createMediaStreamSource(this.localStream);
      this.audioAnalyser = context.createAnalyser();
      this.audioAnalyser.fftSize = 512;
      source.connect(this.audioAnalyser);
      this.audioData = new Uint8Array(this.audioAnalyser.fftSize);
      void context.resume().catch(() => {});
      const tick = () => {
        if (!this.audioAnalyser || !this.audioData) return;
        this.audioAnalyser.getByteTimeDomainData(this.audioData);
        let sum = 0;
        for (let i = 0; i < this.audioData.length; i += 1) {
          const sample = (this.audioData[i] - 128) / 128;
          sum += sample * sample;
        }
        const rms = Math.sqrt(sum / this.audioData.length);
        const speaking = rms > 0.03;
        if (speaking !== this.callSpeaking) {
          this.callSpeaking = speaking;
          this.forceUi();
        }
        this.speakingRafId = requestAnimationFrame(tick);
      };
      tick();
    } catch {
      this.stopVoiceDetection();
    }
  }

  private stopVoiceDetection(): void {
    if (this.speakingRafId) {
      cancelAnimationFrame(this.speakingRafId);
      this.speakingRafId = null;
    }
    if (this.audioAnalyser) {
      try { this.audioAnalyser.disconnect(); } catch {}
    }
    this.audioAnalyser = undefined;
    this.audioData = undefined;
    if (this.audioContext) {
      void this.audioContext.close().catch(() => {});
      this.audioContext = undefined;
    }
  }

  async selectConversation(convo: Conversation, syncUrl: boolean): Promise<void> {
    this.activeConversation = convo;
    this.activeConversationId = convo.id;
    this.enterThreadView();
    this.forceUi();
    if (syncUrl) {
      void this.router.navigate([], {
        relativeTo: this.route,
        queryParams: { c: convo.id },
        queryParamsHandling: 'merge',
      });
    }
    await this.loadMessages(convo.id, false);
    this.maybeShowCallFromParams();
    this.scrollToBottom();
    window.setTimeout(() => this.scrollToBottom(), 80);
  }

  private async activateConversationById(convoId: string): Promise<void> {
    if (!convoId) return;
    if (!this.conversations.length) {
      await this.loadConversations(convoId);
    }
    const convo = this.conversations.find((item) => item.id === convoId) ?? null;
    if (convo) {
      await this.selectConversation(convo, false);
      return;
    }
    if (this.pendingConversation?.id === convoId) {
      this.activeConversation = this.pendingConversation;
      this.activeConversationId = convoId;
      this.enterThreadView();
      this.forceUi();
      await this.loadMessages(convoId, false);
      this.scrollToBottom();
      window.setTimeout(() => this.scrollToBottom(), 80);
      return;
    }
    const fetched = await this.fetchConversationById(convoId);
    if (fetched) {
      this.upsertConversation(fetched);
      this.enterThreadView();
      this.forceUi();
      await this.selectConversation(fetched, false);
      return;
    }
    this.activeConversationId = convoId;
    this.enterThreadView();
    this.forceUi();
    await this.loadMessages(convoId, false);
    this.scrollToBottom();
    window.setTimeout(() => this.scrollToBottom(), 80);
  }

  private upsertConversation(convo: Conversation): void {
    const existingIndex = this.conversations.findIndex((item) => item.id === convo.id);
    if (existingIndex >= 0) return;
    this.conversations = [convo, ...this.conversations];
  }

  private async fetchConversationById(convoId: string): Promise<Conversation | null> {
    try {
      return await this.messagesService.getConversationById(convoId);
    } catch {
      return null;
    }
  }

  private async loadMessages(conversationId: string, silent: boolean): Promise<void> {
    if (!conversationId) return;
    if (!silent) {
      this.loadingMessages = true;
      this.messageError = '';
      this.forceUi();
    }
    const prevLastId = this.messages[this.messages.length - 1]?.id ?? null;
    let shouldScroll = false;
    try {
      const fetched = await this.messagesService.listMessages(conversationId, 300);
      if (silent) {
        this.messages = this.mergeMessages(conversationId, this.messages, fetched, 200);
      } else {
        this.messages = fetched;
      }
      this.rebuildReactions();
      const nextLastId = this.messages[this.messages.length - 1]?.id ?? null;
      shouldScroll = nextLastId !== prevLastId || !silent;
      if (!silent) {
        await this.markConversationNotificationsRead(conversationId);
      }
    } catch (e: any) {
      this.messageError = e?.message ?? String(e);
    } finally {
      this.loadingMessages = false;
      this.forceUi();
      if (shouldScroll) {
        this.scrollToBottom();
      }
    }
  }

  async sendMessage(): Promise<void> {
    if (!this.activeConversationId || this.messageBusy) return;
    let body = this.messageDraft.trim();
    if (!body && !this.messageMediaFile) return;
    if (this.replyingTo) {
      body = this.buildReplyBody(this.replyingTo, body);
    }

    this.messageBusy = true;
    this.messageError = '';
    this.messageMediaError = '';
    this.forceUi();

    try {
      let media:
        | { type: string; path: string; name?: string | null; mime?: string | null; size?: number | null }
        | undefined;
      if (this.messageMediaFile) {
        try {
          const uploaded = await this.mediaService.uploadMessageMedia(
            this.messageMediaFile,
            this.activeConversationId
          );
          const type = this.messageMediaFile.type.startsWith('video/') ? 'video' : 'image';
          media = {
            type,
            path: uploaded.path,
            name: uploaded.name,
            mime: uploaded.mime,
            size: uploaded.size,
          };
        } catch (uploadError: any) {
          this.messageMediaError =
            uploadError?.message ?? 'Upload failed. Check your bucket policy and file type.';
          this.messageBusy = false;
          this.forceUi();
          return;
        }
      }
      const sent = await this.messagesService.sendMessage(this.activeConversationId, body, media);
      this.messages = [...this.messages, sent];
      this.messageDraft = '';
      this.replyingTo = null;
      this.resetMessageInput();
      this.clearMedia();
      this.bumpConversation(sent);
      this.scrollToBottom();
    } catch (e: any) {
      this.messageError = e?.message ?? String(e);
    } finally {
      this.messageBusy = false;
      this.forceUi();
    }
  }

  canSendMessage(): boolean {
    return !!(this.messageDraft.trim() || this.messageMediaFile);
  }

  onMessageInput(event?: Event): void {
    const input = (event?.target as HTMLTextAreaElement | undefined) ?? this.messageInput?.nativeElement;
    if (!input) return;
    input.style.height = 'auto';
    const maxHeight = 160;
    const minHeight = 32;
    const next = Math.min(Math.max(input.scrollHeight, minHeight), maxHeight);
    input.style.height = `${next}px`;
    input.style.overflowY = input.scrollHeight > maxHeight ? 'auto' : 'hidden';
  }

  private scrollToBottom(retry = 0): void {
    const list = this.messageList?.nativeElement;
    if (!list) {
      if (retry < 2) {
        window.setTimeout(() => this.scrollToBottom(retry + 1), 60);
      }
      return;
    }
    const doScroll = () => {
      list.scrollTop = list.scrollHeight;
    };
    requestAnimationFrame(() => {
      doScroll();
      requestAnimationFrame(doScroll);
    });
    if (retry === 0) {
      window.setTimeout(doScroll, 0);
    }
  }

  private mergeMessages(
    conversationId: string,
    existing: Message[],
    incoming: Message[],
    maxItems: number
  ): Message[] {
    const map = new Map<string, Message>();
    for (const msg of existing) {
      if (!msg?.id || msg.conversation_id !== conversationId) continue;
      map.set(msg.id, msg);
    }
    for (const msg of incoming) {
      if (!msg?.id || msg.conversation_id !== conversationId) continue;
      map.set(msg.id, msg);
    }
    const merged = Array.from(map.values());
    merged.sort((a, b) => this.messageEpoch(a.created_at) - this.messageEpoch(b.created_at));
    if (merged.length > maxItems) return merged.slice(-maxItems);
    return merged;
  }

  private messageEpoch(value: string): number {
    if (!value) return 0;
    const asNumber = Number(value);
    if (Number.isFinite(asNumber)) return asNumber;
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  trackMessageById(index: number, message: Message): string | number {
    return message?.id ?? index;
  }

  triggerMediaPicker(): void {
    this.mediaInput?.nativeElement.click();
  }

  onMediaSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] ?? null;
    if (!file) return;
    const type = file.type || '';
    const allowedImage = ['image/png', 'image/jpeg', 'image/webp'];
    const allowedVideo = ['video/mp4', 'video/webm', 'video/quicktime'];
    if (!allowedImage.includes(type) && !allowedVideo.includes(type)) {
      this.messageMediaError = 'Only PNG/JPG/WebP images or MP4/WebM/MOV videos are supported.';
      input.value = '';
      this.forceUi();
      return;
    }
    this.clearMedia();
    this.messageMediaFile = file;
    this.messageMediaType = type.startsWith('video/') ? 'video' : 'image';
    this.messageMediaPreview = URL.createObjectURL(file);
    this.messageMediaError = '';
    input.value = '';
    this.forceUi();
  }

  clearMedia(): void {
    if (this.messageMediaPreview) {
      try { URL.revokeObjectURL(this.messageMediaPreview); } catch {}
    }
    this.messageMediaFile = null;
    this.messageMediaType = null;
    this.messageMediaPreview = '';
    this.messageMediaError = '';
  }

  openImageLightbox(url: string): void {
    this.lightboxUrl = url;
    this.forceUi();
  }

  closeImageLightbox(): void {
    this.lightboxUrl = null;
    this.forceUi();
  }

  messageText(message: Message): string {
    const body = String(message?.body ?? '');
    const trimmed = body.trim();
    if (!trimmed) return '';
    if (this.isReactionMessage(message)) return '';
    const callLog = this.parseCallLog(trimmed);
    if (callLog) return this.formatCallLog(callLog);
    const reply = this.parseReply(trimmed);
    if (reply) {
      const cleaned = reply.body.trim();
      if (cleaned) return cleaned;
      return '';
    }
    if (message?.id && trimmed === message.id) return '';
    if (this.looksLikeId(trimmed)) return '';
    if (this.stripTrailingMeta(trimmed) !== trimmed) {
      return this.stripTrailingMeta(trimmed);
    }
    return body;
  }

  startReply(message: Message): void {
    if (!message) return;
    this.replyingTo = message;
    this.forceUi();
  }

  cancelReply(): void {
    this.replyingTo = null;
    this.forceUi();
  }

  replyPreview(message: Message): { id: string; name: string; text: string } | null {
    const parsed = this.parseReply(String(message?.body ?? ''));
    if (!parsed) return null;
    const target = this.messages.find((m) => m.id === parsed.targetId) ?? null;
    const name = target ? this.displayNameFor(this.senderInfo(target)) : 'Message';
    let text = parsed.text || (target ? this.messageText(target) : '');
    if (!text && target?.media_type) {
      text = target.media_type === 'video' ? 'Video' : 'Photo';
    }
    if (!text) return null;
    return { id: parsed.targetId, name, text };
  }

  scrollToMessage(messageId: string): void {
    if (!messageId) return;
    const el = document.getElementById(`msg-${messageId}`);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      el.classList.add('message-highlight');
      window.setTimeout(() => el.classList.remove('message-highlight'), 900);
      return;
    }
    this.scrollToBottom();
  }

  replySnippet(message: Message | null): string {
    if (!message) return '';
    const text = this.messageText(message);
    if (text) return text;
    if (message.media_type === 'video') return 'Video';
    if (message.media_type === 'image') return 'Photo';
    return '';
  }

  isReactionMessage(message: Message): boolean {
    return !!this.parseReaction(String(message?.body ?? ''));
  }

  messageLikeCount(message: Message): number {
    const data = this.reactionsByMessage.get(message.id);
    return data?.count ?? 0;
  }

  isMessageLikedByMe(message: Message): boolean {
    const data = this.reactionsByMessage.get(message.id);
    return !!data?.likedByMe;
  }

  async toggleMessageLike(message: Message): Promise<void> {
    if (!this.activeConversationId || !message?.id) return;
    const liked = this.isMessageLikedByMe(message);
    const body = this.buildReactionBody(message.id, liked ? 0 : 1);
    try {
      const sent = await this.messagesService.sendMessage(this.activeConversationId, body);
      this.messages = [...this.messages, sent];
      this.bumpConversation(sent);
      this.rebuildReactions();
      this.forceUi();
    } catch {}
  }

  isCallLogMessage(message: Message): boolean {
    const body = String(message?.body ?? '').trim();
    return body.includes(this.callLogPrefix) || !!this.parseCallLog(body);
  }

  private buildCallLogBody(
    status: 'ended' | 'missed',
    kind: 'audio' | 'video',
    durationSeconds: number
  ): string {
    const duration = Math.max(0, Math.floor(durationSeconds));
    return `${this.callLogPrefix}status=${status}|kind=${kind}|duration=${duration}`;
  }

  private parseCallLog(body: string): { status: string; kind: 'audio' | 'video'; duration: number } | null {
    const cleaned = body.replace(/\uFEFF/g, '').trim();
    const unquoted =
      (cleaned.startsWith('"') && cleaned.endsWith('"')) || (cleaned.startsWith("'") && cleaned.endsWith("'"))
        ? cleaned.slice(1, -1)
        : cleaned;
    const match = unquoted.match(/__call__\|status=([^|]+)\|kind=(audio|video)\|duration=([0-9]+)/i);
    if (!match) return null;
    const status = String(match[1] ?? '').trim().toLowerCase();
    const kind = match[2] === 'video' ? 'video' : 'audio';
    const duration = Number(match[3] ?? 0);
    if (!status) return null;
    return {
      status,
      kind,
      duration: Number.isFinite(duration) ? duration : 0,
    };
  }

  private buildReplyBody(target: Message, body: string): string {
    const targetId = target?.id ?? '';
    const text = this.messageText(target) || '';
    const encoded = this.encodeBase64(text.slice(0, 160));
    return `${this.REPLY_PREFIX}id=${targetId}|text=${encoded}||${body}`;
  }

  private parseReply(body: string): { targetId: string; text: string; body: string } | null {
    const trimmed = String(body ?? '').trim();
    if (!trimmed.startsWith(this.REPLY_PREFIX)) return null;
    const parts = trimmed.split('||');
    const meta = parts[0] ?? '';
    const rest = parts.slice(1).join('||');
    const idMatch = meta.match(/id=([^|]+)/i);
    const textMatch = meta.match(/text=([^|]+)/i);
    const targetId = idMatch ? String(idMatch[1]) : '';
    const text = textMatch ? this.decodeBase64(String(textMatch[1])) : '';
    return { targetId, text, body: rest };
  }

  private buildReactionBody(targetId: string, state: 0 | 1): string {
    return `${this.REACTION_PREFIX}target=${targetId}|emoji=❤|state=${state}`;
  }

  private parseReaction(body: string): { targetId: string; emoji: string; state: number } | null {
    const trimmed = String(body ?? '').trim();
    if (!trimmed.startsWith(this.REACTION_PREFIX)) return null;
    const targetMatch = trimmed.match(/target=([^|]+)/i);
    const emojiMatch = trimmed.match(/emoji=([^|]+)/i);
    const stateMatch = trimmed.match(/state=([01])/i);
    if (!targetMatch) return null;
    return {
      targetId: String(targetMatch[1]),
      emoji: emojiMatch ? String(emojiMatch[1]) : '❤',
      state: stateMatch ? Number(stateMatch[1]) : 1,
    };
  }

  private rebuildReactions(): void {
    const perMessage = new Map<string, Map<string, number>>();
    for (const msg of this.messages) {
      const reaction = this.parseReaction(msg.body);
      if (!reaction) continue;
      const targetId = reaction.targetId;
      const senderId = msg.sender_id || '';
      if (!targetId || !senderId) continue;
      if (!perMessage.has(targetId)) perMessage.set(targetId, new Map());
      perMessage.get(targetId)!.set(senderId, reaction.state);
    }
    const summary = new Map<string, { count: number; likedByMe: boolean }>();
    for (const [targetId, states] of perMessage.entries()) {
      let count = 0;
      let likedByMe = false;
      for (const [userId, state] of states.entries()) {
        if (state === 1) count += 1;
        if (userId === this.meId && state === 1) likedByMe = true;
      }
      summary.set(targetId, { count, likedByMe });
    }
    this.reactionsByMessage = summary;
  }

  private encodeBase64(value: string): string {
    try {
      return btoa(unescape(encodeURIComponent(value)));
    } catch {
      return '';
    }
  }

  private decodeBase64(value: string): string {
    try {
      return decodeURIComponent(escape(atob(value)));
    } catch {
      return '';
    }
  }

  private formatCallLog(log: { status: string; kind: 'audio' | 'video'; duration: number }): string {
    const kindLabel = log.kind === 'video' ? 'Video call' : 'Voice call';
    let label = '';
    if (log.status === 'ended') {
      label = `${kindLabel} ended`;
      if (log.duration > 0) {
        label += ` (${this.formatDuration(log.duration)})`;
      }
      return label;
    }
    if (log.status === 'missed') {
      return `Missed ${kindLabel}`;
    }
    if (log.status === 'busy') {
      return `Missed ${kindLabel}`;
    }
    if (log.status === 'declined') {
      return `${kindLabel} declined`;
    }
    return `${kindLabel} call`;
  }

  private formatDuration(totalSeconds: number): string {
    const seconds = Math.max(0, Math.floor(totalSeconds));
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }
    return `${minutes}:${String(secs).padStart(2, '0')}`;
  }

  private stripTrailingMeta(value: string): string {
    const parts = value.split(/\s+/).filter(Boolean);
    if (parts.length < 2) return value;
    const last = parts[parts.length - 1];
    if (this.looksLikeId(last)) {
      return parts.slice(0, -1).join(' ');
    }
    return value;
  }

  private resetMessageInput(): void {
    const input = this.messageInput?.nativeElement;
    if (!input) return;
    const minHeight = 32;
    input.style.height = `${minHeight}px`;
    input.style.overflowY = 'hidden';
  }

  conversationSnippet(convo: Conversation): string {
    const last = convo.last_message;
    if (!last) return 'Start a conversation';
    const body = String(last.body || '').trim();
    const reaction = this.parseReaction(body);
    if (reaction) return 'Liked a message';
    const callLog = this.parseCallLog(body);
    if (callLog) return this.formatCallLog(callLog);
    const reply = this.parseReply(body);
    if (reply) {
      const cleaned = reply.body.trim();
      if (cleaned) return cleaned;
    }
    if (body && !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body)) {
      return body;
    }
    if (last.media_type === 'video') return 'Video';
    if (last.media_type === 'image') return 'Photo';
    return 'Media message';
  }

  private bumpConversation(sent: Message): void {
    const convoId = sent.conversation_id;
    const idx = this.conversations.findIndex((c) => c.id === convoId);
    if (idx < 0) return;
    const updated = {
      ...this.conversations[idx],
      last_message: sent,
      last_message_at: sent.created_at,
    };
    const next = [...this.conversations];
    next.splice(idx, 1);
    this.conversations = [updated, ...next];
    this.activeConversation = updated;
    this.forceUi();
  }

  otherMember(convo: Conversation | null): PostAuthor | null {
    if (!convo) return null;
    if (!this.meId) return convo.members[0] ?? null;
    return convo.members.find((member) => member.user_id !== this.meId) ?? convo.members[0] ?? null;
  }

  displayNameFor(user: PostAuthor | null | undefined): string {
    if (!user) return 'Conversation';
    const display =
      this.cleanDisplayValue(user.display_name) || this.cleanDisplayValue(user.username);
    return display || 'Member';
  }

  displayHandleFor(user: PostAuthor | null | undefined): string {
    const handle = this.cleanDisplayValue(user?.username);
    if (!handle) return '';
    return `@${handle}`;
  }

  isConversationUnread(convo: Conversation): boolean {
    return this.unreadConversationIds.has(convo.id);
  }

  get messagesBadgeCount(): number {
    return this.unreadConversationIds.size;
  }

  private async refreshUnreadConversations(): Promise<void> {
    if (!this.meId) {
      this.messageNotifications = [];
      this.unreadConversationIds.clear();
      this.forceUi();
      return;
    }

    try {
      const { notifications } = await this.notificationsService.list(80);
      const unread = (notifications ?? []).filter(
        (notif) =>
          !notif.read_at &&
          this.isMessageNotification(notif) &&
          typeof notif.entity_id === 'string'
      );
      this.messageNotifications = unread;
      this.unreadConversationIds = new Set(unread.map((notif) => String(notif.entity_id)));
    } catch {}

    this.forceUi();
  }

  private async markConversationNotificationsRead(convoId: string): Promise<void> {
    if (!convoId || !this.messageNotifications.length) {
      this.unreadConversationIds.delete(convoId);
      return;
    }
    const pending = this.messageNotifications.filter((notif) => notif.entity_id === convoId);
    if (!pending.length) {
      this.unreadConversationIds.delete(convoId);
      this.forceUi();
      return;
    }
    try {
      await Promise.all(pending.map((notif) => this.notificationsService.markRead(notif.id)));
    } catch {}
    this.messageNotifications = this.messageNotifications.filter(
      (notif) => notif.entity_id !== convoId
    );
    this.unreadConversationIds.delete(convoId);
    this.forceUi();
  }

  private isMessageNotification(notif: NotificationItem): boolean {
    return String(notif?.type ?? '').toLowerCase() === 'message';
  }

  senderInfo(message: Message): PostAuthor | null {
    if (message.sender) return message.sender;
    const convo = this.activeConversation;
    if (!convo) return null;
    return convo.members.find((member) => member.user_id === message.sender_id) ?? null;
  }

  senderAvatarUrl(message: Message): string {
    return this.senderInfo(message)?.avatar_url ?? '';
  }

  private cleanDisplayValue(value?: string | null): string {
    const trimmed = String(value ?? '').trim();
    if (!trimmed) return '';
    if (this.looksLikeId(trimmed)) return '';
    return trimmed;
  }

  private looksLikeId(value: string): boolean {
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
      return true;
    }
    if (/^\d{8,}$/.test(value)) {
      return true;
    }
    return false;
  }

  initialsFor(user: PostAuthor | null | undefined): string {
    const name = this.displayNameFor(user);
    const parts = name.split(/\s+/).filter(Boolean);
    const a = parts[0]?.[0] ?? 'M';
    const b = parts.length > 1 ? parts[parts.length - 1]?.[0] ?? '' : '';
    return (a + b).toUpperCase();
  }

  formatTime(value?: string | null): string {
    if (!value) return '';
    const raw = String(value).trim();
    const parsed = this.parseTimestamp(raw);
    if (Number.isNaN(parsed.getTime())) return '';
    return parsed.toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  formatTimestamp(value: string): string {
    const raw = String(value ?? '').trim();
    const parsed = this.parseTimestamp(raw);
    if (Number.isNaN(parsed.getTime())) return '';
    return parsed.toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  formatDayLabel(value: string): string {
    const parsed = this.parseTimestamp(String(value ?? '').trim());
    if (Number.isNaN(parsed.getTime())) return String(value ?? '');
    const now = new Date();
    const sameYear = parsed.getFullYear() === now.getFullYear();
    const sameDay =
      parsed.getFullYear() === now.getFullYear() &&
      parsed.getMonth() === now.getMonth() &&
      parsed.getDate() === now.getDate();
    if (sameDay) return 'Today';
    const yesterday = new Date(now);
    yesterday.setDate(now.getDate() - 1);
    const isYesterday =
      parsed.getFullYear() === yesterday.getFullYear() &&
      parsed.getMonth() === yesterday.getMonth() &&
      parsed.getDate() === yesterday.getDate();
    if (isYesterday) return 'Yesterday';
    return parsed.toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      ...(sameYear ? {} : { year: 'numeric' }),
    });
  }

  showDaySeparator(index: number): boolean {
    if (!this.messages.length || index < 0) return false;
    if (index === 0) return true;
    const current = this.dayKey(this.messages[index]?.created_at);
    const previous = this.dayKey(this.messages[index - 1]?.created_at);
    return current !== previous;
  }

  showDaySeparatorVisible(index: number): boolean {
    if (!this.messages.length || index < 0) return false;
    const currentMsg = this.messages[index];
    if (!currentMsg || this.isReactionMessage(currentMsg)) return false;
    let prevIdx = index - 1;
    while (prevIdx >= 0) {
      const prevMsg = this.messages[prevIdx];
      if (prevMsg && !this.isReactionMessage(prevMsg)) {
        const current = this.dayKey(currentMsg.created_at);
        const previous = this.dayKey(prevMsg.created_at);
        return current !== previous;
      }
      prevIdx -= 1;
    }
    return true;
  }

  messageStatus(message: Message): 'sent' | 'read' | null {
    if (!this.meId || message.sender_id !== this.meId) return null;
    const other = this.otherMember(this.activeConversation);
    if (!other) return 'sent';
    const lastRead = other.last_read_at ? this.parseTimestamp(other.last_read_at).getTime() : 0;
    const created = this.parseTimestamp(message.created_at).getTime();
    if (lastRead && created && lastRead >= created) return 'read';
    return 'sent';
  }

  statusGlyph(status: 'sent' | 'read'): string {
    return status === 'read' ? '&#10003;&#10003;' : '&#10003;';
  }

  isEdited(message: Message): boolean {
    if (!message?.updated_at) return false;
    const created = this.parseTimestamp(message.created_at).getTime();
    const updated = this.parseTimestamp(message.updated_at).getTime();
    if (!created || !updated) return false;
    return updated > created + 1000;
  }

  isEditing(message: Message): boolean {
    return !!message && this.editingMessageId === message.id;
  }

  startEditMessage(message: Message): void {
    if (!this.meId || message.sender_id !== this.meId) return;
    if (this.isCallLogMessage(message)) return;
    const body = String(message.body ?? '').trim();
    if (!body) return;
    this.editingMessageId = message.id;
    this.editingDraft = body;
    this.forceUi();
  }

  cancelEditMessage(): void {
    this.editingMessageId = null;
    this.editingDraft = '';
    this.editBusy = false;
    this.forceUi();
  }

  async saveEditMessage(message: Message): Promise<void> {
    if (!this.editingMessageId || this.editBusy) return;
    if (!this.meId || message.sender_id !== this.meId) return;
    const body = this.editingDraft.trim();
    if (!body) return;
    this.editBusy = true;
    this.messageError = '';
    this.forceUi();
    try {
      const updated = await this.messagesService.updateMessage(message.id, body);
      this.messages = this.messages.map((item) => (item.id === message.id ? updated : item));
      this.editingMessageId = null;
      this.editingDraft = '';
      this.bumpConversation(updated);
      await this.loadConversations(this.activeConversationId);
    } catch (e: any) {
      this.messageError = e?.message ?? String(e);
    } finally {
      this.editBusy = false;
      this.forceUi();
    }
  }

  async deleteMessage(message: Message): Promise<void> {
    if (!this.meId || message.sender_id !== this.meId) return;
    const confirmed = typeof window !== 'undefined' ? window.confirm('Delete this message?') : true;
    if (!confirmed) return;
    this.messageError = '';
    this.forceUi();
    try {
      const deleted = await this.messagesService.deleteMessage(message.id);
      if (!deleted) return;
      this.messages = this.messages.filter((item) => item.id !== message.id);
      await this.loadConversations(this.activeConversationId);
    } catch (e: any) {
      this.messageError = e?.message ?? String(e);
    } finally {
      this.forceUi();
    }
  }

  private parseTimestamp(value: string): Date {
    if (!value) return new Date('');
    if (/^\d{10,}$/.test(value)) {
      const numeric = Number(value);
      const ms = value.length === 10 ? numeric * 1000 : numeric;
      return new Date(ms);
    }
    return new Date(value);
  }

  private dayKey(value?: string | null): string {
    const parsed = this.parseTimestamp(String(value ?? '').trim());
    if (Number.isNaN(parsed.getTime())) return '';
    const year = parsed.getFullYear();
    const month = String(parsed.getMonth() + 1).padStart(2, '0');
    const day = String(parsed.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private enterThreadView(): void {
    if (typeof window === 'undefined') return;
    // Only stack list/thread on true phone widths. Desktop keeps both panes.
    this.mobileThreadOnly = window.innerWidth < 900;
    this.updateViewportFlag();
    this.forceUi();
  }

  showConversationList(): void {
    this.mobileThreadOnly = false;
    this.updateViewportFlag();
    this.forceUi();
  }

  private updateViewportFlag(): void {
    if (typeof window === 'undefined') return;
    const narrow = window.innerWidth < 900;
    this.isNarrow = narrow;
    // Leaving phone width → always show list again
    if (!narrow) {
      this.mobileThreadOnly = false;
    }
  }

  private ensureLiveKitLoaded(): Promise<void> {
    if (this.livekitModule || (window as any).LiveKit || (window as any).livekit) {
      this.livekitModule = this.livekitModule || (window as any).LiveKit || (window as any).livekit;
      return Promise.resolve();
    }
    if (this.livekitLoadPromise) return this.livekitLoadPromise;

    this.livekitLoadPromise = (async () => {
      try {
        const mod = await import('livekit-client');
        this.livekitModule = mod;
        (window as any).LiveKit = mod;
        return;
      } catch {}

      return new Promise<void>((resolve, reject) => {
        const existing = document.querySelector('script[data-livekit]') as HTMLScriptElement | null;
        const pickGlobal = () =>
          (window as any).LiveKit || (window as any).livekit || (window as any).Livekit;
        if (existing) {
          const global = pickGlobal();
          if (global) {
            this.livekitModule = global;
            resolve();
            return;
          }
        }

        const script = document.createElement('script');
        script.src = 'https://unpkg.com/livekit-client@2.17.1/dist/livekit-client.umd.min.js';
        script.async = true;
        script.defer = true;
        script.dataset['livekit'] = '1';
        script.onload = () => {
          const global = pickGlobal();
          if (global) {
            this.livekitModule = global;
            resolve();
            return;
          }
          reject(new Error('LiveKit not loaded.'));
        };
        script.onerror = () => {
          const fallback = document.createElement('script');
          fallback.src =
            'https://cdn.jsdelivr.net/npm/livekit-client@2.17.1/dist/livekit-client.umd.min.js';
          fallback.async = true;
          fallback.defer = true;
          fallback.dataset['livekit'] = '1-fallback';
          fallback.onload = () => {
            const global = pickGlobal();
            if (global) {
              this.livekitModule = global;
              resolve();
              return;
            }
            reject(new Error('LiveKit not loaded.'));
          };
          fallback.onerror = () => reject(new Error('LiveKit not loaded.'));
          document.head.appendChild(fallback);
        };
        document.head.appendChild(script);
      });
    })();

    return this.livekitLoadPromise;
  }

  private forceUi(): void {
    this.zone.run(() => this.cdr.detectChanges());
  }

  goBack(): void {
    void this.router.navigate(['/globe']);
  }

  /** iOS MessagesView compose → People */
  goPeople(): void {
    void this.router.navigate(['/people']);
  }

  goHome(): void {
    void this.router.navigate(['/globe']);
  }

  /**
   * iOS: show the word “Read” only under the latest of my messages
   * the peer has read — no tick glyphs.
   */
  isLastReadOwn(message: Message): boolean {
    if (!this.meId || message.sender_id !== this.meId) return false;
    if (this.isCallLogMessage(message)) return false;
    if (String(message.id || '').startsWith('pending-')) return false;
    const other = this.otherMember(this.activeConversation);
    const lastRead = other?.last_read_at
      ? this.parseTimestamp(other.last_read_at).getTime()
      : 0;
    if (!lastRead) return false;
    const created = this.parseTimestamp(message.created_at).getTime();
    if (!created || lastRead + 2000 < created) return false;

    let lastId: string | null = null;
    for (const m of this.messages) {
      if (this.isReactionMessage(m) || this.isCallLogMessage(m)) continue;
      if (m.sender_id !== this.meId) continue;
      if (String(m.id || '').startsWith('pending-')) continue;
      const t = this.parseTimestamp(m.created_at).getTime();
      if (t && lastRead + 2000 >= t) lastId = m.id;
    }
    return lastId === message.id;
  }

  openNotifications(): void {
    void this.router.navigate(['/globe'], { queryParams: { panel: 'notifications' } });
  }

  openSearch(): void {
    void this.router.navigate(['/search']);
  }
}
