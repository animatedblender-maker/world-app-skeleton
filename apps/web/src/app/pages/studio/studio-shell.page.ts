import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { StudioService, type StudioChannel } from '../../core/services/studio.service';

@Component({
  selector: 'app-studio-shell-page',
  standalone: true,
  imports: [CommonModule, RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="studio">
      <aside class="rail">
        <div class="brand">
          <div class="brand-kicker">Matterya</div>
          <div class="brand-title">Studio</div>
        </div>

        <nav class="nav" *ngIf="hasChannel">
          <a routerLink="/studio" routerLinkActive="on" [routerLinkActiveOptions]="{ exact: true }"
            >Dashboard</a
          >
          <a routerLink="/studio/content" routerLinkActive="on">Content</a>
          <a routerLink="/studio/audience" routerLinkActive="on">Audience</a>
        </nav>

        <div class="channel" *ngIf="channel as c">
          <div class="ch-name">{{ c.name }}</div>
          <div class="ch-handle" *ngIf="c.handle">@{{ c.handle }}</div>
          <div class="ch-meta">{{ c.video_count || 0 }} videos</div>
        </div>

        <a class="back" routerLink="/hubs">← Hubs</a>
      </aside>

      <main class="main">
        <div class="banner error" *ngIf="error && error !== 'channel_required'">{{ error }}</div>

        <div class="empty" *ngIf="!loading && !hasChannel">
          <h1>Open Matterya Studio</h1>
          <p>
            Studio is for Hubs channel owners — analytics, content, and reach for your videos.
            Create a channel in the Matterya app, publish a Hubs video, then return here.
          </p>
          <div class="empty-actions">
            <a class="btn" routerLink="/hubs">Browse Hubs</a>
            <a class="btn ghost" routerLink="/profile">Your profile</a>
          </div>
        </div>

        <router-outlet *ngIf="hasChannel"></router-outlet>

        <div class="loading" *ngIf="loading">Loading Studio…</div>
      </main>
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
      .studio {
        display: grid;
        grid-template-columns: 220px minmax(0, 1fr);
        min-height: 100vh;
      }
      @media (max-width: 860px) {
        .studio {
          grid-template-columns: 1fr;
        }
        .rail {
          border-right: none;
          border-bottom: 0.5px solid var(--m-border, #ddd8d1);
        }
        .nav {
          flex-direction: row;
          flex-wrap: wrap;
          gap: 8px;
        }
      }
      .rail {
        padding: 22px 18px;
        background: var(--m-surface, #fefdfb);
        border-right: 0.5px solid var(--m-border, #ddd8d1);
        display: flex;
        flex-direction: column;
        gap: 22px;
      }
      .brand-kicker {
        font-size: 11px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
      }
      .brand-title {
        font-size: 22px;
        font-weight: 650;
        letter-spacing: -0.02em;
      }
      .nav {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }
      .nav a {
        text-decoration: none;
        color: var(--m-ink-secondary, #5c564f);
        padding: 10px 12px;
        border-radius: 12px;
        font-weight: 550;
      }
      .nav a.on {
        background: var(--m-matte-deep, #efebe4);
        color: var(--m-ink, #2c2825);
      }
      .channel {
        margin-top: auto;
        padding: 12px;
        border-radius: 14px;
        background: var(--m-matte-deep, #efebe4);
        border: 0.5px solid var(--m-border, #ddd8d1);
      }
      .ch-name {
        font-weight: 650;
      }
      .ch-handle,
      .ch-meta {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .back {
        font-size: 13px;
        color: var(--m-ink-secondary, #5c564f);
        text-decoration: none;
      }
      .main {
        padding: 24px clamp(16px, 3vw, 32px) 48px;
        min-width: 0;
      }
      .loading,
      .empty {
        max-width: 520px;
      }
      .empty h1 {
        font-size: 28px;
        margin: 0 0 10px;
        letter-spacing: -0.02em;
      }
      .empty p {
        color: var(--m-ink-secondary, #5c564f);
        line-height: 1.5;
      }
      .empty-actions {
        display: flex;
        gap: 10px;
        margin-top: 18px;
        flex-wrap: wrap;
      }
      .btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 11px 18px;
        border-radius: 999px;
        background: var(--m-ink, #2c2825);
        color: var(--m-paper, #f8f6f2);
        text-decoration: none;
        font-weight: 600;
      }
      .btn.ghost {
        background: transparent;
        color: var(--m-ink, #2c2825);
        border: 0.5px solid var(--m-border, #ddd8d1);
      }
      .banner.error {
        margin-bottom: 16px;
        padding: 12px 14px;
        border-radius: 12px;
        background: #f6e9e6;
        color: #6b2f28;
        border: 0.5px solid #e5c9c2;
      }
    `,
  ],
})
export class StudioShellPageComponent implements OnInit {
  loading = true;
  hasChannel = false;
  channel: StudioChannel | null = null;
  error = '';

  constructor(private studio: StudioService) {}

  async ngOnInit(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const { hasChannel, channel } = await this.studio.channel();
      this.hasChannel = hasChannel;
      this.channel = channel;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
      this.hasChannel = false;
    } finally {
      this.loading = false;
    }
  }
}
