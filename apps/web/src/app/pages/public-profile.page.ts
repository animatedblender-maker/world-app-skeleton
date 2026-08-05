import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { MatteryaPostCardComponent } from '../components/matterya-post-card.component';
import type { CountryPost } from '../core/models/post.model';
import { AuthService } from '../core/services/auth.service';
import { FollowService } from '../core/services/follow.service';
import { MessagesService } from '../core/services/messages.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService, type Profile } from '../core/services/profile.service';
import { resolveAvatarUrl } from '../core/utils/media-url.util';
import { HubsCatalogService } from '../hubs/hubs-catalog.service';

/** Pixel port of iOS PublicProfileView — same chrome language as owner profile. */
@Component({
  selector: 'app-public-profile-page',
  standalone: true,
  imports: [CommonModule, BottomTabsComponent, MatteryaPostCardComponent],
  template: `
    <div class="shell">
      <header class="nav">
        <button type="button" class="nav-btn" (click)="back()" aria-label="Back">←</button>
        <div class="nav-title">{{ profile?.display_name || profile?.username || 'Profile' }}</div>
        <button type="button" class="nav-btn" (click)="share()" aria-label="Share">↗</button>
      </header>

      <div class="state" *ngIf="loading">Loading…</div>
      <div class="state error" *ngIf="!loading && error">{{ error }}</div>

      <main *ngIf="!loading && profile as p" class="body">
        <section class="header">
          <div class="identity">
            <div class="avatar">
              <img *ngIf="avatar" [src]="avatar" alt="" />
              <span *ngIf="!avatar">{{ initials }}</span>
            </div>
            <div class="identity-text">
              <div class="name-row">
                <div class="display-name" *ngIf="p.display_name">{{ p.display_name }}</div>
                <button
                  type="button"
                  class="follow-pill"
                  *ngIf="!isOwner && canFollow"
                  [class.on]="viewerFollowing"
                  [disabled]="followBusy"
                  (click)="toggleFollow()"
                >
                  {{ viewerFollowing ? 'Following' : 'Follow' }}
                </button>
              </div>
              <div class="handle" *ngIf="p.username">@{{ p.username }}</div>
              <div class="stats">
                <div class="stat"><div class="stat-val">{{ posts.length }}</div><div class="stat-lab">Posts</div></div>
                <div class="stat"><div class="stat-val">{{ followers }}</div><div class="stat-lab">Followers</div></div>
                <div class="stat"><div class="stat-val">{{ following }}</div><div class="stat-lab">Following</div></div>
              </div>
            </div>
          </div>

          <p class="bio" *ngIf="bio">{{ bio }}</p>
          <div class="country" *ngIf="p.country_name && p.country_name !== 'Unknown'">◎ {{ p.country_name }}</div>

          <button type="button" class="secondary" *ngIf="hasHubVideos" (click)="openChannel()">
            Watch on Hubs
          </button>

          <div class="actions" *ngIf="isOwner">
            <button type="button" class="secondary" (click)="goOwnerEdit()">Edit profile</button>
            <button type="button" class="secondary" (click)="goOwnerSettings()">Settings</button>
          </div>
          <div class="actions" *ngIf="!isOwner">
            <button type="button" class="primary" [disabled]="messageBusy" (click)="message()">
              {{ messageBusy ? 'Opening…' : 'Message' }}
            </button>
            <button type="button" class="secondary" (click)="share()">Share</button>
          </div>
          <div class="hint error" *ngIf="actionError">{{ actionError }}</div>
        </section>

        <section class="posts">
          <div class="section-kicker">Posts</div>
          <div class="section-title">Shared with the world</div>
          <div class="state" *ngIf="loadingPosts">Loading posts…</div>
          <div class="state" *ngIf="!loadingPosts && !posts.length">No posts yet.</div>
          <app-matterya-post-card
            *ngFor="let post of posts; trackBy: trackById"
            [post]="post"
            [edgeToEdge]="true"
          ></app-matterya-post-card>
        </section>
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
      .shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 49px) + 16px);
        width: 100%;
      }
      .nav {
        display: grid;
        grid-template-columns: 44px 1fr 44px;
        align-items: center;
        height: calc(44px + env(safe-area-inset-top));
        padding: env(safe-area-inset-top) 8px 0;
        background: var(--m-canvas, #f8f6f2);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        position: sticky;
        top: 0;
        z-index: 20;
      }
      .nav-title {
        text-align: center;
        font-size: 16px;
        font-weight: 650;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .nav-btn {
        border: 0;
        background: transparent;
        width: 44px;
        height: 44px;
        font-size: 18px;
        color: var(--m-ink, #2c2825);
        cursor: pointer;
      }
      .header {
        padding: 8px var(--m-page-padding, 16px) 20px;
        display: flex;
        flex-direction: column;
        gap: 16px;
      }
      .identity {
        display: flex;
        gap: 20px;
        align-items: center;
      }
      .avatar {
        width: 78px;
        height: 78px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        border: 0.5px solid var(--m-border, #ddd8d1);
        display: grid;
        place-items: center;
        font-weight: 700;
        flex-shrink: 0;
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .name-row {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
      }
      .display-name {
        font-family: var(--m-serif);
        font-size: 24px;
        font-weight: 400;
        line-height: 1.15;
      }
      .follow-pill {
        border: 0;
        border-radius: 999px;
        padding: 8px 14px;
        font-size: 13px;
        font-weight: 650;
        background: var(--m-accent-bright, #7b6347);
        color: var(--m-paper, #f8f6f2);
        cursor: pointer;
      }
      .follow-pill.on {
        background: var(--m-canvas-muted, #f2f0ec);
        color: var(--m-ink, #2c2825);
        border: 0.5px solid var(--m-border, #ddd8d1);
      }
      .handle {
        font-size: 14px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 4px;
      }
      .stats {
        display: flex;
        gap: 18px;
        margin-top: 10px;
      }
      .stat-val {
        font-weight: 700;
        font-size: 15px;
      }
      .stat-lab {
        font-size: 11px;
        color: var(--m-ink-muted, #948b82);
      }
      .bio {
        margin: 0;
        font-size: 15px;
        line-height: 1.45;
        color: var(--m-ink-secondary, #6b645d);
        white-space: pre-wrap;
      }
      .country {
        font-size: 14px;
        color: var(--m-accent, #6b5841);
      }
      .actions {
        display: flex;
        gap: 10px;
      }
      .primary,
      .secondary {
        flex: 1;
        border-radius: var(--m-control-radius, 8px);
        padding: 10px 12px;
        font-size: 14px;
        font-weight: 650;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: var(--m-ink, #2c2825);
        color: var(--m-paper, #f8f6f2);
      }
      .secondary {
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-button-muted, #f0f0f0);
        color: var(--m-ink, #2c2825);
      }
      .posts {
        padding-bottom: 24px;
      }
      .section-kicker {
        font-family: var(--m-serif);
        font-size: 13px;
        font-weight: 650;
        letter-spacing: 2px;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
        padding: 0 var(--m-page-padding, 16px);
      }
      .section-title {
        font-family: var(--m-serif);
        font-size: 28px;
        font-weight: 400;
        padding: 4px var(--m-page-padding, 16px) 16px;
      }
      .state {
        padding: 40px 16px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
      }
      .state.error,
      .hint.error {
        color: var(--m-danger, #ea000b);
      }
      .hint {
        font-size: 12px;
      }
      /* desktop: single-column iOS public profile, full width */
      @media (min-width: 900px) {
        .shell {
          background: var(--m-paper, #f8f6f2);
          padding-bottom: 24px;
        }
        .header {
          max-width: none;
          margin: 0;
          padding: 16px 20px 20px;
          border-radius: 0;
          border: 0;
          border-bottom: 0.5px solid var(--m-divider, #e2ded8);
          background: var(--m-paper, #f8f6f2);
        }
        .nav {
          padding-left: 8px;
          padding-right: 8px;
        }
      }

    `,
  ],
})
export class PublicProfilePageComponent implements OnInit {
  profile: Profile | null = null;
  posts: CountryPost[] = [];
  loading = true;
  loadingPosts = false;
  error = '';
  actionError = '';
  meId: string | null = null;
  isOwner = false;
  canFollow = false;
  viewerFollowing = false;
  followBusy = false;
  messageBusy = false;
  followers = 0;
  following = 0;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private auth: AuthService,
    private profiles: ProfileService,
    private postsService: PostsService,
    private follow: FollowService,
    private messages: MessagesService,
    private catalog: HubsCatalogService,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    const slug = this.route.snapshot.paramMap.get('slug') || '';
    await this.load(slug);
  }

  get avatar(): string | null {
    if (!this.profile) return null;
    return resolveAvatarUrl(this.profile.avatar_url, this.profile.username || this.profile.user_id) || null;
  }

  get initials(): string {
    const n = this.profile?.display_name || this.profile?.username || 'U';
    return n.slice(0, 2).toUpperCase();
  }

  get bio(): string {
    return String(this.profile?.bio || '')
      .replace(/__living_channel__\|[^\n]*/g, '')
      .trim();
  }

  get hasHubVideos(): boolean {
    return this.posts.some((p) => this.catalog.isPlayEligible(p));
  }

  trackById(_: number, p: CountryPost): string {
    return p.id;
  }

  back(): void {
    if (window.history.length > 1) window.history.back();
    else void this.router.navigate(['/feed']);
  }

  goOwnerEdit(): void {
    void this.router.navigate(['/profile']);
  }

  goOwnerSettings(): void {
    void this.router.navigate(['/profile']);
  }

  openChannel(): void {
    if (!this.profile) return;
    void this.router.navigate(['/hubs', 'channel', this.profile.user_id]);
  }

  async share(): Promise<void> {
    if (!this.profile) return;
    const slug = this.profile.username || this.profile.user_id;
    const url = `${window.location.origin}/user/${slug}`;
    try {
      if (navigator.share) await navigator.share({ title: this.profile.display_name || slug, url });
      else await navigator.clipboard.writeText(url);
    } catch {
      // cancelled
    }
  }

  async toggleFollow(): Promise<void> {
    if (!this.meId || !this.profile || !this.canFollow || this.followBusy) return;
    this.followBusy = true;
    this.actionError = '';
    try {
      if (this.viewerFollowing) {
        await this.follow.unfollow(this.meId, this.profile.user_id);
        this.viewerFollowing = false;
        this.followers = Math.max(0, this.followers - 1);
      } else {
        await this.follow.follow(this.meId, this.profile.user_id);
        this.viewerFollowing = true;
        this.followers += 1;
      }
    } catch (e: any) {
      this.actionError = e?.message || 'Follow failed';
    } finally {
      this.followBusy = false;
      this.paint();
    }
  }

  async message(): Promise<void> {
    if (!this.profile || this.messageBusy) return;
    this.messageBusy = true;
    this.actionError = '';
    try {
      const convo = await this.messages.startConversation(this.profile.user_id);
      const id = (convo as any)?.id || (convo as any)?.conversation_id;
      void this.router.navigate(['/messages'], { queryParams: id ? { c: id } : {} });
    } catch (e: any) {
      this.actionError = e?.message || 'Could not open chat';
    } finally {
      this.messageBusy = false;
      this.paint();
    }
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  private async load(slugRaw: string): Promise<void> {
    this.loading = true;
    this.error = '';
    this.profile = null;
    this.paint();
    try {
      const user = await this.auth.getUser().catch(() => null);
      this.meId = user?.id ?? null;
      const slug = slugRaw.trim().replace(/^@/, '');
      if (!slug) throw new Error('Profile not found.');

      let profile: Profile | null = null;
      const byUsername = await this.profiles.profileByUsername(slug);
      profile = byUsername.profileByUsername ?? null;
      if (!profile) {
        const byId = await this.profiles.profileById(slug);
        profile = byId.profileById ?? null;
      }
      if (!profile) throw new Error('Profile not found.');

      // If this is me, send to owner tab layout.
      if (this.meId && profile.user_id === this.meId) {
        void this.router.navigateByUrl('/profile');
        return;
      }

      this.profile = profile;
      this.isOwner = !!this.meId && profile.user_id === this.meId;
      this.canFollow = !!this.meId && !this.isOwner && !String(profile.user_id).startsWith('user_');
      this.loading = false;
      this.paint();

      this.loadingPosts = true;
      this.paint();
      const [posts, counts, following] = await Promise.all([
        this.postsService.listForAuthor(profile.user_id, 40).catch(() => [] as CountryPost[]),
        this.follow.counts(profile.user_id).catch(() => ({ followers: 0, following: 0 })),
        this.meId && this.canFollow
          ? this.follow.isFollowing(this.meId, profile.user_id).catch(() => false)
          : Promise.resolve(false),
      ]);
      this.posts = (posts || []).filter(
        (p) => !this.postsService.isMoment(p) && !this.postsService.isSpark(p)
      );
      this.followers = counts.followers;
      this.following = counts.following;
      this.viewerFollowing = !!following;
    } catch (e: any) {
      this.error = e?.message || 'Profile unavailable';
    } finally {
      this.loading = false;
      this.loadingPosts = false;
      this.paint();
    }
  }
}
