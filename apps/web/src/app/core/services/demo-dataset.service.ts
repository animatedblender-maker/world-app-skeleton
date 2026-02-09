import { Injectable } from '@angular/core';

import { environment } from '../../../envirnoments/envirnoment';
import { supabase } from '../../supabase/supabase.client';
import type { CountryPost, PostAuthor, PostComment, PostLike } from '../models/post.model';
import { FakeDataService } from './fake-data.service';

const POSTS_URL = 'demo_social_dataset_30k/posts.jsonl';
const COMMENTS_URL = 'demo_social_dataset_30k/comments.jsonl';
const CAPTIONS_URL = 'demo_social_dataset_30k/video_captions.jsonl';

type DemoPostRow = {
  id: string;
  author_id: string;
  country_code?: string | null;
  country_name?: string | null;
  category_slug?: string | null;
  title?: string | null;
  body?: string | null;
  visibility?: string | null;
  created_at?: string | null;
  media?: {
    type?: string | null;
    provider?: string | null;
    query?: string | null;
    url?: string | null;
    thumb_url?: string | null;
  } | null;
};

type DemoCommentRow = {
  id: string;
  post_id: string;
  author_id: string;
  parent_id?: string | null;
  body?: string | null;
  created_at?: string | null;
};

type DemoCaptionRow = {
  post_id: string;
  country_code?: string | null;
  category_slug?: string | null;
  caption?: string | null;
};

type PostState = {
  like_count: number;
  comment_count: number;
  view_count: number;
  liked_by_me: boolean;
};

type CommentState = {
  like_count: number;
  liked_by_me: boolean;
};

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hashSeed(value: string): number {
  let h = 2166136261;
  for (let i = 0; i < value.length; i++) {
    h ^= value.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function parseJsonl<T>(text: string): T[] {
  const out: T[] = [];
  const lines = text.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      out.push(JSON.parse(trimmed) as T);
    } catch {
      // Skip bad lines.
    }
  }
  return out;
}

@Injectable({ providedIn: 'root' })
export class DemoDatasetService {
  private postsLoaded = false;
  private postsPromise: Promise<void> | null = null;

  private commentsLoaded = false;
  private commentsPromise: Promise<void> | null = null;

  private captionsLoaded = false;
  private captionsPromise: Promise<void> | null = null;

  private posts: CountryPost[] = [];
  private postsById = new Map<string, CountryPost>();
  private postsByCountry = new Map<string, CountryPost[]>();
  private postsByAuthor = new Map<string, CountryPost[]>();
  private postStates = new Map<string, PostState>();
  private countryFeedCache = new Map<string, { ts: number; posts: CountryPost[] }>();
  private postSearchCache = new Map<string, CountryPost[]>();
  private postMediaMeta = new Map<
    string,
    { type: string; query: string | null; url: string | null; thumb_url: string | null }
  >();
  private captionsByPost = new Map<string, string>();

  private commentsByPost = new Map<string, PostComment[]>();
  private localCommentsByPost = new Map<string, PostComment[]>();
  private commentStates = new Map<string, CommentState>();
  private commentOrderCache = new Map<string, PostComment[]>();

  private profileMap: Map<string, PostAuthor> | null = null;

  private countryOffsets = new Map<string, number>();

  private pexelsCache = new Map<string, { url: string | null; thumb_url: string | null }>();
  private pexelsInflight = new Map<string, Promise<{ url: string | null; thumb_url: string | null }>>();

  constructor(private fakeData: FakeDataService) {}

  async isDemoPostId(postId: string): Promise<boolean> {
    await this.ensurePostsLoaded();
    return this.postsById.has(postId);
  }

  isDemoCommentId(commentId: string): boolean {
    return /^cmt_|^local_/.test(commentId);
  }

  async listByCountry(
    countryCode: string,
    limit = 25,
    opts?: { skipComments?: boolean }
  ): Promise<CountryPost[]> {
    if (opts?.skipComments) {
      await this.ensurePostsLoaded();
    } else {
      await this.ensureCommentsLoaded();
    }
    const code = String(countryCode || '').trim().toUpperCase();
    const list = this.postsByCountry.get(code) ?? [];
    const ordered = this.buildBalancedOrder(list, code);
    const max = Math.max(1, limit);
    const sliced = this.sliceWithOffset(code, ordered, max);
    await this.hydrateMedia(sliced);
    return sliced;
  }

