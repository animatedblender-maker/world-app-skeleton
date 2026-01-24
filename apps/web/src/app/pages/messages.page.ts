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
import { Conversation, Message } from '../core/models/messages.model';
import { PostAuthor } from '../core/models/post.model';
import { VideoPlayerComponent } from '../components/video-player.component';
import { environment } from '../../envirnoments/envirnoment';

@Component({
  selector: 'app-messages-page',
  standalone: true,
  imports: [CommonModule, FormsModule, VideoPlayerComponent],
  template: `
    <div class="wrap">
      <div class="ocean-gradient" aria-hidden="true"></div>
      <div class="ocean-dots" aria-hidden="true"></div>
      <div class="noise" aria-hidden="true"></div>

      <div class="card">
        <button class="ghost-link back-link" type="button" (click)="goBack()">Back</button>
        <div class="layout" [class.thread-only]="mobileThreadOnly">
          <aside class="panel">
            <div class="panel-title">Messages</div>
            <div class="status" *ngIf="loadingConversations">Loading conversations...</div>
            <div class="status error" *ngIf="conversationError">{{ conversationError }}</div>
            <div class="status" *ngIf="!loadingConversations && !conversations.length">
              No conversations yet.
            </div>
            <button
              class="conversation"
              type="button"
              *ngFor="let convo of conversations"
              [class.active]="convo.id === activeConversationId"
              (click)="selectConversation(convo, true)"
            >
              <div class="avatar">
                <img
                  *ngIf="otherMember(convo)?.avatar_url"
                  [src]="otherMember(convo)?.avatar_url"
                  alt="avatar"
                />
                <div class="initials" *ngIf="!otherMember(convo)?.avatar_url">
                  {{ initialsFor(otherMember(convo)) }}
                </div>
              </div>
              <div class="meta">
                <div class="name">{{ displayNameFor(otherMember(convo)) }}</div>
                <div class="snippet">{{ conversationSnippet(convo) }}</div>
              </div>
              <div class="time">{{ formatTime(convo.last_message_at || convo.updated_at) }}</div>
              <span class="conversation-unread" *ngIf="isConversationUnread(convo)"></span>
            </button>
          </aside>

          <section class="thread">
            <div class="thread-header" *ngIf="activeConversation; else emptyThread">
              <button
                class="thread-back"
                type="button"
                *ngIf="mobileThreadOnly"
                (click)="showConversationList()"
              >
                Chats
              </button>
              <div class="avatar large">
                <img
                  *ngIf="otherMember(activeConversation)?.avatar_url"
                  [src]="otherMember(activeConversation)?.avatar_url"
                  alt="avatar"
                />
                <div class="initials" *ngIf="!otherMember(activeConversation)?.avatar_url">
                  {{ initialsFor(otherMember(activeConversation)) }}
                </div>
              </div>
              <div>
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
                  aria-label="Start voice call"
                >
                  &#x260E;
                </button>
                <button
                  class="call-btn"
                  type="button"
                  [disabled]="!canStartCall()"
                  (click)="startCall('video')"
                  aria-label="Start video call"
                >
                  &#x1F4F9;
                </button>
              </div>
            </div>

            <ng-template #emptyThread>
              <div class="thread-empty">Select a conversation to start chatting.</div>
            </ng-template>

            <div class="messages" *ngIf="activeConversation">
              <div class="status" *ngIf="loadingMessages">Loading messages...</div>
              <div class="status error" *ngIf="messageError">{{ messageError }}</div>
              <div class="message-list" *ngIf="!loadingMessages" #messageList>
                <ng-container *ngFor="let message of messages; let i = index">
                  <div class="message-day" *ngIf="showDaySeparator(i)">
                    {{ formatDayLabel(message.created_at) }}
                  </div>
                  <div class="message" [class.me]="message.sender_id === meId">
                    <div class="msg-avatar">
                      <img
                        *ngIf="senderAvatarUrl(message)"
                        [src]="senderAvatarUrl(message)"
                        alt="avatar"
                      />
                      <div class="initials" *ngIf="!senderAvatarUrl(message)">
                        {{ initialsFor(senderInfo(message)) }}
                      </div>
                    </div>
                    <div class="bubble">
                      <div class="body" *ngIf="messageText(message) as text">{{ text }}</div>
                      <div class="message-media" *ngIf="message.media_type && message.media_url">
                        <img
                          *ngIf="message.media_type === 'image'"
                          [src]="message.media_url"
                          alt="message media"
                          (click)="openImageLightbox(message.media_url)"
                        />
                        <app-video-player
                          *ngIf="message.media_type === 'video'"
                          [src]="message.media_url"
                        ></app-video-player>
                        <a
                          class="media-download"
                          [href]="message.media_url"
                          [attr.download]="message.media_name || 'message-media'"
                          target="_blank"
                          rel="noopener"
                        >
                          Download
                        </a>
                      </div>
                      <div class="message-meta">
  <span class="message-time">
    {{ formatTimestamp(message.created_at) }}
    <span class="message-date">{{ formatDayLabel(message.created_at) }}</span>
  </span>
  <span class="message-edited" *ngIf="isEdited(message)">edited</span>
  <span class="message-status" *ngIf="messageStatus(message) as status" [class.read]="status === 'read'" [innerHTML]="statusGlyph(status)"></span>
</div>
<div class="message-actions" *ngIf="message.sender_id === meId && !isEditing(message) && !isCallLogMessage(message)">
  <button class="message-action" type="button" (click)="startEditMessage(message)">Edit</button>
  <button class="message-action danger" type="button" (click)="deleteMessage(message)">Delete</button>
</div>
<div class="message-edit" *ngIf="isEditing(message)">
  <textarea class="message-edit-input" [(ngModel)]="editingDraft" rows="2"></textarea>
  <div class="message-edit-actions">
    <button type="button" class="ghost" (click)="cancelEditMessage()">Cancel</button>
    <button type="button" class="save" (click)="saveEditMessage(message)" [disabled]="editBusy">
      {{ editBusy ? 'Saving...' : 'Save' }}
    </button>
  </div>
</div>
                    </div>
                  </div>
                </ng-container>
              </div>
            </div>

            <form class="composer" *ngIf="activeConversation" (ngSubmit)="sendMessage()">
              <div class="composer-row">
                <button class="composer-attach" type="button" (click)="triggerMediaPicker()">+</button>
                <input
                  #mediaInput
                  type="file"
                  accept="image/png,image/jpeg,image/webp,video/mp4,video/webm,video/quicktime"
                  hidden
                  (change)="onMediaSelected($event)"
                />
                <div class="composer-field">
                  <textarea
                    #messageInput
                    class="composer-input"
                    name="message"
                    [(ngModel)]="messageDraft"
                    placeholder="Write a message..."
                    maxlength="2000"
                    rows="1"
                    (input)="onMessageInput($event)"
                  ></textarea>
                  <div class="composer-preview" *ngIf="messageMediaPreview">
                    <img *ngIf="messageMediaType === 'image'" [src]="messageMediaPreview" alt="preview" />
                    <video
                      *ngIf="messageMediaType === 'video'"
                      [src]="messageMediaPreview"
                      muted
                      playsinline
                    ></video>
                    <button class="composer-clear" type="button" (click)="clearMedia()">Remove</button>
                  </div>
                </div>
                <button class="composer-send" type="submit" [disabled]="messageBusy || !canSendMessage()">
                  {{ messageBusy ? 'Sending...' : 'Send' }}
                </button>
              </div>
              <div class="status error" *ngIf="messageMediaError">{{ messageMediaError }}</div>
            </form>
          </section>
        </div>
      </div>
    </div>

    <div class="lightbox" *ngIf="lightboxUrl" (click)="closeImageLightbox()">
      <div class="lightbox-card" (click)="$event.stopPropagation()">
        <button class="lightbox-close" type="button" (click)="closeImageLightbox()">x</button>
        <img [src]="lightboxUrl" alt="Preview" />
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
        </div>
        <div class="call-body">
          <video
            #remoteVideo
            class="call-remote"
            autoplay
            playsinline
            *ngIf="callType === 'video'"
          ></video>
          <div class="call-avatar" *ngIf="callType !== 'video'">
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
      color:#e6f1ff;
      background:#050b14;
    }
    .wrap{
      min-height:100%;
      height:100%;
      position:relative;
      padding:28px 20px calc(36px + env(safe-area-inset-bottom));
      box-sizing:border-box;
      display:flex;
      flex-direction:column;
    }
    .ocean-gradient{
      position:fixed;
      inset:0;
      background:
        radial-gradient(circle at 12% 20%, rgba(0,255,209,0.12), transparent 52%),
        radial-gradient(circle at 88% 20%, rgba(0,155,220,0.25), transparent 48%),
        linear-gradient(180deg, #0b1526, #050b13 60%, #03060c);
      z-index:0;
    }
    .ocean-dots{
      position:fixed;
      inset:0;
      background-image: radial-gradient(rgba(255,255,255,0.55) 1px, transparent 1px);
      background-size: 18px 18px;
      opacity:0.18;
      z-index:1;
      pointer-events:none;
    }
    .noise{
      position:fixed;
      inset:0;
      background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120' viewBox='0 0 120 120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.8' numOctaves='2'/%3E%3C/filter%3E%3Crect width='120' height='120' filter='url(%23n)' opacity='.08'/%3E%3C/svg%3E");
      opacity:0.12;
      z-index:2;
      pointer-events:none;
    }
    .card{
      position:relative;
      z-index:3;
      max-width:1100px;
      margin:0 auto;
      background:rgba(255,255,255,0.9);
      border-radius:28px;
      padding:22px;
      border:1px solid rgba(7,20,40,0.08);
      box-shadow:0 28px 60px rgba(8,26,52,0.12);
      backdrop-filter: blur(12px);
      color:#0c1422;
      flex:1;
      box-sizing:border-box;
      display:flex;
      flex-direction:column;
      min-height:0;
      overflow:hidden;
    }
    .ghost-link{
      border:0;
      background:none;
      color:rgba(10,20,32,0.7);
      letter-spacing:0.22em;
      font-size:11px;
      text-transform:uppercase;
      cursor:pointer;
    }
    .back-link{
      margin-bottom:12px;
    }
    .layout{
      display:grid;
      grid-template-columns:320px 1fr;
      gap:18px;
      align-items:stretch;
      flex:1;
      min-height:0;
    }
    .layout.thread-only .panel{
      display:none;
    }
    .panel{
      display:flex;
      flex-direction:column;
      gap:10px;
      background:rgba(255,255,255,0.86);
      border-radius:20px;
      padding:14px;
      border:1px solid rgba(7,20,40,0.08);
      min-height:0;
      overflow:auto;
    }
    .panel-title{
      font-weight:800;
      letter-spacing:0.24em;
      text-transform:uppercase;
      font-size:11px;
      color:rgba(9,22,38,0.6);
      margin-bottom:6px;
    }
    .status{
      font-size:13px;
      opacity:0.7;
      padding:6px 0;
    }
    .status.error{
      color:#c55c5c;
    }
    .conversation{
      display:flex;
      align-items:center;
      gap:10px;
      padding:10px;
      border-radius:16px;
      border:1px solid transparent;
      background:rgba(7,20,40,0.03);
      cursor:pointer;
      text-align:left;
      transition: border 160ms ease, background 160ms ease, transform 160ms ease;
    }
    .conversation:hover{
      border-color:rgba(0,155,220,0.3);
      background:rgba(0,155,220,0.1);
      transform: translateY(-1px);
    }
    .conversation.active{
      border-color:rgba(0,155,220,0.5);
      background:rgba(0,155,220,0.15);
    }
    .conversation-unread{
      width:8px;
      height:8px;
      border-radius:999px;
      background:rgba(255,255,255,0.9);
      border:1px solid rgba(7,20,40,0.12);
      flex:0 0 auto;
      margin-left:6px;
    }
    .avatar{
      width:40px;
      height:40px;
      border-radius:50%;
      overflow:hidden;
      background:rgba(0,155,220,0.12);
      display:flex;
      align-items:center;
      justify-content:center;
      font-weight:800;
      color:rgba(5,25,40,0.75);
      flex-shrink:0;
    }
    .avatar img{
      width:100%;
      height:100%;
      object-fit:cover;
    }
    .avatar.large{
      width:48px;
      height:48px;
    }
    .meta{
      flex:1;
      min-width:0;
    }
    .name{
      font-weight:700;
      font-size:14px;
      color:rgba(6,16,30,0.9);
      white-space:nowrap;
      overflow:hidden;
      text-overflow:ellipsis;
    }
    .snippet{
      font-size:12px;
      opacity:0.6;
      white-space:nowrap;
      overflow:hidden;
      text-overflow:ellipsis;
    }
    .time{
      font-size:11px;
      opacity:0.5;
      margin-left:auto;
      white-space:nowrap;
    }
    .thread{
      display:flex;
      flex-direction:column;
      border-radius:20px;
      border:1px solid rgba(7,20,40,0.08);
      background:rgba(255,255,255,0.9);
      min-height:0;
      overflow:hidden;
      min-height:0;
    }
    .thread-back{
      border:0;
      background:none;
      color:rgba(7,20,40,0.6);
      font-size:11px;
      letter-spacing:0.18em;
      text-transform:uppercase;
      cursor:pointer;
      margin-right:8px;
    }
    .thread-header{
      display:flex;
      align-items:center;
      gap:12px;
      padding:14px;
      border-bottom:1px solid rgba(7,20,40,0.08);
      background:rgba(255,255,255,0.95);
    }
    .thread-name{
      font-weight:800;
      font-size:16px;
      color:rgba(7,16,28,0.9);
    }
    .thread-sub{
      font-size:12px;
      opacity:0.6;
    }
    .thread-actions{
      margin-left:auto;
      display:flex;
      gap:8px;
    }
    .call-btn{
      width:34px;
      height:34px;
      border-radius:10px;
      border:1px solid rgba(7,20,40,0.15);
      background:rgba(7,28,42,0.06);
      color:rgba(7,20,40,0.9);
      font-size:16px;
      cursor:pointer;
    }
    .call-btn:disabled{
      opacity:0.45;
      cursor:not-allowed;
    }
    .thread-empty{
      padding:24px;
      font-size:14px;
      opacity:0.6;
    }
    .messages{
      flex:1;
      display:flex;
      flex-direction:column;
      min-height:0;
      overflow:hidden;
    }
    .message-list{
      flex:1;
      padding:14px;
      display:flex;
      flex-direction:column;
      gap:10px;
      overflow-y:auto;
      min-height:0;
    }
    .message-day{
      align-self:center;
      font-size:11px;
      letter-spacing:0.12em;
      text-transform:uppercase;
      color:rgba(7,20,40,0.55);
      background:rgba(7,20,40,0.06);
      border:1px solid rgba(7,20,40,0.08);
      border-radius:999px;
      padding:6px 12px;
    }
    .message{
      display:flex;
      align-items:flex-end;
      gap:10px;
      width:100%;
    }
    .message.me{
      justify-content:flex-end;
    }
    .message.me .msg-avatar{
      order:2;
    }
    .message.me .bubble{
      order:1;
    }
    .msg-avatar{
      width:28px;
      height:28px;
      border-radius:50%;
      overflow:hidden;
      background:rgba(7,20,40,0.1);
      border:1px solid rgba(7,20,40,0.12);
      display:flex;
      align-items:center;
      justify-content:center;
      font-size:11px;
      font-weight:800;
      color:rgba(7,20,40,0.75);
      flex-shrink:0;
    }
    .msg-avatar img{
      width:100%;
      height:100%;
      object-fit:cover;
    }
    .bubble{
      max-width:72%;
      background:rgba(7,20,40,0.05);
      border:1px solid rgba(7,20,40,0.08);
      border-radius:18px;
      padding:10px 12px;
      font-size:14px;
      line-height:1.5;
    }
    .message.me .bubble{
      background:rgba(0,155,220,0.18);
      border-color:rgba(0,155,220,0.4);
    }
    .body{
      white-space:pre-wrap;
      word-break:break-word;
    }
    .message-media{
      margin-top:8px;
      display:flex;
      flex-direction:column;
      gap:8px;
    }
    .message-media img,
    .message-media app-video-player{
      width:100%;
      max-height:280px;
      border-radius:14px;
      overflow:hidden;
      border:1px solid rgba(7,20,40,0.12);
      background:#000;
    }
    .message-media img{
      display:block;
      object-fit:cover;
      cursor:pointer;
    }
    .media-download{
      font-size:11px;
      letter-spacing:0.08em;
      text-transform:uppercase;
      font-weight:700;
      color:rgba(7,20,40,0.65);
      text-decoration:none;
    }
    .message-time{
      font-size:10px;
      opacity:0.6;
    }
    .message-meta{
      display:flex;
      align-items:center;
      justify-content:flex-end;
      gap:8px;
      margin-top:6px;
    }
    .message-date{
      margin-left:6px;
      font-size:10px;
      opacity:0.6;
    }
    .message-edited{
      font-size:10px;
      text-transform:uppercase;
      letter-spacing:0.12em;
      color:rgba(7,20,40,0.55);
    }
    .message-status{
      font-size:11px;
      letter-spacing:0.08em;
      opacity:0.7;
      color:rgba(7,20,40,0.6);
    }
    .message-status.read{
      color:rgba(0,155,220,0.95);
      opacity:1;
    }
    .message-actions{
      display:flex;
      justify-content:flex-end;
      gap:10px;
      margin-top:6px;
    }
    .message-action{
      border:0;
      background:none;
      font-size:10px;
      letter-spacing:0.12em;
      text-transform:uppercase;
      color:rgba(7,20,40,0.65);
      cursor:pointer;
    }
    .message-action.danger{
      color:rgba(200,70,70,0.9);
    }
    .message-edit{
      margin-top:8px;
      display:flex;
      flex-direction:column;
      gap:8px;
    }
    .message-edit-input{
      width:100%;
      border-radius:12px;
      border:1px solid rgba(7,20,40,0.18);
      padding:8px 10px;
      font-family:inherit;
      font-size:13px;
      resize:vertical;
      min-height:60px;
    }
    .message-edit-actions{
      display:flex;
      justify-content:flex-end;
      gap:8px;
    }
    .message-edit-actions .ghost{
      border:0;
      background:none;
      font-size:10px;
      letter-spacing:0.12em;
      text-transform:uppercase;
      color:rgba(7,20,40,0.6);
      cursor:pointer;
    }
    .message-edit-actions .save{
      border:0;
      border-radius:999px;
      padding:6px 14px;
      background:rgba(0,155,220,0.9);
      color:#fff;
      font-size:11px;
      letter-spacing:0.08em;
      text-transform:uppercase;
      cursor:pointer;
    }
    .composer{
      display:flex;
      flex-direction:column;
      gap:10px;
      padding:12px 14px;
      border-top:1px solid rgba(7,20,40,0.08);
      background:rgba(255,255,255,0.95);
    }
    .composer-row{
      display:flex;
      gap:10px;
      align-items:flex-end;
    }
    .composer-field{
      flex:1;
      display:flex;
      flex-direction:column;
      gap:8px;
      border-radius:16px;
      border:1px solid rgba(7,20,40,0.14);
      background:white;
      padding:10px 12px;
      min-height:56px;
    }
    .composer-input{
      width:100%;
      border:0;
      padding:4px 0;
      font-size:14px;
      font-family:inherit;
      background:transparent;
      min-height:32px;
      max-height:160px;
      line-height:1.45;
      resize:none;
      overflow-y:hidden;
    }
    .composer-attach{
      width:38px;
      height:38px;
      border-radius:50%;
      border:1px solid rgba(7,20,40,0.15);
      background:white;
      font-weight:900;
      font-size:18px;
      line-height:1;
      cursor:pointer;
      color:rgba(7,20,40,0.7);
    }
    .composer-send{
      border:0;
      border-radius:999px;
      padding:10px 18px;
      background:rgba(0,155,220,0.85);
      color:white;
      font-weight:700;
      cursor:pointer;
      box-shadow:0 12px 24px rgba(0,155,220,0.25);
    }
    .composer-send:disabled{
      opacity:0.6;
      cursor:not-allowed;
      box-shadow:none;
    }
    .composer-preview{
      display:flex;
      align-items:center;
      gap:12px;
      background:rgba(7,20,40,0.04);
      border:1px solid rgba(7,20,40,0.12);
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
      border:1px solid rgba(7,20,40,0.1);
    }
    .composer-clear{
      border:0;
      background:none;
      color:rgba(7,20,40,0.6);
      font-weight:700;
      letter-spacing:0.12em;
      text-transform:uppercase;
      font-size:10px;
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
    .lightbox-card img{
      width:100%;
      height:auto;
      max-height:70vh;
      display:block;
      border-radius:12px;
    }
    .lightbox-close{
      position:absolute;
      top:8px;
      right:8px;
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
      padding:16px;
    }
    .call-card{
      width:min(92vw, 520px);
      height:min(86vh, 680px);
      background:rgba(8,16,28,0.96);
      border-radius:24px;
      padding:18px;
      display:flex;
      flex-direction:column;
      color:#e8f1ff;
      box-shadow:0 24px 60px rgba(0,0,0,0.35);
    }
    .call-card.video{
      width:min(96vw, 720px);
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
    @media (max-width: 900px){
      .wrap{
        padding:16px 12px 16px;
      }
      .layout{
        grid-template-columns:1fr;
        height:100%;
      }
      .panel{
        max-height:240px;
        overflow:auto;
      }
      .layout.thread-only{
        height:100%;
      }
      .thread{
        min-height:0;
        height:100%;
      }
      .messages{
        min-height:0;
      }
      .message-list{
        min-height:0;
      }
    }
    @media (max-width: 600px){
      .wrap{
        padding:12px;
      }
      .card{
        padding:16px;
      }
      .bubble{
        max-width:86%;
      }
      .composer-send{
        width:100%;
      }
      .composer-row{
        flex-direction:column;
        align-items:stretch;
      }
      .composer-attach{
        width:100%;
        border-radius:14px;
        height:42px;
      }
      .call-card{
        height:min(88vh, 620px);
      }
      .call-local{
        width:96px;
        height:72px;
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
  lightboxUrl: string | null = null;
  meId: string | null = null;
  editingMessageId: string | null = null;
  editingDraft = '';
  editBusy = false;
  private pendingConversation: Conversation | null = null;
  private routeSub?: Subscription;
  private pendingSub?: Subscription;
  private pollTimer: number | null = null;
  mobileThreadOnly = false;
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
  private incomingOffer: { conversationId: string; from: string; sdp: any; callType: 'audio' | 'video' } | null =
    null;
  private ws?: WebSocket;
  private wsConnected = false;
  private pc?: RTCPeerConnection;
  private localStream?: MediaStream;
  private remoteStream?: MediaStream;
  private pendingCandidates: RTCIceCandidateInit[] = [];
  private readonly callLogPrefix = '__call__|';
  private callStartAt: number | null = null;
  private callLogSent = false;
  private destroyed = false;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private auth: AuthService,
    private messagesService: MessagesService,
    private mediaService: MediaService,
    private notificationsService: NotificationsService,
    private push: PushService,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    void this.push.syncIfGranted();
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;
    this.forceUi();
    void this.connectSignaling();

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
      if (!convoId) return;
      if (convoId !== this.activeConversationId) {
        void this.activateConversationById(convoId);
        return;
      }
      if (!this.messages.length) {
        void this.loadMessages(convoId, false);
      }
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
    this.routeSub?.unsubscribe();
    this.pendingSub?.unsubscribe();
    if (this.pollTimer) {
      window.clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    this.ws?.close();
    this.cleanupCall();
    this.clearMedia();
  }

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
    return this.callActive || this.callConnecting || this.callIncoming;
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
    if (this.callIncoming) return 'Incoming call';
    if (this.callConnecting) return 'Connecting...';
    if (this.callActive) return 'In call';
    return '';
  }

  private markCallActive(): void {
    if (!this.callStartAt) {
      this.callStartAt = Date.now();
    }
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

  async startCall(type: 'audio' | 'video'): Promise<void> {
    if (!this.activeConversationId || !this.canStartCall()) return;
    this.callType = type;
    this.callConversationId = this.activeConversationId;
    this.callConnecting = true;
    this.callIncoming = false;
    this.callActive = false;
    this.callFromId = this.meId;
    this.callError = '';
    this.callStartAt = null;
    this.callLogSent = false;
    this.forceUi();
    try {
      await this.ensurePeerConnection(type);
      if (!this.pc) return;
      const offer = await this.pc.createOffer();
      await this.pc.setLocalDescription(offer);
      this.sendSignal('call-offer', this.callConversationId, { sdp: offer, callType: type });
    } catch (e: any) {
      this.callError = e?.message ?? 'Call failed.';
      this.cleanupCall(false);
    }
  }

  async acceptCall(): Promise<void> {
    if (!this.incomingOffer) return;
    const offer = this.incomingOffer;
    this.callConversationId = offer.conversationId;
    this.callType = offer.callType;
    this.callFromId = offer.from;
    this.callIncoming = false;
    this.callConnecting = true;
    this.callActive = false;
    this.callError = '';
    this.callStartAt = null;
    this.callLogSent = false;
    this.forceUi();
    try {
      await this.ensurePeerConnection(offer.callType);
      if (!this.pc) return;
      await this.pc.setRemoteDescription(offer.sdp);
      await this.flushIceCandidates();
      const answer = await this.pc.createAnswer();
      await this.pc.setLocalDescription(answer);
      this.sendSignal('call-answer', offer.conversationId, { sdp: answer });
      this.incomingOffer = null;
    } catch (e: any) {
      this.callError = e?.message ?? 'Call failed.';
      this.cleanupCall(false);
    }
  }

  declineCall(): void {
    if (!this.incomingOffer) return;
    this.sendSignal('call-decline', this.incomingOffer.conversationId);
    this.cleanupCall();
  }

  toggleMute(): void {
    if (!this.localStream) return;
    const next = !this.callMuted;
    this.localStream.getAudioTracks().forEach((track) => {
      track.enabled = !next;
    });
    this.callMuted = next;
    this.forceUi();
  }

  toggleCamera(): void {
    if (!this.localStream) return;
    const next = !this.callCameraOff;
    this.localStream.getVideoTracks().forEach((track) => {
      track.enabled = !next;
    });
    this.callCameraOff = next;
    this.forceUi();
  }

  endCall(): void {
    if (this.callConversationId) {
      this.sendSignal('call-end', this.callConversationId);
    }
    const meta = this.getCallLogMeta();
    const status = this.callActive || this.callStartAt ? 'ended' : 'missed';
    void this.sendCallLog(status, meta);
    this.cleanupCall();
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
      }
    } catch {}
    this.callLogSent = true;
  }

  private async connectSignaling(): Promise<void> {
    if (this.destroyed || !this.meId) return;
    const token = await this.auth.getAccessToken();
    if (!token) return;
    const base = environment.apiBaseUrl || environment.graphqlEndpoint.replace(/\/graphql$/, '');
    const wsBase = base.startsWith('https') ? base.replace(/^https/, 'wss') : base.replace(/^http/, 'ws');
    const wsUrl = `${wsBase}/ws?token=${encodeURIComponent(token)}`;

    if (this.ws && this.ws.url === wsUrl && this.ws.readyState <= WebSocket.OPEN) return;
    this.ws?.close();

    const socket = new WebSocket(wsUrl);
    this.ws = socket;

    socket.onopen = () => {
      this.wsConnected = true;
      this.forceUi();
    };
    socket.onmessage = (event) => {
      void this.handleSignal(String(event.data ?? ''));
    };
    socket.onclose = () => {
      this.wsConnected = false;
      this.ws = undefined;
      this.forceUi();
      if (!this.destroyed) {
        window.setTimeout(() => void this.connectSignaling(), 3000);
      }
    };
    socket.onerror = () => {
      this.wsConnected = false;
    };
  }

  private sendSignal(type: string, conversationId: string | null, payload?: Record<string, any>): void {
    if (!conversationId || !this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    const msg = {
      type,
      conversationId,
      from: this.meId,
      ...(payload ?? {}),
    };
    try {
      this.ws.send(JSON.stringify(msg));
    } catch {}
  }

  private async handleSignal(raw: string): Promise<void> {
    let msg: any = null;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    const type = String(msg?.type ?? '');
    const conversationId = String(msg?.conversationId ?? '');
    const from = String(msg?.from ?? '');
    if (!type || !conversationId || !from || from === this.meId) return;

    if (type === 'call-offer') {
      if (this.callActive || this.callConnecting || this.callIncoming) {
        this.sendSignal('call-busy', conversationId);
        return;
      }
      const callType = msg?.callType === 'video' ? 'video' : 'audio';
      if (!msg?.sdp) return;
      this.incomingOffer = { conversationId, from, sdp: msg.sdp, callType };
      this.callConversationId = conversationId;
      this.callType = callType;
      this.callFromId = from;
      this.callIncoming = true;
      this.callConnecting = false;
      this.callActive = false;
      this.callStartAt = null;
      this.callLogSent = false;
      this.forceUi();
      if (conversationId !== this.activeConversationId) {
        await this.activateConversationById(conversationId);
      }
      return;
    }

    if (conversationId !== this.callConversationId) return;

    if (type === 'call-answer' && msg?.sdp) {
      if (!this.pc) return;
      await this.pc.setRemoteDescription(msg.sdp);
      await this.flushIceCandidates();
      this.callActive = true;
      this.callConnecting = false;
      this.markCallActive();
      this.forceUi();
      return;
    }

    if (type === 'ice-candidate' && msg?.candidate) {
      if (!this.pc) {
        this.pendingCandidates.push(msg.candidate);
        return;
      }
      if (this.pc.remoteDescription) {
        try {
          await this.pc.addIceCandidate(msg.candidate);
        } catch {}
      } else {
        this.pendingCandidates.push(msg.candidate);
      }
      return;
    }

    if (type === 'call-decline' || type === 'call-busy') {
      if (this.callFromId === this.meId) {
        void this.sendCallLog('missed', this.getCallLogMeta());
      }
      this.cleanupCall();
      return;
    }

    if (type === 'call-end') {
      this.cleanupCall();
    }
  }

  private async ensurePeerConnection(callType: 'audio' | 'video'): Promise<void> {
    if (this.pc) return;
    this.callMuted = false;
    this.callCameraOff = false;

    const constraints: MediaStreamConstraints = {
      audio: true,
      video: callType === 'video',
    };
    this.localStream = await navigator.mediaDevices.getUserMedia(constraints);
    this.remoteStream = new MediaStream();
    this.pendingCandidates = [];

    const iceServers: RTCIceServer[] = [{ urls: 'stun:stun.l.google.com:19302' }];
    this.pc = new RTCPeerConnection({ iceServers });

    this.pc.ontrack = (event) => {
      const stream = event.streams?.[0];
      if (!stream || !this.remoteStream) return;
      for (const track of stream.getTracks()) {
        if (!this.remoteStream.getTracks().some((t) => t.id === track.id)) {
          this.remoteStream.addTrack(track);
        }
      }
      this.attachRemoteStream();
    };

    this.pc.onicecandidate = (event) => {
      if (!event.candidate) return;
      this.sendSignal('ice-candidate', this.callConversationId, { candidate: event.candidate });
    };

    this.pc.onconnectionstatechange = () => {
      const state = this.pc?.connectionState;
      if (state === 'connected') {
        this.callActive = true;
        this.callConnecting = false;
        this.markCallActive();
        this.forceUi();
      }
      if (state === 'failed' || state === 'disconnected' || state === 'closed') {
        if (this.callActive || this.callConnecting) {
          this.cleanupCall();
        }
      }
    };

    this.localStream.getTracks().forEach((track) => {
      this.pc?.addTrack(track, this.localStream as MediaStream);
    });

    this.forceUi();
    requestAnimationFrame(() => {
      this.attachLocalStream();
    });
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

  private async flushIceCandidates(): Promise<void> {
    if (!this.pc || !this.pendingCandidates.length) return;
    const pending = [...this.pendingCandidates];
    this.pendingCandidates = [];
    for (const candidate of pending) {
      try {
        await this.pc.addIceCandidate(candidate);
      } catch {}
    }
  }

  private cleanupCall(resetError = true): void {
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
    this.pendingCandidates = [];
    this.callStartAt = null;
    this.callLogSent = false;

    if (this.pc) {
      this.pc.ontrack = null;
      this.pc.onicecandidate = null;
      this.pc.onconnectionstatechange = null;
      this.pc.close();
    }
    this.pc = undefined;

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
      const fetched = await this.messagesService.listMessages(conversationId, 60);
      if (silent) {
        this.messages = this.mergeMessages(conversationId, this.messages, fetched, 200);
      } else {
        this.messages = fetched;
      }
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
    const body = this.messageDraft.trim();
    if (!body && !this.messageMediaFile) return;

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

  private scrollToBottom(): void {
    const list = this.messageList?.nativeElement;
    if (!list) return;
    requestAnimationFrame(() => {
      list.scrollTop = list.scrollHeight;
    });
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
    const callLog = this.parseCallLog(trimmed);
    if (callLog) return this.formatCallLog(callLog);
    if (message?.id && trimmed === message.id) return '';
    if (this.looksLikeId(trimmed)) return '';
    if (this.stripTrailingMeta(trimmed) !== trimmed) {
      return this.stripTrailingMeta(trimmed);
    }
    return body;
  }

  isCallLogMessage(message: Message): boolean {
    const body = String(message?.body ?? '').trim();
    return !!this.parseCallLog(body);
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
    if (!body.startsWith(this.callLogPrefix)) return null;
    const raw = body.slice(this.callLogPrefix.length);
    const parts = raw.split('|');
    const data: Record<string, string> = {};
    for (const part of parts) {
      const [key, value] = part.split('=');
      if (!key || value === undefined) continue;
      data[key] = value;
    }
    const status = String(data['status'] ?? '').trim();
    const kind = data['kind'] === 'video' ? 'video' : 'audio';
    const duration = Number(data['duration'] ?? 0);
    if (!status) return null;
    return {
      status,
      kind,
      duration: Number.isFinite(duration) ? duration : 0,
    };
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
    const callLog = this.parseCallLog(body);
    if (callLog) return this.formatCallLog(callLog);
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
    this.mobileThreadOnly = window.innerWidth <= 900;
  }

  showConversationList(): void {
    this.mobileThreadOnly = false;
    this.forceUi();
  }

  private forceUi(): void {
    this.zone.run(() => this.cdr.detectChanges());
  }

  goBack(): void {
    void this.router.navigate(['/globe']);
  }
}


