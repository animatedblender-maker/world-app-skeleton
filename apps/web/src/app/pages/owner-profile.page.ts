import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { MatteryaPostCardComponent } from '../components/matterya-post-card.component';
import { MatteryaTopbarComponent } from '../components/matterya-topbar.component';
import type { CountryPost } from '../core/models/post.model';
import { AuthService } from '../core/services/auth.service';
import { FollowService } from '../core/services/follow.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService, type Profile } from '../core/services/profile.service';
import { resolveAvatarUrl } from '../core/utils/media-url.util';
import { NotificationsUiService } from '../core/services/notifications-ui.service';
import { HubsCatalogService } from '../hubs/hubs-catalog.service';

type LibrarySection = 'posts' | 'savedPosts' | 'savedVideos' | 'savedReels';

/**
 * Pixel port of iOS ProfileView (owner tab) — not the overloaded public profile page.
 */
@Component({
  selector: 'app-owner-profile-page',
  standalone: true,
  imports: [
    CommonModule,
    BottomTabsComponent,
    MatteryaTopbarComponent,
    MatteryaPostCardComponent,
  ],
  template: `
    <div class="profile-shell">
      <app-matterya-topbar
        title="Matterya"
        (search)="openSearch()"
        (notifications)="openNotifications()"
      ></app-matterya-topbar>

      <main class="profile-body" *ngIf="profile; else loadingTpl">
        <section class="header">
          <div class="identity">
            <div class="avatar">
              <img *ngIf="avatar" [src]="avatar" alt="" />
              <span *ngIf="!avatar">{{ initials }}</span>
            </div>
            <div class="identity-text">
              <div class="display-name" *ngIf="profile.display_name">{{ profile.display_name }}</div>
              <div class="handle" *ngIf="profile.username">@{{ profile.username }}</div>
              <div class="stats">
                <div class="stat">
                  <div class="stat-val">{{ posts.length }}</div>
                  <div class="stat-lab">Posts</div>
                </div>
                <div class="stat">
                  <div class="stat-val">{{ followers }}</div>
                  <div class="stat-lab">Followers</div>
                </div>
                <div class="stat">
                  <div class="stat-val">{{ following }}</div>
                  <div class="stat-lab">Following</div>
                </div>
              </div>
            </div>
          </div>

          <div class="actions">
            <button type="button" class="secondary" (click)="openEdit()">Edit profile</button>
            <button type="button" class="secondary" (click)="openSettings()">Settings</button>
          </div>

          <p class="bio" *ngIf="bio">{{ bio }}</p>
          <div class="country" *ngIf="profile.country_name && profile.country_name !== 'Unknown'">
            ◎ {{ profile.country_name }}
          </div>

          <button type="button" class="secondary channel" *ngIf="hasHubVideos" (click)="openMyChannel()">
            Your channel on Hubs
          </button>
        </section>

        <div class="lib-chips">
          <button
            type="button"
            class="chip"
            *ngFor="let s of sections"
            [class.active]="section === s.id"
            (click)="section = s.id"
          >
            {{ s.title }}
          </button>
        </div>

        <section class="lib">
          <div class="lib-head">
            <div class="lib-kicker">{{ sectionKicker }}</div>
            <div class="lib-title">{{ sectionTitle }}</div>
          </div>

          <div class="state" *ngIf="loadingPosts">Loading…</div>
          <div class="state" *ngIf="!loadingPosts && !sectionPosts.length">{{ emptyMessage }}</div>

          <app-matterya-post-card
            *ngFor="let post of sectionPosts; trackBy: trackById"
            [post]="post"
            [edgeToEdge]="true"
          ></app-matterya-post-card>
        </section>
      </main>

      <ng-template #loadingTpl>
        <div class="state">Loading your profile…</div>
      </ng-template>

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
      .profile-shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 49px) + 16px);
        width: 100%;
      }
      .header {
        padding: 12px var(--m-page-padding, 16px) 18px;
        display: flex;
        flex-direction: column;
        gap: 18px;
      }
      .identity {
        display: flex;
        gap: 22px;
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
        font-size: 22px;
        font-weight: 650;
        flex-shrink: 0;
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .display-name {
        font-family: var(--m-serif);
        font-size: 26px;
        font-weight: 400;
        line-height: 1.15;
        color: var(--m-ink, #2c2825);
      }
      .handle {
        margin-top: 4px;
        font-size: 14px;
        color: var(--m-ink-muted, #948b82);
      }
      .stats {
        display: flex;
        gap: 18px;
        margin-top: 10px;
      }
      .stat-val {
        font-size: 15px;
        font-weight: 700;
      }
      .stat-lab {
        font-size: 11px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 1px;
      }
      .actions {
        display: flex;
        gap: 10px;
      }
      .secondary {
        flex: 1;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-button-muted, #f0f0f0);
        border-radius: var(--m-control-radius, 8px);
        padding: 10px 12px;
        font-size: 14px;
        font-weight: 650;
        color: var(--m-ink, #2c2825);
        cursor: pointer;
      }
      .secondary.channel {
        flex: none;
        width: 100%;
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
      .lib-chips {
        display: flex;
        gap: 8px;
        overflow-x: auto;
        padding: 0 var(--m-page-padding, 16px) 16px;
        scrollbar-width: none;
      }
      .lib-chips::-webkit-scrollbar {
        display: none;
      }
      .chip {
        flex-shrink: 0;
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
        font-weight: 650;
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
        bottom: 0;
        height: 1px;
        background: var(--m-ink, #2c2825);
      }
      .lib {
        padding-bottom: 24px;
      }
      .lib-head {
        padding: 0 var(--m-page-padding, 16px) 16px;
      }
      .lib-kicker {
        font-family: var(--m-serif);
        font-size: 13px;
        font-weight: 650;
        letter-spacing: 2px;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
      }
      .lib-title {
        margin-top: 4px;
        font-family: var(--m-serif);
        font-size: 28px;
        font-weight: 400;
        color: var(--m-ink, #2c2825);
      }
      .state {
        padding: 40px 16px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
      }
      @media (min-width: 900px) {
        /* iOS ProfileView: single column, full content width — not a masonry grid */
        .profile-shell {
          background: var(--m-paper, #f8f6f2);
          padding-bottom: 24px;
        }
        .profile-body {
          max-width: none;
          margin: 0;
          padding: 0;
          width: 100%;
        }
        .header {
          padding: 18px 20px 20px;
          gap: 16px;
          border-bottom: 0.5px solid var(--m-divider, #e2ded8);
          background: var(--m-paper, #f8f6f2);
          border-radius: 0;
          border: 0;
          margin: 0;
        }
        .identity {
          gap: 22px;
        }
        .avatar {
          width: 88px;
          height: 88px;
        }
        .display-name {
          font-size: 28px;
        }
        .lib-chips {
          padding: 8px 12px 12px;
          border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        }
        .lib {
          display: block;
          background: transparent;
          border: 0;
          border-radius: 0;
          padding-bottom: 32px;
          max-width: 680px;
          margin: 0 auto;
        }
        .lib-head {
          padding: 16px 16px 12px;
        }
        .lib-title {
          font-size: 28px;
        }
        .header {
          max-width: 680px;
          margin: 0 auto;
        }
        .lib-chips {
          max-width: 680px;
          margin: 0 auto;
        }
      }

    `,
  ],
})
export class OwnerProfilePageComponent implements OnInit {
  profile: Profile | null = null;
  posts: CountryPost[] = [];
  followers = 0;
  following = 0;
  loadingPosts = false;
  section: LibrarySection = 'posts';
  sections: { id: LibrarySection; title: string }[] = [
    { id: 'posts', title: 'Posts' },
    { id: 'savedPosts', title: 'Saved' },
    { id: 'savedVideos', title: 'Videos' },
    { id: 'savedReels', title: 'Sparks' },
  ];

