import { CommonModule } from '@angular/common';
import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/** Public Terms of Service stub — pairs with Privacy Policy store listing. */
@Component({
  selector: 'app-terms-page',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="legal-shell">
      <header class="legal-top">
        <a class="brand" routerLink="/">Matterya</a>
        <nav class="legal-nav">
          <a routerLink="/privacy">Privacy Policy</a>
          <a routerLink="/terms" class="active">Terms</a>
        </nav>
      </header>
      <main class="legal-body">
        <p class="kicker">Legal</p>
        <h1>Terms of Service</h1>
        <p class="meta">Last updated: 4 August 2026</p>
        <p>
          By using Matterya you agree to use the service lawfully, respect other users, and not
          abuse, spam, or attempt to disrupt the platform. You retain ownership of content you
          create; you grant Matterya a licence to host and display it as needed to operate the
          service.
        </p>
        <p>
          For privacy details see our
          <a routerLink="/privacy">Privacy Policy</a>. Questions:
          <a href="mailto:legal@matterya.com">legal@matterya.com</a>.
        </p>
        <p class="note">
          A fuller Terms of Service document may be published here as Matterya expands.
        </p>
      </main>
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
      .legal-shell {
        min-height: 100vh;
      }
      .legal-top {
        position: sticky;
        top: 0;
        z-index: 10;
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: calc(10px + env(safe-area-inset-top)) 16px 10px;
        background: rgba(248, 246, 242, 0.92);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
      }
      .brand {
        font-family: var(--m-serif, Georgia, serif);
        font-size: 20px;
        color: inherit;
        text-decoration: none;
      }
      .legal-nav {
        display: flex;
        gap: 14px;
        font-size: 13px;
        font-weight: 650;
      }
      .legal-nav a {
        color: var(--m-ink-muted, #948b82);
        text-decoration: none;
      }
      .legal-nav a.active {
        color: var(--m-ink, #2c2825);
      }
      .legal-body {
        max-width: none;
        margin: 0;
        padding: 28px 16px 64px;
        line-height: 1.6;
        font-size: 15px;
        width: 100%;
        box-sizing: border-box;
      }
      .kicker {
        margin: 0 0 6px;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
      }
      h1 {
        font-family: var(--m-serif, Georgia, serif);
        font-weight: 400;
        font-size: 28px;
      }
      .meta {
        color: var(--m-ink-muted, #948b82);
      }
      a {
        color: var(--m-accent-bright, #7b6347);
      }
      .note {
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
      }
      /* desktop layout */

      @media (min-width: 900px) {
        :host { background: var(--m-canvas-muted, #f2f0ec); }
        .legal-body {
          max-width: 760px;
          margin: 24px auto 48px;
          background: var(--m-surface, #fefdfb);
          border: 0.5px solid var(--m-border, #ddd8d1);
          border-radius: 16px;
          padding: 36px 40px 64px;
        }
        h1 { font-size: 34px; }
      }

    `,
  ],
})
export class TermsPageComponent {}
