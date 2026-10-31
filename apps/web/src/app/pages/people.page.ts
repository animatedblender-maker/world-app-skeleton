import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { Router } from '@angular/router';

import { VerifiedBadgeComponent } from '../components/verified-badge.component';
import { AuthService } from '../core/services/auth.service';
import { ProfileService, showsVerifiedBadge, type Profile } from '../core/services/profile.service';
import { FollowService } from '../core/services/follow.service';
import { FakeDataService } from '../core/services/fake-data.service';
import { CountriesService, type CountryModel } from '../data/countries.service';
import { resolveAvatarUrl } from '../core/utils/media-url.util';

/** Pixel port of iOS PeopleView — paper list, ink Follow, verified bronze. */
@Component({
  selector: 'app-people-page',
  standalone: true,
  imports: [CommonModule, VerifiedBadgeComponent],
  template: `
    <div class="people-shell">
      <header class="nav">
        <button class="nav-btn" type="button" (click)="goBack()" aria-label="Back">←</button>
        <div class="nav-title">People</div>
        <span class="nav-spacer"></span>
      </header>

      <section class="people-body">
        <div class="people-state" *ngIf="loading && !people.length">Loading people…</div>
        <div class="people-state error" *ngIf="error && !people.length">{{ error }}</div>
        <div class="people-state" *ngIf="!loading && !error && !people.length">
          No people yet. Check back soon for new members.
        </div>

        <div class="people-list" *ngIf="people.length">
          <div class="person-card" *ngFor="let person of people">
            <button class="person-main" type="button" (click)="openUserProfile(person)">
              <div class="person-avatar">
                <img
                  *ngIf="avatarFor(person)"
                  [src]="avatarFor(person)"
                  alt=""
                />
                <div class="person-fallback" *ngIf="!avatarFor(person)">
                  {{ (person.display_name || person.username || 'User').slice(0, 2).toUpperCase() }}
                </div>
              </div>
              <div class="person-copy">
                <div class="person-name-row">
                  <div class="person-name">{{ person.display_name || person.username || 'Member' }}</div>
                  <app-verified-badge *ngIf="isVerified(person)" [size]="14"></app-verified-badge>
                </div>
                <div class="person-meta">
                  @{{ person.username || 'user' }}
                  <span *ngIf="person.country_name"> · {{ person.country_name }}</span>
                </div>
              </div>
            </button>
            <button
              *ngIf="meId && person.user_id !== meId && !isDemo(person)"
              class="follow-chip"
              type="button"
              [class.following]="isFollowingAuthor(person.user_id)"
              (click)="toggleFollow(person.user_id); $event.stopPropagation()"
              [disabled]="followBusyFor(person.user_id)"
            >
              {{ isFollowingAuthor(person.user_id) ? 'Following' : 'Follow' }}
            </button>
          </div>
        </div>

        <button
          class="load-more-btn"
          type="button"
          *ngIf="hasMore && !loading"
          (click)="loadMore()"
          [disabled]="loadingMore"
        >
          {{ loadingMore ? 'Loading…' : 'Load more' }}
        </button>
      </section>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100vh;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
      }
      .people-shell {
        max-width: 680px;
        margin: 0 auto;
        min-height: 100vh;
        padding-bottom: calc(28px + env(safe-area-inset-bottom, 0px));
        box-sizing: border-box;
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
        z-index: 10;
      }
      .nav-title {
        text-align: center;
        font-size: 16px;
        font-weight: 650;
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
      .people-body {
        padding: 12px var(--m-page-padding, 16px) 24px;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .people-state {
        font-size: 14px;
        color: var(--m-ink-muted, #948b82);
        padding: 24px 0;
        text-align: center;
      }
      .people-state.error {
        color: var(--m-danger, #ea000b);
      }
      .people-list {
        display: flex;
        flex-direction: column;
        gap: 0;
      }
      @media (min-width: 900px) {
        .people-shell {
          max-width: 920px;
        }
        .people-list {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 8px;
        }
      }
      .person-card {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 10px 4px;
      }
      .person-main {
        flex: 1;
        display: flex;
        align-items: center;
        gap: 12px;
        border: 0;
        background: transparent;
        padding: 0;
        text-align: left;
        cursor: pointer;
        color: inherit;
        min-width: 0;
      }
      .person-avatar {
        width: 44px;
        height: 44px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        border: 0.5px solid var(--m-border, #ddd8d1);
        display: grid;
        place-items: center;
        flex: 0 0 auto;
      }
      .person-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .person-fallback {
        font-size: 12px;
        font-weight: 700;
      }
      .person-copy {
        min-width: 0;
      }
      .person-name-row {
        display: inline-flex;
        align-items: center;
        gap: 5px;
      }
      .person-name {
        font-size: 14px;
        font-weight: 650;
      }
      .person-meta {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .follow-chip {
        border: 0;
        border-radius: 999px;
        padding: 7px 14px;
        background: var(--m-ink, #2c2825);
        color: var(--m-paper, #f8f6f2);
        cursor: pointer;
        font-weight: 700;
        font-size: 12px;
        flex-shrink: 0;
      }
      .follow-chip.following {
        background: var(--m-surface-muted, var(--m-canvas-muted, #f2f0ec));
        color: var(--m-ink-secondary, #6b645d);
        border: 0.5px solid var(--m-border, #ddd8d1);
      }
      .follow-chip:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
      .load-more-btn {
        align-self: flex-start;
        margin-top: 8px;
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: var(--m-control-radius, 8px);
        padding: 10px 14px;
        background: var(--m-matte, #f6f3ef);
        color: var(--m-ink, #2c2825);
        cursor: pointer;
        font-weight: 650;
        font-size: 13px;
      }
      .load-more-btn:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
    `,
  ],
})
export class PeoplePageComponent implements OnInit, OnDestroy {
  people: Profile[] = [];
  countries: CountryModel[] = [];
  meId: string | null = null;
  loading = false;
  loadingMore = false;
  error = '';
  hasMore = false;