  constructor(
    private auth: AuthService,
    private profiles: ProfileService,
    private postsService: PostsService,
    private follow: FollowService,
    private catalog: HubsCatalogService,
    private router: Router,
    private notificationsUi: NotificationsUiService,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    await this.load();
  }

  get avatar(): string | null {
    if (!this.profile) return null;
    return resolveAvatarUrl(this.profile.avatar_url, this.profile.username || this.profile.user_id) || null;
  }

  get initials(): string {
    const n = this.profile?.display_name || this.profile?.username || 'ME';
    return n.slice(0, 2).toUpperCase();
  }

  get bio(): string {
    const raw = String(this.profile?.bio || '');
    // Strip iOS living channel marker if present
    return raw.replace(/__living_channel__\|[^\n]*/g, '').trim();
  }

  get hasHubVideos(): boolean {
    return this.posts.some((p) => this.catalog.isPlayEligible(p));
  }

  get sectionPosts(): CountryPost[] {
    switch (this.section) {
      case 'posts':
        return this.posts;
      case 'savedPosts':
        return this.catalog.savedVideos(this.catalog.currentCatalog.length ? this.catalog.currentCatalog : this.posts)
          .filter((p) => !this.catalog.isPlayEligible(p));
      case 'savedVideos':
        return this.catalog.savedVideos(
          this.catalog.currentCatalog.length ? this.catalog.currentCatalog : this.posts
        );
      case 'savedReels':
        return this.catalog
          .reels(this.catalog.currentCatalog.length ? this.catalog.currentCatalog : this.posts)
          .filter((p) => this.catalog.isSaved(p.id));
      default:
        return [];
    }
  }

