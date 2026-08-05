import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import type { CountryPost } from '../core/models/post.model';
import { HubsCatalogService } from './hubs-catalog.service';

export type HubsPlaybackState = {
  post: CountryPost | null;
  expanded: boolean;
  playing: boolean;
  muted: boolean;
};

const initial: HubsPlaybackState = {
  post: null,
  expanded: false,
  playing: false,
  muted: false,
};

/**
 * Global continuous Hubs long-form player — ports AppState hubPlayback* + GlobalHubPlaybackLayer.
 * Single source of truth for watch + mini player across routes.
 */
@Injectable({ providedIn: 'root' })
export class HubsPlaybackService {
  private readonly state$ = new BehaviorSubject<HubsPlaybackState>(initial);
  readonly changes$ = this.state$.asObservable();

  constructor(private catalog: HubsCatalogService) {}

  get snapshot(): HubsPlaybackState {
    return this.state$.value;
  }

  get post(): CountryPost | null {
    return this.state$.value.post;
  }

  get expanded(): boolean {
    return this.state$.value.expanded;
  }

  get playing(): boolean {
    return this.state$.value.playing;
  }

  get muted(): boolean {
    return this.state$.value.muted;
  }

  get isMini(): boolean {
    const s = this.state$.value;
    return !!s.post && !s.expanded;
  }

  get isActive(): boolean {
    return !!this.state$.value.post;
  }

  start(post: CountryPost, expanded = true): void {
    this.catalog.recordWatch(post.id);
    this.state$.next({
      post,
      expanded,
      playing: true,
      muted: this.state$.value.muted,
    });
  }

  minimize(): void {
    const s = this.state$.value;
    if (!s.post) return;
    this.state$.next({ ...s, expanded: false });
  }

  expand(): void {
    const s = this.state$.value;
    if (!s.post) return;
    this.state$.next({ ...s, expanded: true, playing: true });
  }

  stop(): void {
    this.state$.next({ ...initial, muted: this.state$.value.muted });
  }

  setPlaying(playing: boolean): void {
    const s = this.state$.value;
    if (!s.post) return;
    this.state$.next({ ...s, playing });
  }

  togglePlay(): void {
    this.setPlaying(!this.state$.value.playing);
  }

  setMuted(muted: boolean): void {
    const s = this.state$.value;
    this.state$.next({ ...s, muted });
  }

  toggleMute(): void {
    this.setMuted(!this.state$.value.muted);
  }

  updatePost(post: CountryPost): void {
    const s = this.state$.value;
    if (!s.post || s.post.id !== post.id) return;
    this.state$.next({ ...s, post });
  }
}
