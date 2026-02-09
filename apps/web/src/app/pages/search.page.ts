import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { PostsService } from '../core/services/posts.service';
import { ProfileService, type Profile } from '../core/services/profile.service';
import type { CountryPost } from '../core/models/post.model';

type SearchTab = 'posts' | 'people';

@Component({
  selector: 'app-search-page',
  standalone: true,
  imports: [CommonModule, FormsModule, BottomTabsComponent],
  template: `
    <div class="search-page">
      <header class="search-header">
        <div class="search-title">Search</div>
        <div class="search-bar">
          <span class="search-icon">🔍</span>
          <input
            type="text"
            name="search"
            autocomplete="off"
            placeholder="Search posts or people..."
            [(ngModel)]="query"
            (ngModelChange)="queueSearch()"
          />
          <button type="button" class="clear-btn" *ngIf="query" (click)="clearSearch()">x</button>
        </div>
        <div class="search-tabs">
          <button
            type="button"
            class="tab"
            [class.active]="activeTab === 'posts'"
            (click)="setTab('posts')"
          >
            Posts
          </button>
          <button
            type="button"
            class="tab"
            [class.active]="activeTab === 'people'"
            (click)="setTab('people')"
          >
            People
          </button>
        </div>
      </header>

      <section class="search-results">
        <div class="empty-state" *ngIf="!query && !isLoading">
          Start typing to search.
        </div>
        <div class="empty-state" *ngIf="query && !isLoading && !hasResults()">
          No results yet.
        </div>
        <div class="loader" *ngIf="isLoading">Searching...</div>

        <ng-container *ngIf="activeTab === 'posts'">
          <article
            class="post-card"
            *ngFor="let post of postResults; trackBy: trackPost"
            (click)="openPost(post)"
          >
            <div class="post-header">
              <div class="avatar">
                <img *ngIf="post.author?.avatar_url" [src]="post.author?.avatar_url" alt="avatar" />
                <span *ngIf="!post.author?.avatar_url">
                  {{ initialsFor(post.author?.display_name || post.author?.username || 'U') }}
                </span>
              </div>
              <div class="meta">
                <div class="name">{{ post.author?.display_name || post.author?.username || 'Member' }}</div>
                <div class="handle">@{{ post.author?.username || post.author?.user_id }}</div>
              </div>
            </div>
            <div class="post-body" *ngIf="post.body">{{ post.body }}</div>
            <div class="post-media" *ngIf="post.media_type && post.media_type !== 'none'">
              <img
                *ngIf="post.media_type === 'image'"
                [src]="post.media_url || post.thumb_url"
                alt="Post media"
              />
              <img
                *ngIf="post.media_type === 'video'"
                [src]="post.thumb_url || post.media_url"
                alt="Post video"
              />
            </div>
          </article>
          <button
            type="button"
            class="load-more"
            *ngIf="canLoadMorePosts()"
            (click)="loadMorePosts()"
          >
            Load more
          </button>
        </ng-container>

        <ng-container *ngIf="activeTab === 'people'">
          <button
            type="button"
            class="result-row"
            *ngFor="let profile of peopleResults; trackBy: trackProfile"
            (click)="openProfile(profile)"
          >
            <div class="avatar">
              <img *ngIf="profile.avatar_url" [src]="profile.avatar_url" alt="avatar" />
              <span *ngIf="!profile.avatar_url">
                {{ initialsFor(profile.display_name || profile.username || 'U') }}
              </span>
            </div>
            <div class="meta">
              <div class="name">{{ profile.display_name || profile.username || 'Member' }}</div>
              <div class="handle">@{{ profile.username || profile.user_id }}</div>
            </div>
          </button>
          <button
            type="button"
            class="load-more"
            *ngIf="canLoadMorePeople()"
            (click)="loadMorePeople()"
          >
            Load more
          </button>
        </ng-container>

      </section>
    </div>

    <app-bottom-tabs></app-bottom-tabs>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100svh;
        background: var(--app-bg);
        color: rgba(10, 18, 32, 0.92);
      }
      .search-page {
        min-height: 100svh;
        padding: calc(env(safe-area-inset-top) + 6px) 0
          calc(var(--tabs-height, 64px) + env(safe-area-inset-bottom));
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .search-header {
        position: sticky;
        top: 0;
        z-index: 2;
        background: var(--app-bg);
        padding: 10px 16px 8px;
        border-bottom: 1px solid rgba(7, 20, 40, 0.08);
      }
      .search-title {
        font-weight: 800;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        font-size: 11px;
        color: rgba(9, 22, 38, 0.65);
        margin-bottom: 8px;
      }
      .search-bar {
        display: flex;
        align-items: center;
        gap: 8px;
        background: rgba(7, 20, 40, 0.04);
        border: 1px solid rgba(7, 20, 40, 0.12);
        border-radius: 14px;
        padding: 8px 12px;
      }
      .search-bar input {
        border: 0;
        outline: none;
        background: transparent;
        flex: 1;
        font-size: 14px;
        color: inherit;
      }
      .search-icon {
        font-size: 16px;
        opacity: 0.7;
      }
      .clear-btn {
        border: 0;
        background: rgba(7, 20, 40, 0.1);
        width: 22px;
        height: 22px;
        border-radius: 50%;
        cursor: pointer;
        font-size: 12px;
        color: rgba(7, 20, 40, 0.8);
      }
      .search-tabs {
        margin-top: 10px;
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }
      .search-tabs .tab {
        border: 1px solid transparent;
        border-radius: 999px;
        padding: 6px 12px;
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        background: rgba(7, 20, 40, 0.08);
        color: rgba(7, 20, 40, 0.82);
        cursor: pointer;
      }
      .search-tabs .tab.active {
        border-color: rgba(0, 155, 220, 0.45);
        background: rgba(0, 155, 220, 0.14);
        color: rgba(7, 20, 40, 0.9);
      }
      .search-results {
        flex: 1;
        overflow: auto;
        min-height: 0;
        padding: 10px 16px calc(48px + var(--tabs-safe, 64px));
        display: grid;
        gap: 12px;
      }
      .loader,
      .empty-state {
        text-align: center;
        color: rgba(7, 20, 40, 0.55);
        font-size: 13px;
      }
      .post-card {
        background: rgba(7, 20, 40, 0.03);
        border-radius: 16px;
        padding: 12px;
        border: 1px solid rgba(7, 20, 40, 0.08);
        display: grid;
        gap: 10px;
        cursor: pointer;
      }
      .post-header {
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .avatar {
        width: 40px;
        height: 40px;
        border-radius: 50%;
        background: rgba(0, 155, 220, 0.12);
        display: grid;
        place-items: center;
        overflow: hidden;
        font-weight: 800;
        color: rgba(7, 20, 40, 0.8);
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .meta .name {
        font-weight: 800;
        font-size: 14px;
      }
      .meta .handle {
        font-size: 12px;
        color: rgba(7, 20, 40, 0.6);
      }
      .post-body {
        font-size: 14px;
        color: rgba(7, 20, 40, 0.85);
      }
      .post-media img {
        width: 100%;
        border-radius: 14px;
        display: block;
        background: #0b0f16;
      }
      .result-row {
        border: 1px solid rgba(7, 20, 40, 0.08);
        background: rgba(7, 20, 40, 0.03);
        border-radius: 14px;
        padding: 10px 12px;
        display: flex;
        align-items: center;
        gap: 12px;
        cursor: pointer;
        text-align: left;
      }
      .load-more {
        border: 1px solid rgba(0, 155, 220, 0.3);
        background: rgba(0, 155, 220, 0.08);
        color: rgba(7, 20, 40, 0.82);
        border-radius: 999px;
        padding: 8px 14px;
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        cursor: pointer;
        justify-self: center;
      }
    `,
  ],
})
export class SearchPageComponent implements OnInit, OnDestroy {
  query = '';
  activeTab: SearchTab = 'posts';
  isLoading = false;

