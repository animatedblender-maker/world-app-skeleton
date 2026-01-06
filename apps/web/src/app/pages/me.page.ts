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
        <div class="title">Loading your profile...</div>
        <div class="sub">{{ status }}</div>
      </div>
    </div>
  `,
  styles: [`
    :host, .redirect{
      position: fixed;
      inset: 0;
      display:grid;
      place-items:center;
      background:
        radial-gradient(1100px 800px at 50% 30%, rgba(0,255,209,0.12), transparent 60%),
        radial-gradient(900px 700px at 60% 70%, rgba(140,0,255,0.10), transparent 55%),
        rgba(6,8,14,0.92);
      color: rgba(255,255,255,0.86);
    }
    .card{
      border-radius:24px;
      padding:20px;
      background: rgba(10,12,20,0.65);
      border: 1px solid rgba(255,255,255,0.12);
      box-shadow: 0 30px 90px rgba(0,0,0,0.45);
      text-align:center;
      width:min(420px, 90vw);
    }
    .title{ font-weight:900; letter-spacing:0.08em; margin-bottom:6px; }
    .sub{ font-size:13px; opacity:0.75; }
  `],
})
export class MePageComponent implements OnInit {
  status = 'Resolving slug...';

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
        this.status = 'Not authenticated. Redirecting to login...';
        await this.router.navigateByUrl('/auth');
        return;
      }

      const { meProfile } = await this.profiles.meProfile();
      const slug =
        meProfile?.username?.trim() ||
        userId;

      await this.router.navigate(['/user', slug]);
    } catch (e: any) {
      this.status = e?.message ?? String(e);
    }
  }
}