  async listForAuthor(authorId: string, limit = 25): Promise<CountryPost[]> {
    await this.ensureCommentsLoaded();
    const list = this.postsByAuthor.get(authorId) ?? [];
    const sorted = [...list].sort((a, b) => {
      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
    });
    const sliced = sorted.slice(0, Math.max(1, limit));
    await this.hydrateMedia(sliced);
    return sliced;
  }

  async getPostById(postId: string): Promise<CountryPost | null> {
    await this.ensureCommentsLoaded();
    const post = this.postsById.get(postId) ?? null;
    if (!post) return null;
    await this.hydrateMedia([post]);
    return post;
  }

  async searchPosts(query: string, limit = 20): Promise<CountryPost[]> {
    const needle = String(query || '').trim().toLowerCase();
    if (!needle) return [];
    await this.ensurePostsLoaded();
    const cached = this.postSearchCache.get(needle);
    if (cached) {
      if (limit <= 0) return cached;
      const sliced = cached.slice(0, Math.max(1, limit));
      await this.hydrateMedia(sliced);
      return sliced;
    }
    const matches = this.posts.filter((post) => {
      const title = String(post.title || '').toLowerCase();
      const body = String(post.body || '').toLowerCase();
      const caption = String(post.media_caption || '').toLowerCase();
      return title.includes(needle) || body.includes(needle) || caption.includes(needle);
    });
    const sorted = matches.sort((a, b) => {
      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
    });
    this.postSearchCache.set(needle, sorted);
    if (this.postSearchCache.size > 40) {
      const first = this.postSearchCache.keys().next().value;
      if (first) this.postSearchCache.delete(first);
    }
    if (limit <= 0) return sorted;
    const sliced = sorted.slice(0, Math.max(1, limit));
    await this.hydrateMedia(sliced);
    return sliced;
  }

  async listComments(postId: string, limit = 25): Promise<PostComment[]> {
    await this.ensureCommentsLoaded();
    const base = this.getOrderedComments(postId);
    const local = this.localCommentsByPost.get(postId) ?? [];
    const merged = [...base, ...local];
    return merged.slice(0, Math.max(1, limit));
  }

  async addComment(postId: string, body: string, parentId?: string | null): Promise<PostComment> {
    await this.ensurePostsLoaded();
    const me = await supabase.auth.getUser();
    const meId = me.data.user?.id ?? 'me';
    const now = new Date().toISOString();

    const author: PostAuthor = {
      user_id: meId,
      display_name: 'You',
      username: null,
      avatar_url: null,
      country_name: null,
      country_code: null,
    };

    const comment: PostComment = {
      id: `local_${Date.now()}_${Math.floor(Math.random() * 10000)}`,
      post_id: postId,
      parent_id: parentId ?? null,
      author_id: meId,
      body: body.trim(),
      like_count: 0,
      liked_by_me: false,
      created_at: now,
      updated_at: now,
      author,
    };

    const list = this.localCommentsByPost.get(postId) ?? [];
    list.push(comment);
    this.localCommentsByPost.set(postId, list);

    const state = this.postStates.get(postId);
    if (state) {
      state.comment_count += 1;
      const post = this.postsById.get(postId);
      if (post) post.comment_count = state.comment_count;
    }

    return comment;
  }

  async likePost(postId: string): Promise<CountryPost> {
    await this.ensurePostsLoaded();
    const post = this.postsById.get(postId);
    if (!post) throw new Error('Post not found.');
    const state = this.ensurePostState(postId);
    if (!state.liked_by_me) {
      state.liked_by_me = true;
      state.like_count += 1;
    }
    this.applyState(post, state);
    return post;
  }

  async unlikePost(postId: string): Promise<CountryPost> {
    await this.ensurePostsLoaded();
    const post = this.postsById.get(postId);
    if (!post) throw new Error('Post not found.');
    const state = this.ensurePostState(postId);
    if (state.liked_by_me) {
      state.liked_by_me = false;
      state.like_count = Math.max(0, state.like_count - 1);
    }
    this.applyState(post, state);
    return post;
  }

