import {
  AfterViewInit,
  Component,
  ChangeDetectorRef,
  NgZone,
  OnInit,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { CountriesService, type CountryModel } from '../data/countries.service';
import { GlobeService } from '../globe/globe.service';
import { UiStateService } from '../state/ui-state.service';
import { SearchUiService } from '../search/search-ui.service';
import { AuthService } from '../core/services/auth.service';
import { GraphqlService } from '../core/services/graphql.service';
import { MediaService } from '../core/services/media.service';
import { ProfileService, type Profile } from '../core/services/profile.service';
import { PresenceService, type PresenceSnapshot } from '../core/services/presence.service';

type Panel = 'profile' | 'presence' | 'posts' | null;
type CountryTab = 'posts' | 'stats' | 'media';

@Component({
  selector: 'app-globe-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <!-- ✅ FULLSCREEN MAP BACKGROUND (ALWAYS) -->
    <div id="globe" class="globe-bg"></div>

    <!-- ✅ Top search bar -->
    <div class="topbar">
      <div class="searchwrap">
        <input id="search" placeholder="Search a country on the map…" />
        <div id="clearBtn" class="clear-btn">×</div>
        <div id="suggestions" class="suggestions"></div>
      </div>
      <button id="go" class="go-btn">GO</button>
    </div>

    <!-- ✅ Overlay layout on top of the ocean -->
    <div class="stage" [class.focus]="!!selectedCountry">
      <ng-container *ngIf="selectedCountry">
        <!-- LEFT: country mini area (analytics etc) -->
        <div class="left-column">
          <div class="left-card">
            <div class="li-title">{{ selectedCountry.name }}</div>
            <div class="li-sub">{{ selectedCountry.code || '—' }}</div>

            <div class="li-box">
              <div class="li-row">
                <span class="k">ONLINE</span>
                <span class="v">{{ localOnline ?? 0 }}</span>
              </div>
              <div class="li-row">
                <span class="k">TOTAL</span>
                <span class="v">{{ localTotal ?? 0 }}</span>
              </div>
              <div class="li-hint">Country analytics will live here.</div>
            </div>
          </div>
        </div>

        <!-- RIGHT: main posts container (dominant) -->
        <div class="main-pane">
          <div class="main-card">
            <div class="main-head">
              <div class="mh-title">COUNTRY FEED</div>
              <div class="mh-sub">{{ selectedCountry.name }} • public space</div>
            </div>

            <div class="tabs">
              <button class="tab" [class.active]="countryTab==='posts'" (click)="countryTab='posts'">POSTS</button>
              <button class="tab" [class.active]="countryTab==='stats'" (click)="countryTab='stats'">STATS</button>
              <button class="tab" [class.active]="countryTab==='media'" (click)="countryTab='media'">MEDIA</button>
            </div>

            <div class="tab-body">
              <ng-container [ngSwitch]="countryTab">
                <div *ngSwitchCase="'posts'" class="placeholder">
                  <div class="ph-title">Posts (next step)</div>
                  <div class="ph-sub">This will show public posts from users in {{ selectedCountry.name }}.</div>
                </div>

                <div *ngSwitchCase="'stats'" class="placeholder">
                  <div class="ph-title">Stats (later)</div>
                  <div class="ph-sub">Country analytics panel will live here.</div>
                </div>

                <div *ngSwitchCase="'media'" class="placeholder">
                  <div class="ph-title">Media (later)</div>
                  <div class="ph-sub">Images / videos / curated content later.</div>
                </div>
              </ng-container>
            </div>
          </div>
        </div>
      </ng-container>
    </div>

    <!-- ✅ Stats pill (includes local line like before) -->
    <div class="stats-pill">
      <div class="pill-row">
        <small>Total users: <b>{{ totalUsers ?? '—' }}</b></small>
        <small>Online now: <b>{{ onlineUsers ?? '—' }}</b></small>
      </div>

      <div class="pill-row" *ngIf="selectedCountry">
        <small class="muted">
          Local ({{ selectedCountry.name }}{{ selectedCountry.code ? ' (' + selectedCountry.code + ')' : '' }}):
          <b>{{ localOnline ?? 0 }}</b> online /
          <b>{{ localTotal ?? 0 }}</b> total
        </small>
      </div>

      <div class="pill-row">
        <small id="heartbeatState">{{ heartbeatText || '—' }}</small>
      </div>

      <div class="pill-row">
        <small id="authState">
          {{ userEmail ? ('Logged in: ' + userEmail) : 'Logged out' }}
        </small>
      </div>

      <div class="pill-row" *ngIf="loadingProfile">
        <small style="opacity:.75">Loading profile…</small>
      </div>
      <div class="pill-row" *ngIf="profileError">
        <small style="color:#ff8b8b; font-weight:800; letter-spacing:.08em;">
          {{ profileError }}
        </small>
      </div>
    </div>

    <div class="node-backdrop" *ngIf="menuOpen" (click)="closeMenu()"></div>

    <!-- ✅ Avatar orb -->
    <div class="user-node">
      <button class="node-orb" type="button" (click)="toggleMenu()" [attr.aria-expanded]="menuOpen">
        <ng-container *ngIf="nodeAvatarUrl; else initialsTpl">
          <img
            class="orb-img"
            [src]="nodeAvatarUrl"
            alt="avatar"
            [style.transform]="nodeAvatarTransform"
          />
        </ng-container>

        <ng-template #initialsTpl>
          <div class="orb-initials">{{ initials }}</div>
        </ng-template>

        <span class="orb-pulse"></span>
        <span class="orb-ring"></span>
      </button>

      <div class="node-menu" *ngIf="menuOpen" (click)="$event.stopPropagation()">
        <div class="node-head">
          <div class="node-title">YOUR NODE</div>
          <div class="node-sub">{{ profile?.display_name || 'Unnamed' }}</div>
          <div class="node-sub2">{{ userEmail || '—' }}</div>

          <div class="node-sub2" *ngIf="profileError" style="color: rgba(255,120,120,0.95); opacity:1;">
            {{ profileError }}
          </div>
        </div>

        <div class="node-actions">
          <button class="node-btn" type="button" (click)="openPanel('profile')">
            <span class="dot"></span><span>PROFILE</span>
          </button>

          <button class="node-btn" type="button" (click)="openPanel('presence')">
            <span class="dot"></span><span>MY PRESENCE</span>
          </button>

          <button class="node-btn" type="button" (click)="openPanel('posts')">
            <span class="dot"></span><span>MY POSTS</span>
          </button>

          <button class="node-btn danger" type="button" (click)="logout()">
            <span class="dot"></span><span>LOGOUT</span>
          </button>
        </div>

        <div class="node-foot">
          <button class="ghost" type="button" (click)="closeMenu()">CLOSE</button>
        </div>
      </div>
    </div>

    <!-- ✅ OVERLAY PANEL -->
    <div class="overlay" *ngIf="panel" (click)="closePanel()">
      <div class="panel" (click)="$event.stopPropagation()">
        <div class="panel-head">
          <div class="panel-title">
            {{ panel === 'profile' ? 'PROFILE' : (panel === 'presence' ? 'MY PRESENCE' : 'MY POSTS') }}
          </div>
          <button class="x" type="button" (click)="closePanel()">×</button>
        </div>

        <!-- ✅ PROFILE (FULL editor restored) -->
        <div class="panel-body" *ngIf="panel === 'profile'">
          <div class="avatar-row">
            <div class="avatar-big" [class.adjusting]="adjustingAvatar" (click)="openAvatarPreview()">
              <ng-container *ngIf="draftAvatarUrl; else bigInitTpl">
                <div class="avatar-viewport">
                  <img
                    class="avatar-img"
                    [src]="draftAvatarUrl"
                    alt="avatar"
                    [style.transform]="draftAvatarTransform"
                    [class.dragging]="dragging"
                    (pointerdown)="onAvatarDragStart($event)"
                    (click)="$event.stopPropagation(); openAvatarPreview()"
                  />
                </div>
              </ng-container>

              <ng-template #bigInitTpl>
                <div class="big-initials">{{ initials }}</div>
              </ng-template>

              <span class="big-ring"></span>

              <div class="drag-hint" *ngIf="adjustingAvatar && draftAvatarUrl">
                Drag to reposition
              </div>
            </div>

            <div class="avatar-actions">
              <label class="upload-btn" [class.disabled]="uploadingAvatar">
                {{ uploadingAvatar ? 'UPLOADING…' : 'CHANGE AVATAR' }}
                <input type="file" accept="image/*" (change)="onAvatar($event)" [disabled]="uploadingAvatar" />
              </label>

              <button class="upload-btn" type="button" (click)="toggleAdjustAvatar()" [disabled]="!draftAvatarUrl">
                {{ adjustingAvatar ? 'DONE' : 'ADJUST' }}
              </button>

              <button class="upload-btn" type="button" (click)="resetAvatarPosition()" [disabled]="!draftAvatarUrl">
                RESET POSITION
              </button>
            </div>
          </div>

          <div class="field">
            <label>DISPLAY NAME</label>
            <input [(ngModel)]="editDisplayName" placeholder="Your screen name" />
          </div>

          <div class="field">
            <label>BIO</label>
            <textarea [(ngModel)]="editBio" rows="3" placeholder="160 chars, tell the world who you are…"></textarea>
          </div>

          <div class="field">
            <label>COUNTRY</label>
            <input [value]="profile?.country_name || '—'" disabled />
          </div>

          <div class="row">
            <button class="cta" type="button" (click)="saveProfileAndClose()" [disabled]="saveState==='saving'">
              {{ saveState === 'saving' ? 'SAVING…' : (saveState === 'saved' ? 'SAVED ✓' : 'SAVE') }}
            </button>
            <div class="msg" *ngIf="msg">{{ msg }}</div>
          </div>
        </div>

        <!-- ✅ PRESENCE -->
        <div class="panel-body" *ngIf="panel === 'presence'">
          <div class="presence-box">
            <div class="presence-line"><span class="k">STATUS</span><span class="v">ONLINE</span></div>
            <div class="presence-line"><span class="k">COUNTRY</span><span class="v">{{ profile?.country_name || '—' }}</span></div>
            <div class="presence-line"><span class="k">CODE</span><span class="v">{{ profile?.country_code || '—' }}</span></div>
            <div class="presence-line"><span class="k">CITY</span><span class="v">{{ cityName }}</span></div>
          </div>
        </div>

        <!-- ✅ MY POSTS -->
        <div class="panel-body" *ngIf="panel === 'posts'">
          <div class="presence-box">
            <div class="presence-line"><span class="k">POSTS</span><span class="v">0</span></div>
            <div class="presence-line"><span class="k">STATE</span><span class="v">COMING SOON</span></div>
          </div>
        </div>
      </div>
    </div>

    <!-- ✅ Avatar preview -->
    <div class="preview-overlay" *ngIf="avatarPreviewOpen" (click)="closeAvatarPreview()">
      <div class="preview-circle" (click)="$event.stopPropagation()">
        <ng-container *ngIf="draftAvatarUrl; else prevInitTpl">
          <img class="preview-img" [src]="draftAvatarUrl" alt="avatar preview" />
        </ng-container>
        <ng-template #prevInitTpl>
          <div class="big-initials">{{ initials }}</div>
        </ng-template>
        <span class="preview-ring"></span>
      </div>
    </div>
  `,
  styles: [`
    /* ✅ Map background always fullscreen */
    .globe-bg{
      position: fixed;
      inset: 0;
      width: 100vw;
      height: 100vh;
      z-index: 1;
    }

    /* ✅ Overlay layer above the map */
    .stage{
      position: fixed;
      inset: 0;
      z-index: 2;
      pointer-events: none;
    }

    /* ✅ Focus overlay grid (pushed down so search never overlaps) */
    .stage.focus{
      display: grid;
      grid-template-columns: min(420px, 34vw) 1fr;
      gap: 14px;
      padding: 104px 16px 16px;
      box-sizing: border-box;
      pointer-events: none;
    }

    .left-column{ pointer-events: none; }
    .left-card{
      pointer-events: none;
      border-radius: 22px;
      border: 1px solid rgba(255,255,255,0.10);
      background: rgba(10,12,20,0.40);
      backdrop-filter: blur(12px);
      box-shadow: 0 30px 90px rgba(0,0,0,0.35);
      padding: 14px;
      color: rgba(255,255,255,0.92);
    }

    .li-title{ font-weight: 900; letter-spacing: .12em; font-size: 11px; text-transform: uppercase; }
    .li-sub{ margin-top: 2px; font-size: 11px; opacity: .75; font-weight: 800; letter-spacing: .08em; }
    .li-box{
      margin-top: 12px;
      border-radius: 16px;
      background: rgba(10,12,20,0.45);
      border: 1px solid rgba(255,255,255,0.10);
      backdrop-filter: blur(10px);
      padding: 10px;
    }
    .li-row{ display:flex; justify-content:space-between; align-items:center; gap: 12px; margin-bottom: 8px; }
    .li-row .k{ opacity:.65; letter-spacing:.16em; font-weight: 900; font-size: 10px; }
    .li-row .v{ color: rgba(0,255,209,0.92); font-weight: 900; letter-spacing: .10em; font-size: 12px; }
    .li-hint{ margin-top: 4px; opacity: .72; font-size: 11px; line-height: 1.35; }

    .main-pane{ pointer-events: auto; min-width:0; }

    /* ✅ ONLY posts container is expensive whitish */
    .main-card{
      height: 100%;
      border-radius: 26px;
      padding: 16px;
      background: rgba(248, 250, 252, 0.86);
      border: 1px solid rgba(0,0,0,0.08);
      backdrop-filter: blur(16px);
      box-shadow: 0 30px 90px rgba(0,0,0,0.22);
      color: rgba(10,12,18,0.92);
      overflow: hidden;
      display:flex;
      flex-direction: column;
      pointer-events: auto;
    }
    .main-head{ margin-bottom: 10px; }
    .mh-title{ font-weight: 900; letter-spacing: .16em; font-size: 12px; text-transform: uppercase; }
    .mh-sub{ margin-top: 4px; opacity: .72; font-weight: 800; letter-spacing: .08em; font-size: 12px; }

    .tabs{ display:flex; gap: 8px; margin: 12px 0; flex-wrap: wrap; }
    .tab{
      border: 1px solid rgba(0,0,0,0.10);
      background: rgba(255,255,255,0.80);
      color: rgba(10,12,18,0.78);
      padding: 10px 12px;
      border-radius: 14px;
      font-weight: 900;
      letter-spacing: .14em;
      font-size: 11px;
      cursor: pointer;
    }
    .tab.active{
      border-color: rgba(0,255,209,0.28);
      background: rgba(0,255,209,0.12);
      color: rgba(10,12,18,0.92);
      box-shadow: 0 0 0 1px rgba(0,255,209,0.10) inset, 0 0 24px rgba(0,255,209,0.08);
    }

    .tab-body{ flex: 1; min-height: 0; overflow: auto; }
    .placeholder{
      border-radius: 18px;
      border: 1px solid rgba(0,0,0,0.08);
      background: rgba(255,255,255,0.86);
      padding: 14px;
    }
    .ph-title{ font-weight: 900; letter-spacing: .10em; font-size: 12px; text-transform: uppercase; }
    .ph-sub{ margin-top: 6px; opacity: .78; font-size: 12px; line-height: 1.4; }

    /* ✅ Stats pill */
    .stats-pill{
      position: fixed;
      left: 16px;
      bottom: 16px;
      z-index: 9996;
      width: min(360px, calc(100vw - 32px));
      border-radius: 16px;
      padding: 10px 12px;
      background: rgba(220, 228, 235, 0.88);
      border: 1px solid rgba(0,0,0,0.06);
      box-shadow: 0 18px 60px rgba(0,0,0,0.16);
      backdrop-filter: blur(10px);
      pointer-events: none;
    }
    .pill-row{ display:flex; gap: 12px; flex-wrap: wrap; align-items:center; }
    .pill-row small{ color: rgba(10,12,18,0.70); font-size: 12px; }
    .pill-row b{ color: rgba(10,12,18,0.86); }
    .muted{ color: rgba(10,12,18,0.62); }

    /* ✅ Menu + orb */
    .node-backdrop{ position: fixed; inset: 0; z-index: 9997; background: transparent; }

    .user-node{
      position: fixed;
      top: 16px;
      right: 16px;
      z-index: 9999;
      width: 44px;
      height: 44px;
      user-select: none;
      pointer-events: auto;
    }

    .node-orb{
      width: 44px;
      height: 44px;
      border-radius: 999px;
      border: 1px solid rgba(0,255,209,0.28);
      background: rgba(10,12,20,0.55);
      backdrop-filter: blur(12px);
      box-shadow: 0 18px 60px rgba(0,0,0,0.45),
                  0 0 0 1px rgba(0,255,209,0.18) inset,
                  0 0 38px rgba(0,255,209,0.12);
      position: relative;
      overflow: hidden;
      cursor: pointer;
      padding: 0;
      display:grid;
      place-items:center;
      pointer-events:auto;
    }
    .orb-img{ width: 120%; height: 120%; object-fit: cover; border-radius: 999px; will-change: transform; transform: translate3d(0,0,0); transition: transform 90ms linear; }
    .orb-initials{ font-weight: 900; letter-spacing: 0.12em; font-size: 11px; color: rgba(255,255,255,0.92); text-transform: uppercase; }
    .orb-pulse{ position:absolute; inset:-8px; border-radius:999px; background: radial-gradient(circle at 50% 50%, rgba(0,255,209,0.16), transparent 60%); animation: pulse 2.8s ease-in-out infinite; pointer-events:none; }
    @keyframes pulse{ 0%,100% { transform: scale(0.98); opacity: .55; } 50% { transform: scale(1.06); opacity: .95; } }
    .orb-ring{ position:absolute; inset:-2px; border-radius:999px; background: conic-gradient(from 180deg, rgba(0,255,209,0.0), rgba(0,255,209,0.65), rgba(140,0,255,0.55), rgba(0,255,209,0.0)); filter: blur(10px); opacity: 0.35; pointer-events:none; }

    .node-menu{
      position: absolute;
      top: 52px;
      right: 0;
      width: 260px;
      border-radius: 22px;
      padding: 14px;
      background: rgba(10,12,20,0.62);
      border: 1px solid rgba(0,255,209,0.20);
      backdrop-filter: blur(14px);
      box-shadow: 0 30px 90px rgba(0,0,0,0.50);
      overflow:hidden;
      z-index: 9999;
      pointer-events:auto;
    }
    .node-menu::before{
      content:"";
      position:absolute;
      inset:-2px;
      border-radius: 24px;
      background: conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.55), rgba(140,0,255,0.45), rgba(0,255,209,0));
      filter: blur(14px);
      opacity: 0.22;
      pointer-events:none;
    }
    .node-menu > *{ position:relative; z-index:1; }
    .node-head{ margin-bottom: 10px; }
    .node-title{ font-weight: 900; letter-spacing: 0.18em; font-size: 12px; color: rgba(255,255,255,0.90); }
    .node-sub{ margin-top: 6px; font-weight: 800; letter-spacing: 0.08em; color: rgba(0,255,209,0.92); font-size: 12px; }
    .node-sub2{ margin-top: 3px; opacity: .68; font-size: 12px; color: rgba(255,255,255,0.84); }

    .node-actions{ display:grid; gap: 8px; margin-top: 10px; }
    .node-btn{
      width: 100%;
      border: 0;
      border-radius: 16px;
      padding: 12px 12px;
      cursor: pointer;
      background: rgba(255,255,255,0.06);
      color: rgba(255,255,255,0.86);
      display:flex;
      align-items:center;
      gap: 10px;
      letter-spacing: 0.14em;
      font-weight: 900;
      font-size: 11px;
    }
    .node-btn:hover{ background: rgba(0,255,209,0.12); box-shadow: 0 0 0 1px rgba(0,255,209,0.20) inset, 0 0 24px rgba(0,255,209,0.10); }
    .node-btn .dot{ width: 8px; height: 8px; border-radius: 999px; background: rgba(0,255,209,0.92); box-shadow: 0 0 16px rgba(0,255,209,0.55); flex:0 0 auto; }
    .node-btn.danger .dot{ background: rgba(255,120,120,0.95); box-shadow: 0 0 16px rgba(255,120,120,0.45); }
    .node-foot{ margin-top: 10px; display:flex; justify-content:flex-end; }
    .ghost{ border: 0; background: transparent; color: rgba(0,255,209,0.92); font-weight: 900; letter-spacing: 0.14em; cursor: pointer; font-size: 11px; text-decoration: underline; }

    /* overlay panels */
    .overlay{
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.35);
      backdrop-filter: blur(6px);
      z-index: 9998;
      display:grid;
      place-items:center;
      padding: 18px;
    }
    .panel{
      width: min(720px, 94vw);
      border-radius: 26px;
      padding: 16px;
      background: rgba(10,12,20,0.60);
      border: 1px solid rgba(0,255,209,0.20);
      box-shadow: 0 30px 90px rgba(0,0,0,0.55), 0 0 50px rgba(0,255,209,0.10);
      backdrop-filter: blur(14px);
      color: rgba(255,255,255,0.92);
      position: relative;
      overflow:hidden;
      pointer-events: auto;
    }
    .panel::before{
      content:"";
      position:absolute;
      inset:-2px;
      border-radius: 28px;
      background: conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.55), rgba(140,0,255,0.45), rgba(0,255,209,0));
      filter: blur(16px);
      opacity: 0.18;
      pointer-events:none;
    }
    .panel > *{ position:relative; z-index:1; }
    .panel-head{ display:flex; align-items:center; justify-content:space-between; margin-bottom: 12px; }
    .panel-title{ font-weight: 900; letter-spacing: 0.18em; font-size: 12px; }
    .x{
      width: 38px;
      height: 38px;
      border-radius: 14px;
      border: 1px solid rgba(255,255,255,0.10);
      background: rgba(255,255,255,0.06);
      color: rgba(255,255,255,0.90);
      cursor: pointer;
      font-size: 18px;
    }
    .x:hover{ background: rgba(0,255,209,0.10); border-color: rgba(0,255,209,0.20); }
    .panel-body{ display:grid; gap: 12px; }

    /* profile editor styles (restored) */
    .avatar-row{ display:flex; align-items:center; justify-content:space-between; gap: 14px; flex-wrap: wrap; }
    .avatar-actions{ display:grid; gap: 10px; justify-items: start; }
    .avatar-big{
      width: 168px; height: 168px; border-radius: 999px; position: relative; overflow:hidden;
      border: 1px solid rgba(0,255,209,0.25); background: rgba(0,0,0,0.25);
      box-shadow: 0 0 28px rgba(0,255,209,0.12);
      display:grid; place-items:center; cursor: pointer;
    }
    .avatar-big.adjusting{
      outline: 2px solid rgba(0,255,209,0.35);
      box-shadow: 0 0 0 6px rgba(0,255,209,0.12), 0 0 28px rgba(0,255,209,0.18);
    }
    .avatar-viewport{ width:100%; height:100%; overflow:hidden; border-radius: 999px; }
    .avatar-img{
      width: 130%; height: 130%; object-fit: cover;
      transform: translate3d(0,0,0);
      will-change: transform;
      touch-action: none;
      user-select: none;
      pointer-events: auto;
      transition: transform 90ms linear;
    }
    .avatar-img.dragging{ transition: none; }
    .drag-hint{
      position:absolute; bottom: 10px; left: 50%; transform: translateX(-50%);
      padding: 6px 10px; border-radius: 999px;
      background: rgba(0,0,0,0.35); border: 1px solid rgba(255,255,255,0.10);
      font-size: 10px; letter-spacing: .12em; font-weight: 900; opacity: .9; pointer-events:none;
    }
    .big-initials{ font-weight: 900; letter-spacing: 0.14em; font-size: 22px; }
    .big-ring{
      position:absolute; inset:-2px; border-radius: 999px;
      background: conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.55), rgba(140,0,255,0.45), rgba(0,255,209,0));
      filter: blur(12px); opacity: 0.22; pointer-events:none;
    }
    .upload-btn{
      display:inline-flex; align-items:center; justify-content:center;
      padding: 12px 14px; border-radius: 16px; cursor:pointer;
      border: 1px solid rgba(255,255,255,0.12);
      background: rgba(255,255,255,0.06);
      color: rgba(255,255,255,0.88);
      font-weight: 900; letter-spacing: 0.14em; font-size: 11px;
      user-select:none;
    }
    .upload-btn:hover{
      border-color: rgba(0,255,209,0.22);
      background: rgba(0,255,209,0.10);
      box-shadow: 0 0 24px rgba(0,255,209,0.10);
    }
    .upload-btn.disabled{ opacity: .65; cursor: not-allowed; }
    .upload-btn input{ display:none; }

    .field{ display:grid; gap: 8px; }
    .field label{ font-size: 11px; opacity: .72; letter-spacing: 0.14em; font-weight: 900; }
    .field input, .field textarea{
      padding: 12px; border-radius: 16px;
      border: 1px solid rgba(255,255,255,0.12);
      background: rgba(0,0,0,0.28);
      color: rgba(255,255,255,0.92);
      outline:none;
      resize: none;
    }
    .field input:focus, .field textarea:focus{
      border-color: rgba(0,255,209,0.35);
      box-shadow: 0 0 0 3px rgba(0,255,209,0.10);
    }
    .field input:disabled{ opacity: .65; cursor: not-allowed; }

    .row{ display:flex; align-items:center; gap: 12px; flex-wrap: wrap; margin-top: 2px; }
    .cta{
      border:0; border-radius: 16px; padding: 12px 14px; cursor: pointer;
      background: linear-gradient(90deg, rgba(0,255,209,0.85), rgba(140,0,255,0.75));
      color: rgba(6,8,14,0.96);
      font-weight: 900; letter-spacing: 0.16em; font-size: 12px;
      box-shadow: 0 18px 50px rgba(0,255,209,0.16);
    }
    .cta:disabled{ opacity:.6; cursor:not-allowed; }
    .msg{ font-size: 12px; opacity: .85; }

    .presence-box{
      border-radius: 18px;
      border: 1px solid rgba(255,255,255,0.10);
      background: rgba(255,255,255,0.05);
      padding: 12px;
      display:grid;
      gap: 10px;
    }
    .presence-line{ display:flex; justify-content:space-between; gap: 12px; align-items:center; }
    .presence-line .k{ opacity:.65; letter-spacing:.16em; font-weight: 900; font-size: 11px; }
    .presence-line .v{ color: rgba(0,255,209,0.92); font-weight: 900; letter-spacing: .08em; font-size: 12px; }

    .preview-overlay{
      position: fixed; inset:0;
      background: rgba(0,0,0,0.55);
      backdrop-filter: blur(10px);
      z-index: 10000;
      display:grid; place-items:center;
      padding: 20px;
      pointer-events: auto;
    }
    .preview-circle{
      width: 420px; height: 420px;
      max-width: 90vw; max-height: 90vw;
      border-radius: 999px;
      overflow: hidden;
      position: relative;
      background: rgba(10,12,20,0.62);
      border: 1px solid rgba(0,255,209,0.22);
      box-shadow: 0 40px 120px rgba(0,0,0,0.65), 0 0 60px rgba(0,255,209,0.14);
      display:grid; place-items:center;
    }
    .preview-img{ width: 100%; height: 100%; object-fit: cover; }
    .preview-ring{
      position:absolute; inset:-2px; border-radius: 999px;
      background: conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.55), rgba(140,0,255,0.45), rgba(0,255,209,0));
      filter: blur(18px);
      opacity: 0.22;
      pointer-events:none;
    }
  `],
})
export class GlobePageComponent implements OnInit, AfterViewInit {
  menuOpen = false;
  panel: Panel = null;

  userEmail = '';
  profile: Profile | null = null;

  loadingProfile = false;
  profileError = '';

  selectedCountry: CountryModel | null = null;

  totalUsers: number | null = null;
  onlineUsers: number | null = null;
  heartbeatText = '';

  localTotal: number | null = null;
  localOnline: number | null = null;

  private lastPresenceSnap: PresenceSnapshot | null = null;

  countryTab: CountryTab = 'posts';

  // --- Avatar orb state ---
  nodeAvatarUrl = '';
  private nodeNormX = 0;
  private nodeNormY = 0;

  // --- Profile editor state (restored) ---
  editDisplayName = '';
  editBio = '';

  draftAvatarUrl = '';
  private draftNormX = 0;
  private draftNormY = 0;

  saveState: 'idle' | 'saving' | 'saved' = 'idle';
  uploadingAvatar = false;
  msg = '';

  adjustingAvatar = false;
  avatarPreviewOpen = false;

  dragging = false;
  private startX = 0;
  private startY = 0;
  private basePxX = 0;
  private basePxY = 0;

  private raf = 0;
  private pendingPxX = 0;
  private pendingPxY = 0;

  private readonly NODE_SIZE = 44;
  private readonly NODE_SCALE = 1.20;

  private readonly EDIT_SIZE = 168;
  private readonly EDIT_SCALE = 1.30;

  private readonly AVATAR_OUT_SIZE = 512;

  constructor(
    private countriesService: CountriesService,
    private globeService: GlobeService,
    private ui: UiStateService,
    private searchUi: SearchUiService,
    private auth: AuthService,
    private gql: GraphqlService,
    private router: Router,
    private media: MediaService,
    private profiles: ProfileService,
    private presence: PresenceService,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  /** ✅ Angular templates can’t do `(profile as any)`; do it here. */
  get cityName(): string {
    const p: any = this.profile as any;
    return (p?.city_name ?? p?.cityName ?? '—') as string;
  }

  private maxOffset(size: number, scale: number): number {
    const scaled = size * scale;
    return Math.max(0, (scaled - size) / 2);
  }

  private clampNorm(v: number): number {
    if (!Number.isFinite(v)) return 0;
    return Math.max(-1, Math.min(1, v));
  }

  get initials(): string {
    const name = (this.profile?.display_name || this.userEmail || 'U').trim();
    const parts = name.split(/\s+/).filter(Boolean);
    const a = parts[0]?.[0] ?? 'U';
    const b = parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? '') : '';
    return (a + b).toUpperCase();
  }

  get nodeAvatarTransform(): string {
    const mo = this.maxOffset(this.NODE_SIZE, this.NODE_SCALE);
    const x = this.nodeNormX * mo;
    const y = this.nodeNormY * mo;
    return `translate3d(${x}px, ${y}px, 0)`;
  }

  get draftAvatarTransform(): string {
    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);
    const x = this.draftNormX * mo;
    const y = this.draftNormY * mo;
    return `translate3d(${x}px, ${y}px, 0)`;
  }

  async ngOnInit(): Promise<void> {
    this.loadingProfile = true;
    this.profileError = '';
    this.forceUi();

    try {
      const user = await this.auth.getUser();
      this.userEmail = user?.email ?? '';

      const { meProfile } = await this.profiles.meProfile();
      this.profile = meProfile;

      this.editDisplayName =
        meProfile?.display_name ?? (this.userEmail?.split('@')[0] ?? '');
      this.editBio = (meProfile as any)?.bio ?? '';

      this.nodeAvatarUrl = (meProfile as any)?.avatar_url ?? '';
      this.draftAvatarUrl = this.nodeAvatarUrl;

      this.nodeNormX = 0;
      this.nodeNormY = 0;
      this.draftNormX = 0;
      this.draftNormY = 0;

      if (this.nodeAvatarUrl) this.preloadImage(this.nodeAvatarUrl);

      this.cdr.detectChanges();
    } catch (e: any) {
      this.profileError = e?.message ?? String(e);
    } finally {
      this.loadingProfile = false;
      this.forceUi();
    }
  }

  async ngAfterViewInit(): Promise<void> {
    this.zone.runOutsideAngular(async () => {
      const globeEl = document.getElementById('globe');
      if (!globeEl) return;

      this.globeService.init(globeEl);

      const data = await this.countriesService.loadCountries();
      this.ui.setCountries(data.countries);
      this.globeService.setData(data);

      try {
        await this.presence.start({
          countries: data.countries,
          meCountryCode: ((this.profile as any)?.country_code ?? null),
          meCountryName: ((this.profile as any)?.country_name ?? null),
          meCityName: ((this.profile as any)?.city_name ?? null),
          onHeartbeat: (txt) => {
            this.zone.run(() => {
              this.heartbeatText = txt;
              this.forceUi();
            });
          },
          onUpdate: (snap) => {
            this.zone.run(() => {
              this.lastPresenceSnap = snap;
              this.totalUsers = snap.totalUsers;
              this.onlineUsers = snap.onlineUsers;

              this.globeService.setConnections((snap as any).points as any);
              this.globeService.setConnectionsOnline((snap as any).onlineIds as any);

              this.globeService.setConnectionsCountryFilter(this.selectedCountry?.code ?? null);

              this.recomputeLocal();
              this.forceUi();
            });
          },
        });
      } catch (e: any) {
        this.zone.run(() => {
          this.heartbeatText = `presence ✗ (${e?.message ?? e})`;
          this.forceUi();
        });
      }

      this.globeService.onCountryClick((country: CountryModel) => {
        this.zone.run(() => {
          this.selectedCountry = country;
          this.countryTab = 'posts';

          this.ui.setMode('focus');
          this.ui.setSelected(country.id);
          this.searchUi.setInputValue(country.name);
          this.searchUi.setClearButtonVisible(true);

          this.globeService.setSoloCountry(country.id);
          this.globeService.setConnectionsCountryFilter(country.code ?? null);

          // keep country pushed to the left/top since UI overlays
          this.globeService.setViewPadding({
            top: 14,
            left: 14,
            right: 520,
            bottom: 220,
          });

          this.globeService.selectCountry(country.id);
          this.globeService.showFocusLabel(country.id);
          this.globeService.flyTo(country.center.lat, country.center.lng, country.flyAltitude, 900);

          this.recomputeLocal();
          this.forceUi();

          setTimeout(() => this.globeService.resize(), 0);
          setTimeout(() => this.globeService.resize(), 60);
        });
      });

      this.searchUi.init({
        getCountries: () => this.ui.countries,
        isFocusMode: () => this.ui.labelMode === 'focus',
        onSearch: (country) => {
          this.zone.run(() => {
            this.selectedCountry = country;
            this.countryTab = 'posts';

            this.ui.setMode('focus');
            this.ui.setSelected(country.id);

            this.globeService.setSoloCountry(country.id);
            this.globeService.setConnectionsCountryFilter(country.code ?? null);

            this.globeService.setViewPadding({
              top: 14,
              left: 14,
              right: 520,
              bottom: 220,
            });

            this.globeService.selectCountry(country.id);
            this.globeService.showFocusLabel(country.id);
            this.globeService.flyTo(country.center.lat, country.center.lng, country.flyAltitude, 900);

            this.recomputeLocal();
            this.forceUi();

            setTimeout(() => this.globeService.resize(), 0);
            setTimeout(() => this.globeService.resize(), 60);
          });
        },
        onClear: () => {
          this.zone.run(() => {
            this.selectedCountry = null;

            this.ui.setMode('all');
            this.ui.setSelected(null);

            this.globeService.setSoloCountry(null);
            this.globeService.setConnectionsCountryFilter(null);
            this.globeService.resetView();

            this.localTotal = null;
            this.localOnline = null;

            this.forceUi();

            setTimeout(() => this.globeService.resize(), 0);
            setTimeout(() => this.globeService.resize(), 60);
          });
        },
      });

      try {
        await this.auth.getAccessToken();
        await this.gql.query<any>(`query { __typename }`);
      } catch {}

      this.zone.run(() => console.log('✅ Globe page ready'));
    });
  }

  private recomputeLocal(): void {
    if (!this.selectedCountry?.code) {
      this.localTotal = null;
      this.localOnline = null;
      return;
    }
    const snap: any = this.lastPresenceSnap as any;
    if (!snap) {
      this.localTotal = null;
      this.localOnline = null;
      return;
    }
    const cc = String(this.selectedCountry.code).toUpperCase();
    const entry = snap.byCountry?.[cc];
    this.localTotal = entry?.total ?? 0;
    this.localOnline = entry?.online ?? 0;
  }

  // -----------------------------
  // Menu / panels
  // -----------------------------
  toggleMenu(): void { this.menuOpen = !this.menuOpen; }
  closeMenu(): void { this.menuOpen = false; }

  openPanel(p: Exclude<Panel, null>): void {
    this.panel = p;
    this.menuOpen = false;

    this.msg = '';
    this.saveState = 'idle';

    if (p === 'profile') {
      this.draftAvatarUrl = this.nodeAvatarUrl;
      this.draftNormX = this.nodeNormX;
      this.draftNormY = this.nodeNormY;
      this.editDisplayName = this.profile?.display_name ?? this.editDisplayName;
      this.editBio = (this.profile as any)?.bio ?? this.editBio;
    }

    this.forceUi();
  }

  closePanel(): void {
    this.panel = null;
    this.adjustingAvatar = false;
    this.dragging = false;
    this.msg = '';
    this.saveState = 'idle';
    this.avatarPreviewOpen = false;
    this.forceUi();
  }

  // -----------------------------
  // Avatar preview / adjust
  // -----------------------------
  openAvatarPreview(): void {
    if (!this.draftAvatarUrl) return;
    this.avatarPreviewOpen = true;
    this.forceUi();
  }

  closeAvatarPreview(): void {
    this.avatarPreviewOpen = false;
    this.forceUi();
  }

  toggleAdjustAvatar(): void {
    if (!this.draftAvatarUrl) return;
    this.adjustingAvatar = !this.adjustingAvatar;
    this.forceUi();
  }

  resetAvatarPosition(): void {
    this.draftNormX = 0;
    this.draftNormY = 0;
    this.forceUi();
  }

  onAvatarDragStart(ev: PointerEvent): void {
    if (!this.adjustingAvatar) return;
    if (!this.draftAvatarUrl) return;

    this.dragging = true;
    this.startX = ev.clientX;
    this.startY = ev.clientY;

    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);
    this.basePxX = this.draftNormX * mo;
    this.basePxY = this.draftNormY * mo;

    (ev.target as HTMLElement).setPointerCapture?.(ev.pointerId);

    const move = (e: PointerEvent) => this.onAvatarDragMove(e);
    const up = () => this.onAvatarDragEnd(move, up);

    window.addEventListener('pointermove', move, { passive: true });
    window.addEventListener('pointerup', up, { passive: true });

    this.forceUi();
  }

  private onAvatarDragMove(ev: PointerEvent): void {
    if (!this.dragging) return;

    const dx = ev.clientX - this.startX;
    const dy = ev.clientY - this.startY;

    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);
    const clampPx = (v: number) => Math.max(-mo, Math.min(mo, v));

    this.pendingPxX = clampPx(this.basePxX + dx);
    this.pendingPxY = clampPx(this.basePxY + dy);

    if (!this.raf) {
      this.raf = requestAnimationFrame(() => {
        this.draftNormX = this.clampNorm(mo ? this.pendingPxX / mo : 0);
        this.draftNormY = this.clampNorm(mo ? this.pendingPxY / mo : 0);
        this.raf = 0;
      });
    }
  }

  private onAvatarDragEnd(move: (e: PointerEvent) => void, up: () => void): void {
    this.dragging = false;
    window.removeEventListener('pointermove', move as any);
    window.removeEventListener('pointerup', up as any);
    this.forceUi();
  }

  // -----------------------------
  // Avatar upload + crop (restored)
  // -----------------------------
  private async cropAvatarToSquare(file: File): Promise<File> {
    const type = (file.type || '').toLowerCase();

    if (type === 'image/gif') throw new Error('GIF avatars are disabled for now.');
    if (!type.startsWith('image/')) throw new Error('Please choose an image file.');

    const outType =
      type === 'image/png' || type === 'image/webp' ? 'image/png' : 'image/jpeg';
    const outExt = outType === 'image/png' ? 'png' : 'jpg';

    const bitmap = await createImageBitmap(file);

    const side = Math.min(bitmap.width, bitmap.height);
    const sx = Math.floor((bitmap.width - side) / 2);
    const sy = Math.floor((bitmap.height - side) / 2);

    const canvas = document.createElement('canvas');
    canvas.width = this.AVATAR_OUT_SIZE;
    canvas.height = this.AVATAR_OUT_SIZE;

    const ctx = canvas.getContext('2d', { alpha: true });
    if (!ctx) throw new Error('Canvas not supported.');

    (ctx as any).imageSmoothingEnabled = true;
    (ctx as any).imageSmoothingQuality = 'high';

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(bitmap, sx, sy, side, side, 0, 0, canvas.width, canvas.height);

    bitmap.close?.();

    const blob: Blob = await new Promise((resolve, reject) => {
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error('Failed to crop image.'))),
        outType,
        outType === 'image/jpeg' ? 0.92 : undefined
      );
    });

    return new File([blob], `avatar.${outExt}`, { type: outType });
  }

  async onAvatar(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.msg = '';
    this.uploadingAvatar = true;
    this.forceUi();

    try {
      const cropped = await this.cropAvatarToSquare(file);

      const r = await this.media.uploadAvatar(cropped);
      const url = (r as any)?.url;
      if (!url) throw new Error('Upload succeeded but returned no URL.');

      this.draftAvatarUrl = url;
      this.preloadImage(url);

      this.draftNormX = 0;
      this.draftNormY = 0;

      this.msg = 'Uploaded. Press SAVE to apply.';
    } catch (err: any) {
      this.msg = err?.message ?? String(err);
    } finally {
      this.uploadingAvatar = false;
      input.value = '';
      this.forceUi();
    }
  }

  async saveProfileAndClose(): Promise<void> {
    this.msg = '';
    this.saveState = 'saving';
    this.forceUi();

    try {
      const dn = this.editDisplayName.trim();
      const bio = this.editBio.trim();

      if (!dn) throw new Error('Display name is required.');

      const res = await this.profiles.updateProfile({
        display_name: dn,
        bio: bio ? bio.slice(0, 160) : null,
        avatar_url: this.draftAvatarUrl || null,
      });

      this.profile = (res as any).updateProfile;

      this.nodeAvatarUrl = (this.profile as any)?.avatar_url ?? '';
      this.nodeNormX = this.draftNormX;
      this.nodeNormY = this.draftNormY;

      if (this.nodeAvatarUrl) this.preloadImage(this.nodeAvatarUrl);

      try {
        await this.presence.setMyLocation(
          (this.profile as any)?.country_code ?? null,
          (this.profile as any)?.country_name ?? null,
          (this.profile as any)?.city_name ?? null
        );
      } catch {}

      this.saveState = 'saved';
      this.forceUi();

      window.setTimeout(() => {
        this.zone.run(() => this.closePanel());
      }, 220);
    } catch (e: any) {
      this.msg = e?.message ?? String(e);
      this.saveState = 'idle';
      this.forceUi();
    }
  }

  async logout(): Promise<void> {
    this.presence.stop();
    await this.auth.logout();
    await this.router.navigateByUrl('/auth');
  }

  private preloadImage(url: string): void {
    const img = new Image();
    img.decoding = 'async';
    img.loading = 'eager';
    img.src = url;
  }

  private forceUi(): void {
    this.zone.run(() => this.cdr.detectChanges());
  }
}
