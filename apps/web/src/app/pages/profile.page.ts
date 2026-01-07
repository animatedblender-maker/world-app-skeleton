import {
  Component,
  ChangeDetectorRef,
  NgZone,
  OnDestroy,
  OnInit,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { ProfileService, type Profile } from '../core/services/profile.service';
import { AuthService } from '../core/services/auth.service';
import { MediaService } from '../core/services/media.service';
import { PostsService } from '../core/services/posts.service';
import { FollowService } from '../core/services/follow.service';

@Component({
  selector: 'app-profile-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="wrap">
      <div class="ocean-gradient" aria-hidden="true"></div>
      <div class="ocean-dots" aria-hidden="true"></div>
      <div class="noise" aria-hidden="true"></div>
      <div class="card" *ngIf="!loading && !error && profile; else stateTpl">
        <button class="ghost-link back-link" type="button" (click)="goBack()">← BACK</button>
        <div class="head">
            <div class="avatar-block" (click)="openAvatarModal()">
              <div class="avatar">
                <img
                  *ngIf="avatarImage"
                  [src]="avatarImage"
                alt="avatar"
                [style.transform]="avatarTransform"
                class="img"
              />
              <div class="init" *ngIf="!avatarImage">{{ initials }}</div>
              <span class="ring"></span>
            </div>
            <button
              *ngIf="isOwner && profileEditMode"
              type="button"
              class="micro-btn outline"
              (click)="toggleAvatarEditor($event)"
            >
              {{ editingAvatar ? 'Close avatar editor' : 'Edit avatar' }}
            </button>
          </div>

          <div class="info">
            <div class="title-row" *ngIf="!editingName">
              <div class="title">{{ profile!.display_name || profile!.username || 'User' }}</div>
            <div class="title-actions">
                <button class="micro-btn" *ngIf="isOwner && profileEditMode" type="button" (click)="startNameEdit()">Refine name</button>
                <button
                  class="micro-btn outline edit-profile-toggle"
                  *ngIf="isOwner"
                  type="button"
                  (click)="onProfileEditAction()"
                  [disabled]="profileEditSaving"
                >
                  <ng-container *ngIf="!profileEditMode">
                    Edit profile
                  </ng-container>
                    <ng-container *ngIf="profileEditMode">
                      <span *ngIf="!profileEditSaved">Save</span>
                      <span *ngIf="profileEditSaved" class="saved-check" aria-live="polite">
                        <span aria-hidden="true">✓</span>
                        <span aria-hidden="true" class="check-arrow">↗</span>
                        Saved
                      </span>
                    </ng-container>
                </button>
              </div>
              <button
                class="share-icon bare share-emoji"
                type="button"
                (click)="copyShareLink()"
                [disabled]="!shareUrl"
                aria-label="Copy profile link"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 -960 960 960"
                  role="img"
                  aria-hidden="true"
                  focusable="false"
                >
                  <path
                    fill="#e3e3e3"
                    d="M680-80q-50 0-85-35t-35-85q0-6 3-28L282-392q-16 15-37 23.5t-45 8.5q-50 0-85-35t-35-85q0-50 35-85t85-35q24 0 45 8.5t37 23.5l281-164q-2-7-2.5-13.5T560-760q0-50 35-85t85-35q50 0 85 35t35 85q0 50-35 85t-85 35q-24 0-45-8.5T598-672L317-508q2 7 2.5 13.5t.5 14.5q0 8-.5 14.5T317-452l281 164q16-15 37-23.5t45-8.5q50 0 85 35t35 85q0 50-35 85t-85 35Zm0-80q17 0 28.5-11.5T720-200q0-17-11.5-28.5T680-240q-17 0-28.5 11.5T640-200q0 17 11.5 28.5T680-160ZM200-440q17 0 28.5-11.5T240-480q0-17-11.5-28.5T200-520q-17 0-28.5 11.5T160-480q0 17 11.5 28.5T200-440Zm480-280q17 0 28.5-11.5T720-760q0-17-11.5-28.5T680-800q-17 0-28.5 11.5T640-760q0 17 11.5 28.5T680-720Zm0 520ZM200-480Zm480-280Z"
                  />
                </svg>
              </button>
            </div>
            <div class="share-feedback" [class.error]="!!shareError" *ngIf="shareCopied || shareError">
              {{ shareError || (shareCopied ? 'Link copied' : '') }}
            </div>

            <div class="edit-row" *ngIf="editingName">
              <input
                class="text-input"
                [(ngModel)]="draftDisplayName"
                maxlength="80"
                placeholder="Display name"
              />
              <div class="edit-actions">
                <button class="btn" type="button" (click)="saveDisplayName()" [disabled]="nameSaving">
                  {{ nameSaving ? 'Saving…' : 'Save' }}
                </button>
                <button class="ghost-link" type="button" (click)="cancelNameEdit()">Cancel</button>
              </div>
            </div>

              <div class="handle-row" *ngIf="!editingUsername">
                <div class="sub handle">
                  @{{ profile!.username || 'username pending' }}
                </div>
                <button
                  class="micro-btn"
                  type="button"
                  *ngIf="isOwner && profileEditMode"
                  (click)="startUsernameEdit()"
                >
                  {{ profile!.username ? 'Edit handle' : 'Set handle' }}
                </button>
              </div>

            <div class="social-row" *ngIf="profile">
              <div class="stat-card">
                <div class="stat-value">
                  {{ followMetaLoading && followersCount === null ? '…' : followersCount ?? '—' }}
                </div>
                <div class="stat-label">Followers</div>
              </div>
              <div class="stat-card">
                <div class="stat-value">
                  {{ followMetaLoading && followingCount === null ? '…' : followingCount ?? '—' }}
                </div>
                <div class="stat-label">Following</div>
              </div>
              <div class="follow-cta" *ngIf="!isOwner">
                <button
                  class="follow-btn"
                  type="button"
                  [class.following]="viewerFollowing"
                  [disabled]="followBusy || followMetaLoading"
                  (click)="toggleFollow()"
                >
                  <span *ngIf="followMetaLoading && !viewerFollowing">Loading</span>
                  <ng-container *ngIf="!followMetaLoading || viewerFollowing">
                    {{ viewerFollowing ? 'Following' : 'Follow' }}
                  </ng-container>
                </button>
                <small class="hint error" *ngIf="followError">{{ followError }}</small>
              </div>
            </div>

            <div class="edit-row" *ngIf="editingUsername">
              <input
                class="text-input"
                [(ngModel)]="draftUsername"
                (ngModelChange)="onUsernameDraftChange()"
                maxlength="24"
                placeholder="username"
                autocapitalize="off"
                autocomplete="off"
                spellcheck="false"
              />
              <small class="hint">
                Use 3-24 letters, numbers, dots, or underscores. No spaces.
              </small>
              <div class="edit-actions">
                <button class="btn" type="button" (click)="saveUsername()" [disabled]="usernameSaving">
                  {{ usernameSaving ? 'Saving...' : 'Save handle' }}
                </button>
                <button class="ghost-link" type="button" (click)="cancelUsernameEdit()">Cancel</button>
                <small class="hint error" *ngIf="usernameError">{{ usernameError }}</small>
              </div>
            </div>

            <div class="meta">
              <span *ngIf="profile!.country_name">{{ profile!.country_name }}</span>
              <span *ngIf="profile!.city_name">• {{ profile!.city_name }}</span>
            </div>

            <div class="bio" *ngIf="!editingBio">
              <div>{{ bio || 'No bio yet.' }}</div>
              <button class="micro-btn" *ngIf="isOwner && profileEditMode" type="button" (click)="startBioEdit()">Refine bio</button>
            </div>

            <div class="edit-row" *ngIf="editingBio">
              <textarea
                class="text-input textarea"
                [(ngModel)]="draftBio"
                maxlength="160"
                placeholder="Tell the world about you"
              ></textarea>
              <div class="edit-actions">
                <button class="btn" type="button" (click)="saveBio()" [disabled]="bioSaving">
                  {{ bioSaving ? 'Saving…' : 'Save bio' }}
                </button>
                <button class="ghost-link" type="button" (click)="cancelBioEdit()">Cancel</button>
              </div>
            </div>
          </div>
        </div>

        <div class="composer profile-composer" *ngIf="canPostFromProfile">
          <div class="composer-row">
            <div class="composer-avatar">
              <img
                *ngIf="avatarImage"
                [src]="avatarImage"
                alt="avatar"
              />
              <div class="composer-initials" *ngIf="!avatarImage">{{ initials }}</div>
            </div>
            <div class="composer-main">
              <div class="composer-top">
                <div>
                  <div class="composer-title">Share with {{ profile!.country_name }}</div>
                  <div class="composer-hint">Posts appear in {{ profile!.country_name }}'s live feed.</div>
                </div>
                <div class="composer-cta">
                  <button
                    class="pill-link ghost"
                    type="button"
                    *ngIf="profileComposerOpen"
                    (click)="profileComposerOpen = false"
                  >
                    Cancel
                  </button>
                </div>
              </div>
              <button
                class="composer-trigger"
                type="button"
                *ngIf="!profileComposerOpen"
                (click)="profileComposerOpen = true"
              >
                What's new in {{ profile!.country_name }}?
              </button>
              <ng-container *ngIf="profileComposerOpen">
                <input
                  class="composer-input"
                  [(ngModel)]="postTitle"
                  maxlength="120"
                  placeholder="Add a headline (optional)"
                />
                <textarea
                  class="composer-textarea"
                  rows="3"
                  maxlength="5000"
                  placeholder="Tell {{ profile!.country_name }} what's happening..."
                  [(ngModel)]="postBody"
                ></textarea>
              </ng-container>
            </div>
          </div>

          <div class="composer-actions" *ngIf="profileComposerOpen">
            <button class="btn" type="button" (click)="submitProfilePost()" [disabled]="postBusy || !canPostFromProfile">
              {{ postBusy ? 'Posting…' : ('Post to ' + profile!.country_name) }}
            </button>
            <div class="composer-status" [class.error]="!!postError" *ngIf="postError || postFeedback">
              {{ postError || postFeedback }}
            </div>
          </div>
        </div>

        <div class="avatar-editor" *ngIf="editingAvatar">
          <div class="editor-head">
            <div>
              <div class="sec-title">Avatar</div>
              <small>Upload a square image (PNG/JPG/WebP). Drag to position inside the circle.</small>
            </div>
            <label class="btn-file">
              Choose image
              <input type="file" accept="image/*" (change)="onAvatar($event)" />
            </label>
          </div>

          <div class="editor-preview">
            <div
              class="avatar large"
              (pointerdown)="onAvatarDragStart($event)"
              [class.adjusting]="true"
              *ngIf="draftAvatarUrl"
            >
              <img
                class="img"
                [src]="draftAvatarUrl"
                alt="preview"
                [style.transform]="draftAvatarTransform"
              />
              <span class="ring"></span>
            </div>
            <div class="muted" *ngIf="!draftAvatarUrl">Choose an image to begin.</div>
          </div>

          <div class="edit-actions">
            <button class="btn" type="button" (click)="saveAvatar()" [disabled]="!draftAvatarUrl || avatarSaving">
              {{ avatarSaving ? 'Saving…' : 'Save avatar' }}
            </button>
            <button class="ghost-link" type="button" (click)="cancelAvatarEdit()">Cancel</button>
            <small class="hint error" *ngIf="avatarError">{{ avatarError }}</small>
          </div>
        </div>
      </div>

      <ng-template #stateTpl>
        <div class="card state">
          <div *ngIf="loading">Loading profile…</div>
          <div *ngIf="!loading">{{ error || 'Profile not found.' }}</div>
        </div>
      </ng-template>
    </div>

    <div class="avatar-modal" *ngIf="avatarModalOpen" (click)="closeAvatarModal()">
      <div class="avatar-modal-card" (click)="$event.stopPropagation()">
        <div class="avatar large">
          <img
            class="img"
            [src]="avatarModalImage"
            alt="avatar"
            [style.transform]="avatarModalTransform"
          />
          <span class="ring"></span>
        </div>
        <button class="ghost-link" type="button" (click)="closeAvatarModal()">Close</button>
      </div>
    </div>
  `,
  styles: [`
    :host{
      position: fixed;
      inset: 0;
      display:block;
      pointer-events:auto;
      z-index:30;
    }
    .wrap{
      position: fixed;
      inset: 0;
      padding: 86px 16px 32px;
      box-sizing: border-box;
      overflow: auto;
      background: #031421;
      color: rgba(255,255,255,0.92);
    }
    .wrap > .ocean-gradient,
    .wrap > .ocean-dots,
    .wrap > .noise{
      position:absolute;
      inset:0;
      pointer-events:none;
    }
    .ocean-gradient{
      z-index:0;
      background:
        radial-gradient(1400px 900px at 38% 20%, rgba(0,255,209,0.18), transparent 60%),
        radial-gradient(1100px 900px at 65% 70%, rgba(140,0,255,0.14), transparent 64%),
        #031421;
      animation: oceanPulse 18s ease-in-out infinite;
    }
    .ocean-dots{
      z-index:1;
      background-image:
        radial-gradient(circle at 20% 20%, rgba(255,255,255,0.35) 0.8px, transparent 2px),
        radial-gradient(circle at 70% 30%, rgba(255,255,255,0.25) 0.6px, transparent 2px),
        radial-gradient(circle at 40% 70%, rgba(255,255,255,0.20) 0.7px, transparent 2.2px);
      background-size: 220px 220px, 340px 340px, 520px 520px;
      opacity:0.45;
      mix-blend-mode: screen;
      animation: driftDots 48s linear infinite;
    }
    .noise{
      z-index:2;
      background-image:
        linear-gradient(0deg, rgba(255,255,255,0.04) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255,255,255,0.04) 1px, transparent 1px);
      background-size: 4px 4px;
      opacity:0.12;
      pointer-events:none;
      animation: drift 18s linear infinite;
    }
    @keyframes oceanPulse{
      0%{ opacity:0.85; transform: scale(1); }
      50%{ opacity:1; transform: scale(1.02); }
      100%{ opacity:0.85; transform: scale(1); }
    }
    @keyframes driftDots{
      0%{ transform: translate3d(0,0,0); }
      50%{ transform: translate3d(-80px,-40px,0); }
      100%{ transform: translate3d(0,0,0); }
    }
    @keyframes drift{
      0%{ transform: translate3d(0,0,0); }
      50%{ transform: translate3d(-10px, 10px,0); }
      100%{ transform: translate3d(0,0,0); }
    }
    .card{
      position: relative;
      z-index:3;
      width: min(900px, 100%);
      margin: 0 auto;
      border-radius: 28px;
      padding: 24px;
      background: rgba(245,247,250,0.95);
      border: 1px solid rgba(0,0,0,0.08);
      box-shadow: 0 30px 90px rgba(0,0,0,0.50);
      color: rgba(10,12,18,0.92);
      min-height: 200px;
    }
    .state{
      text-align:center;
      font-weight:800;
      font-size:14px;
    }
    .share-row{
      margin-bottom: 18px;
    }
    .share-box{
      border-radius: 18px;
      border: 1px solid rgba(0,0,0,0.08);
      background: rgba(255,255,255,0.94);
      padding: 14px;
    }
    .share-box.empty{
      display:flex;
      flex-direction:column;
      gap:8px;
      align-items:flex-start;
    }
    .share-label{ font-weight: 900; font-size: 12px; letter-spacing: .12em; opacity:.65; }
    .share-link{
      font-family: 'JetBrains Mono','SFMono-Regular','Consolas',monospace;
      font-size:12px;
      word-break: break-all;
      margin-top:6px;
    }
    .share-placeholder{
      font-size:13px;
      opacity:0.7;
    }
    .share-actions{
      margin-top:10px;
      display:flex;
      gap:12px;
      align-items:center;
      flex-wrap:wrap;
    }
    .composer{
      margin-top:20px;
      border-radius:20px;
      border:1px solid rgba(0,0,0,0.06);
      background:rgba(255,255,255,0.95);
      padding:16px;
      box-shadow:0 20px 60px rgba(0,0,0,0.10);
    }
    .composer.profile-composer{ margin-bottom:20px; }
    .composer-row{ display:flex; gap:14px; align-items:flex-start; }
    .composer-avatar{
      width:48px;
      height:48px;
      border-radius:999px;
      overflow:hidden;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.9);
      display:grid;
      place-items:center;
      flex:0 0 auto;
    }
    .composer-avatar img{ width:100%; height:100%; object-fit:cover; }
    .composer-initials{ font-weight:900; letter-spacing:0.12em; color:rgba(10,12,18,0.8); }
    .composer-main{ flex:1; }
    .composer-top{ display:flex; justify-content:space-between; gap:12px; flex-wrap:wrap; }
    .composer-cta{ display:flex; gap:8px; align-items:center; }
    .composer-title{ font-weight:900; letter-spacing:0.12em; font-size:12px; }
    .composer-hint{ font-size:12px; opacity:0.7; margin-top:4px; }
    .pill-link{
      border:0;
      border-radius:999px;
      padding:6px 16px;
      font-size:10px;
      letter-spacing:0.18em;
      font-weight:900;
      text-transform:uppercase;
      background:rgba(0,0,0,0.05);
      color:rgba(10,12,18,0.75);
      cursor:pointer;
    }
    .pill-link.ghost{
      background:transparent;
      border:1px solid rgba(10,12,18,0.15);
    }
    .composer-trigger{
      width:100%;
      margin-top:10px;
      border-radius:16px;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.9);
      text-align:left;
      padding:12px;
      font-weight:600;
      color:rgba(10,12,18,0.65);
      cursor:pointer;
    }
    .composer-input,
    .composer-textarea{
      width:100%;
      margin-top:10px;
      border-radius:16px;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.9);
      padding:12px;
      font-family:inherit;
      font-size:14px;
    }
    .composer-textarea{ min-height:90px; resize:vertical; }
    .composer-actions{ margin-top:12px; display:flex; align-items:center; gap:12px; flex-wrap:wrap; }
    .composer-status{ font-size:12px; font-weight:700; letter-spacing:0.08em; color:rgba(0,120,255,0.9); }
    .composer-status.error{ color:#c33; }
    .btn{
      border:0;
      border-radius:16px;
      padding:10px 14px;
      background: linear-gradient(90deg, rgba(0,255,209,0.85), rgba(140,0,255,0.75));
      color: rgba(6,8,14,0.96);
      font-weight:900;
      letter-spacing:0.12em;
      cursor:pointer;
    }
    .btn:disabled{
      opacity:0.6;
      cursor:not-allowed;
    }
    .micro-btn{
      border:0;
      border-radius:999px;
      padding:6px 16px;
      text-transform:uppercase;
      letter-spacing:0.18em;
      font-size:10px;
      font-weight:900;
      background: rgba(10,12,18,0.06);
      color: rgba(10,12,18,0.78);
      box-shadow: inset 0 0 0 1px rgba(10,12,18,0.06), 0 12px 32px rgba(0,0,0,0.08);
      cursor:pointer;
      transition: transform 160ms ease, box-shadow 160ms ease, background 160ms ease;
    }
    .micro-btn:hover{
      transform: translateY(-1px);
      box-shadow: inset 0 0 0 1px rgba(10,12,18,0.12), 0 18px 40px rgba(0,0,0,0.12);
    }
    .micro-btn.outline{
      background: rgba(255,255,255,0.9);
      color: rgba(6,8,14,0.85);
      box-shadow: inset 0 0 0 1px rgba(0,0,0,0.05), 0 10px 30px rgba(0,0,0,0.09);
    }
    .share-icon{
      border:0;
      border-radius:999px;
      width:36px;
      height:36px;
      display:grid;
      place-items:center;
      background:rgba(10,12,18,0.08);
      cursor:pointer;
      font-size:16px;
    }
    .share-icon.bare{
      background:transparent;
      width:auto;
      height:auto;
      font-size:20px;
      line-height:1;
    }
    .share-icon.share-emoji{
      width:24px;
      height:24px;
      padding:0;
      margin-left:auto;
    }
    .edit-profile-toggle .saved-check{
      display:inline-flex;
      align-items:center;
      gap:4px;
      color:#00c781;
      font-weight:700;
      letter-spacing:0.05em;
    }
    .edit-profile-toggle .saved-check .check-arrow{
      font-size:14px;
    }
    .share-icon.share-emoji svg{
      width:100%;
      height:100%;
      display:block;
    }
    .share-icon:disabled{
      opacity:0.4;
      cursor:not-allowed;
    }
    .hint{
      font-size:12px;
      opacity:0.75;
    }
    .hint.error{
      color:#c33;
      opacity:1;
    }
    .sr-only{
      position:absolute;
      width:1px;
      height:1px;
      padding:0;
      margin:-1px;
      overflow:hidden;
      clip:rect(0,0,0,0);
      border:0;
    }
    .head{
      display:flex;
      gap:20px;
      align-items:flex-start;
      flex-wrap:wrap;
    }
    .avatar-block{
      display:flex;
      flex-direction:column;
      align-items:center;
      gap:8px;
      cursor:pointer;
    }
    .avatar{
      width: 110px;
      height: 110px;
      border-radius:999px;
      overflow:hidden;
      position:relative;
      border:1px solid rgba(0,255,209,0.24);
      background: rgba(10,12,20,0.12);
      display:grid;
      place-items:center;
    }
    .avatar.large{
      width: 180px;
      height: 180px;
    }
    .img{
      width:120%;
      height:120%;
      object-fit: cover;
      transition: transform 120ms linear;
    }
    .ring{
      position:absolute;
      inset:-2px;
      border-radius:999px;
      background: conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.55), rgba(140,0,255,0.45), rgba(0,255,209,0));
      filter: blur(12px);
      opacity:0.25;
      pointer-events:none;
    }
    .ghost-link{
      border:0;
      background:transparent;
      color: rgba(0,120,255,0.85);
      font-size:12px;
      text-transform:uppercase;
      letter-spacing:0.12em;
      font-weight:800;
      cursor:pointer;
    }
    .back-link{
      color: rgba(0,0,0,0.65);
      margin-bottom:12px;
      display:inline-flex;
      align-items:center;
      gap:6px;
    }
    .ghost-link.strong{
      letter-spacing:0.18em;
    }
    .handle-row{
      display:flex;
      align-items:center;
      gap:12px;
      flex-wrap:wrap;
      margin-top:4px;
    }
    .sub.handle{
      margin:0;
    }
    .info{ flex:1; min-width:0; }
    .title{ font-size:20px; font-weight:900; letter-spacing:.08em; text-transform:uppercase; }
    .title-row{
      display:flex;
      align-items:center;
      gap:12px;
      flex-wrap:wrap;
    }
    .title-actions{
      display:flex;
      align-items:center;
      gap:10px;
    }
    .sub{
      margin-top:4px;
      font-weight:800;
      opacity:0.75;
    }
    .meta{
      margin-top:6px;
      font-size:13px;
      opacity:0.7;
      font-weight:700;
      display:flex;
      gap:6px;
      flex-wrap:wrap;
    }
    .social-row{
      margin-top:12px;
      display:flex;
      gap:14px;
      flex-wrap:wrap;
      align-items:center;
    }
    .stat-card{
      min-width:110px;
      border-radius:18px;
      padding:12px 14px;
      background: rgba(0,0,0,0.035);
      border:1px solid rgba(0,0,0,0.05);
      box-shadow: 0 18px 40px rgba(0,0,0,0.08);
    }
    .stat-value{
      font-weight:900;
      font-size:18px;
      letter-spacing:0.08em;
      color: rgba(6,8,14,0.88);
    }
    .stat-label{
      font-size:11px;
      letter-spacing:0.18em;
      text-transform:uppercase;
      opacity:0.6;
      font-weight:800;
    }
    .follow-cta{
      margin-left:auto;
      display:flex;
      flex-direction:column;
      gap:6px;
      align-items:flex-end;
    }
    .follow-btn{
      border:0;
      border-radius:999px;
      padding:10px 22px;
      background: linear-gradient(120deg, rgba(0,255,209,0.95), rgba(140,0,255,0.78));
      color: rgba(6,8,14,0.92);
      font-weight:900;
      letter-spacing:0.2em;
      text-transform:uppercase;
      cursor:pointer;
      box-shadow: 0 18px 50px rgba(0,255,209,0.28);
      transition: transform 160ms ease, box-shadow 160ms ease, opacity 160ms ease;
    }
    .follow-btn.following{
      background: rgba(10,12,20,0.9);
      color: rgba(255,255,255,0.9);
      box-shadow: 0 18px 40px rgba(0,0,0,0.24);
    }
    .follow-btn:disabled{
      opacity:0.6;
      cursor:not-allowed;
      box-shadow:none;
      transform:none;
    }
    .bio{
      margin-top:12px;
      line-height:1.5;
      font-size:14px;
    }
    .text-input{
      width:100%;
      border-radius:14px;
      border:1px solid rgba(0,0,0,0.12);
      padding:10px 12px;
      font-size:14px;
      font-family:inherit;
      background: rgba(255,255,255,0.95);
    }
    .textarea{
      min-height:90px;
      resize:vertical;
    }
    .edit-row{
      margin-top:10px;
    }
    .edit-actions{
      margin-top:10px;
      display:flex;
      gap:12px;
      align-items:center;
      flex-wrap:wrap;
    }
    .avatar-editor{
      margin-top:24px;
      border-top:1px solid rgba(0,0,0,0.08);
      padding-top:16px;
    }
    .editor-head{
      display:flex;
      justify-content:space-between;
      align-items:center;
      gap:16px;
      flex-wrap:wrap;
    }
    .sec-title{
      font-weight:900;
      letter-spacing:.12em;
      font-size:12px;
      text-transform:uppercase;
    }
    .btn-file{
      border:1px solid rgba(0,0,0,0.1);
      border-radius:14px;
      padding:10px 12px;
      cursor:pointer;
      background:rgba(255,255,255,0.95);
      font-weight:800;
      letter-spacing:.08em;
    }
    .btn-file input{
      display:none;
    }
    .editor-preview{
      margin-top:18px;
      display:flex;
      justify-content:center;
    }
    .avatar-modal{
      position: fixed;
      inset:0;
      background: rgba(0,0,0,0.55);
      display:grid;
      place-items:center;
      z-index:40;
    }
    .avatar-modal-card{
      background: rgba(10,12,20,0.92);
      border:1px solid rgba(255,255,255,0.12);
      border-radius:24px;
      padding:24px;
      text-align:center;
      color:rgba(255,255,255,0.92);
    }
  `],
})
export class ProfilePageComponent implements OnInit, OnDestroy {
  profile: Profile | null = null;
  loading = false;
  error = '';
  private sub?: Subscription;

  shareUrl = '';
  shareCopied = false;
  shareError = '';
  private shareTimer: any = null;

  isOwner = false;
  private meId: string | null = null;
  followersCount: number | null = null;
  followingCount: number | null = null;
  followMetaLoading = false;
  viewerFollowing = false;
  followBusy = false;
  followError = '';
  private followProfileId: string | null = null;
  postTitle = '';
  postBody = '';
  postBusy = false;
  postError = '';
  postFeedback = '';
  profileComposerOpen = false;

  avatarImage = '';
  avatarNormX = 0;
  avatarNormY = 0;
  avatarModalOpen = false;

  editingName = false;
  nameSaving = false;
  draftDisplayName = '';

  editingUsername = false;
  usernameSaving = false;
  draftUsername = '';
  usernameError = '';

  editingBio = false;
  bioSaving = false;
  draftBio = '';
  bio = '';
  profileEditMode = false;
  profileEditSaving = false;
  profileEditSaved = false;
  private profileEditCloseTimer: any = null;

  editingAvatar = false;
  avatarSaving = false;
  avatarError = '';
  draftAvatarUrl = '';

  private readonly AVATAR_OUT_SIZE = 512;
  private readonly EDIT_SIZE = 180;
  private readonly EDIT_SCALE = 1.25;
  private readonly USERNAME_PATTERN = /^[a-z0-9._]{3,24}$/;

  private draftNormX = 0;
  private draftNormY = 0;
  private dragging = false;
  private startX = 0;
  private startY = 0;
  private basePxX = 0;
  private basePxY = 0;
  private pendingPxX = 0;
  private pendingPxY = 0;
  private raf = 0;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private profiles: ProfileService,
    private auth: AuthService,
    private media: MediaService,
    private posts: PostsService,
    private follows: FollowService,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;

    this.sub = this.route.paramMap.subscribe((params) => {
      const slug = params.get('slug') ?? '';
      this.loadProfile(slug);
    });
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
    if (this.shareTimer) clearTimeout(this.shareTimer);
    if (this.profileEditCloseTimer) clearTimeout(this.profileEditCloseTimer);
  }

  get initials(): string {
    const name = (this.profile?.display_name || this.profile?.username || 'U').trim();
    const parts = name.split(/\s+/).filter(Boolean);
    const a = parts[0]?.[0] ?? 'U';
    const b = parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? '') : '';
    return (a + b).toUpperCase();
  }

  get avatarTransform(): string {
    const mo = this.maxOffset(110, 1.2);
    return `translate3d(${this.avatarNormX * mo}px, ${this.avatarNormY * mo}px, 0)`;
  }

  get draftAvatarTransform(): string {
    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);
    return `translate3d(${this.draftNormX * mo}px, ${this.draftNormY * mo}px, 0)`;
  }

  get avatarModalImage(): string {
    return this.draftAvatarUrl || this.avatarImage;
  }

  get avatarModalTransform(): string {
    const mo = this.maxOffset(180, 1.2);
    return `translate3d(${this.avatarNormX * mo}px, ${this.avatarNormY * mo}px, 0)`;
  }

  get canPostFromProfile(): boolean {
    if (!this.isOwner || !this.profile) return false;
    const code = (this.profile as any)?.country_code;
    const name = this.profile.country_name;
    return !!code && !!name;
  }

  async goHome(): Promise<void> {
    await this.router.navigateByUrl('/');
  }

  private async loadProfile(slugRaw: string): Promise<void> {
    this.loading = true;
    this.error = '';
    this.profile = null;
    this.resetFollowState();
    this.forceUi();

    try {
      const slug = (slugRaw || '').trim();
      if (!slug) throw new Error('Profile not found.');

      const username = slug.startsWith('@') ? slug.slice(1) : slug;

      let profile: Profile | null = null;

      if (username) {
        const byUsername = await this.profiles.profileByUsername(username);
        profile = byUsername.profileByUsername ?? null;
      }

      if (!profile) {
        const byId = await this.profiles.profileById(slug);
        profile = byId.profileById ?? null;
      }

      if (!profile) {
        this.error = 'Profile not found.';
      } else {
        this.applyProfile(profile);
      }
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.loading = false;
      this.forceUi();
    }
  }

  private applyProfile(profile: Profile): void {
    this.profile = profile;
    this.avatarImage = (profile as any)?.avatar_url ?? '';
    this.bio = (profile as any)?.bio ?? '';
    this.draftDisplayName = profile.display_name ?? '';
    this.draftBio = this.bio ?? '';
    this.draftUsername = profile.username ?? '';
    this.usernameError = '';
    this.shareUrl = this.buildShareUrl(profile);
    this.shareCopied = false;
    this.shareError = '';
    this.isOwner = !!this.meId && profile.user_id === this.meId;
    this.resetFollowState();
    if (!this.canPostFromProfile) this.profileComposerOpen = false;
    void this.loadFollowMeta(profile);
  }

  private resetFollowState(): void {
    this.followersCount = null;
    this.followingCount = null;
    this.viewerFollowing = false;
    this.followError = '';
    this.followMetaLoading = false;
    this.followProfileId = null;
    this.followBusy = false;
  }

  private async loadFollowMeta(profile: Profile): Promise<void> {
    if (!profile?.user_id) {
      this.resetFollowState();
      return;
    }

    const targetId = profile.user_id;
    this.followProfileId = targetId;
    this.followMetaLoading = true;
    this.followError = '';
    this.forceUi();

    try {
      const [counts, viewerFollows] = await Promise.all([
        this.follows.counts(targetId),
        !this.isOwner && this.meId ? this.follows.isFollowing(this.meId, targetId) : Promise.resolve(false),
      ]);
      if (this.followProfileId !== targetId) return;
      this.followersCount = counts.followers;
      this.followingCount = counts.following;
      this.viewerFollowing = viewerFollows;
    } catch (e: any) {
      if (this.followProfileId === targetId) {
        this.followError = e?.message ?? String(e);
      }
    } finally {
      if (this.followProfileId === targetId) {
        this.followMetaLoading = false;
        this.forceUi();
      }
    }
  }

  async toggleFollow(): Promise<void> {
    if (!this.profile || this.isOwner) return;

    if (!this.meId) {
      await this.router.navigate(['/auth']);
      return;
    }

    if (this.followMetaLoading || this.followBusy) return;

    this.followBusy = true;
    this.followError = '';
    this.forceUi();

    try {
      if (this.viewerFollowing) {
        await this.follows.unfollow(this.meId, this.profile.user_id);
        this.viewerFollowing = false;
        const next = (this.followersCount ?? 1) - 1;
        this.followersCount = next < 0 ? 0 : next;
      } else {
        await this.follows.follow(this.meId, this.profile.user_id);
        this.viewerFollowing = true;
        this.followersCount = (this.followersCount ?? 0) + 1;
      }
    } catch (e: any) {
      this.followError = e?.message ?? String(e);
    } finally {
      this.followBusy = false;
      this.forceUi();
    }
  }

  async submitProfilePost(): Promise<void> {
    if (!this.profile || !this.meId || !this.canPostFromProfile) return;
    const body = this.postBody.trim();
    if (!body) {
      this.postError = 'Write something before posting.';
      return;
    }

    this.postBusy = true;
    this.postError = '';
    this.postFeedback = '';
    this.forceUi();

    try {
      const title = this.postTitle.trim();
      const countryCode = String((this.profile as any)?.country_code || '').toUpperCase();
      const countryName = this.profile.country_name;
      if (!countryCode || !countryName) throw new Error('Country details missing.');

      await this.posts.createPost({
        authorId: this.meId,
        title: title || null,
        body,
        countryCode,
        countryName,
        cityName: (this.profile as any)?.city_name ?? null,
      });

      this.postTitle = '';
      this.postBody = '';
      this.profileComposerOpen = false;
      this.postFeedback = `Shared with ${countryName}.`;
      this.forceUi();
      setTimeout(() => {
        this.postFeedback = '';
        this.cdr.detectChanges();
      }, 2000);
    } catch (e: any) {
      this.postError = e?.message ?? String(e);
    } finally {
      this.postBusy = false;
      this.forceUi();
    }
  }

  startNameEdit(): void {
    this.draftDisplayName = this.profile?.display_name ?? '';
    this.editingName = true;
  }

  cancelNameEdit(): void {
    this.editingName = false;
    this.draftDisplayName = this.profile?.display_name ?? '';
  }

  async saveDisplayName(): Promise<void> {
    if (!this.profile) return;
    const name = this.draftDisplayName.trim();
    if (!name) return;

    this.nameSaving = true;
    this.forceUi();

    try {
      const res = await this.profiles.updateProfile({ display_name: name });
      this.applyProfile(res.updateProfile);
      this.editingName = false;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.nameSaving = false;
      this.forceUi();
    }
  }

  startUsernameEdit(): void {
    if (!this.isOwner) return;
    this.usernameError = '';
    this.draftUsername = this.profile?.username ?? '';
    this.editingUsername = true;
  }

  cancelUsernameEdit(): void {
    this.editingUsername = false;
    this.usernameError = '';
    this.draftUsername = this.profile?.username ?? '';
  }

  onUsernameDraftChange(): void {
    if (this.usernameError) {
      this.usernameError = '';
      this.forceUi();
    }
  }

  async saveUsername(): Promise<void> {
    if (!this.profile || !this.isOwner) return;
    const normalized = this.normalizeUsername(this.draftUsername);
    if (!normalized) {
      this.usernameError = 'Username is required.';
      return;
    }
    if (!this.USERNAME_PATTERN.test(normalized)) {
      this.usernameError = 'Use 3-24 letters, numbers, dots, or underscores.';
      return;
    }
    if ((this.profile.username ?? '') === normalized) {
      this.editingUsername = false;
      return;
    }

    this.usernameSaving = true;
    this.usernameError = '';
    this.forceUi();

    try {
      const res = await this.profiles.updateProfile({ username: normalized });
      this.applyProfile(res.updateProfile);
      this.editingUsername = false;
    } catch (e: any) {
      const message = (e?.message ?? String(e)).toLowerCase();
      if (message.includes('duplicate') || message.includes('unique')) {
        this.usernameError = 'Handle already taken.';
      } else {
        this.usernameError = e?.message ?? String(e);
      }
    } finally {
      this.usernameSaving = false;
      this.forceUi();
    }
  }

  startBioEdit(): void {
    this.draftBio = this.bio ?? '';
    this.editingBio = true;
  }

  cancelBioEdit(): void {
    this.editingBio = false;
    this.draftBio = this.bio ?? '';
  }

  async saveBio(): Promise<void> {
    const text = this.draftBio.trim();
    this.bioSaving = true;
    this.forceUi();

    try {
      const res = await this.profiles.updateProfile({
        bio: text ? text.slice(0, 160) : null,
      });
      this.applyProfile(res.updateProfile);
      this.editingBio = false;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.bioSaving = false;
      this.forceUi();
    }
  }

  toggleAvatarEditor(event: Event): void {
    event.stopPropagation();
    this.editingAvatar = !this.editingAvatar;
    this.avatarError = '';
    if (this.editingAvatar) {
      this.draftAvatarUrl = this.avatarImage || '';
      this.draftNormX = this.avatarNormX;
      this.draftNormY = this.avatarNormY;
    }
  }

  cancelAvatarEdit(): void {
    this.editingAvatar = false;
    this.avatarError = '';
    this.draftAvatarUrl = '';
    this.draftNormX = this.avatarNormX;
    this.draftNormY = this.avatarNormY;
  }

  openAvatarModal(): void {
    if (!this.avatarImage && !this.draftAvatarUrl) return;
    this.avatarModalOpen = true;
  }

  closeAvatarModal(): void {
    this.avatarModalOpen = false;
  }

  goBack(): void {
    void this.router.navigate(['/globe'], { queryParams: {} });
  }

  async onAvatar(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.avatarError = '';
    this.avatarSaving = false;
    this.forceUi();

    try {
      const cropped = await this.cropAvatarToSquare(file);
      const upload = await this.media.uploadAvatar(cropped);
      if (!upload.url) throw new Error('Upload returned no URL.');

      this.draftAvatarUrl = upload.url;
      this.draftNormX = 0;
      this.draftNormY = 0;
    } catch (e: any) {
      this.avatarError = e?.message ?? String(e);
    } finally {
      input.value = '';
      this.forceUi();
    }
  }

  async saveAvatar(): Promise<void> {
    if (!this.draftAvatarUrl) return;
    this.avatarSaving = true;
    this.avatarError = '';
    this.forceUi();

    try {
      const res = await this.profiles.updateProfile({
        avatar_url: this.draftAvatarUrl,
      });
      this.applyProfile(res.updateProfile);
      this.avatarImage = this.profile?.avatar_url ?? '';
      this.avatarNormX = this.draftNormX;
      this.avatarNormY = this.draftNormY;
      this.editingAvatar = false;
    } catch (e: any) {
      this.avatarError = e?.message ?? String(e);
    } finally {
      this.avatarSaving = false;
      this.forceUi();
    }
  }

  onAvatarDragStart(ev: PointerEvent): void {
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
  }

  private onAvatarDragMove(ev: PointerEvent): void {
    if (!this.dragging) return;
    const dx = ev.clientX - this.startX;
    const dy = ev.clientY - this.startY;
    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);

    const clamp = (v: number) => Math.max(-mo, Math.min(mo, v));

    this.pendingPxX = clamp(this.basePxX + dx);
    this.pendingPxY = clamp(this.basePxY + dy);

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
  }

  async copyShareLink(): Promise<void> {
    if (!this.shareUrl) return;
    this.shareError = '';
    this.shareCopied = false;
    this.forceUi();

    try {
      if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(this.shareUrl);
      } else {
        throw new Error('Clipboard unavailable.');
      }

      this.shareCopied = true;
      this.forceUi();

      if (typeof window !== 'undefined') {
        if (this.shareTimer) clearTimeout(this.shareTimer);
        this.shareTimer = window.setTimeout(() => {
          this.zone.run(() => {
            this.shareCopied = false;
            this.cdr.detectChanges();
          });
        }, 1600);
      }
    } catch (e: any) {
      this.shareError = e?.message ?? String(e);
      this.forceUi();
    }
  }

  onProfileEditAction(): void {
    if (!this.isOwner) return;
    if (!this.profileEditMode) {
      this.profileEditMode = true;
      this.profileEditSaved = false;
      this.profileEditSaving = false;
      return;
    }
    if (this.profileEditSaving) return;

    this.profileEditSaving = true;
    this.profileEditSaved = true;
    this.forceUi();

    if (this.profileEditCloseTimer) {
      clearTimeout(this.profileEditCloseTimer);
    }

    this.profileEditCloseTimer = window.setTimeout(() => {
      this.completeProfileEditClose();
    }, 700);
  }

  private completeProfileEditClose(): void {
    this.profileEditMode = false;
    this.profileEditSaving = false;
    this.profileEditSaved = false;
    this.profileEditCloseTimer = null;
    this.cancelNameEdit();
    this.cancelUsernameEdit();
    this.cancelBioEdit();
    if (this.editingAvatar) {
      this.cancelAvatarEdit();
    }
    this.forceUi();
  }

  private buildShareUrl(profile: Profile | null): string {
    if (!profile) return '';
    const slug = profile.username?.trim();
    if (!slug) return '';

    const base =
      typeof window !== 'undefined' && window.location ? window.location.origin : '';
    return base ? `${base}/user/${encodeURIComponent(slug)}` : `/user/${encodeURIComponent(slug)}`;
  }

  private normalizeUsername(value: string): string {
    return value.trim().replace(/^@+/, '').toLowerCase();
  }

  private clampNorm(v: number): number {
    return Math.max(-1, Math.min(1, v));
  }

  private maxOffset(size: number, scale: number): number {
    const scaled = size * scale;
    return Math.max(0, (scaled - size) / 2);
  }

  private async cropAvatarToSquare(file: File): Promise<File> {
    const type = (file.type || '').toLowerCase();
    if (type === 'image/gif') throw new Error('GIF avatars are disabled.');
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

  private forceUi(): void {
    this.zone.run(() => this.cdr.detectChanges());
  }
}
