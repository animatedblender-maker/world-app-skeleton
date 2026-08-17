import { CommonModule } from '@angular/common';
import {
  Component,
  EventEmitter,
  Input,
  OnChanges,
  Output,
  SimpleChanges,
} from '@angular/core';
import { FormsModule } from '@angular/forms';

import type { PostComment } from '../core/models/post.model';
import { AuthService } from '../core/services/auth.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService } from '../core/services/profile.service';
import { resolveAvatarUrl } from '../core/utils/media-url.util';
import { HubsCatalogService } from '../hubs/hubs-catalog.service';
import { HubsEngagementService } from '../hubs/hubs-engagement.service';

type ThreadItem = { comment: PostComment; depth: 0 | 1 };

/**
 * Ports iOS PostCommentsView / FacebookCommentRow:
 * threaded list, Like/Reply/time, load-more in place, composer with replies.
 * Always stays on the feed card — never navigates to post detail.
 */
@Component({
  selector: 'app-post-comments',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="pc">
      <div class="pc-status" *ngIf="loading && !threaded.length">Loading comments…</div>

      <div class="pc-empty" *ngIf="!loading && !threaded.length">
        No comments yet. Be the first to comment.
      </div>

      <div class="pc-list" *ngIf="visibleThreaded.length">
        <div
          class="pc-row"
          *ngFor="let item of visibleThreaded; trackBy: trackItem"
          [class.reply]="item.depth > 0"
          [attr.data-depth]="item.depth"
        >
          <div class="pc-indent" *ngIf="item.depth > 0" aria-hidden="true">
            <span class="pc-guide"></span>
          </div>
          <div class="pc-avatar" [class.sm]="item.depth > 0">
            <img *ngIf="avatarOf(item.comment)" [src]="avatarOf(item.comment)!" alt="" />
            <span *ngIf="!avatarOf(item.comment)">{{ initialsOf(item.comment) }}</span>
          </div>
          <div class="pc-main">
            <div class="pc-name">{{ nameOf(item.comment) }}</div>
            <div class="pc-body">{{ item.comment.body }}</div>
            <div class="pc-actions">
              <button
                type="button"
                class="pc-act"
                [class.on]="item.comment.liked_by_me"
                [disabled]="liking[item.comment.id]"
                (click)="toggleLike(item.comment)"
              >
                {{ item.comment.liked_by_me ? 'Liked' : 'Like' }}
              </button>
              <button type="button" class="pc-act" (click)="startReply(item.comment)">Reply</button>
              <span class="pc-time" *ngIf="item.comment.created_at">
                {{ relativeTime(item.comment.created_at) }}
              </span>
              <span class="pc-likes" *ngIf="(item.comment.like_count || 0) > 0">
                <svg viewBox="0 0 16 16" width="10" height="10" aria-hidden="true">
                  <path
                    fill="currentColor"
                    d="M2.5 14V7.2h2.4V14H2.5zm3.2-6.5 2.7-4.6c.25-.42.8-.55 1.2-.3.35.22.48.68.3 1.05L8.8 6.8h3.55c.85 0 1.45.8 1.2 1.58l-1.25 4.05A1.7 1.7 0 0 1 10.7 13.7H5.7V7.5z"
                  />
                </svg>
                {{ item.comment.like_count }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <button
        type="button"
        class="pc-more"
        *ngIf="threaded.length > maxVisible"
        (click)="loadMore()"
      >
        Load more comments ({{ remaining }} more)
      </button>

      <div class="pc-composer" *ngIf="showsComposer">
        <div class="pc-reply-bar" *ngIf="replyTo as rt">
          <span>Replying to <strong>@{{ rt.name }}</strong></span>
          <button type="button" class="pc-cancel" (click)="cancelReply()">Cancel</button>
        </div>
        <div class="pc-compose-row" [class.replying]="!!replyTo">
          <div class="pc-avatar" [class.sm]="!!replyTo">
            <img *ngIf="meAvatar" [src]="meAvatar" alt="" />
            <span *ngIf="!meAvatar">{{ meInitials }}</span>
          </div>
          <textarea
            class="pc-input"
            rows="1"
            [(ngModel)]="draft"
            [placeholder]="replyTo ? 'Write a reply…' : 'Write a comment…'"
            [disabled]="submitting"
            (keydown.enter)="onEnter($event)"
          ></textarea>
          <button
            type="button"
            class="pc-send"
            *ngIf="draft.trim()"
            [disabled]="submitting || !draft.trim()"
            (click)="submit()"
            aria-label="Post comment"
          >
            <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
              <path
                fill="currentColor"
                d="M3.4 20.6 21 12 3.4 3.4l.1 6.7L15 12 3.5 13.9z"
              />
            </svg>
          </button>
        </div>
        <div class="pc-hint" *ngIf="!meId">Sign in to comment.</div>
      </div>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
      }
      .pc {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .pc-status,
      .pc-empty {
        font-size: 14px;
        color: var(--m-ink-muted, #948b82);
        padding: 4px 0 2px;
      }
      .pc-list {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .pc-row {
        display: flex;
        align-items: flex-start;
        gap: 8px;
        position: relative;
        width: 100%;
        box-sizing: border-box;
      }
      /*
       * iOS CommentThreadLayout.indentPerLevel = 44 —
       * replies sit under the parent with a clear left gutter + guide.
       */
      .pc-row.reply {
        padding-left: 0;
        margin-left: 0;
      }
      .pc-indent {
        flex: 0 0 44px;
        width: 44px;
        min-width: 44px;
        align-self: stretch;
        position: relative;
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        justify-content: stretch;
        padding-right: 8px;
        box-sizing: border-box;
      }
      .pc-guide {
        display: block;
        width: 2px;
        flex: 1 1 auto;
        min-height: 28px;
        border-radius: 1px;
        background: color-mix(in srgb, var(--m-accent, #7b6347) 50%, transparent);
        margin-top: 2px;
        margin-bottom: 2px;
      }
      .pc-avatar {
        width: 32px;
        height: 32px;
        border-radius: 8px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        display: grid;
        place-items: center;
        font-size: 10px;
        font-weight: 700;
        flex-shrink: 0;
        color: var(--m-ink-muted, #948b82);
        box-shadow: inset 0 0 0 1px rgba(44, 40, 37, 0.1);
      }
      .pc-avatar.sm {
        width: 26px;
        height: 26px;
        font-size: 9px;
      }
      .pc-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .pc-main {
        flex: 1;
        min-width: 0;
      }
      .pc-name {
        font-size: 14px;
        font-weight: 650;
        color: var(--m-ink, #2c2825);
        line-height: 1.25;
      }
      .pc-row.reply .pc-name {
        font-size: 12px;
      }
      .pc-body {
        font-size: 14px;
        color: var(--m-ink, #2c2825);
        line-height: 1.4;
        margin-top: 2px;
        white-space: pre-wrap;
        word-break: break-word;
      }
      .pc-actions {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 12px;
        margin-top: 4px;
      }
      .pc-act {
        border: 0;
        background: transparent;
        padding: 0;
        font-size: 12px;
        font-weight: 650;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
      }
      .pc-act.on {
        color: var(--m-ink, #2c2825);
      }
      .pc-act:disabled {
        opacity: 0.55;
        cursor: default;
      }
      .pc-time {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .pc-likes {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        font-size: 12px;
        font-weight: 650;
        color: var(--m-ink-secondary, #6b645d);
      }
      .pc-more {
        border: 0;
        background: transparent;
        padding: 2px 0;
        align-self: flex-start;
        font-size: 14px;
        font-weight: 650;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
      }
      .pc-composer {
        margin-top: 2px;
      }
      .pc-reply-bar {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-bottom: 8px;
      }
      .pc-reply-bar strong {
        color: var(--m-accent, #7b6347);
        font-weight: 650;
      }
      .pc-cancel {
        border: 0;
        background: transparent;
        padding: 0;
        font-size: 12px;
        font-weight: 650;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
      }
      .pc-compose-row {
        display: flex;
        align-items: flex-start;
        gap: 8px;
      }
      .pc-compose-row.replying {
        padding-left: 44px; /* same indent as reply rows */
      }
      .pc-input {
        flex: 1;
        min-width: 0;
        resize: none;
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 20px;
        background: var(--m-surface, #fefdfb);
        color: var(--m-ink, #2c2825);
        font: inherit;
        font-size: 14px;
        line-height: 1.35;
        padding: 10px 12px;
        min-height: 40px;
        max-height: 120px;
        outline: none;
      }
      .pc-input:focus {
        border-color: color-mix(in srgb, var(--m-accent, #7b6347) 55%, var(--m-border, #ddd8d1));
      }
      .pc-send {
        border: 0;
        background: transparent;
        color: var(--m-accent, #7b6347);
        padding: 8px 4px;
        cursor: pointer;
        line-height: 0;
        flex-shrink: 0;
      }
      .pc-send:disabled {
        opacity: 0.45;
        cursor: default;
      }
      .pc-hint {
        margin-top: 6px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
    `,
  ],
})
export class PostCommentsComponent implements OnChanges {
  @Input({ required: true }) postId!: string;
  @Input() totalCommentCount = 0;
  @Input() showsComposer = true;
  @Input() initialVisible = 8;
  /** Optional seed post for hub/local engagement fallbacks */
  @Input() post: { id: string; comment_count?: number | null } | null = null;

  @Output() commentCountChange = new EventEmitter<number>();

  comments: PostComment[] = [];
  loading = false;
  submitting = false;
  draft = '';
  maxVisible = 8;
  liking: Record<string, boolean> = {};
  replyTo: { rootId: string; name: string } | null = null;

  meId: string | null = null;
  meAvatar: string | null = null;
  meName = 'You';
  meUsername: string | null = null;
  private meLoaded = false;

  constructor(
    private posts: PostsService,
    private engagement: HubsEngagementService,
    private catalog: HubsCatalogService,
    private auth: AuthService,
    private profiles: ProfileService
  ) {}

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['initialVisible'] && !changes['initialVisible'].previousValue) {
      this.maxVisible = this.initialVisible || 8;
    }
    if (changes['postId'] && this.postId) {
      this.maxVisible = this.initialVisible || 8;
      this.comments = [];
      this.replyTo = null;
      this.draft = '';
      void this.bootstrap();
    }
  }

  private async bootstrap(): Promise<void> {
    if (!this.meLoaded) {
      this.meLoaded = true;
      try {
        const user = await this.auth.getUser().catch(() => null);
        this.meId = user?.id ?? null;
        if (this.meId) {
          const { meProfile: profile } = await this.profiles.meProfile().catch(() => ({
            meProfile: null as any,
          }));
          if (profile) {
            this.meName = profile.display_name || profile.username || 'You';
            this.meUsername = profile.username ?? null;
            this.meAvatar = profile.avatar_url
              ? resolveAvatarUrl(profile.avatar_url, profile.username || profile.user_id) || null
              : null;
          }
        }
      } catch {
        // guest
      }
    }
    await this.loadComments();
  }

  get meInitials(): string {
    return (this.meName || 'Y').slice(0, 2).toUpperCase();
  }

  get threaded(): ThreadItem[] {
    return this.orderComments(this.comments);
  }

  get visibleThreaded(): ThreadItem[] {
    return this.threaded.slice(0, this.maxVisible);
  }

  get remaining(): number {
    const total = Math.max(this.totalCommentCount || 0, this.threaded.length);
    return Math.max(0, total - this.maxVisible);
  }

  trackItem(_: number, item: ThreadItem): string {
    return item.comment.id;
  }

  nameOf(c: PostComment): string {
    return c.author?.display_name || c.author?.username || 'Member';
  }

  initialsOf(c: PostComment): string {
    return this.nameOf(c).slice(0, 2).toUpperCase();
  }

  avatarOf(c: PostComment): string | null {
    const seed = c.author?.username || c.author_id;
    return resolveAvatarUrl(c.author?.avatar_url, seed) || null;
  }

  relativeTime(iso: string): string {
    return this.catalog.relativeTime(iso);
  }

  loadMore(): void {
    this.maxVisible = Math.min(
      this.maxVisible + 25,
      Math.max(this.threaded.length, this.totalCommentCount || 0, this.maxVisible + 25)
    );
  }

  startReply(c: PostComment): void {
    const rootId = this.threadRootId(c);
    const name = c.author?.username || this.nameOf(c);
    this.replyTo = { rootId, name };
  }

  cancelReply(): void {
    this.replyTo = null;
  }

  onEnter(ev: Event): void {
    const ke = ev as KeyboardEvent;
    if (ke.shiftKey) return;
    ke.preventDefault();
    void this.submit();
  }

  async loadComments(): Promise<void> {
    if (!this.postId) return;
    const showSpinner = !this.comments.length;
    if (showSpinner) this.loading = true;
    try {
      let loaded: PostComment[] = [];
      try {
        if (this.post) {
          loaded = await this.engagement.loadComments(this.post as any);
        } else {
          loaded = await this.posts.listComments(this.postId, 200);
        }
      } catch {
        loaded = await this.posts.listComments(this.postId, 200).catch(() => []);
      }
      this.comments = (loaded || []).filter((c) => String(c?.body || '').trim());
      this.emitCount();
    } finally {
      this.loading = false;
    }
  }

  async submit(): Promise<void> {
    const body = this.draft.trim();
    if (!body || this.submitting) return;
    if (!this.meId) return;
    this.submitting = true;
    const parentId = this.replyTo?.rootId ?? null;
    try {
      let created: PostComment | null = null;
      try {
        if (this.post && String(this.postId).match(/^(ia_|hub_|archive_)/)) {
          created = await this.engagement.addComment(this.post as any, body, {
            id: this.meId,
            display_name: this.meName,
            username: this.meUsername,
            avatar_url: this.meAvatar,
            parent_id: parentId,
          });
        } else {
          created = await this.posts.addComment(this.postId, body, parentId);
        }
      } catch {
        // local optimistic fallback
        created = {
          id: `local_${Date.now()}`,
          post_id: this.postId,
          parent_id: parentId,
          author_id: this.meId,
          body,
          like_count: 0,
          liked_by_me: false,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          author: {
            user_id: this.meId,
            display_name: this.meName,
            username: this.meUsername,
            avatar_url: this.meAvatar,
            country_name: null,
            country_code: null,
          },
        };
      }
      if (created) {
        // Ensure reply parent sticks even if the API omits parent_id
        if (parentId && !created.parent_id) {
          created = { ...created, parent_id: parentId };
        }
        const without = this.comments.filter((c) => c.id !== created!.id);
        this.comments = [...without, created];
        // Soft refresh — re-apply parent_id if server drops it
        void this.loadComments().then(() => {
          if (!parentId || !created) return;
          this.comments = this.comments.map((c) =>
            c.id === created!.id && !c.parent_id ? { ...c, parent_id: parentId } : c
          );
        });
      }
      this.draft = '';
      this.replyTo = null;
      this.emitCount();
    } finally {
      this.submitting = false;
    }
  }

  async toggleLike(c: PostComment): Promise<void> {
    if (this.liking[c.id]) return;
    this.liking = { ...this.liking, [c.id]: true };
    const liked = !c.liked_by_me;
    // optimistic
    this.comments = this.comments.map((row) =>
      row.id === c.id
        ? {
            ...row,
            liked_by_me: liked,
            like_count: Math.max(0, (row.like_count || 0) + (liked ? 1 : -1)),
          }
        : row
    );
    try {
      const updated = liked
        ? await this.posts.likeComment(c.id)
        : await this.posts.unlikeComment(c.id);
      this.comments = this.comments.map((row) => (row.id === c.id ? { ...row, ...updated } : row));
    } catch {
      // keep optimistic
    } finally {
      const next = { ...this.liking };
      delete next[c.id];
      this.liking = next;
    }
  }

  private emitCount(): void {
    const n = Math.max(this.totalCommentCount || 0, this.comments.length);
    this.commentCountChange.emit(n);
  }

  private orderComments(comments: PostComment[]): ThreadItem[] {
    const norm = (raw: string | null | undefined) => {
      const t = String(raw || '').trim().toLowerCase();
      return t || null;
    };
    const byId = new Map(comments.map((c) => [norm(c.id) || c.id, c]));
    const isRoot = (c: PostComment) => !norm(c.parent_id);
    const rootKeyOf = (c: PostComment): string => {
      let current = c;
      const visited = new Set<string>();
      while (true) {
        const pid = norm(current.parent_id);
        if (!pid || visited.has(pid)) break;
        visited.add(pid);
        const parent = byId.get(pid);
        if (!parent) break;
        current = parent;
      }
      return norm(current.id) || current.id;
    };

    const roots = comments.filter(isRoot).sort((a, b) => a.created_at.localeCompare(b.created_at));
    const replies = comments.filter((c) => !isRoot(c));
    const items: ThreadItem[] = [];
    const included = new Set<string>();

    for (const root of roots) {
      const key = norm(root.id) || root.id;
      items.push({ comment: root, depth: 0 });
      included.add(key);
      const threadReplies = replies
        .filter((r) => rootKeyOf(r) === key)
        .sort((a, b) => a.created_at.localeCompare(b.created_at));
      for (const reply of threadReplies) {
        const rk = norm(reply.id) || reply.id;
        items.push({ comment: reply, depth: 1 });
        included.add(rk);
      }
    }

    // Replies whose parent is missing still indent as depth 1
    for (const orphan of comments
      .filter((c) => !included.has(norm(c.id) || c.id))
      .sort((a, b) => a.created_at.localeCompare(b.created_at))) {
      items.push({ comment: orphan, depth: isRoot(orphan) ? 0 : 1 });
    }
    return items;
  }

  private threadRootId(c: PostComment): string {
    const norm = (raw: string | null | undefined) => {
      const t = String(raw || '').trim().toLowerCase();
      return t || null;
    };
    const byId = new Map(this.comments.map((x) => [norm(x.id) || x.id, x]));
    let current = c;
    const visited = new Set<string>();
    while (true) {
      const pid = norm(current.parent_id);
      if (!pid || visited.has(pid)) break;
      visited.add(pid);
      const parent = byId.get(pid);
      if (!parent) break;
      current = parent;
    }
    return current.id;
  }
}
