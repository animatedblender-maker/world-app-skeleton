import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import {
  AnonymousComment,
  AnonymousPost,
  AnonymousService,
  AnonymousSession,
  AnonymousSpace,
  AnonymousSpaceFilter,
  type AnonymousApiError,
} from '../core/services/anonymous.service';
import { NotificationsUiService } from '../core/services/notifications-ui.service';

type Phase =
  | 'loading'
  | 'unauthenticated'
  | 'under18'
  | 'missing_birthdate'
  | 'need_attest'
  | 'need_username'
  | 'suspended'
  | 'offline'
  | 'ready';

type ShellTab = 'spaces' | 'feed' | 'me';
type View =
  | { kind: 'shell' }
  | { kind: 'space'; slug: string }
  | { kind: 'post'; id: string; spaceSlug?: string }
  | { kind: 'create_space' };

const SPACE_FILTERS: Array<{ id: AnonymousSpaceFilter; title: string }> = [
  { id: 'for_you', title: 'For You' },
  { id: 'popular', title: 'Popular' },
  { id: 'newest', title: 'Newest' },
  { id: 'joined', title: 'Joined' },
  { id: 'free', title: 'Free' },
  { id: 'paid', title: 'Paid' },
];

@Component({
  selector: 'app-anonymous-page',
  standalone: true,
  imports: [CommonModule, FormsModule, BottomTabsComponent],
  template: `
    <div class="anon-shell">
      <header class="anon-top">
        <div class="anon-top-row">
          <button
            *ngIf="view.kind !== 'shell'"
            type="button"
            class="icon-btn"
            aria-label="Back"
            (click)="goBack()"
          >
            ‹
          </button>
          <div class="anon-brand">
            <div class="anon-title">{{ headerTitle }}</div>
            <div class="anon-chip" *ngIf="view.kind === 'shell'">Anonymous mode</div>
          </div>
          <button
            type="button"
            class="icon-btn"
            aria-label="Notifications"
            (click)="openNotifications()"
          >
            <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.5">
              <path d="M6 9a6 6 0 0 1 12 0c0 4 1.5 5.5 1.5 5.5H4.5S6 13 6 9z" stroke-linejoin="round" />
              <path d="M10 18.5a2 2 0 0 0 4 0" stroke-linecap="round" />
            </svg>
          </button>
        </div>

        <nav class="shell-tabs" *ngIf="phase === 'ready' && view.kind === 'shell'">
          <button
            type="button"
            class="shell-tab"
            *ngFor="let t of shellTabs"
            [class.active]="shellTab === t.id"
            (click)="setShellTab(t.id)"
          >
            {{ t.title }}
          </button>
        </nav>
      </header>

      <!-- Phases -->
      <main class="anon-body" *ngIf="phase === 'loading'">
        <div class="skeleton" *ngFor="let i of skeletonSlots"></div>
      </main>

      <main class="anon-body gate" *ngIf="phase === 'unauthenticated'">
        <div class="gate-icon" aria-hidden="true">⛨</div>
        <h1>Sign in for Anonymous</h1>
        <p>
          Anonymous is 18+ and requires a Matterya account so we can confirm age eligibility before
          showing Spaces or posts.
        </p>
        <button type="button" class="btn primary" (click)="goAuth()">Sign in</button>
        <p class="muted">Return to Matterya from the tab bar anytime.</p>
      </main>

      <main class="anon-body gate" *ngIf="phase === 'under18'">
        <div class="gate-icon" aria-hidden="true">⛨</div>
        <h1>Adults only</h1>
        <p>
          Anonymous is only available to people 18 and older. No posts, Spaces, or search are shown
          until age eligibility is confirmed.
        </p>
        <p class="muted">Return to Matterya from the tab bar anytime.</p>
      </main>

      <main class="anon-body gate" *ngIf="phase === 'missing_birthdate'">
        <div class="gate-icon" aria-hidden="true">⛨</div>
        <h1>Birthday needed</h1>
        <p>Add your birthday in Matterya profile settings before entering Anonymous.</p>
        <button type="button" class="btn primary" (click)="goProfileSetup()">Open profile settings</button>
        <p class="muted">Return to Matterya from the tab bar anytime.</p>
      </main>

      <main class="anon-body gate" *ngIf="phase === 'need_attest'">
        <div class="gate-icon" aria-hidden="true">✓</div>
        <h1>Confirm you’re 18+</h1>
        <p>
          Before entering Anonymous, confirm you are at least 18 years old. Private Anonymous content
          stays hidden until you do.
        </p>
        <div class="privacy-card">
          Your Anonymous name is public within Anonymous. Other members can’t see your Matterya
          profile. Matterya may link identities for safety and legal compliance.
        </div>
        <button
          type="button"
          class="btn primary"
          [disabled]="busy"
          (click)="attest()"
        >
          {{ busy ? 'Confirming…' : 'I confirm I am 18 or older' }}
        </button>
        <p class="muted">
          False confirmation may result in account restrictions. Age assurance may be re-checked over
          time.
        </p>
        <p class="error" *ngIf="error">{{ error }}</p>
      </main>

      <main class="anon-body gate" *ngIf="phase === 'need_username'">
        <h1>Claim your Anonymous name</h1>
        <p>
          You’ll get one persistent generated username for all Anonymous Spaces. It’s separate from
          your Matterya profile.
        </p>
        <div class="username-card">
          <div class="label">Generated username</div>
          <div class="username">{{ previewUsername || '…' }}</div>
        </div>
        <div class="warn-card">
          <strong>Usernames can’t be changed later.</strong>
          <p>
            Your Anonymous name is public within Anonymous. Other members can’t see your Matterya
            profile. Matterya may link identities for safety and legal compliance.
          </p>
        </div>
        <button
          type="button"
          class="btn primary"
          [disabled]="busy"
          (click)="claimUsername()"
        >
          {{ busy ? 'Claiming…' : 'Confirm username' }}
        </button>
        <p class="muted">v1 usernames are generated for you — custom real-name handles aren’t allowed.</p>
        <p class="error" *ngIf="error">{{ error }}</p>
      </main>

      <main class="anon-body gate" *ngIf="phase === 'suspended'">
        <div class="gate-icon" aria-hidden="true">!</div>
        <h1>Anonymous suspended</h1>
        <p>Your Anonymous access is restricted. Contact support if you believe this is a mistake.</p>
      </main>

      <main class="anon-body gate" *ngIf="phase === 'offline'">
        <div class="gate-icon" aria-hidden="true">⌀</div>
        <h1>Can’t reach Anonymous</h1>
        <p>Check your connection and try again.</p>
        <button type="button" class="btn primary" (click)="bootstrap()">Try again</button>
        <p class="error" *ngIf="error">{{ error }}</p>
      </main>

      <!-- Ready: Spaces directory -->
      <main class="anon-body" *ngIf="phase === 'ready' && view.kind === 'shell' && shellTab === 'spaces'">
        <div class="chips">
          <button
            type="button"
            class="chip"
            *ngFor="let f of spaceFilters"
            [class.active]="spaceFilter === f.id"
            (click)="setSpaceFilter(f.id)"
          >
            {{ f.title }}
          </button>
          <button type="button" class="chip create" (click)="openCreateSpace()">+ Space</button>
        </div>

        <div class="state" *ngIf="spacesLoading && !spaces.length">Loading Spaces…</div>
        <div class="state error" *ngIf="!spacesLoading && spacesError">{{ spacesError }}</div>
        <div class="state" *ngIf="!spacesLoading && !spacesError && !spaces.length">
          <ng-container [ngSwitch]="spaceFilter">
            <ng-container *ngSwitchCase="'joined'">
              <strong>No joined Spaces</strong>
              <p>Join a free Space to see it here.</p>
            </ng-container>
            <ng-container *ngSwitchCase="'paid'">
              <strong>Paid Spaces coming soon</strong>
              <p>Paid memberships aren’t live yet. You can browse labels, but joining stays disabled.</p>
            </ng-container>
            <ng-container *ngSwitchDefault>
              <strong>No Spaces yet</strong>
              <p>Create a free Space or refresh when more appear.</p>
            </ng-container>
          </ng-container>
        </div>

        <button
          type="button"
          class="space-card"
          *ngFor="let s of spaces; trackBy: trackSpace"
          (click)="openSpace(s)"
        >
          <div class="space-card-top">
            <div class="space-title">{{ s.title }}</div>
            <span class="pill" *ngIf="s.admission !== 'free' || s.billing_mode !== 'free'">Paid</span>
            <span class="pill soft" *ngIf="s.joined">Joined</span>
          </div>
          <div class="space-slug">a/{{ s.slug }}</div>
          <p class="space-desc" *ngIf="s.description">{{ s.description }}</p>
          <div class="space-meta">
            <span>{{ s.member_count || 0 }} members</span>
            <span>·</span>
            <span>{{ s.post_count || 0 }} posts</span>
            <span *ngIf="s.category">· {{ s.category }}</span>
          </div>
        </button>

        <button
          type="button"
          class="btn ghost load-more"
          *ngIf="spacesCursor"
          [disabled]="spacesLoading"
          (click)="loadMoreSpaces()"
        >
          {{ spacesLoading ? 'Loading…' : 'Load more' }}
        </button>
      </main>

      <!-- Ready: Feed -->
      <main class="anon-body" *ngIf="phase === 'ready' && view.kind === 'shell' && shellTab === 'feed'">
        <div class="state" *ngIf="feedLoading && !feedPosts.length">Loading feed…</div>
        <div class="state error" *ngIf="!feedLoading && feedError">{{ feedError }}</div>
        <div class="state" *ngIf="!feedLoading && !feedError && !feedPosts.length">
          <strong>Nothing in your feed</strong>
          <p>Join free Spaces or refresh. Private previews stay hidden.</p>
        </div>

        <article class="post-card" *ngFor="let p of feedPosts; trackBy: trackPost" (click)="openPost(p)">
          <div class="post-meta">
            <button type="button" class="linkish" (click)="openSpaceSlug(p.space_slug, $event)">
              a/{{ p.space_slug || 'space' }}
            </button>
            <span>·</span>
            <span>@{{ p.author.username }}</span>
            <span>·</span>
            <span>{{ relativeTime(p.created_at) }}</span>
          </div>
          <h2 class="post-title" *ngIf="p.title">{{ p.title }}</h2>
          <p class="post-body">{{ p.body }}</p>
          <div class="post-actions" (click)="$event.stopPropagation()">
            <button type="button" class="vote" [class.on]="p.my_vote === 1" (click)="votePost(p, 1)">▲</button>
            <span class="score">{{ p.score || 0 }}</span>
            <button type="button" class="vote" [class.on]="p.my_vote === -1" (click)="votePost(p, -1)">▼</button>
            <span class="comments">{{ p.comment_count || 0 }} comments</span>
          </div>
        </article>

        <button
          type="button"
          class="btn ghost load-more"
          *ngIf="feedCursor"
          [disabled]="feedLoading"
          (click)="loadMoreFeed()"
        >
          {{ feedLoading ? 'Loading…' : 'Load more' }}
        </button>
      </main>

      <!-- Ready: Me -->
      <main class="anon-body me" *ngIf="phase === 'ready' && view.kind === 'shell' && shellTab === 'me'">
        <div class="me-card" *ngIf="session?.profile as profile">
          <div class="me-handle">@{{ profile.username }}</div>
          <p class="muted">
            This identity is only for Anonymous. Your ordinary Matterya avatar and name never appear
            here.
          </p>
        </div>
        <div class="privacy-card">
          Your Anonymous name is public within Anonymous. Other members can’t see your Matterya
          profile. Matterya may link identities for safety and legal compliance.
        </div>
        <button type="button" class="btn ghost" (click)="setSpaceFilter('joined')">
          View joined Spaces
        </button>
      </main>

      <!-- Space detail -->
      <main class="anon-body" *ngIf="phase === 'ready' && view.kind === 'space'">
        <div class="state" *ngIf="spaceLoading && !currentSpace">Loading Space…</div>
        <div class="state error" *ngIf="!spaceLoading && spaceError && !currentSpace">{{ spaceError }}</div>

        <ng-container *ngIf="currentSpace as space">
          <div class="space-detail-head">
            <h1>{{ space.title }}</h1>
            <div class="space-slug">a/{{ space.slug }}</div>
            <p *ngIf="space.description">{{ space.description }}</p>
            <div class="space-meta">
              <span>{{ space.member_count || 0 }} members</span>
              <span>·</span>
              <span>{{ space.post_count || 0 }} posts</span>
            </div>
            <div class="space-actions">
              <button
                type="button"
                class="btn primary"
                *ngIf="!space.joined && isFreeSpace(space)"
                [disabled]="busy"
                (click)="joinCurrent()"
              >
                Join
              </button>
              <button
                type="button"
                class="btn ghost"
                *ngIf="space.joined"
                [disabled]="busy"
                (click)="leaveCurrent()"
              >
                Leave
              </button>
              <button
                type="button"
                class="btn ghost"
                *ngIf="!isFreeSpace(space)"
                (click)="tryPaidCheckout()"
              >
                Paid — coming soon
              </button>
            </div>
            <div class="rules" *ngIf="space.rules?.length">
              <div class="label">Rules</div>
              <ol>
                <li *ngFor="let r of space.rules">{{ r.text }}</li>
              </ol>
            </div>
          </div>

          <div class="composer" *ngIf="space.joined || isFreeSpace(space)">
            <div class="label">New post</div>
            <input class="field" [(ngModel)]="composeTitle" name="composeTitle" placeholder="Title (optional)" />
            <textarea
              class="field area"
              [(ngModel)]="composeBody"
              name="composeBody"
              rows="4"
              placeholder="Write something (text only)"
            ></textarea>
            <p class="muted tiny">
              Don’t share real names, contact info, or anything that links to your Matterya profile.
            </p>
            <button
              type="button"
              class="btn primary"
              [disabled]="busy || !composeBody.trim()"
              (click)="submitPost()"
            >
              {{ busy ? 'Posting…' : 'Post' }}
            </button>
            <p class="error" *ngIf="composeError">{{ composeError }}</p>
          </div>

          <div class="state" *ngIf="spacePostsLoading && !spacePosts.length">Loading posts…</div>
          <div class="state" *ngIf="!spacePostsLoading && !spacePosts.length">
            No posts yet. Seed a thoughtful first conversation.
          </div>

          <article
            class="post-card"
            *ngFor="let p of spacePosts; trackBy: trackPost"
            (click)="openPost(p, space.slug)"
          >
            <div class="post-meta">
              <span>@{{ p.author.username }}</span>
              <span>·</span>
              <span>{{ relativeTime(p.created_at) }}</span>
            </div>
            <h2 class="post-title" *ngIf="p.title">{{ p.title }}</h2>
            <p class="post-body">{{ p.body }}</p>
            <div class="post-actions" (click)="$event.stopPropagation()">
              <button type="button" class="vote" [class.on]="p.my_vote === 1" (click)="votePost(p, 1)">▲</button>
              <span class="score">{{ p.score || 0 }}</span>
              <button type="button" class="vote" [class.on]="p.my_vote === -1" (click)="votePost(p, -1)">▼</button>
              <span class="comments">{{ p.comment_count || 0 }} comments</span>
            </div>
          </article>

          <button
            type="button"
            class="btn ghost load-more"
            *ngIf="spacePostsCursor"
            [disabled]="spacePostsLoading"
            (click)="loadMoreSpacePosts()"
          >
            {{ spacePostsLoading ? 'Loading…' : 'Load more' }}
          </button>
        </ng-container>
      </main>

      <!-- Post detail -->
      <main class="anon-body" *ngIf="phase === 'ready' && view.kind === 'post'">
        <div class="state" *ngIf="postLoading && !currentPost">Loading post…</div>
        <div class="state error" *ngIf="!postLoading && postError && !currentPost">{{ postError }}</div>

        <ng-container *ngIf="currentPost as post">
          <article class="post-card detail">
            <div class="post-meta">
              <button
                type="button"
                class="linkish"
                *ngIf="post.space_slug"
                (click)="openSpaceSlug(post.space_slug)"
              >
                a/{{ post.space_slug }}
              </button>
              <span *ngIf="post.space_slug">·</span>
              <span>@{{ post.author.username }}</span>
              <span>·</span>
              <span>{{ relativeTime(post.created_at) }}</span>
            </div>
            <h1 class="post-title" *ngIf="post.title">{{ post.title }}</h1>
            <p class="post-body detail-body">{{ post.body }}</p>
            <div class="post-actions">
              <button type="button" class="vote" [class.on]="post.my_vote === 1" (click)="votePost(post, 1)">▲</button>
              <span class="score">{{ post.score || 0 }}</span>
              <button type="button" class="vote" [class.on]="post.my_vote === -1" (click)="votePost(post, -1)">▼</button>
            </div>
          </article>

          <section class="comments">
            <div class="label">Comments</div>
            <div class="state soft" *ngIf="!commentsLoading && !comments.length">
              No comments yet — start the thread.
            </div>
            <div class="comment" *ngFor="let c of comments; trackBy: trackComment">
              <div class="post-meta">
                <span>@{{ c.author.username }}</span>
                <span>·</span>
                <span>{{ relativeTime(c.created_at) }}</span>
              </div>
              <p>{{ c.body }}</p>
              <div class="post-actions">
                <button type="button" class="vote" [class.on]="c.my_vote === 1" (click)="voteComment(c, 1)">▲</button>
                <span class="score">{{ c.score || 0 }}</span>
                <button type="button" class="vote" [class.on]="c.my_vote === -1" (click)="voteComment(c, -1)">▼</button>
              </div>
            </div>

            <div class="composer">
              <textarea
                class="field area"
                [(ngModel)]="commentBody"
                name="commentBody"
                rows="3"
                placeholder="Add a comment"
              ></textarea>
              <button
                type="button"
                class="btn primary"
                [disabled]="busy || !commentBody.trim()"
                (click)="submitComment()"
              >
                {{ busy ? 'Sending…' : 'Comment' }}
              </button>
              <p class="error" *ngIf="composeError">{{ composeError }}</p>
            </div>
          </section>
        </ng-container>
      </main>

      <!-- Create Space -->
      <main class="anon-body" *ngIf="phase === 'ready' && view.kind === 'create_space'">
        <h1>Create a free Space</h1>
        <p class="muted">Text-only free Spaces for now. Paid Spaces stay disabled until billing is live.</p>
        <label class="label">Title</label>
        <input class="field" [(ngModel)]="newSpaceTitle" name="newSpaceTitle" maxlength="80" />
        <label class="label">Description</label>
        <textarea class="field area" [(ngModel)]="newSpaceDesc" name="newSpaceDesc" rows="4" maxlength="500"></textarea>
        <label class="label">Category (optional)</label>
        <input class="field" [(ngModel)]="newSpaceCategory" name="newSpaceCategory" maxlength="40" />
        <button
          type="button"
          class="btn primary"
          [disabled]="busy || !newSpaceTitle.trim()"
          (click)="submitCreateSpace()"
        >
          {{ busy ? 'Creating…' : 'Create Space' }}
        </button>
        <p class="error" *ngIf="composeError">{{ composeError }}</p>
      </main>

      <app-bottom-tabs></app-bottom-tabs>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100%;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
      }
      .anon-shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 72px) + 20px);
        background: var(--m-paper, #f8f6f2);
      }
      .anon-top {
        position: sticky;
        top: 0;
        z-index: 40;
        background: rgba(254, 253, 251, 0.94);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        backdrop-filter: blur(14px);
        -webkit-backdrop-filter: blur(14px);
      }
      .anon-top-row {
        display: grid;
        grid-template-columns: 44px 1fr 44px;
        align-items: center;
        gap: 4px;
        padding: 8px 12px;
        padding-top: calc(8px + env(safe-area-inset-top));
      }
      .anon-brand {
        text-align: center;
        min-width: 0;
      }
      .anon-title {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 22px;
        color: var(--m-ink, #2c2825);
        line-height: 1.15;
      }
      .anon-chip {
        display: inline-block;
        margin-top: 4px;
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
        padding: 2px 8px;
        border-radius: 999px;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-canvas-muted, #f2f0ec);
      }
      .icon-btn {
        border: 0;
        background: transparent;
        color: var(--m-ink, #2c2825);
        width: 40px;
        height: 40px;
        border-radius: 12px;
        cursor: pointer;
        font-size: 28px;
        line-height: 1;
        display: grid;
        place-items: center;
      }
      .shell-tabs {
        display: flex;
        gap: 4px;
        overflow-x: auto;
        padding: 0 12px 10px;
        scrollbar-width: none;
      }
      .shell-tabs::-webkit-scrollbar {
        display: none;
      }
      .shell-tab {
        flex: 0 0 auto;
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        padding: 8px 12px;
        cursor: pointer;
        position: relative;
      }
      .shell-tab.active {
        color: var(--m-ink, #2c2825);
      }
      .shell-tab.active::after {
        content: '';
        position: absolute;
        left: 12px;
        right: 12px;
        bottom: 2px;
        height: 1px;
        background: var(--m-ink, #2c2825);
      }
      .anon-body {
        max-width: 720px;
        margin: 0 auto;
        padding: 16px var(--m-page-padding, 16px) 28px;
      }
      .anon-body.gate {
        padding-top: 36px;
      }
      .anon-body.gate h1,
      .anon-body h1 {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 28px;
        font-weight: 400;
        margin: 0 0 12px;
      }
      .anon-body.gate p,
      .anon-body p {
        color: var(--m-ink-secondary, #6b645d);
        line-height: 1.5;
        margin: 0 0 14px;
      }
      .gate-icon {
        font-size: 36px;
        color: var(--m-ink-muted, #948b82);
        margin-bottom: 16px;
      }
      .muted {
        color: var(--m-ink-muted, #948b82) !important;
        font-size: 13px;
      }
      .muted.tiny {
        font-size: 12px;
      }
      .error {
        color: var(--m-danger, #ea000b) !important;
        font-size: 14px;
      }
      .privacy-card,
      .warn-card,
      .username-card,
      .me-card {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 14px;
        padding: 16px;
        margin: 0 0 16px;
        color: var(--m-ink-secondary, #6b645d);
        line-height: 1.45;
      }
      .warn-card strong,
      .me-handle {
        display: block;
        color: var(--m-ink, #2c2825);
        margin-bottom: 8px;
      }
      .me-handle {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 26px;
      }
      .username-card .label,
      .label {
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
        margin-bottom: 8px;
      }
      .username {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 26px;
        color: var(--m-ink, #2c2825);
      }
      .btn {
        border: 0;
        border-radius: 12px;
        padding: 14px 18px;
        font-size: 15px;
        font-weight: 650;
        cursor: pointer;
        width: 100%;
        margin: 8px 0;
      }
      .btn:disabled {
        opacity: 0.55;
        cursor: default;
      }
      .btn.primary {
        background: var(--m-ink, #2c2825);
        color: var(--m-surface, #fefdfb);
      }
      .btn.ghost {
        background: transparent;
        color: var(--m-ink, #2c2825);
        border: 0.5px solid var(--m-border, #ddd8d1);
      }
      .btn.load-more {
        margin-top: 12px;
      }
      .skeleton {
        height: 96px;
        border-radius: 14px;
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        margin-bottom: 12px;
      }
      .chips {
        display: flex;
        gap: 4px;
        overflow-x: auto;
        margin: 0 -16px 12px;
        padding: 0 16px 8px;
        scrollbar-width: none;
      }
      .chips::-webkit-scrollbar {
        display: none;
      }
      .chip {
        flex: 0 0 auto;
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        padding: 8px 12px;
        cursor: pointer;
        position: relative;
      }
      .chip.active {
        color: var(--m-ink, #2c2825);
      }
      .chip.active::after {
        content: '';
        position: absolute;
        left: 12px;
        right: 12px;
        bottom: 2px;
        height: 1px;
        background: var(--m-ink, #2c2825);
      }
      .chip.create {
        margin-left: auto;
        color: var(--m-accent-bright, #7b6347);
      }
      .space-card,
      .post-card {
        display: block;
        width: 100%;
        text-align: left;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
        border-radius: 14px;
        padding: 14px 16px;
        margin: 0 0 10px;
        color: inherit;
        cursor: pointer;
      }
      .space-card-top {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      .space-title,
      .post-title {
        font-size: 17px;
        font-weight: 650;
        color: var(--m-ink, #2c2825);
        margin: 0;
      }
      .space-slug {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .space-desc,
      .post-body {
        margin: 8px 0 0;
        color: var(--m-ink-secondary, #6b645d);
        font-size: 14px;
        line-height: 1.45;
        display: -webkit-box;
        -webkit-line-clamp: 4;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .detail-body {
        -webkit-line-clamp: unset;
        display: block;
        font-size: 16px;
        white-space: pre-wrap;
      }
      .space-meta,
      .post-meta {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        margin-top: 10px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .pill {
        font-size: 10px;
        font-weight: 700;
        text-transform: uppercase;
        padding: 2px 8px;
        border-radius: 999px;
        background: rgba(123, 99, 71, 0.12);
        color: var(--m-accent-bright, #7b6347);
      }
      .pill.soft {
        background: var(--m-canvas-muted, #f2f0ec);
        color: var(--m-ink-muted, #948b82);
      }
      .post-actions {
        display: flex;
        align-items: center;
        gap: 8px;
        margin-top: 10px;
      }
      .vote {
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
        font-size: 14px;
        padding: 4px 6px;
      }
      .vote.on {
        color: var(--m-accent-bright, #7b6347);
      }
      .score,
      .comments {
        font-size: 13px;
        color: var(--m-ink-secondary, #6b645d);
      }
      .linkish {
        border: 0;
        background: transparent;
        color: var(--m-accent-bright, #7b6347);
        cursor: pointer;
        padding: 0;
        font: inherit;
      }
      .state {
        padding: 36px 8px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
        font-size: 14px;
        line-height: 1.45;
      }
      .state strong {
        display: block;
        color: var(--m-ink, #2c2825);
        font-size: 16px;
        margin-bottom: 6px;
      }
      .state.error {
        color: var(--m-danger, #ea000b);
      }
      .state.soft {
        padding: 16px 0;
      }
      .space-detail-head h1 {
        margin-bottom: 4px;
      }
      .space-actions {
        display: flex;
        gap: 8px;
        margin: 12px 0;
      }
      .space-actions .btn {
        width: auto;
        flex: 1;
        margin: 0;
      }
      .rules {
        margin: 12px 0 20px;
        padding: 12px 14px;
        border-radius: 12px;
        background: var(--m-canvas-muted, #f2f0ec);
      }
      .rules ol {
        margin: 0;
        padding-left: 18px;
        color: var(--m-ink-secondary, #6b645d);
        font-size: 13px;
      }
      .composer {
        margin: 16px 0 20px;
        padding: 14px;
        border-radius: 14px;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
      }
      .field {
        width: 100%;
        box-sizing: border-box;
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 10px;
        padding: 12px 14px;
        margin: 0 0 10px;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
        font: inherit;
      }
      .field.area {
        resize: vertical;
        min-height: 96px;
      }
      .comments .comment {
        padding: 12px 0;
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
      }
      .comments .comment p {
        margin: 6px 0 0;
        color: var(--m-ink, #2c2825);
        white-space: pre-wrap;
      }
      @media (min-width: 900px) {
        .anon-shell {
          padding-bottom: 28px;
        }
        .anon-body {
          padding-top: 20px;
        }
      }
    `,
  ],
})
export class AnonymousPageComponent implements OnInit, OnDestroy {
  phase: Phase = 'loading';
  session: AnonymousSession | null = null;
  error = '';
  busy = false;
  previewUsername = '';