  private readonly PAGE_SIZE = 30;
  private followingIds = new Set<string>();
  private followBusyMap = new Map<string, boolean>();

  constructor(
    private router: Router,
    private auth: AuthService,
    private profiles: ProfileService,
    private followService: FollowService,
    private fakeData: FakeDataService,
    private countriesService: CountriesService,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    this.setAppBackground();
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;
    await this.loadCountries();
    await this.refreshFollowingSnapshot();
    await this.loadPeople(true);
  }

  ngOnDestroy(): void {
    this.clearAppBackground();
  }

  avatarFor(person: Profile): string {
    return resolveAvatarUrl(person.avatar_url, person.username || person.user_id) || '';
  }

  isVerified(person: Profile): boolean {
    return showsVerifiedBadge(person);
  }

  isDemo(person: Profile): boolean {
    return String(person.user_id || '').startsWith('user_');
  }

  goBack(): void {
    if (window.history.length > 1) window.history.back();
    else void this.router.navigate(['/search']);
  }

  openUserProfile(person: Profile): void {
    const slug = String(person.username ?? '').trim() || String(person.user_id ?? '').trim();
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  isFollowingAuthor(userId?: string | null): boolean {
    return !!userId && this.followingIds.has(userId);
  }

  followBusyFor(userId?: string | null): boolean {
    const key = String(userId ?? '').trim();
    return !!key && this.followBusyMap.get(key) === true;
  }

  async toggleFollow(userId: string): Promise<void> {
    const key = String(userId ?? '').trim();
    if (!this.meId || !key || key === this.meId || this.followBusyFor(key)) return;
    this.followBusyMap.set(key, true);
    this.paint();
    try {
      if (this.followingIds.has(key)) {
        await this.followService.unfollow(this.meId, key);
        this.followingIds.delete(key);
      } else {
        await this.followService.follow(this.meId, key);
        this.followingIds.add(key);
      }
    } finally {
      this.followBusyMap.delete(key);
      this.paint();
    }
  }

  async loadMore(): Promise<void> {
    if (this.loadingMore || !this.hasMore) return;
    await this.loadPeople(false);
  }

  private async loadCountries(): Promise<void> {
    try {
      const data = await this.countriesService.loadCountries();
      this.countries = data.countries ?? [];
    } catch {
      this.countries = [];
    }
  }

  private async refreshFollowingSnapshot(): Promise<void> {
    if (!this.meId) return;
    try {
      const ids = await this.followService.listFollowingIds(this.meId);
      this.followingIds = new Set((ids ?? []).map((id: string) => String(id)));
    } catch {
      this.followingIds = new Set();
    }
  }

  private async loadPeople(reset: boolean): Promise<void> {
    const offset = reset ? 0 : this.people.length;
    if (reset) {
      this.loading = true;
      this.error = '';
      this.people = [];
    } else {
      this.loadingMore = true;
    }
    this.paint();
    try {
      const [real, fake] = await Promise.all([
        this.profiles.browseProfilesReal(this.PAGE_SIZE, offset),
        this.fakeData.getProfiles(this.countries),
      ]);
      const fakeSlice = fake.slice(offset, offset + this.PAGE_SIZE);
      const next = this.mergePeople(reset ? [] : this.people, real.browseProfiles ?? [], fakeSlice);
      this.people = next;
      this.hasMore =
        (real.browseProfiles?.length ?? 0) >= this.PAGE_SIZE || fake.length > offset + this.PAGE_SIZE;
    } catch (e: any) {
      this.error = e?.message ?? 'Failed to load people.';
      this.hasMore = false;
    } finally {
      this.loading = false;
      this.loadingMore = false;
      this.paint();
    }
  }

  private mergePeople(base: Profile[], real: Profile[], fake: Profile[]): Profile[] {
    const next: Profile[] = [];
    const seen = new Set<string>();
    const push = (profile: Profile) => {
      const key = String(profile.user_id || profile.username || '').trim();
      if (!key || seen.has(key)) return;
      seen.add(key);
      next.push(profile);
    };
    base.forEach(push);
    real.forEach(push);
    fake.forEach(push);
    return next;
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  private setAppBackground(): void {
    try {
      const root = document.documentElement;
      root.classList.remove('app-bg-globe', 'app-bg-feed', 'app-bg-light');
      root.classList.add('app-bg-feed');
      document.body.style.backgroundColor = 'var(--m-paper, #f8f6f2)';
      document.documentElement.style.backgroundColor = 'var(--m-paper, #f8f6f2)';
    } catch {
      // ignore
    }
  }

  private clearAppBackground(): void {
    try {
      const root = document.documentElement;
      root.classList.remove('app-bg-globe', 'app-bg-feed', 'app-bg-light');
      root.classList.add('app-bg-light');
    } catch {
      // ignore
    }
  }
}