  async recordView(postId: string): Promise<void> {
    if (!postId) return;
    await this.ensurePostsLoaded();
    const state = this.ensurePostState(postId);
    state.view_count += 1;
    const post = this.postsById.get(postId);
    if (post) this.applyState(post, state);
  }

  async listLikes(postId: string, limit = 25): Promise<PostLike[]> {
    await this.ensurePostsLoaded();
    const state = this.postStates.get(postId);
    const max = Math.max(0, Math.min(limit, state?.like_count ?? 0));
    if (!max) return [];
    const profiles = await this.fakeData.getProfiles();
    if (!profiles.length) return [];

    const rng = mulberry32(hashSeed(`${postId}|likes`));
    const picks = new Set<number>();
    while (picks.size < max && picks.size < profiles.length) {
      picks.add(Math.floor(rng() * profiles.length));
    }

    const now = new Date().toISOString();
    return [...picks].map((idx) => {
      const profile = profiles[idx];
      return {
        user_id: profile.user_id,
        created_at: now,
        user: this.profileToAuthor(profile),
      };
    });
  }

  async likeComment(commentId: string): Promise<PostComment> {
    await this.ensureCommentsLoaded();
    const comment = this.findComment(commentId);
    if (!comment) throw new Error('Comment not found.');
    const state = this.ensureCommentState(commentId, comment);
    if (!state.liked_by_me) {
      state.liked_by_me = true;
      state.like_count += 1;
    }
    comment.liked_by_me = state.liked_by_me;
    comment.like_count = state.like_count;
    return comment;
  }

  async unlikeComment(commentId: string): Promise<PostComment> {
    await this.ensureCommentsLoaded();
    const comment = this.findComment(commentId);
    if (!comment) throw new Error('Comment not found.');
    const state = this.ensureCommentState(commentId, comment);
    if (state.liked_by_me) {
      state.liked_by_me = false;
      state.like_count = Math.max(0, state.like_count - 1);
    }
    comment.liked_by_me = state.liked_by_me;
    comment.like_count = state.like_count;
    return comment;
  }

  private async ensurePostsLoaded(): Promise<void> {
    if (this.postsLoaded) return;
    if (this.postsPromise) return this.postsPromise;

    this.postsPromise = (async () => {
      await this.ensureCaptionsLoaded();

      const text = await this.fetchText(POSTS_URL);
      const rows = parseJsonl<DemoPostRow>(text);
      const authorIds = new Set<string>();
      for (const row of rows) {
        const authorId = this.normalizeAuthorId(row?.author_id);
        if (authorId) authorIds.add(authorId);
      }

      await this.ensureProfileMap(authorIds);

      for (const row of rows) {
        const authorId = this.normalizeAuthorId(row?.author_id);
        if (!row?.id || !authorId) continue;
        const author = this.profileMap?.get(authorId) ?? null;
        const mediaType = row.media?.type ?? 'none';
        const mediaUrl = row.media?.url ?? null;
        const thumbUrl = row.media?.thumb_url ?? null;
        const caption = this.captionsByPost.get(row.id) ?? null;
        const authorCountryCode = author?.country_code ?? row.country_code ?? null;
        const authorCountryName = author?.country_name ?? row.country_name ?? null;

        const createdAt = row.created_at || new Date().toISOString();
        const post: CountryPost = {
          id: row.id,
          title: row.title ?? null,
          body: this.normalizeBody(row.body ?? '', authorCountryName || row.country_name || null),
          media_type: mediaType,
          media_url: mediaUrl,
          thumb_url: thumbUrl,
          media_caption: caption,
          visibility: (row.visibility as any) || 'public',
          like_count: 0,
          comment_count: 0,
          view_count: 0,
          liked_by_me: false,
          created_at: createdAt,
          updated_at: createdAt,
          author_id: authorId,
          country_name: authorCountryName,
          country_code: authorCountryCode,
          city_name: null,
          author,
        };

        const likeCount = this.seedCount(row.id, 8000);
        const viewCount = this.seedCount(`${row.id}|views`, 180000);
        const state: PostState = {
          like_count: likeCount,
          comment_count: 0,
          view_count: Math.max(viewCount, likeCount * 6),
          liked_by_me: false,
        };
        this.postStates.set(row.id, state);
        this.applyState(post, state);

        this.posts.push(post);
        this.postsById.set(row.id, post);

        const cc = String(authorCountryCode || '').trim().toUpperCase();
        if (cc) {
          const list = this.postsByCountry.get(cc) ?? [];
          list.push(post);
          this.postsByCountry.set(cc, list);
        }

        const authorList = this.postsByAuthor.get(authorId) ?? [];
        authorList.push(post);
        this.postsByAuthor.set(authorId, authorList);

        this.postMediaMeta.set(row.id, {
          type: mediaType,
          query: row.media?.query ?? null,
          url: mediaUrl,
          thumb_url: thumbUrl,
        });
      }

      this.postsLoaded = true;
    })();

    return this.postsPromise;
  }

