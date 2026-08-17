import { Injectable } from '@angular/core';
import type { CountryPost } from '../core/models/post.model';
import { PostsService } from '../core/services/posts.service';
import { HubsSeedService } from './hubs-seed.service';

export type HubsHomeFilter =
  | 'all'
  | 'comedy'
  | 'travel'
  | 'nature'
  | 'music'
  | 'food'
  | 'sports'
  | 'tech'
  | 'fitness'
  | 'film'
  | 'culture'
  | 'history'
  | 'education'
  | 'animals'
  | 'cars'
  | 'news'
  | 'fashion'
  | 'gaming'
  | 'kids'
  | 'social'
  | 'daily'
  | 'trending'
  | 'recent';

export type HubsLibrarySection = 'history' | 'reels' | 'saved' | 'liked' | 'uploads';

export type HubsChannel = {
  id: string;
  authorID: string;
  title: string;
  handle: string | null;
  author: CountryPost['author'];
  videos: CountryPost[];
  reels: CountryPost[];
  hasCustomChannelName: boolean;
  videoCount: number;
  reelCount: number;
  totalViews: number;
  latestVideo: CountryPost | null;
};

export const HUBS_HOME_FILTERS: { id: HubsHomeFilter; title: string }[] = [
  { id: 'all', title: 'For you' },
  { id: 'comedy', title: 'Comedy' },
  { id: 'music', title: 'Music' },
  { id: 'travel', title: 'Travel' },
  { id: 'nature', title: 'Nature' },
  { id: 'food', title: 'Food' },
  { id: 'sports', title: 'Sports' },
  { id: 'tech', title: 'Tech' },
  { id: 'fitness', title: 'Fitness' },
  { id: 'film', title: 'Film' },
  { id: 'culture', title: 'Culture' },
  { id: 'history', title: 'History' },
  { id: 'education', title: 'Education' },
  { id: 'animals', title: 'Animals' },
  { id: 'cars', title: 'Cars' },
  { id: 'news', title: 'News' },
  { id: 'fashion', title: 'Fashion' },
  { id: 'gaming', title: 'Gaming' },
  { id: 'kids', title: 'Kids' },
  { id: 'social', title: 'Social' },
  { id: 'daily', title: 'Daily' },
  { id: 'trending', title: 'Trending' },
  { id: 'recent', title: 'Latest' },
];

const HISTORY_KEY = 'matterya.play.watch_history_v1';
const POSITIONS_KEY = 'matterya.play.playback_positions_v1';
const SAVED_KEY = 'matterya.play.saved_video_ids_v1';

/** Ports iOS YouTubeCatalogService + play catalog merge. */
@Injectable({ providedIn: 'root' })
export class HubsCatalogService {
  private catalog: CountryPost[] = [];
  private channels: HubsChannel[] = [];
  private loadPromise: Promise<CountryPost[]> | null = null;
  private positions: Record<string, number> = {};
  private livePositions: Record<string, number> = {};
  private lastDiskPersist: Record<string, number> = {};

  constructor(
    private seed: HubsSeedService,
    private posts: PostsService
  ) {
    try {
      const raw = localStorage.getItem(POSITIONS_KEY);
      if (raw) {
        const parsed = JSON.parse(raw) as Record<string, number>;
        this.positions = { ...parsed };
        this.livePositions = { ...parsed };
      }
    } catch {
      // ignore
    }
  }

  get currentCatalog(): CountryPost[] {
    return this.catalog;
  }

  get currentChannels(): HubsChannel[] {
    return this.channels;
  }

  isPlayEligible(post: CountryPost | null | undefined): boolean {
    if (!post) return false;
    if (this.posts.isMoment(post)) return false;
    return this.hasVideo(post);
  }

  isReel(post: CountryPost | null | undefined): boolean {
    return this.posts.isSpark(post);
  }

  isLongForm(post: CountryPost | null | undefined): boolean {
    return this.isPlayEligible(post) && !this.isReel(post);
  }

  async loadCatalog(opts?: {
    forceRefresh?: boolean;
    followingIDs?: string[];
    viewerCountry?: string | null;
  }): Promise<CountryPost[]> {
    if (this.catalog.length && !opts?.forceRefresh) {
      return this.catalog;
    }
    if (this.loadPromise && !opts?.forceRefresh) {
      return this.loadPromise;
    }
    this.loadPromise = this.buildCatalog(opts).finally(() => {
      this.loadPromise = null;
    });
    return this.loadPromise;
  }

