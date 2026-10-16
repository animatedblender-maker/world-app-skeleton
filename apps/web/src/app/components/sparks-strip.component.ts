import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, EventEmitter, Input, OnChanges, Output, SimpleChanges } from '@angular/core';

import type { CountryPost } from '../core/models/post.model';
import { Frame0PosterService } from '../core/services/frame0-poster.service';
import { resolveMediaUrl } from '../core/utils/media-url.util';

/** Ports iOS SparksHorizontalStrip — same chrome on Feed and Hubs. */
@Component({
  selector: 'app-sparks-strip',
  standalone: true,
  imports: [CommonModule],
  template: `
    <section class="sparks-strip" *ngIf="posts.length">
      <div class="head">
        <div>
          <div class="title">{{ title }}</div>
          <div class="sub">{{ subtitle }}</div>
        </div>
        <button type="button" class="brand" *ngIf="showsBrand" (click)="brandTap.emit()">
          Matterya&nbsp;<b>Hubs</b>
        </button>
      </div>
      <div class="rail">
        <button
          type="button"
          class="tile"
          *ngFor="let p of posts; trackBy: track"
          (click)="open.emit(p)"
        >
          <!-- iOS: play overlays removed — clean posters / Frame0 only -->
          <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" loading="lazy" decoding="async" />
        </button>
      </div>
    </section>
  `,
  styles: [
    `
      .sparks-strip {
        padding: 8px 0 16px;
      }
      .head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
        padding: 0 16px 10px;
      }
      .title {
        font-size: 17px;
        font-weight: 650;
        color: var(--m-ink, #2c2825);
      }
      .sub {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .brand {
        border: 0;
        background: transparent;
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 14px;
        color: var(--m-ink, #2c2825);
        cursor: pointer;
        white-space: nowrap;
        padding: 0;
      }
      .brand b {
        font-family: system-ui, -apple-system, sans-serif;
        font-weight: 700;
      }
      .rail {
        display: flex;
        gap: 10px;
        overflow-x: auto;
        padding: 0 16px;
        scrollbar-width: none;
      }
      .rail::-webkit-scrollbar {
        display: none;
      }
      .tile {
        flex: 0 0 96px;
        width: 96px;
        aspect-ratio: 9 / 16;
        border: 0;
        padding: 0;
        border-radius: 12px;
        overflow: hidden;
        background: #171412;
        position: relative;
        cursor: pointer;
      }
      .tile img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
    `,
  ],
})
export class SparksStripComponent implements OnChanges {
  @Input() posts: CountryPost[] = [];
  @Input() title = 'Sparks for you';
  @Input() subtitle = 'Swipe the world on Matterya';
  @Input() showsBrand = true;
  @Output() open = new EventEmitter<CountryPost>();
  @Output() brandTap = new EventEmitter<void>();

  constructor(
    private frame0: Frame0PosterService,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['posts'] && this.posts?.length) {
      void this.frame0.prefetch(this.posts.map((p) => p.id)).then(() => {
        try {
          this.cdr.detectChanges();
        } catch {
          // destroyed
        }
      });
    }
  }

  track(_: number, p: CountryPost): string {
    return p.id;
  }

  /** Image poster only — never fall back to video media_url. */
  thumb(p: CountryPost): string | null {
    const raw = String(p.thumb_url || '').trim();
    if (raw && !raw.startsWith('{') && !raw.startsWith('[')) {
      const url = resolveMediaUrl(raw) || raw;
      if (url && !/\.(mp4|webm|mov|m4v)(\?|#|$)/i.test(url)) return url;
    }
    return this.frame0.url(p.id);
  }
}