  get sectionKicker(): string {
    switch (this.section) {
      case 'posts':
        return 'Posts';
      case 'savedPosts':
        return 'Saved posts';
      case 'savedVideos':
        return 'Saved videos';
      case 'savedReels':
        return 'Saved sparks';
    }
  }

  get sectionTitle(): string {
    switch (this.section) {
      case 'posts':
        return "Everything you've shared";
      case 'savedPosts':
        return 'Bookmarks from your feed';
      case 'savedVideos':
        return 'Videos you bookmarked';
      case 'savedReels':
        return 'Sparks you saved';
    }
  }

  get emptyMessage(): string {
    switch (this.section) {
      case 'posts':
        return 'Nothing shared yet. Use Create to post.';
      case 'savedPosts':
        return 'Save posts from the feed to revisit them here.';
      case 'savedVideos':
        return 'Save videos from the feed to watch them later.';
      case 'savedReels':
        return 'Save Sparks to keep them here.';
    }
  }

  trackById(_: number, p: CountryPost): string {
    return p.id;
  }

  openSearch(): void {
    void this.router.navigate(['/search']);
  }

  openNotifications(): void {
    this.notificationsUi.open();
  }

  openEdit(): void {
    const slug = this.profile?.username || this.profile?.user_id;
    if (slug) void this.router.navigate(['/user-edit', slug], { queryParams: { edit: '1' } });
  }

  openSettings(): void {
    void this.router.navigate(['/settings']);
  }

  openMyChannel(): void {
    if (!this.profile?.user_id) return;
    void this.router.navigate(['/hubs', 'channel', this.profile.user_id]);
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  private async load(): Promise<void> {
    try {
      const user = await this.auth.getUser();
      if (!user?.id) {
        void this.router.navigate(['/auth']);
        return;
      }
      const { meProfile } = await this.profiles.meProfile();
      this.profile = meProfile;
      if (!this.profile) {
        void this.router.navigate(['/profile-setup']);
        return;
      }
      this.paint();

      this.loadingPosts = true;
      this.paint();
      const [posts, counts] = await Promise.all([
        this.postsService.listForAuthor(this.profile.user_id, 40).catch(() => [] as CountryPost[]),
        this.follow.counts(this.profile.user_id).catch(() => ({ followers: 0, following: 0 })),
      ]);
      this.posts = (posts || []).filter(
        (p) => !this.postsService.isMoment(p) && !this.postsService.isSpark(p)
      );
      this.followers = counts.followers;
      this.following = counts.following;
    } catch {
      // keep empty
    } finally {
      this.loadingPosts = false;
      this.paint();
    }
  }
}
