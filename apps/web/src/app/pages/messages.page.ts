import { ChangeDetectorRef, Component, ElementRef, NgZone, OnDestroy, OnInit, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { AuthService } from '../core/services/auth.service';
import { MessagesService } from '../core/services/messages.service';
import { MediaService } from '../core/services/media.service';
import { NotificationsService, type NotificationItem } from '../core/services/notifications.service';
import { Conversation, Message } from '../core/models/messages.model';
import { PostAuthor } from '../core/models/post.model';
import { VideoPlayerComponent } from '../components/video-player.component';

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
            </div>

            <ng-template #emptyThread>
              <div class="thread-empty">Select a conversation to start chatting.</div>
            </ng-template>

            <div class="messages" *ngIf="activeConversation">
              <div class="status" *ngIf="loadingMessages">Loading messages...</div>
              <div class="status error" *ngIf="messageError">{{ messageError }}</div>
              <div class="message-list" *ngIf="!loadingMessages">
                <div
                  class="message"
                  *ngFor="let message of messages"
                  [class.me]="message.sender_id === meId"
                >
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
                    <div class="body" *ngIf="message.body">{{ message.body }}</div>
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
                    <div class="message-time">{{ formatTimestamp(message.created_at) }}</div>
                  </div>
                </div>
              </div>
            </div>

            <form class="composer" *ngIf="activeConversation" (ngSubmit)="sendMessage()">
              <div class="composer-row">
                <button class="composer-attach" type="button" (click)="triggerMediaPicker()">+</button>
                <input
                  #mediaInput
                  type="file"
                  accept="image/*,video/*"
                  hidden
                  (change)="onMediaSelected($event)"
                />
                <input
                  class="composer-input"
                  name="message"
                  [(ngModel)]="messageDraft"
                  placeholder="Write a message..."
                  maxlength="2000"
                  autocomplete="off"
                />
                <button class="composer-send" type="submit" [disabled]="messageBusy || !canSendMessage()">
                  {{ messageBusy ? 'Sending...' : 'Send' }}
                </button>
              </div>
              <div class="composer-preview" *ngIf="messageMediaPreview">
                <img *ngIf="messageMediaType === 'image'" [src]="messageMediaPreview" alt="preview" />
                <video *ngIf="messageMediaType === 'video'" [src]="messageMediaPreview" muted></video>
                <button class="composer-clear" type="button" (click)="clearMedia()">Remove</button>
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
  `,
  styles: [
    `
    :host{
      display:block;
      min-height:100vh;
      position:relative;
      color:#e6f1ff;
      background:#050b14;
    }
    .wrap{
      min-height:100vh;
      position:relative;
      padding:28px 20px 36px;
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
      min-height:320px;
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
      min-height:320px;
      overflow:hidden;
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
    .thread-empty{
      padding:24px;
      font-size:14px;
      opacity:0.6;
    }
    .messages{
      flex:1;
      display:flex;
      flex-direction:column;
      min-height:200px;
    }
    .message-list{
      flex:1;
      padding:14px;
      display:flex;
      flex-direction:column;
      gap:10px;
      overflow-y:auto;
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
      margin-top:6px;
      text-align:right;
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
      align-items:center;
    }
    .composer-input{
      flex:1;
      border-radius:999px;
      border:1px solid rgba(7,20,40,0.14);
      padding:10px 14px;
      font-size:14px;
      font-family:inherit;
      background:white;
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
      border:1px dashed rgba(7,20,40,0.18);
      border-radius:14px;
      padding:10px;
    }
    .composer-preview img,
    .composer-preview video{
      width:140px;
      height:90px;
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
    @media (max-width: 900px){
      .layout{
        grid-template-columns:1fr;
        height: calc(100dvh - 160px);
      }
      .panel{
        max-height:240px;
        overflow:auto;
      }
      .layout.thread-only{
        height: calc(100dvh - 130px);
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
    }
    `
  ],
})
export class MessagesPageComponent implements OnInit, OnDestroy {
  @ViewChild('mediaInput') mediaInput?: ElementRef<HTMLInputElement>;
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
  private pendingConversation: Conversation | null = null;
  private routeSub?: Subscription;
  private pendingSub?: Subscription;
  private pollTimer: number | null = null;
  mobileThreadOnly = false;
  unreadConversationIds = new Set<string>();
  private messageNotifications: NotificationItem[] = [];

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private auth: AuthService,
    private messagesService: MessagesService,
    private mediaService: MediaService,
    private notificationsService: NotificationsService,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;
    this.forceUi();

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
    this.routeSub?.unsubscribe();
    this.pendingSub?.unsubscribe();
    if (this.pollTimer) {
      window.clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
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
    try {
      this.messages = await this.messagesService.listMessages(conversationId, 60);
      if (!silent) {
        await this.markConversationNotificationsRead(conversationId);
      }
    } catch (e: any) {
      this.messageError = e?.message ?? String(e);
    } finally {
      this.loadingMessages = false;
      this.forceUi();
    }
  }

  async sendMessage(): Promise<void> {
    if (!this.activeConversationId || this.messageBusy) return;
    const body = this.messageDraft.trim();
    if (!body && !this.messageMediaFile) return;

    this.messageBusy = true;
    this.messageError = '';
    this.forceUi();

    try {
      let media:
        | { type: string; path: string; name?: string | null; mime?: string | null; size?: number | null }
        | undefined;
      if (this.messageMediaFile) {
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
      }
      const sent = await this.messagesService.sendMessage(this.activeConversationId, body, media);
      this.messages = [...this.messages, sent];
      this.messageDraft = '';
      this.clearMedia();
      this.bumpConversation(sent);
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

  triggerMediaPicker(): void {
    this.mediaInput?.nativeElement.click();
  }

  onMediaSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] ?? null;
    if (!file) return;
    const type = file.type || '';
    if (!type.startsWith('image/') && !type.startsWith('video/')) {
      this.messageMediaError = 'Only images and videos are supported.';
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

  conversationSnippet(convo: Conversation): string {
    const last = convo.last_message;
    if (!last) return 'Start a conversation';
    const body = String(last.body || '').trim();
    if (body) return body;
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
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
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
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return '';
    return parsed.toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
    });
  }

  formatTimestamp(value: string): string {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return value;
    return parsed.toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
    });
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