  private async ensureCommentsLoaded(): Promise<void> {
    if (this.commentsLoaded) return;
    if (this.commentsPromise) return this.commentsPromise;

    this.commentsPromise = (async () => {
      await this.ensurePostsLoaded();

      const text = await this.fetchText(COMMENTS_URL);
      const rows = parseJsonl<DemoCommentRow>(text);
      const authorIds = new Set<string>();
      for (const row of rows) {
        const authorId = this.normalizeAuthorId(row?.author_id);
        if (authorId) authorIds.add(authorId);
      }
      await this.ensureProfileMap(authorIds);

      for (const row of rows) {
        const authorId = this.normalizeAuthorId(row?.author_id);
        if (!row?.id || !row?.post_id || !authorId) continue;
        const author = this.profileMap?.get(authorId) ?? null;
        const createdAt = row.created_at || new Date().toISOString();

        const comment: PostComment = {
          id: row.id,
          post_id: row.post_id,
          parent_id: row.parent_id ?? null,
          author_id: authorId,
          body: row.body ?? '',
          like_count: this.seedCount(row.id, 160),
          liked_by_me: false,
          created_at: createdAt,
          updated_at: createdAt,
          author,
        };

        const list = this.commentsByPost.get(row.post_id) ?? [];
        list.push(comment);
        this.commentsByPost.set(row.post_id, list);
        this.commentStates.set(row.id, {
          like_count: comment.like_count,
          liked_by_me: false,
        });

        const state = this.postStates.get(row.post_id);
        if (state) {
          state.comment_count += 1;
        }
      }

      for (const [postId, state] of this.postStates.entries()) {
        const post = this.postsById.get(postId);
        if (post) post.comment_count = state.comment_count;
      }

      this.commentsLoaded = true;
    })();

    return this.commentsPromise;
  }

  private async ensureCaptionsLoaded(): Promise<void> {
    if (this.captionsLoaded) return;
    if (this.captionsPromise) return this.captionsPromise;

    this.captionsPromise = (async () => {
      const text = await this.fetchText(CAPTIONS_URL);
      const rows = parseJsonl<DemoCaptionRow>(text);
      for (const row of rows) {
        if (!row?.post_id || !row?.caption) continue;
        this.captionsByPost.set(row.post_id, row.caption);
      }
      this.captionsLoaded = true;
    })();

    return this.captionsPromise;
  }

  private async ensureProfileMap(authorIds?: Set<string>): Promise<void> {
    if (!this.profileMap) {
      const profiles = await this.fakeData.getProfiles();
      const map = new Map<string, PostAuthor>();
      for (const profile of profiles) {
        map.set(profile.user_id, this.profileToAuthor(profile));
      }
      this.profileMap = map;
    }

    if (authorIds && authorIds.size) {
      await this.fakeData.ensureProfilesById(authorIds);
      for (const authorId of authorIds) {
        if (this.profileMap?.has(authorId)) continue;
        const profile = await this.fakeData.getProfileById(authorId);
        if (profile) {
          this.profileMap?.set(authorId, this.profileToAuthor(profile));
        }
      }
    }
  }

  private profileToAuthor(profile: {
    user_id: string;
    display_name?: string | null;
    username?: string | null;
    avatar_url?: string | null;
    country_name?: string | null;
    country_code?: string | null;
  }): PostAuthor {
    return {
      user_id: profile.user_id,
      display_name: profile.display_name ?? null,
      username: profile.username ?? null,
      avatar_url: profile.avatar_url ?? null,
      country_name: profile.country_name ?? null,
      country_code: profile.country_code ?? null,
    };
  }

