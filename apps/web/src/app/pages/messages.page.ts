import { Component, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { AuthService } from '../core/services/auth.service';
import { MessagesService } from '../core/services/messages.service';
import { Conversation, Message } from '../core/models/messages.model';
import { PostAuthor } from '../core/models/post.model';

@Component({
  selector: 'app-messages-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="wrap">
      <div class="ocean-gradient" aria-hidden="true"></div>
      <div class="ocean-dots" aria-hidden="true"></div>
      <div class="noise" aria-hidden="true"></div>

      <div class="card">
        <button class="ghost-link back-link" type="button" (click)="goBack()">Back</button>
        <div class="layout">
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
                <div class="snippet">
                  {{ convo.last_message?.body || 'Start a conversation' }}
                </div>
              </div>
              <div class="time">{{ formatTime(convo.last_message_at || convo.updated_at) }}</div>
            </button>
          </aside>

          <section class="thread">
            <div class="thread-header" *ngIf="activeConversation; else emptyThread">
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
                <div class="thread-sub">@{{ otherMember(activeConversation)?.username || 'user' }}</div>
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
                  <div class="bubble">
                    <div class="body">{{ message.body }}</div>
                    <div class="meta">{{ formatTimestamp(message.created_at) }}</div>
                  </div>
                </div>
              </div>
            </div>

            <form class="composer" *ngIf="activeConversation" (ngSubmit)="sendMessage()">
              <input
                class="composer-input"
                name="message"
                [(ngModel)]="messageDraft"
                placeholder="Write a message..."
                maxlength="2000"
                autocomplete="off"
              />
              <button class="composer-send" type="submit" [disabled]="messageBusy || !messageDraft.trim()">
                {{ messageBusy ? 'Sending...' : 'Send' }}
              </button>
            </form>
          </section>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
    :host{
      display:block;
      min-height:100vh;
      position:relative;
      color:#0c1422;
      background:#e8f5ff;
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
        radial-gradient(circle at 12% 18%, rgba(120,232,255,0.35), transparent 52%),
        radial-gradient(circle at 88% 20%, rgba(0,176,255,0.18), transparent 48%),
        linear-gradient(180deg, #d9f2ff, #f7fbff 60%, #ffffff);
      z-index:0;
    }
    .ocean-dots{
      position:fixed;
      inset:0;
      background-image: radial-gradient(rgba(255,255,255,0.55) 1px, transparent 1px);
      background-size: 18px 18px;
      opacity:0.4;
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
      background:rgba(255,255,255,0.82);
      border-radius:28px;
      padding:22px;
      border:1px solid rgba(7,20,40,0.08);
      box-shadow:0 28px 60px rgba(8,26,52,0.12);
      backdrop-filter: blur(12px);
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
    }
    .message.me{
      justify-content:flex-end;
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
    .meta{
      display:block;
    }
    .bubble .meta{
      font-size:11px;
      opacity:0.6;
      margin-top:6px;
      text-align:right;
    }
    .composer{
      display:flex;
      gap:10px;
      padding:12px 14px;
      border-top:1px solid rgba(7,20,40,0.08);
      background:rgba(255,255,255,0.95);
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
    @media (max-width: 900px){
      .layout{
        grid-template-columns:1fr;
      }
      .panel{
        max-height:240px;
        overflow:auto;
      }
      .thread{
        min-height:360px;
      }
    }
    @media (max-width: 600px){
      .card{
        padding:16px;
      }
      .bubble{
        max-width:86%;
      }
      .composer{
        flex-direction:column;
      }
      .composer-send{
        width:100%;
      }
    }
    `
  ],
})
export class MessagesPageComponent implements OnInit, OnDestroy {
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
  meId: string | null = null;
  private pendingConversation: Conversation | null = null;
  private routeSub?: Subscription;
  private pendingSub?: Subscription;
  private pollTimer: number | null = null;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private auth: AuthService,
    private messagesService: MessagesService
  ) {}

  async ngOnInit(): Promise<void> {
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;

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
      void this.loadMessages(convo.id, false);
    });

    await this.loadConversations();
    this.startPolling();
  }

  ngOnDestroy(): void {
    this.routeSub?.unsubscribe();
    this.pendingSub?.unsubscribe();
    if (this.pollTimer) {
      window.clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  async loadConversations(selectId?: string | null): Promise<void> {
    this.loadingConversations = true;
    this.conversationError = '';

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
    }
  }

  private startPolling(): void {
    if (this.pollTimer) return;
    this.pollTimer = window.setInterval(() => {
      void this.loadConversations();
      if (this.activeConversationId) {
        void this.loadMessages(this.activeConversationId, true);
      }
    }, 6000);
  }

  async selectConversation(convo: Conversation, syncUrl: boolean): Promise<void> {
    this.activeConversation = convo;
    this.activeConversationId = convo.id;
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
      await this.loadMessages(convoId, false);
      return;
    }
    const fetched = await this.fetchConversationById(convoId);
    if (fetched) {
      this.upsertConversation(fetched);
      await this.selectConversation(fetched, false);
      return;
    }
    this.activeConversationId = convoId;
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
    }
    try {
      this.messages = await this.messagesService.listMessages(conversationId, 60);
    } catch (e: any) {
      this.messageError = e?.message ?? String(e);
    } finally {
      this.loadingMessages = false;
    }
  }

  async sendMessage(): Promise<void> {
    if (!this.activeConversationId || this.messageBusy) return;
    const body = this.messageDraft.trim();
    if (!body) return;

    this.messageBusy = true;
    this.messageError = '';

    try {
      const sent = await this.messagesService.sendMessage(this.activeConversationId, body);
      this.messages = [...this.messages, sent];
      this.messageDraft = '';
      this.bumpConversation(sent);
    } catch (e: any) {
      this.messageError = e?.message ?? String(e);
    } finally {
      this.messageBusy = false;
    }
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
  }

  otherMember(convo: Conversation | null): PostAuthor | null {
    if (!convo) return null;
    if (!this.meId) return convo.members[0] ?? null;
    return convo.members.find((member) => member.user_id !== this.meId) ?? convo.members[0] ?? null;
  }

  displayNameFor(user: PostAuthor | null | undefined): string {
    if (!user) return 'Conversation';
    return user.display_name || user.username || 'Member';
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
    return parsed.toLocaleString(undefined, {
      dateStyle: 'medium',
      timeStyle: 'short',
    });
  }

  goBack(): void {
    void this.router.navigate(['/globe']);
  }
}
