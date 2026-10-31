import { Injectable } from '@angular/core';
import type { CountryPost, PostComment } from '../core/models/post.model';
import { PostsService } from '../core/services/posts.service';

type LocalEngagement = {
  likes: Record<string, boolean>;
  likeCounts: Record<string, number>;
  comments: Record<string, PostComment[]>;
};

const STORAGE_KEY = 'hub.engagement.v1';

/** Local likes/comments for seed/hub IDs (ia_*, hub_*, non-UUID) — ports HubEngagementStore. */
@Injectable({ providedIn: 'root' })
export class HubsEngagementService {
  private state: LocalEngagement = { likes: {}, likeCounts: {}, comments: {} };

  constructor(private posts: PostsService) {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw) as LocalEngagement;
        this.state = {
          likes: parsed.likes || {},
          likeCounts: parsed.likeCounts || {},
          comments: parsed.comments || {},
        };
      }
    } catch {
      // ignore
    }
  }

  usesLocalEngagement(postID: string): boolean {
    if (!postID) return true;
    if (
      postID.startsWith('ia_') ||
      postID.startsWith('hub_') ||
      postID.startsWith('archive_') ||
      postID.startsWith('post_') ||
      postID.startsWith('demo_') ||
      postID.startsWith('hub_cmt_')
    ) {
      return true;
    }
    // UUID v4-ish
    return !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      postID
    );
  }

  applyLikeState(post: CountryPost): CountryPost {
    if (!this.usesLocalEngagement(post.id)) return post;
    const liked = this.state.likes[post.id];
    const count = this.state.likeCounts[post.id];
    if (liked == null && count == null) return post;
    return {
      ...post,
      liked_by_me: liked ?? post.liked_by_me,
      like_count: count ?? post.like_count,
    };
  }

  applyMany(posts: CountryPost[]): CountryPost[] {
    return posts.map((p) => this.applyLikeState(p));
  }

  async toggleLike(post: CountryPost): Promise<CountryPost> {
    if (this.usesLocalEngagement(post.id)) {
      const currently = this.state.likes[post.id] ?? !!post.liked_by_me;
      const next = !currently;
      this.state.likes[post.id] = next;
      const base = this.state.likeCounts[post.id] ?? post.like_count ?? 0;
      this.state.likeCounts[post.id] = Math.max(0, base + (next ? 1 : -1));
      this.persist();
      return this.applyLikeState({ ...post, liked_by_me: currently, like_count: base });
    }
    try {
      if (post.liked_by_me) {
        return await this.posts.unlikePost(post.id);
      }
      return await this.posts.likePost(post.id);
    } catch {
      return post;
    }
  }

  listComments(postID: string): PostComment[] {
    return (this.state.comments[postID] || []).slice();
  }

  /**
   * Load comments for a hub/watch post.
   * Seed/archive IDs have no GraphQL rows — seed a stable demo thread (like iOS
   * PostsService + demo comments) and merge any on-device replies the user added.
   */
  async loadComments(post: CountryPost): Promise<PostComment[]> {
    const local = this.listComments(post.id).filter((c) => this.hasCommentBody(c));
    if (this.usesLocalEngagement(post.id)) {
      // Hub/archive IDs: synthetic seed is instant (no comments.jsonl parse).
      // Previously we walked the 30k demo comments pool and blocked the watch page.
      let seeded: PostComment[] = [];
      try {
        seeded = this.seedCommentsForHubPost(post);
      } catch {
        seeded = [];
      }
      // Local (user) replies first, then seeded thread (dedupe by id)
      const seen = new Set(local.map((c) => c.id));
      const rest = seeded.filter((c) => !seen.has(c.id) && this.hasCommentBody(c));
      return [...local, ...rest];
    }
    try {
      const remote = (await this.posts.listComments(post.id, 50)).filter((c) =>
        this.hasCommentBody(c)
      );
      if (remote.length) return remote;
      // Fallback if API empty
      return local.length ? local : this.seedCommentsForHubPost(post);
    } catch {
      return local.length ? local : this.seedCommentsForHubPost(post);
    }
  }

  /** Drop blank / whitespace-only comments — never show empty bubbles. */
  private hasCommentBody(c: PostComment | null | undefined): boolean {
    return !!String(c?.body || '').trim();
  }

  /**
   * Stable demo thread for hub/seed posts — pure sync, no network / jsonl.
   * Same post id always gets the same names/bodies via hash.
   */
  private seedCommentsForHubPost(post: CountryPost): PostComment[] {
    const target = Math.min(
      40,
      Math.max(8, Number(post.comment_count) || this.pseudoCount(post.id + '|c', 8, 28))
    );
    return this.fallbackSyntheticComments(post, target);
  }

  private fallbackSyntheticComments(post: CountryPost, count: number): PostComment[] {
    const bodies = [
      'This is great — more of this please.',
      'Watching from another country, love the vibe.',
      'How is this not more popular?',
      'Came here from Hubs, staying for the whole catalog.',
      'Solid edit. Who else is rewatching?',
      'The sound on this is perfect.',
      'Matterya Hubs is underrated for finds like this.',
      'Bookmarking for later 🔥',
      'Anyone know the creator’s other videos?',
      'This made my day.',
    ];
    const names = [
      'Alex', 'Sam', 'Jordan', 'Riley', 'Casey', 'Morgan', 'Avery', 'Quinn', 'Jamie', 'Taylor',
    ];
    const out: PostComment[] = [];
    const n = Math.max(1, count);
    for (let i = 0; i < n; i++) {
      const h = this.hashSeed(`${post.id}|syn|${i}`);
      const name = names[h % names.length];
      const body = String(bodies[(h >> 3) % bodies.length] || '').trim();
      if (!body) continue;
      const minsAgo = 15 + (h % 60_000);
      const created = new Date(Date.now() - minsAgo * 60_000).toISOString();
      out.push({
        id: `hub_syn_${post.id}_${i}`,
        post_id: post.id,
        parent_id: null,
        author_id: `hub_user_${h % 5000}`,
        body,
        like_count: h % 40,
        liked_by_me: false,
        created_at: created,
        updated_at: created,
        author: {
          user_id: `hub_user_${h % 5000}`,
          display_name: name,
          username: name.toLowerCase(),
          avatar_url: null,
          country_name: null,
          country_code: null,
        },
      });
    }
    return out;
  }

  private hashSeed(input: string): number {
    let h = 2166136261;
    for (let i = 0; i < input.length; i++) {
      h ^= input.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }

  private pseudoCount(seed: string, min: number, max: number): number {
    const h = this.hashSeed(seed);
    return min + (h % (max - min + 1));
  }

  async addComment(
    post: CountryPost,
    body: string,
    author: {
      id: string;
      display_name?: string | null;
      username?: string | null;
      avatar_url?: string | null;
      parent_id?: string | null;
    }
  ): Promise<PostComment | null> {
    const text = body.trim();
    if (!text) return null;
    if (this.usesLocalEngagement(post.id)) {
      const comment: PostComment = {
        id: `hub_cmt_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        post_id: post.id,
        parent_id: author.parent_id ?? null,
        author_id: author.id,
        body: text,
        like_count: 0,
        liked_by_me: false,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        author: {
          user_id: author.id,
          display_name: author.display_name ?? null,
          username: author.username ?? null,
          avatar_url: author.avatar_url ?? null,
          country_name: null,
          country_code: null,
        },
      };
      const list = this.state.comments[post.id] || [];
      list.unshift(comment);
      this.state.comments[post.id] = list;
      this.persist();
      return comment;
    }
    try {
      return await this.posts.addComment(post.id, text);
    } catch {
      return null;
    }
  }

  private persist(): void {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.state));
    } catch {
      // ignore
    }
  }
}
