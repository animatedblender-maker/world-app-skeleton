import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { ProfileService } from '../core/services/profile.service';

@Component({
  selector: 'app-me-page',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="redirect">
      <div class="card">
        <div class="title">Loading your profile…</div>
        <div class="sub">{{ status }}</div>
      </div>
    </div>
  `,
  styles: [
    `
      :host,
      .redirect {
        position: fixed;
        inset: 0;
        display: grid;
        place-items: center;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
      }
      .card {
        border-radius: 16px;
        padding: 20px;
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        text-align: center;
        width: min(420px, 90vw);
      }
      .title {
        font-weight: 650;
        margin-bottom: 6px;
      }
      .sub {
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
      }
    `,
  ],
})
export class MePageComponent implements OnInit {
  status = 'Resolving slug…';

  constructor(
    private auth: AuthService,
    private profiles: ProfileService,
    private router: Router
  ) {}

  async ngOnInit(): Promise<void> {
    try {
      const user = await this.auth.getUser();
      const userId = user?.id;
      if (!userId) {
        this.status = 'Not authenticated. Redirecting to login…';
        await this.router.navigateByUrl('/auth');
        return;
      }

      const { meProfile } = await this.profiles.meProfile();
      const slug = meProfile?.username?.trim() || userId;
      await this.router.navigate(['/user', slug]);
    } catch (e: any) {
      this.status = e?.message ?? String(e);
    }
  }
}