  private async buildCatalog(opts?: {
    followingIDs?: string[];
    viewerCountry?: string | null;
  }): Promise<CountryPost[]> {
    // Seed catalog only when Archive is enabled (see HubsSeedService.ARCHIVE_CONTENT_ENABLED).
    const [seedSparks, seedLong] = await Promise.all([
      this.seed.sparkSeedVideos().catch(() => [] as CountryPost[]),
      this.seed.longFormVideos(8).catch(() => [] as CountryPost[]),
    ]);

    let networkReels: CountryPost[] = [];
    let networkLong: CountryPost[] = [];
    try {
      // Recent network posts only (seed catalog covers offline hubs when Archive is on).
      const recent = await this.posts.listRecent(40).catch(() => [] as CountryPost[]);
      const networkVideos = (recent || [])
        .filter((p: CountryPost) => this.isPlayEligible(p))
        .filter((p: CountryPost) => this.allowArchiveMedia(p));
      networkReels = networkVideos.filter((p: CountryPost) => this.isReel(p));
      networkLong = networkVideos.filter((p: CountryPost) => !this.isReel(p));
    } catch {
      // network optional — seed-only when Archive is on
    }

    // Network first when Archive is off; seed only when gate is on.
    const merged = this.dedupeById([
      ...networkReels,
      ...networkLong,
      ...seedSparks,
      ...seedLong,
    ]);

    this.catalog = this.applyLocalEngagement(merged);
    this.channels = this.buildChannels(this.catalog);
    void opts;
    return this.catalog;
  }

  findPost(id: string): CountryPost | null {
    return this.catalog.find((p) => p.id === id) ?? null;
  }

  async resolvePost(id: string): Promise<CountryPost | null> {
    const local = this.findPost(id) || (await this.seed.postById(id));
    if (local) return this.applyLocalEngagement([local])[0];
    try {
      const remote = await this.posts.getPostById(id);
      if (remote && this.isPlayEligible(remote)) return remote;
    } catch {
      // ignore
    }
    return null;
  }

  filterVideos(
    videos: CountryPost[],
    homeFilter: HubsHomeFilter,
    followingIDs: Set<string>,
    viewerCountry: string | null | undefined
  ): CountryPost[] {
    const base = videos.filter((p) => this.isLongForm(p));
    switch (homeFilter) {
      case 'all':
        return this.rankForYou(base, followingIDs, viewerCountry);
      case 'trending':
        return base.slice().sort((a, b) => {
          if (a.view_count === b.view_count) {
            return (b.created_at || '').localeCompare(a.created_at || '');
          }
          return (b.view_count || 0) - (a.view_count || 0);
        });
      case 'recent':
        return base.slice().sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
      default: {
        const slug = homeFilter;
        const byHub = base.filter((post) => {
          const hub = this.hubSlugOf(post);
          return hub === slug;
        });
        if (byHub.length) return byHub;
        return this.keywordFilter(base, [slug]);
      }
    }
  }

  reels(from: CountryPost[]): CountryPost[] {
    return from
      .filter((p) => this.isPlayEligible(p) && this.isReel(p))
      .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
  }

  subscriptionFeed(videos: CountryPost[], followingIDs: Set<string>): CountryPost[] {
    return videos
      .filter((p) => this.isPlayEligible(p) && followingIDs.has(p.author_id))
      .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
  }

  subscriptionChannels(channels: HubsChannel[], followingIDs: Set<string>): HubsChannel[] {
    return channels.filter((c) => followingIDs.has(c.authorID));
  }

  relatedVideos(post: CountryPost, catalog: CountryPost[], limit = 24): CountryPost[] {
    return this.relatedVideosRanked(post, catalog).slice(0, limit);
  }