  private applyState(post: CountryPost, state: PostState): void {
    post.like_count = state.like_count;
    post.comment_count = state.comment_count;
    post.view_count = state.view_count;
    post.liked_by_me = state.liked_by_me;
  }

  private ensurePostState(postId: string): PostState {
    let state = this.postStates.get(postId);
    if (!state) {
      state = { like_count: 0, comment_count: 0, view_count: 0, liked_by_me: false };
      this.postStates.set(postId, state);
    }
    return state;
  }

  private ensureCommentState(commentId: string, comment: PostComment): CommentState {
    let state = this.commentStates.get(commentId);
    if (!state) {
      state = { like_count: comment.like_count, liked_by_me: comment.liked_by_me };
      this.commentStates.set(commentId, state);
    }
    return state;
  }

  private findComment(commentId: string): PostComment | null {
    for (const list of this.commentsByPost.values()) {
      const found = list.find((item) => item.id === commentId);
      if (found) return found;
    }
    for (const list of this.localCommentsByPost.values()) {
      const found = list.find((item) => item.id === commentId);
      if (found) return found;
    }
    return null;
  }

  private seedCount(seed: string, max: number): number {
    const rng = mulberry32(hashSeed(seed));
    return Math.floor(Math.pow(rng(), 2) * max);
  }

  private buildBalancedOrder(list: CountryPost[], code: string): CountryPost[] {
    const now = Date.now();
    const bucket = Math.floor(now / (1000 * 60 * 15));
    const cacheKey = `${code}:${bucket}`;
    const cached = this.countryFeedCache.get(cacheKey);
    if (cached) return cached.posts;

    const sorted = [...list].sort((a, b) => {
      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
    });

    const byAuthor = new Map<string, CountryPost[]>();
    for (const post of sorted) {
      const listForAuthor = byAuthor.get(post.author_id) ?? [];
      listForAuthor.push(post);
      byAuthor.set(post.author_id, listForAuthor);
    }

    const authors = Array.from(byAuthor.keys());
    const rng = mulberry32(hashSeed(`${code}|${bucket}`));
    for (let i = authors.length - 1; i > 0; i -= 1) {
      const j = Math.floor(rng() * (i + 1));
      const tmp = authors[i];
      authors[i] = authors[j];
      authors[j] = tmp;
    }

    const result: CountryPost[] = [];
    let remaining = true;
    while (remaining) {
      remaining = false;
      for (const authorId of authors) {
        const posts = byAuthor.get(authorId);
        if (!posts || !posts.length) continue;
        result.push(posts.shift() as CountryPost);
        remaining = true;
      }
    }

    this.countryFeedCache.set(cacheKey, { ts: now, posts: result });
    return result;
  }

  private sliceWithOffset(code: string, ordered: CountryPost[], limit: number): CountryPost[] {
    if (!ordered.length) return [];
    if (ordered.length <= limit) return [...ordered];
    const offset = this.countryOffsets.get(code) ?? 0;
    const start = offset % ordered.length;
    const end = start + limit;
    const nextOffset = (start + limit) % ordered.length;
    this.countryOffsets.set(code, nextOffset);

    if (end <= ordered.length) {
      return ordered.slice(start, end);
    }
    const head = ordered.slice(start);
    const tail = ordered.slice(0, end - ordered.length);
    return [...head, ...tail];
  }

  private normalizeBody(body: string, countryName: string | null): string {
    const trimmed = String(body || '').trim();
    if (!trimmed) return '';
    let cleaned = trimmed;
    const genericPattern = /^in\s+[A-Za-z][^,.:;-]{1,60}[,.:;-]\s*/i;
    cleaned = cleaned.replace(genericPattern, '').trim();
    if (!cleaned || !countryName) return cleaned;
    const escaped = countryName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const pattern = new RegExp(`^In\\s+${escaped}\\b[\\s,.-]*`, 'i');
    return cleaned.replace(pattern, '').trim();
  }