  postResults: CountryPost[] = [];
  peopleResults: Profile[] = [];
  private postVisibleCount = 40;
  private peopleVisibleCount = 40;
  private hasMorePosts = false;
  private hasMorePeople = false;
  private searchSeq = 0;

  private searchTimer: ReturnType<typeof setTimeout> | null = null;
  private searchIdleHandle: number | null = null;

  constructor(
    private posts: PostsService,
    private profiles: ProfileService,
    private router: Router
  ) {}

  ngOnInit(): void {
    // no-op
  }

  ngOnDestroy(): void {
    if (this.searchTimer) {
      clearTimeout(this.searchTimer);
      this.searchTimer = null;
    }
  }

  setTab(tab: SearchTab): void {
    if (this.activeTab === tab) return;
    this.activeTab = tab;
    this.queueSearch();
  }

  clearSearch(): void {
    this.query = '';
    this.postResults = [];
    this.peopleResults = [];
    this.postVisibleCount = 40;
    this.peopleVisibleCount = 40;
    this.hasMorePosts = false;
    this.hasMorePeople = false;
  }

  queueSearch(): void {
    if (this.searchTimer) clearTimeout(this.searchTimer);
    if (this.searchIdleHandle !== null && 'cancelIdleCallback' in window) {
      (window as any).cancelIdleCallback(this.searchIdleHandle);
      this.searchIdleHandle = null;
    }
    this.searchTimer = setTimeout(() => {
      if ('requestIdleCallback' in window) {
        this.searchIdleHandle = (window as any).requestIdleCallback(
          () => {
            this.searchIdleHandle = null;
            void this.runSearch();
          },
          { timeout: 800 }
        );
      } else {
        void this.runSearch();
      }
    }, 360);
  }