  /** Full ranked related list (no limit) for infinite “More on Hubs”. */
  relatedVideosRanked(post: CountryPost, catalog: CountryPost[]): CountryPost[] {
    const base = catalog.filter((p) => this.isLongForm(p) && p.id !== post.id);
    return base.slice().sort((a, b) => {
      const score = (p: CountryPost) => {
        let s = 0;
        if (p.author_id === post.author_id) s += 1000;
        if (
          post.country_code &&
          p.country_code &&
          p.country_code.toUpperCase() === post.country_code.toUpperCase()
        ) {
          s += 200;
        }
        if (this.hubSlugOf(p) && this.hubSlugOf(p) === this.hubSlugOf(post)) s += 150;
        s += Math.min(p.view_count || 0, 500) / 10;
        return s;
      };
      const d = score(b) - score(a);
      if (d !== 0) return d;
      return (b.created_at || '').localeCompare(a.created_at || '');
    });
  }

  /**
   * Next page for infinite related rail. When the ranked pool is exhausted,
   * reshuffles long-form catalog (excluding the current post) so the rail
   * never dead-ends.
   */
  relatedVideosPage(
    post: CountryPost,
    catalog: CountryPost[],
    offset: number,
    pageSize: number,
    cycle: number
  ): { items: CountryPost[]; nextOffset: number; nextCycle: number } {
    let pool = this.relatedVideosRanked(post, catalog);
    if (!pool.length) {
      return { items: [], nextOffset: 0, nextCycle: cycle };
    }
    // Extra cycles: re-order by a different salt so the feed feels endless.
    if (cycle > 0) {
      pool = pool
        .slice()
        .sort((a, b) => {
          const ha = this.pageHash(`${post.id}|${cycle}|${a.id}`);
          const hb = this.pageHash(`${post.id}|${cycle}|${b.id}`);
          return ha - hb;
        });
    }
    if (offset >= pool.length) {
      return this.relatedVideosPage(post, catalog, 0, pageSize, cycle + 1);
    }
    const items = pool.slice(offset, offset + pageSize);
    const nextOffset = offset + items.length;
    if (nextOffset >= pool.length) {
      return { items, nextOffset: 0, nextCycle: cycle + 1 };
    }
    return { items, nextOffset, nextCycle: cycle };
  }