  shellTab: ShellTab = 'spaces';
  shellTabs: Array<{ id: ShellTab; title: string }> = [
    { id: 'spaces', title: 'Spaces' },
    { id: 'feed', title: 'Feed' },
    { id: 'me', title: 'Me' },
  ];
  view: View = { kind: 'shell' };
  private viewStack: View[] = [];

  spaceFilters = SPACE_FILTERS;
  spaceFilter: AnonymousSpaceFilter = 'for_you';
  spaces: AnonymousSpace[] = [];
  spacesCursor: string | null = null;
  spacesLoading = false;
  spacesError = '';

  feedPosts: AnonymousPost[] = [];
  feedCursor: string | null = null;
  feedLoading = false;
  feedError = '';

  currentSpace: AnonymousSpace | null = null;
  spaceLoading = false;
  spaceError = '';
  spacePosts: AnonymousPost[] = [];
  spacePostsCursor: string | null = null;
  spacePostsLoading = false;

  currentPost: AnonymousPost | null = null;
  postLoading = false;
  postError = '';
  comments: AnonymousComment[] = [];
  commentsLoading = false;

  composeTitle = '';
  composeBody = '';
  commentBody = '';
  composeError = '';
  newSpaceTitle = '';
  newSpaceDesc = '';
  newSpaceCategory = '';