  private getOrderedComments(postId: string): PostComment[] {
    const cached = this.commentOrderCache.get(postId);
    if (cached) return cached;
    const base = this.commentsByPost.get(postId) ?? [];
    if (!base.length) {
      this.commentOrderCache.set(postId, []);
      return [];
    }

    const deduped: PostComment[] = [];
    const seen = new Set<string>();
    for (const comment of base) {
      const key = `${comment.author_id}|${this.normalizeCommentBody(comment.body)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      deduped.push(comment);
    }

    const rng = mulberry32(hashSeed(`${postId}|comments`));
    for (let i = deduped.length - 1; i > 0; i -= 1) {
      const j = Math.floor(rng() * (i + 1));
      const temp = deduped[i];
      deduped[i] = deduped[j];
      deduped[j] = temp;
    }

    this.commentOrderCache.set(postId, deduped);
    return deduped;
  }

  private normalizeCommentBody(body: string): string {
    return String(body || '').trim().toLowerCase().replace(/\s+/g, ' ');
  }

  private normalizeAuthorId(rawId: string | null | undefined): string | null {
    const value = String(rawId || '').trim();
    if (!value) return null;
    const match = value.match(/^user_(\d+)$/i);
    if (!match) return value;
    const num = parseInt(match[1], 10);
    if (!Number.isFinite(num) || num <= 0) return value;
    const padded = String(num).padStart(6, '0');
    return `user_${padded}`;
  }

  private resolveAssetUrl(path: string): string {
    const baseHref = document.querySelector('base')?.getAttribute('href') ?? '/';
    const resolvedBase = new URL(baseHref, window.location.origin).toString();
    return new URL(path, resolvedBase).toString();
  }

  private async fetchText(path: string): Promise<string> {
    if (typeof window === 'undefined' || typeof document === 'undefined') {
      return '';
    }
    const url = this.resolveAssetUrl(path);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Failed to load ${path}: ${res.status}`);
    return res.text();
  }

  private async hydrateMedia(posts: CountryPost[]): Promise<void> {
    if (!environment.pexelsApiKey) return;
    const work = posts.map(async (post) => {
      if (!post || post.media_type === 'none') return;
      if (post.media_url) return;
      const meta = this.postMediaMeta.get(post.id);
      if (!meta || !meta.query) return;
      const key = `${meta.type}:${meta.query}`.toLowerCase();
      const cached = this.pexelsCache.get(key);
      if (cached) {
        post.media_url = cached.url;
        post.thumb_url = cached.thumb_url;
        return;
      }
      const inflight = this.pexelsInflight.get(key);
      if (inflight) {
        const resolved = await inflight;
        post.media_url = resolved.url;
        post.thumb_url = resolved.thumb_url;
        return;
      }
      const task = this.fetchPexels(meta.type, meta.query);
      this.pexelsInflight.set(key, task);
      const resolved = await task;
      this.pexelsInflight.delete(key);
      this.pexelsCache.set(key, resolved);
      post.media_url = resolved.url;
      post.thumb_url = resolved.thumb_url;
    });
    await Promise.all(work);
  }

  private async fetchPexels(type: string, query: string): Promise<{ url: string | null; thumb_url: string | null }> {
    const apiKey = environment.pexelsApiKey || '';
    if (!apiKey) return { url: null, thumb_url: null };
    const headers = { Authorization: apiKey };

    if (type === 'video') {
      const url = `https://api.pexels.com/videos/search?query=${encodeURIComponent(query)}&per_page=1`;
      const res = await fetch(url, { headers });
      if (!res.ok) return { url: null, thumb_url: null };
      const data = await res.json();
      const video = data?.videos?.[0];
      if (!video) return { url: null, thumb_url: null };
      const files = Array.isArray(video.video_files) ? video.video_files : [];
      const mp4 = files
        .filter((file: any) => String(file?.file_type || '').toLowerCase() === 'video/mp4')
        .sort((a: any, b: any) => (a?.width ?? 0) - (b?.width ?? 0));
      const picked = mp4.find((file: any) => (file?.width ?? 0) >= 720) || mp4[0];
      const thumb = (video.video_pictures?.[0]?.picture as string) || video.image || null;
      return { url: picked?.link ?? null, thumb_url: thumb };
    }

    const url = `https://api.pexels.com/v1/search?query=${encodeURIComponent(query)}&per_page=1`;
    const res = await fetch(url, { headers });
    if (!res.ok) return { url: null, thumb_url: null };
    const data = await res.json();
    const photo = data?.photos?.[0];
    const src = photo?.src || {};
    return { url: src?.large ?? src?.medium ?? null, thumb_url: src?.medium ?? null };
  }
}