  private pageHash(input: string): number {
    let h = 2166136261;
    for (let i = 0; i < input.length; i++) {
      h ^= input.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }

  buildChannels(videos: CountryPost[]): HubsChannel[] {
    const eligible = videos.filter((p) => this.isPlayEligible(p));
    const grouped = new Map<string, CountryPost[]>();
    for (const post of eligible) {
      const list = grouped.get(post.author_id) ?? [];
      list.push(post);
      grouped.set(post.author_id, list);
    }
    const channels: HubsChannel[] = [];
    for (const [authorID, posts] of grouped) {
      const longForm = posts
        .filter((p) => !this.isReel(p))
        .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
      const reels = posts
        .filter((p) => this.isReel(p))
        .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
      if (!longForm.length && !reels.length) continue;

      const hubTitle = this.stableHubChannelTitle(authorID);
      const rawAuthor = longForm[0]?.author || reels[0]?.author;
      const title =
        hubTitle ||
        rawAuthor?.display_name ||
        rawAuthor?.username ||
        'Channel';
      const author = hubTitle
        ? {
            user_id: authorID,
            display_name: hubTitle,
            username: rawAuthor?.username || this.hubUsername(authorID),
            avatar_url: rawAuthor?.avatar_url ?? null,
            country_name: rawAuthor?.country_name ?? null,
            country_code: rawAuthor?.country_code ?? null,
          }
        : rawAuthor;

      channels.push({
        id: authorID,
        authorID,
        title,
        handle: author?.username ? `@${author.username}` : null,
        author: author ?? null,
        videos: longForm,
        reels,
        hasCustomChannelName: false,
        videoCount: longForm.length,
        reelCount: reels.length,
        totalViews: posts.reduce((sum, p) => sum + (p.view_count || 0), 0),
        latestVideo: longForm[0] || reels[0] || null,
      });
    }
    return channels.sort((a, b) => {
      if (a.totalViews === b.totalViews) {
        return (b.latestVideo?.created_at || '').localeCompare(a.latestVideo?.created_at || '');
      }
      return b.totalViews - a.totalViews;
    });
  }

  channelForAuthor(authorID: string): HubsChannel | null {
    return this.channels.find((c) => c.authorID === authorID) ?? null;
  }

  async expandChannel(authorID: string): Promise<HubsChannel | null> {
    let channel = this.channelForAuthor(authorID);
    // Expand full hub seed corpus when opening a hub_* channel.
    if (authorID.startsWith('hub_') && !authorID.startsWith('hub_spark_')) {
      const slug = authorID.slice('hub_'.length);
      const full = await this.seed.videosForHub(slug);
      if (full.length) {
        const existing = new Set(this.catalog.map((p) => p.id));
        const toAdd = full.filter((p) => !existing.has(p.id));
        if (toAdd.length) {
          this.catalog = this.dedupeById([...this.catalog, ...toAdd]);
          this.channels = this.buildChannels(this.catalog);
          channel = this.channelForAuthor(authorID);
        }
      }
    }
    return channel;
  }

  search(
    query: string,
    videos: CountryPost[],
    channels: HubsChannel[]
  ): { videos: CountryPost[]; channels: HubsChannel[] } {
    const q = query.trim().toLowerCase();
    if (!q) return { videos: [], channels: [] };
    const matchedVideos = videos.filter((p) => this.isPlayEligible(p)).filter((post) => {
      const headline = this.displayHeadline(post).toLowerCase();
      const body = this.displayBody(post).toLowerCase();
      const name = (post.author?.display_name || '').toLowerCase();
      const user = (post.author?.username || '').toLowerCase();
      return (
        headline.includes(q) || body.includes(q) || name.includes(q) || user.includes(q)
      );
    });
    const matchedChannels = channels.filter(
      (c) =>
        c.title.toLowerCase().includes(q) ||
        (c.handle || '').toLowerCase().includes(q) ||
        (c.author?.display_name || '').toLowerCase().includes(q)
    );
    return { videos: matchedVideos, channels: matchedChannels };
  }

  // --- History / resume / saved ---

  recordWatch(postID: string): void {
    const history = this.historyIDs().filter((id) => id !== postID);
    history.unshift(postID);
    try {
      localStorage.setItem(HISTORY_KEY, JSON.stringify(history.slice(0, 120)));
    } catch {
      // ignore
    }
  }

  historyIDs(): string[] {
    try {
      const raw = localStorage.getItem(HISTORY_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed.map(String) : [];
    } catch {
      return [];
    }
  }

  historyVideos(videos: CountryPost[]): CountryPost[] {
    const byId = new Map(videos.map((p) => [p.id, p]));
    const seen = new Set<string>();
    const ordered: CountryPost[] = [];

    // 1) Explicit watch history (newest first)
    for (const id of this.historyIDs()) {
      const p = byId.get(id);
      if (!p || !this.isLongForm(p) || seen.has(p.id)) continue;
      seen.add(p.id);
      ordered.push(p);
    }

    // 2) Any long-form with a saved resume position (not finished)
    const posEntries = Object.entries(this.positions)
      .filter(([, sec]) => Number(sec) >= 1)
      .sort((a, b) => Number(b[1]) - Number(a[1]));
    for (const [id] of posEntries) {
      const p = byId.get(id);
      if (!p || !this.isLongForm(p) || seen.has(p.id)) continue;
      seen.add(p.id);
      ordered.push(p);
    }

    return ordered;
  }

  /** Infinite “Continue watching” rail: history + in-progress, then more long-form catalog. */
  continueWatchingFeed(videos: CountryPost[], limit = 0): CountryPost[] {
    const primary = this.historyVideos(videos);
    const seen = new Set(primary.map((p) => p.id));
    const rest = videos.filter((p) => this.isLongForm(p) && !seen.has(p.id));
    const merged = [...primary, ...rest];
    if (limit > 0) return merged.slice(0, limit);
    return merged;
  }

  playbackPosition(postID: string): number {
    return this.livePositions[postID] ?? this.positions[postID] ?? 0;
  }

  notePlaybackPosition(seconds: number, postID: string, duration?: number | null): void {
    const clamped = Math.max(0, seconds);
    if (clamped < 0.5) return;
    this.livePositions[postID] = clamped;
    const now = Date.now();
    if (this.lastDiskPersist[postID] && now - this.lastDiskPersist[postID] < 2000) return;
    this.lastDiskPersist[postID] = now;
    this.savePlaybackPosition(clamped, postID, duration);
  }

  savePlaybackPosition(seconds: number, postID: string, duration?: number | null): void {
    const clamped = Math.max(0, seconds);
    const prior = this.playbackPosition(postID);
    if (clamped < 1) {
      if (prior >= 1) return;
      delete this.positions[postID];
      delete this.livePositions[postID];
      this.persistPositions();
      return;
    }
    if (duration && duration > 0 && clamped >= duration - 2) {
      delete this.positions[postID];
      delete this.livePositions[postID];
      this.persistPositions();
      return;
    }
    this.positions[postID] = clamped;
    this.livePositions[postID] = clamped;
    // Cap map size
    const keys = Object.keys(this.positions);
    if (keys.length > 80) {
      for (const k of keys.slice(0, keys.length - 80)) {
        delete this.positions[k];
      }
    }
    this.persistPositions();
  }

  savedIDs(): Set<string> {
    try {
      const raw = localStorage.getItem(SAVED_KEY);
      if (!raw) return new Set();
      const parsed = JSON.parse(raw);
      return new Set(Array.isArray(parsed) ? parsed.map(String) : []);
    } catch {
      return new Set();
    }
  }

  isSaved(postID: string): boolean {
    return this.savedIDs().has(postID);
  }

  toggleSave(postID: string): boolean {
    const ids = this.savedIDs();
    if (ids.has(postID)) ids.delete(postID);
    else ids.add(postID);
    try {
      localStorage.setItem(SAVED_KEY, JSON.stringify([...ids]));
    } catch {
      // ignore
    }
    return ids.has(postID);
  }

  savedVideos(videos: CountryPost[]): CountryPost[] {
    const saved = this.savedIDs();
    return videos.filter((p) => this.isLongForm(p) && saved.has(p.id));
  }

  likedVideos(videos: CountryPost[]): CountryPost[] {
    return videos
      .filter((p) => this.isPlayEligible(p) && p.liked_by_me)
      .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
  }

  myUploads(videos: CountryPost[], userID: string | null | undefined): CountryPost[] {
    if (!userID) return [];
    return videos
      .filter((p) => this.isPlayEligible(p) && p.author_id === userID)
      .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
  }

  displayHeadline(post: CountryPost): string {
    const t = (post.title || '').trim();
    if (t) return t;
    const body = this.displayBody(post).trim();
    if (body) return body.length > 90 ? body.slice(0, 87) + '…' : body;
    return 'Video';
  }

  displayBody(post: CountryPost): string {
    let body = String(post.body || '');
    body = body.replace(/__spark__\|/g, '').replace(/__story__\|[^\n]*/g, '').trim();
    return body;
  }

  displayAuthor(post: CountryPost): string {
    return (
      post.author?.display_name ||
      post.author?.username ||
      this.stableHubChannelTitle(post.author_id) ||
      'Creator'
    );
  }

  formatViews(n: number): string {
    if (!n || n < 0) return '0 views';
    if (n < 1000) return `${n} views`;
    if (n < 1_000_000) return `${(n / 1000).toFixed(n < 10_000 ? 1 : 0)}K views`;
    return `${(n / 1_000_000).toFixed(1)}M views`;
  }

  relativeTime(iso: string | null | undefined): string {
    if (!iso) return '';
    const t = Date.parse(iso);
    if (!Number.isFinite(t)) return '';
    const sec = Math.max(0, Math.floor((Date.now() - t) / 1000));
    if (sec < 60) return 'just now';
    if (sec < 3600) return `${Math.floor(sec / 60)}m ago`;
    if (sec < 86400) return `${Math.floor(sec / 3600)}h ago`;
    if (sec < 86400 * 30) return `${Math.floor(sec / 86400)}d ago`;
    return new Date(t).toLocaleDateString();
  }

  mediaUrl(post: CountryPost): string {
    const raw = String(post.media_url || '').trim();
    if (!raw) return '';
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        if (Array.isArray(parsed?.urls) && parsed.urls[0]) return String(parsed.urls[0]);
        if (parsed?.url) return String(parsed.url);
      } catch {
        return raw;
      }
    }
    return raw;
  }