  skeletonSlots = [0, 1, 2, 3, 4];

  private destroyed = false;

  constructor(
    private anon: AnonymousService,
    private router: Router,
    private notificationsUi: NotificationsUiService,
    private cdr: ChangeDetectorRef
  ) {}

  get headerTitle(): string {
    if (this.view.kind === 'create_space') return 'New Space';
    if (this.view.kind === 'space') return this.currentSpace?.title || 'Space';
    if (this.view.kind === 'post') return 'Post';
    return 'Anonymous';
  }

  ngOnInit(): void {
    void this.bootstrap();
  }

  ngOnDestroy(): void {
    this.destroyed = true;
  }

  private paint(): void {
    if (this.destroyed) return;
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  async bootstrap(): Promise<void> {
    this.phase = 'loading';
    this.error = '';
    this.paint();
    const res = await this.anon.session();
    if (this.destroyed) return;
    if (!res || (res as AnonymousApiError).ok === false) {
      const err = res as AnonymousApiError;
      this.error = this.anon.errorMessage(err);
      if (err?.code === 'unauthenticated' || err?.status === 401) {
        this.phase = 'unauthenticated';
      } else if (err?.code === 'under_18') {
        this.phase = 'under18';
      } else if (err?.code === 'missing_birthdate') {
        this.phase = 'missing_birthdate';
      } else {
        this.phase = 'offline';
      }
      this.paint();
      return;
    }
    this.applySession(res as AnonymousSession);
  }

  private applySession(session: AnonymousSession): void {
    this.session = session;
    if (!session.eligible) {
      if (session.code === 'missing_birthdate') {
        this.phase = 'missing_birthdate';
      } else if (session.code === 'under_18') {
        this.phase = 'under18';
      } else {
        this.phase = 'under18';
      }
      this.paint();
      return;
    }
    if (session.profile?.state === 'suspended') {
      this.phase = 'suspended';
      this.paint();
      return;
    }
    if (!session.age_attested) {
      this.phase = 'need_attest';
      this.paint();
      return;
    }
    if (!session.profile) {
      this.phase = 'need_username';
      this.previewUsername = this.localPreviewUsername();
      this.paint();
      return;
    }
    this.phase = 'ready';
    this.paint();
    void this.loadSpaces(true);
    void this.loadFeed(true);
  }

  async attest(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.error = '';
    this.paint();
    const res = await this.anon.attest();
    this.busy = false;
    if ((res as AnonymousApiError).ok === false) {
      this.error = this.anon.errorMessage(res as AnonymousApiError);
      this.paint();
      return;
    }
    const next = await this.anon.session();
    if ((next as AnonymousApiError).ok === false) {
      // Attest succeeded; advance locally.
      this.applySession({
        ok: true,
        eligible: true,
        profile: (res as any).profile ?? null,
        age_attested: true,
        paid_enabled: this.session?.paid_enabled ?? false,
      });
      return;
    }
    this.applySession(next as AnonymousSession);
  }

  async claimUsername(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.error = '';
    this.paint();
    const res = await this.anon.claimProfile();
    this.busy = false;
    if ((res as AnonymousApiError).ok === false) {
      this.error = this.anon.errorMessage(res as AnonymousApiError);
      this.paint();
      return;
    }
    const profile = (res as { profile: any }).profile;
    this.applySession({
      ok: true,
      eligible: true,
      profile,
      age_attested: true,
      paid_enabled: this.session?.paid_enabled ?? false,
    });
  }

  setShellTab(tab: ShellTab): void {
    this.shellTab = tab;
    this.view = { kind: 'shell' };
    this.viewStack = [];
    if (tab === 'feed' && !this.feedPosts.length) void this.loadFeed(true);
    if (tab === 'spaces' && !this.spaces.length) void this.loadSpaces(true);
    this.paint();
  }

  setSpaceFilter(filter: AnonymousSpaceFilter): void {
    this.spaceFilter = filter;
    this.shellTab = 'spaces';
    void this.loadSpaces(true);
  }

  async loadSpaces(reset: boolean): Promise<void> {
    if (this.spacesLoading) return;
    this.spacesLoading = true;
    if (reset) {
      this.spaces = [];
      this.spacesCursor = null;
      this.spacesError = '';
    }
    this.paint();
    const res = await this.anon.listSpaces(
      this.spaceFilter,
      reset ? null : this.spacesCursor,
      24
    );
    this.spacesLoading = false;
    if ((res as AnonymousApiError).ok === false) {
      this.spacesError = this.anon.errorMessage(res as AnonymousApiError, 'Couldn’t load Spaces.');
      this.paint();
      return;
    }
    const ok = res as { spaces: AnonymousSpace[]; next_cursor: string | null };
    this.spaces = reset ? ok.spaces : [...this.spaces, ...ok.spaces];
    this.spacesCursor = ok.next_cursor;
    this.paint();
  }

  loadMoreSpaces(): void {
    if (!this.spacesCursor) return;
    void this.loadSpaces(false);
  }

  async loadFeed(reset: boolean): Promise<void> {
    if (this.feedLoading) return;
    this.feedLoading = true;
    if (reset) {
      this.feedPosts = [];
      this.feedCursor = null;
      this.feedError = '';
    }
    this.paint();
    const res = await this.anon.feed({
      sort: 'for_you',
      cursor: reset ? null : this.feedCursor,
      limit: 24,
    });
    this.feedLoading = false;
    if ((res as AnonymousApiError).ok === false) {
      this.feedError = this.anon.errorMessage(res as AnonymousApiError, 'Couldn’t load feed.');
      this.paint();
      return;
    }
    const ok = res as { posts: AnonymousPost[]; next_cursor: string | null };
    this.feedPosts = reset ? ok.posts : [...this.feedPosts, ...ok.posts];
    this.feedCursor = ok.next_cursor;
    this.paint();
  }

  loadMoreFeed(): void {
    if (!this.feedCursor) return;
    void this.loadFeed(false);
  }

  openCreateSpace(): void {
    this.pushView({ kind: 'create_space' });
    this.composeError = '';
    this.newSpaceTitle = '';
    this.newSpaceDesc = '';
    this.newSpaceCategory = '';
  }

  openSpace(space: AnonymousSpace): void {
    this.pushView({ kind: 'space', slug: space.slug });
    void this.loadSpace(space.slug);
  }

  openSpaceSlug(slug: string | undefined | null, event?: Event): void {
    event?.stopPropagation();
    if (!slug) return;
    this.pushView({ kind: 'space', slug });
    void this.loadSpace(slug);
  }

  async loadSpace(slug: string): Promise<void> {
    this.spaceLoading = true;
    this.spaceError = '';
    this.currentSpace = null;
    this.spacePosts = [];
    this.spacePostsCursor = null;
    this.composeTitle = '';
    this.composeBody = '';
    this.composeError = '';
    this.paint();
    const res = await this.anon.space(slug);
    this.spaceLoading = false;
    if ((res as AnonymousApiError).ok === false) {
      this.spaceError = this.anon.errorMessage(
        res as AnonymousApiError,
        'This Space may be private, removed, or temporarily unavailable.'
      );
      this.paint();
      return;
    }
    this.currentSpace = (res as { space: AnonymousSpace }).space;
    this.paint();
    void this.loadSpacePosts(true);
  }

  async loadSpacePosts(reset: boolean): Promise<void> {
    if (!this.currentSpace || this.spacePostsLoading) return;
    this.spacePostsLoading = true;
    if (reset) {
      this.spacePosts = [];
      this.spacePostsCursor = null;
    }
    this.paint();
    const res = await this.anon.listPosts(this.currentSpace.id, {
      sort: 'new',
      cursor: reset ? null : this.spacePostsCursor,
      limit: 24,
    });
    this.spacePostsLoading = false;
    if ((res as AnonymousApiError).ok === false) {
      this.spaceError = this.anon.errorMessage(res as AnonymousApiError, 'Couldn’t load posts.');
      this.paint();
      return;
    }
    const ok = res as { posts: AnonymousPost[]; next_cursor: string | null };
    this.spacePosts = reset ? ok.posts : [...this.spacePosts, ...ok.posts];
    this.spacePostsCursor = ok.next_cursor;
    this.paint();
  }

  loadMoreSpacePosts(): void {
    if (!this.spacePostsCursor) return;
    void this.loadSpacePosts(false);
  }

  openPost(post: AnonymousPost, spaceSlug?: string): void {
    this.pushView({
      kind: 'post',
      id: post.id,
      spaceSlug: spaceSlug || post.space_slug,
    });
    void this.loadPost(post.id);
  }

  async loadPost(id: string): Promise<void> {
    this.postLoading = true;
    this.postError = '';
    this.currentPost = null;
    this.comments = [];
    this.commentBody = '';
    this.composeError = '';
    this.paint();
    const res = await this.anon.getPost(id);
    this.postLoading = false;
    if ((res as AnonymousApiError).ok === false) {
      this.postError = this.anon.errorMessage(res as AnonymousApiError, 'Post unavailable.');
      this.paint();
      return;
    }
    this.currentPost = (res as { post: AnonymousPost }).post;
    this.paint();
    this.commentsLoading = true;
    const commentsRes = await this.anon.listComments(id);
    this.commentsLoading = false;
    if ((commentsRes as AnonymousApiError).ok !== false) {
      this.comments = (commentsRes as { comments: AnonymousComment[] }).comments || [];
    }
    this.paint();
  }

  async joinCurrent(): Promise<void> {
    if (!this.currentSpace || this.busy) return;
    if (!this.isFreeSpace(this.currentSpace)) {
      this.tryPaidCheckout();
      return;
    }
    this.busy = true;
    this.paint();
    const res = await this.anon.join(this.currentSpace.id);
    this.busy = false;
    if ((res as AnonymousApiError).ok === false) {
      this.spaceError = this.anon.errorMessage(res as AnonymousApiError);
      this.paint();
      return;
    }
    this.currentSpace = { ...this.currentSpace, joined: true };
    this.paint();
  }

  async leaveCurrent(): Promise<void> {
    if (!this.currentSpace || this.busy) return;
    this.busy = true;
    this.paint();
    const res = await this.anon.leave(this.currentSpace.id);
    this.busy = false;
    if ((res as AnonymousApiError).ok === false) {
      this.spaceError = this.anon.errorMessage(res as AnonymousApiError);
      this.paint();
      return;
    }
    this.currentSpace = { ...this.currentSpace, joined: false };
    this.paint();
  }

  async tryPaidCheckout(): Promise<void> {
    const res = await this.anon.checkoutStart({});
    this.composeError = this.anon.errorMessage(
      res,
      'Paid Spaces are coming soon. Join free Spaces for now.'
    );
    this.spaceError = this.composeError;
    this.paint();
  }

  async submitPost(): Promise<void> {
    if (!this.currentSpace || this.busy) return;
    const body = this.composeBody.trim();
    if (!body) return;
    this.busy = true;
    this.composeError = '';
    this.paint();
    const res = await this.anon.createPost(this.currentSpace.id, {
      title: this.composeTitle.trim() || undefined,
      body,
    });
    this.busy = false;
    if ((res as AnonymousApiError).ok === false) {
      this.composeError = this.anon.errorMessage(res as AnonymousApiError);
      this.paint();
      return;
    }
    const post = (res as { post: AnonymousPost }).post;
    this.composeTitle = '';
    this.composeBody = '';
    this.spacePosts = [post, ...this.spacePosts];
    this.currentSpace = {
      ...this.currentSpace,
      post_count: (this.currentSpace.post_count || 0) + 1,
      joined: true,
    };
    this.paint();
  }

  async submitComment(): Promise<void> {
    if (!this.currentPost || this.busy) return;
    const body = this.commentBody.trim();
    if (!body) return;
    this.busy = true;
    this.composeError = '';
    this.paint();
    const res = await this.anon.createComment(this.currentPost.id, { body });
    this.busy = false;
    if ((res as AnonymousApiError).ok === false) {
      this.composeError = this.anon.errorMessage(res as AnonymousApiError);
      this.paint();
      return;
    }
    const comment = (res as { comment: AnonymousComment }).comment;
    this.commentBody = '';
    this.comments = [...this.comments, comment];
    this.currentPost = {
      ...this.currentPost,
      comment_count: (this.currentPost.comment_count || 0) + 1,
    };
    this.paint();
  }

  async submitCreateSpace(): Promise<void> {
    if (this.busy) return;
    const title = this.newSpaceTitle.trim();
    if (!title) return;
    this.busy = true;
    this.composeError = '';
    this.paint();
    const res = await this.anon.createSpace({
      title,
      description: this.newSpaceDesc.trim() || undefined,
      category: this.newSpaceCategory.trim() || undefined,
    });
    this.busy = false;
    if ((res as AnonymousApiError).ok === false) {
      this.composeError = this.anon.errorMessage(res as AnonymousApiError);
      this.paint();
      return;
    }
    const space = (res as { space: AnonymousSpace }).space;
    this.spaces = [space, ...this.spaces];
    this.viewStack = [];
    this.view = { kind: 'space', slug: space.slug };
    this.currentSpace = space;
    this.spacePosts = [];
    this.paint();
  }

  async votePost(post: AnonymousPost, value: 1 | -1): Promise<void> {
    const next = post.my_vote === value ? 0 : value;
    const res = await this.anon.vote('post', post.id, next as -1 | 0 | 1);
    if ((res as AnonymousApiError).ok === false) return;
    const ok = res as { value: number; score: number };
    post.my_vote = ok.value;
    post.score = ok.score;
    this.paint();
  }

  async voteComment(comment: AnonymousComment, value: 1 | -1): Promise<void> {
    const next = comment.my_vote === value ? 0 : value;
    const res = await this.anon.vote('comment', comment.id, next as -1 | 0 | 1);
    if ((res as AnonymousApiError).ok === false) return;
    const ok = res as { value: number; score: number };
    comment.my_vote = ok.value;
    comment.score = ok.score;
    this.paint();
  }

  goBack(): void {
    const prev = this.viewStack.pop();
    if (prev) {
      this.view = prev;
      this.paint();
      return;
    }
    this.view = { kind: 'shell' };
    this.paint();
  }

  private pushView(next: View): void {
    this.viewStack.push(this.view);
    this.view = next;
    this.paint();
  }

  openNotifications(): void {
    this.notificationsUi.open();
  }

  goProfileSetup(): void {
    void this.router.navigate(['/settings']);
  }

  goAuth(): void {
    void this.router.navigate(['/auth'], { queryParams: { next: '/anonymous' } });
  }

  isFreeSpace(space: AnonymousSpace): boolean {
    return space.admission === 'free' && (space.billing_mode === 'free' || !space.billing_mode);
  }

  relativeTime(iso: string): string {
    const t = Date.parse(iso);
    if (!Number.isFinite(t)) return '';
    const sec = Math.max(0, Math.floor((Date.now() - t) / 1000));
    if (sec < 60) return 'just now';
    if (sec < 3600) return `${Math.floor(sec / 60)}m`;
    if (sec < 86400) return `${Math.floor(sec / 3600)}h`;
    if (sec < 86400 * 7) return `${Math.floor(sec / 86400)}d`;
    return new Date(t).toLocaleDateString();
  }

  trackSpace(_: number, s: AnonymousSpace): string {
    return s.id;
  }
  trackPost(_: number, p: AnonymousPost): string {
    return p.id;
  }
  trackComment(_: number, c: AnonymousComment): string {
    return c.id;
  }

  private localPreviewUsername(): string {
    const adjectives = [
      'quiet', 'bright', 'swift', 'calm', 'bold', 'keen', 'soft', 'wild',
      'clear', 'noble', 'lunar', 'misty', 'solar', 'tidal', 'velvet', 'winter',
    ];
    const nouns = [
      'orbit', 'comet', 'river', 'forest', 'harbor', 'meadow', 'nebula', 'pebble',
      'phoenix', 'quartz', 'raven', 'spark', 'summit', 'valley', 'willow', 'zenith',
    ];
    const a = adjectives[Math.floor(Math.random() * adjectives.length)];
    const n = nouns[Math.floor(Math.random() * nouns.length)];
    const num = String(Math.floor(Math.random() * 9000) + 1000);
    return `${a}_${n}_${num}`;
  }
}
