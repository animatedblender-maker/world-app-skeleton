import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { ProfileService, type Profile } from '../core/services/profile.service';
import { FollowService } from '../core/services/follow.service';
import { FakeDataService } from '../core/services/fake-data.service';
import { CountriesService, type CountryModel } from '../data/countries.service';

@Component({
  selector: 'app-people-page',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="people-shell">
      <header class="people-header">
        <button class="back-btn" type="button" (click)="goBack()">Back</button>
        <div>
          <div class="people-title">People</div>
          <div class="people-subtitle">Real and propagated accounts across Matterya</div>
        </div>
      </header>

      <section class="people-body">
        <div class="people-state" *ngIf="loading && !people.length">Loading people...</div>
        <div class="people-state error" *ngIf="error && !people.length">{{ error }}</div>

        <div class="people-list" *ngIf="people.length">
          <div class="person-card" *ngFor="let person of people">
            <button class="person-main" type="button" (click)="openUserProfile(person)">
              <div class="person-avatar">
                <img *ngIf="person.avatar_url" [src]="normalizeAvatarUrl(person.avatar_url)" alt="avatar" />
                <div class="person-fallback" *ngIf="!person.avatar_url">
                  {{ (person.display_name || person.username || 'User').slice(0, 2).toUpperCase() }}
                </div>
              </div>
              <div class="person-copy">
                <div class="person-name">{{ person.display_name || person.username || 'Member' }}</div>
                <div class="person-meta">
                  @{{ person.username || 'user' }}
                  <span *ngIf="person.country_name"> · {{ person.country_name }}</span>
                  <span *ngIf="person.city_name"> · {{ person.city_name }}</span>
                </div>
              </div>
            </button>
            <button
              *ngIf="meId && person.user_id !== meId"
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
          {{ loadingMore ? 'Loading...' : 'Load more people' }}
        </button>
      </section>
    </div>
  `,
  styles: [`
    :host {
      display: block;
      min-height: 100vh;
      background: linear-gradient(180deg, #f6f8fb 0%, #eef2f7 100%);
      color: #0f172a;
    }
    .people-shell {
      max-width: 920px;
      margin: 0 auto;
      min-height: 100vh;
      padding: 18px 16px calc(28px + env(safe-area-inset-bottom, 0px));
      box-sizing: border-box;
    }
    .people-header {
      display: flex;
      align-items: center;
      gap: 14px;
      margin-bottom: 18px;
    }
    .back-btn,
    .load-more-btn,
    .follow-chip {
      border: 1px solid rgba(15, 23, 42, 0.12);
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.96);
      color: rgba(15, 23, 42, 0.88);
      cursor: pointer;
      font-weight: 900;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .back-btn {
      padding: 10px 14px;
      font-size: 11px;
    }
    .people-title {
      font-size: 20px;
      font-weight: 900;
      letter-spacing: 0.04em;
    }
    .people-subtitle {
      font-size: 12px;
      opacity: 0.66;
      font-weight: 700;
    }
    .people-body {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .people-state {
      font-size: 12px;
      font-weight: 800;
      opacity: 0.7;
    }
    .people-state.error {
      color: #c2410c;
    }
    .people-list {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .person-card {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      padding: 14px 16px;
      border-radius: 18px;
      background: rgba(255, 255, 255, 0.98);
      border: 1px solid rgba(15, 23, 42, 0.08);
      box-shadow: 0 16px 40px rgba(15, 23, 42, 0.08);
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
    }
    .person-avatar {
      width: 46px;
      height: 46px;
      border-radius: 999px;
      overflow: hidden;
      background: rgba(241, 245, 249, 0.96);
      border: 1px solid rgba(15, 23, 42, 0.08);
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
      font-size: 13px;
      font-weight: 900;
      letter-spacing: 0.08em;
    }
    .person-copy {
      min-width: 0;
    }
    .person-name {
      font-size: 14px;
      font-weight: 900;
    }
    .person-meta {
      font-size: 12px;
      opacity: 0.68;
    }
    .follow-chip,
    .load-more-btn {
      padding: 10px 14px;
      font-size: 11px;
    }
    .follow-chip.following {
      background: rgba(15, 23, 42, 0.06);
    }
    .load-more-btn {
      align-self: flex-start;
      margin-top: 6px;
    }
    @media (max-width: 640px) {
      .people-shell {
        padding-left: 12px;
        padding-right: 12px;
      }
      .person-card {
        align-items: flex-start;
        flex-direction: column;
      }
      .follow-chip {
        align-self: flex-start;
      }
    }
  `],
})
export class PeoplePageComponent implements OnInit, OnDestroy {
  people: Profile[] = [];
  countries: CountryModel[] = [];
  meId: string | null = null;
  loading = false;
  loadingMore = false;
  error = '';
  hasMore = false;

  private readonly PAGE_SIZE = 80;
  private followingIds = new Set<string>();
  private followBusyMap = new Map<string, boolean>();

  constructor(
    private router: Router,
    private auth: AuthService,
    private profiles: ProfileService,
    private followService: FollowService,
    private fakeData: FakeDataService,
    private countriesService: CountriesService
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

  normalizeAvatarUrl(url?: string | null): string {
    const trimmed = String(url ?? '').trim();
    if (!trimmed) return '';
    if (/^https?:\/\//i.test(trimmed)) return trimmed;
    return trimmed;
  }

  goBack(): void {
    void this.router.navigate(['/globe']);
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

  private setAppBackground(): void {
    try {
      const root = document.documentElement;
      root.classList.remove('app-bg-globe', 'app-bg-feed', 'app-bg-light');
      root.classList.add('app-bg-feed');
      const computed = getComputedStyle(root).getPropertyValue('--app-bg').trim() || '#f6f8fb';
      document.body.style.backgroundColor = computed;
      document.documentElement.style.backgroundColor = computed;
    } catch {}
  }

  private clearAppBackground(): void {
    try {
      const root = document.documentElement;
      root.classList.remove('app-bg-globe', 'app-bg-feed', 'app-bg-light');
      root.classList.add('app-bg-light');
    } catch {}
  }
}