  private hubSlugOf(post: CountryPost): string | null {
    if (String(post.external_ref_type || '').toLowerCase() === 'hub') {
      return (post.external_ref_id || '').toLowerCase() || null;
    }
    return null;
  }

  private hasVideo(post: CountryPost): boolean {
    const media = String(post.media_type || '').toLowerCase();
    if (media === 'video' || media === 'reel' || media === 'spark') return true;
    const url = this.mediaUrl(post);
    if (!url) return false;
    return (
      /\.(mp4|webm|m3u8|mov)(\?|$)/i.test(url) ||
      url.includes('/download/') ||
      url.includes('archive.org')
    );
  }

  /** Drop Internet Archive rows while ARCHIVE_CONTENT_ENABLED is false. */
  private allowArchiveMedia(post: CountryPost): boolean {
    if (HubsSeedService.ARCHIVE_CONTENT_ENABLED) return true;
    const id = String(post.id || '').toLowerCase();
    if (id.startsWith('ia_') || id.startsWith('hub_spark_') || id.startsWith('hub_')) return false;
    const author = String(post.author_id || '').toLowerCase();
    if (author.startsWith('hub_') || author.startsWith('ia_') || author.startsWith('archive_')) return false;
    const media = this.mediaUrl(post).toLowerCase();
    const thumb = String(post.thumb_url || '').toLowerCase();
    if (media.includes('archive.org') || thumb.includes('archive.org')) return false;
    return true;
  }

