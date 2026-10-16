import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

/**
 * Web port of iOS media-session contract (docs/butter-smooth/09-MEDIA-SESSION.md).
 * At most ONE playing surface app-wide.
 */
export type MediaSessionMode = 'idle' | 'feedAutoplay' | 'hubs' | 'sparks';

export type MediaSessionState = {
  mode: MediaSessionMode;
  /** Post / content id owning the session (feed focus, hubs post, spark post). */
  ownerId: string | null;
  /** Intersection score of current feed focus (0–1). */
  feedScore: number;
};

const initial: MediaSessionState = { mode: 'idle', ownerId: null, feedScore: 0 };

@Injectable({ providedIn: 'root' })
export class MediaSessionService {
  private readonly state$ = new BehaviorSubject<MediaSessionState>(initial);
  readonly changes$ = this.state$.asObservable();

  get snapshot(): MediaSessionState {
    return this.state$.value;
  }

  get mode(): MediaSessionMode {
    return this.state$.value.mode;
  }

  get ownerId(): string | null {
    return this.state$.value.ownerId;
  }

  /** True when Hubs continuous layer owns playback — feed must not autoplay. */
  get hubsOwns(): boolean {
    return this.state$.value.mode === 'hubs';
  }

  get sparksOwns(): boolean {
    return this.state$.value.mode === 'sparks';
  }

  /** Claim feed focus autoplay for one post id. No-op if hubs/sparks own the session. */
  claimFeed(postId: string, score = 1): boolean {
    const id = String(postId || '').trim();
    if (!id) return false;
    if (this.hubsOwns || this.sparksOwns) return false;
    const cur = this.state$.value;
    if (cur.mode === 'feedAutoplay' && cur.ownerId === id) {
      if (score !== cur.feedScore) {
        this.state$.next({ ...cur, feedScore: score });
      }
      return true;
    }
    // Prefer the more-visible card during fling; small epsilon avoids thrash.
    if (cur.mode === 'feedAutoplay' && cur.ownerId && score + 0.05 < cur.feedScore) {
      return false;
    }
    this.state$.next({ mode: 'feedAutoplay', ownerId: id, feedScore: score });
    this.broadcastContentFocus(id, true);
    return true;
  }

  /** Release feed ownership if this post still owns it. */
  releaseFeed(postId?: string | null): void {
    const cur = this.state$.value;
    if (cur.mode !== 'feedAutoplay') return;
    if (postId && cur.ownerId && cur.ownerId !== postId) return;
    this.state$.next(initial);
    this.broadcastContentFocus(null, false);
  }

  claimHubs(postId: string): void {
    const id = String(postId || '').trim() || null;
    this.state$.next({ mode: 'hubs', ownerId: id, feedScore: 0 });
    this.broadcastContentFocus(id, true);
  }

  releaseHubs(): void {
    if (this.state$.value.mode !== 'hubs') return;
    this.state$.next(initial);
    this.broadcastContentFocus(null, false);
  }

  claimSparks(postId?: string | null): void {
    const id = String(postId || '').trim() || null;
    this.state$.next({ mode: 'sparks', ownerId: id, feedScore: 0 });
    this.broadcastContentFocus(id, true);
  }

  releaseSparks(): void {
    if (this.state$.value.mode !== 'sparks') return;
    this.state$.next(initial);
    this.broadcastContentFocus(null, false);
  }

  /** Is this post the current feed focus winner? */
  isFeedFocus(postId: string): boolean {
    const s = this.state$.value;
    return s.mode === 'feedAutoplay' && s.ownerId === postId;
  }

  private broadcastContentFocus(ownerId: string | null, active: boolean): void {
    try {
      window.dispatchEvent(
        new CustomEvent('video-player-content-focus', {
          detail: { ownerId, active },
        })
      );
      window.dispatchEvent(
        new CustomEvent('matterya-media-session', {
          detail: { ...this.state$.value, active },
        })
      );
    } catch {
      // SSR / non-browser
    }
  }
}