  private async runSearch(): Promise<void> {
    const term = this.query.trim();
    if (!term || term.length < 2) {
      this.clearSearch();
      return;
    }
    const seq = ++this.searchSeq;
    this.isLoading = true;
    try {
      if (this.activeTab === 'posts') {
        const limit = this.postVisibleCount + 1;
        const results = await this.posts.searchPosts(term, limit);
        if (seq !== this.searchSeq) return;
        this.hasMorePosts = results.length > this.postVisibleCount;
        this.postResults = results.slice(0, this.postVisibleCount);
        this.peopleResults = [];
        this.hasMorePeople = false;
      } else if (this.activeTab === 'people') {
        const limit = this.peopleVisibleCount + 1;
        const result = await this.profiles.searchProfilesReal(term, limit);
        if (seq !== this.searchSeq) return;
        const people = result.searchProfiles ?? [];
        this.hasMorePeople = people.length > this.peopleVisibleCount;
        this.peopleResults = people.slice(0, this.peopleVisibleCount);
        this.postResults = [];
        this.hasMorePosts = false;
      }
    } catch {
      this.postResults = [];
      this.peopleResults = [];
      this.hasMorePosts = false;
      this.hasMorePeople = false;
    } finally {
      this.isLoading = false;
    }
  }

  openPost(post: CountryPost): void {
    void this.router.navigate(['/globe'], {
      queryParams: { post: post.id, tab: 'posts', panel: null },
    });
  }

  openProfile(profile: Profile): void {
    const slug = profile.username || profile.user_id;
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  hasResults(): boolean {
    return this.postResults.length > 0 || this.peopleResults.length > 0;
  }

  canLoadMorePosts(): boolean {
    return this.hasMorePosts;
  }

  canLoadMorePeople(): boolean {
    return this.hasMorePeople;
  }

  loadMorePosts(): void {
    this.postVisibleCount += 40;
    void this.runSearch();
  }

  loadMorePeople(): void {
    this.peopleVisibleCount += 40;
    void this.runSearch();
  }

  initialsFor(value: string): string {
    const raw = String(value || '').trim();
    if (!raw) return 'U';
    return raw.slice(0, 2).toUpperCase();
  }

  trackPost(_: number, post: CountryPost): string {
    return post.id;
  }

  trackProfile(_: number, profile: Profile): string {
    return profile.user_id;
  }

  // countries removed from search page; country travel handled on globe page.
}