  private rankForYou(
    base: CountryPost[],
    followingIDs: Set<string>,
    viewerCountry: string | null | undefined
  ): CountryPost[] {
    const country = (viewerCountry || '').toUpperCase();
    return base
      .slice()
      .sort((a, b) => {
        const score = (p: CountryPost) => {
          let s = Math.log10((p.view_count || 0) + 10) * 20;
          s += Math.log10((p.like_count || 0) + 2) * 15;
          if (followingIDs.has(p.author_id)) s += 80;
          if (country && p.country_code?.toUpperCase() === country) s += 40;
          // Mild recency for network posts
          const ageH = (Date.now() - Date.parse(p.created_at || '')) / 3600000;
          if (Number.isFinite(ageH) && ageH < 72) s += Math.max(0, 30 - ageH / 3);
          // Seed hub diversity: slight boost by slug hash so shelves aren't one category
          const hub = this.hubSlugOf(p) || '';
          s += (hub.charCodeAt(0) || 0) % 7;
          return s;
        };
        return score(b) - score(a);
      });
  }

  private keywordFilter(base: CountryPost[], words: string[]): CountryPost[] {
    const keys = words.map((w) => w.toLowerCase());
    return base.filter((p) => {
      const hay = [
        p.title,
        p.body,
        p.media_caption,
        p.author?.display_name,
        p.author?.username,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return keys.some((k) => hay.includes(k));
    });
  }

  private stableHubChannelTitle(authorID: string): string | null {
    if (authorID.startsWith('hub_spark_')) {
      return HubsSeedService.channelDisplayName(authorID.slice('hub_spark_'.length), true);
    }
    if (authorID.startsWith('hub_')) {
      const slug = authorID.slice('hub_'.length);
      if (!slug || slug.includes(' ') || slug.length >= 32) return null;
      return HubsSeedService.channelDisplayName(slug, false);
    }
    return null;
  }

  private hubUsername(authorID: string): string | null {
    if (authorID.startsWith('hub_spark_')) return `sparks_${authorID.slice('hub_spark_'.length)}`;
    if (authorID.startsWith('hub_')) return authorID.slice('hub_'.length);
    return null;
  }

  private dedupeById(posts: CountryPost[]): CountryPost[] {
    const seen = new Set<string>();
    const out: CountryPost[] = [];
    for (const p of posts) {
      if (!p?.id || seen.has(p.id)) continue;
      seen.add(p.id);
      out.push(p);
    }
    return out;
  }

  private applyLocalEngagement(posts: CountryPost[]): CountryPost[] {
    // Liked state for seed ids lives in localStorage via hubs-engagement; applied by caller when needed.
    return posts;
  }

  private persistPositions(): void {
    try {
      localStorage.setItem(POSITIONS_KEY, JSON.stringify(this.positions));
    } catch {
      // ignore
    }
  }
}
