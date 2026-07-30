import { Injectable } from '@angular/core';
import { environment } from '../../../envirnoments/envirnoment';
import { GqlService } from './gql.service';
import { CountryPost, PostComment, PostLike } from '../models/post.model';
import { PostEventsService } from './post-events.service';
import { DemoDatasetService } from './demo-dataset.service';
import { SUPABASE_URL } from '../../config/supabase.config';
import { resolveAvatarUrl as resolveAvatarMediaUrl } from '../utils/media-url.util';

@Injectable({ providedIn: 'root' })
export class PostsService {
  constructor(
    private gql: GqlService,
    private postEvents: PostEventsService,
    private demoData: DemoDatasetService
  ) {}

  async listByCountry(
    countryCode: string,
    limit = 25,
    opts?: { demoLimit?: number; skipComments?: boolean }
  ): Promise<CountryPost[]> {
    const safeLimit = Math.max(1, Math.min(80, limit || 25));
    const query = `
      query PostsByCountry($code: String!, $limit: Int) {
        postsByCountry(country_code: $code, limit: $limit) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    try {
      const { postsByCountry } = await this.withTimeout(
        this.gql.request<{ postsByCountry: any[] }>(query, {
          code: countryCode,
          limit: safeLimit,
        }),
        8000,
        'postsByCountry'
      );
      const realPosts = (postsByCountry ?? [])
        .map((row) => this.mapPost(row))
        .filter((p) => !this.isMoment(p));
      if (!environment.useDemoDataset) return realPosts;

      const demoLimit = Math.min(opts?.demoLimit ?? safeLimit, 40);
      const demoPosts = await this.withTimeout(
        this.demoData.listByCountry(countryCode, demoLimit, {
          skipComments: opts?.skipComments ?? true,
        }),
        2500,
        'demoPostsByCountry'
      ).catch(() => [] as CountryPost[]);
      return this.mergePosts(realPosts, demoPosts, safeLimit);
    } catch {
      if (!environment.useDemoDataset) return [];
      try {
        return await this.withTimeout(
          this.demoData.listByCountry(countryCode, Math.min(safeLimit, 20), {
            skipComments: true,
          }),
          2500,
          'demoPostsByCountryFallback'
        );
      } catch {
        return [];
      }
    }
  }

  async listRecent(limit = 40, before?: string | null): Promise<CountryPost[]> {
    const query = `
      query RecentPosts($limit: Int, $before: String) {
        recentPosts(limit: $limit, before: $before) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;
    try {
      const { recentPosts } = await this.withTimeout(
        this.gql.request<{ recentPosts: any[] }>(query, {
          limit: Math.max(1, Math.min(80, limit || 40)),
          before: before ?? null,
        }),
        8000,
        'recentPosts'
      );
      // Moments must never appear as regular feed posts (also strip markers in mapPost).
      return (recentPosts ?? [])
        .map((row) => this.mapPost(row))
        .filter((p) => !this.isMoment(p));
    } catch {
      return [];
    }
  }

  isMoment(post: CountryPost | null | undefined): boolean {
    if (!post) return false;
    const media = String(post.media_type || '').toLowerCase();
    if (media === 'story' || media === 'moment') return true;
    return String(post.body || '').includes('__story__|');
  }

  isSpark(post: CountryPost | null | undefined): boolean {
    if (!post) return false;
    if (this.isMoment(post)) return false;
    const media = String(post.media_type || '').toLowerCase();
    if (media === 'reel' || media === 'spark') return true;
    const raw = String(post.media_url || '').trim();
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        const flag = parsed?.reel ?? parsed?.spark;
        return flag === true || flag === 'true' || flag === 1 || flag === '1';
      } catch {
        return false;
      }
    }
    return false;
  }

  isMomentActive(post: CountryPost): boolean {
    if (!this.isMoment(post)) return false;
    const body = String(post.body || '');
    const match = body.match(/__story__\|expires=([^\s|]+)/i);
    if (!match?.[1]) return true;
    const expires = Date.parse(match[1]);
    if (!Number.isFinite(expires)) return true;
    return expires > Date.now();
  }

  async listActiveMoments(
    limit = 40,
    opts?: {
      authorId?: string | null;
      followingIds?: string[];
      countryCode?: string | null;
    }
  ): Promise<CountryPost[]> {
    // Country/recent feeds exclude moments on the API; author feeds include them.
    const followingIds = (opts?.followingIds ?? []).filter(Boolean).slice(0, 8);
    const batches = await Promise.all([
      opts?.authorId
        ? this.listForAuthor(opts.authorId, 24).catch(() => [] as CountryPost[])
        : Promise.resolve([] as CountryPost[]),
      ...followingIds.map((id) => this.listForAuthor(id, 10).catch(() => [] as CountryPost[])),
    ]);

    const seen = new Set<string>();
    const moments: CountryPost[] = [];
    for (const batch of batches) {
      for (const post of batch) {
        if (!post?.id || seen.has(post.id)) continue;
        if (!this.isMomentActive(post)) continue;
        seen.add(post.id);
        moments.push(post);
      }
    }
    moments.sort((a, b) => {
      const ta = Date.parse(a.created_at || '') || 0;
      const tb = Date.parse(b.created_at || '') || 0;
      return tb - ta;
    });
    return moments.slice(0, Math.max(1, limit));
  }

  async loadHomeFeed(opts?: {
    authorId?: string | null;
    countryCode?: string | null;
    followingIds?: string[];
    maxPosts?: number;
  }): Promise<CountryPost[]> {
    const maxPosts = opts?.maxPosts ?? 50;
    const followingIds = (opts?.followingIds ?? []).filter(Boolean).slice(0, 6);

    // Prefer recent + country; author/following are best-effort with short timeouts.
    const batches = await Promise.all([
      this.listRecent(40).catch(() => [] as CountryPost[]),
      opts?.countryCode
        ? this.listByCountry(opts.countryCode, 24, {
            demoLimit: 12,
            skipComments: true,
          }).catch(() => [] as CountryPost[])
        : Promise.resolve([] as CountryPost[]),
      opts?.authorId
        ? this.withTimeout(this.listForAuthor(opts.authorId, 12), 5000, 'feedAuthor').catch(
            () => [] as CountryPost[]
          )
        : Promise.resolve([] as CountryPost[]),
      ...followingIds.map((id) =>
        this.withTimeout(this.listForAuthor(id, 3), 4000, 'feedFollowing').catch(
          () => [] as CountryPost[]
        )
      ),
    ]);

    const seen = new Set<string>();
    const merged: CountryPost[] = [];
    for (const batch of batches) {
      for (const post of batch) {
        if (!post?.id || seen.has(post.id)) continue;
        if (this.isMoment(post) || this.isSpark(post)) continue;
        seen.add(post.id);
        merged.push(post);
      }
    }

    merged.sort((a, b) => {
      const ta = Date.parse(a.created_at || '') || 0;
      const tb = Date.parse(b.created_at || '') || 0;
      return tb - ta;
    });
    return merged.slice(0, maxPosts);
  }

  async listForAuthor(userId: string, limit = 25): Promise<CountryPost[]> {
    if (!userId) return [];
    if (environment.useDemoDataset && /^user_/.test(userId)) {
      return this.demoData.listForAuthor(userId, limit);
    }
    const query = `
      query PostsByAuthor($authorId: ID!, $limit: Int) {
        postsByAuthor(user_id: $authorId, limit: $limit) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    try {
      const { postsByAuthor } = await this.withTimeout(
        this.gql.request<{ postsByAuthor: any[] }>(query, {
          authorId: userId,
          limit: Math.max(1, Math.min(60, limit || 25)),
        }),
        8000,
        'postsByAuthor'
      );
      return (postsByAuthor ?? []).map((row) => this.mapPost(row));
    } catch {
      return [];
    }
  }

  async searchPosts(query: string, limit = 25): Promise<CountryPost[]> {
    const term = String(query || '').trim();
    if (!term) return [];
    const searchQuery = `
      query SearchPosts($query: String!, $limit: Int) {
        searchPosts(query: $query, limit: $limit) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    try {
      const { searchPosts } = await this.gql.request<{ searchPosts: any[] }>(searchQuery, {
        query: term,
        limit,
      });
      return (searchPosts ?? []).map((row) => this.mapPost(row));
    } catch {
      return [];
    }
  }

  async getPostById(postId: string): Promise<CountryPost | null> {
    if (!postId) return null;
    if (environment.useDemoDataset && (await this.demoData.isDemoPostId(postId))) {
      return this.demoData.getPostById(postId);
    }
    const query = `
      query PostById($postId: ID!) {
        postById(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    const { postById } = await this.gql.request<{ postById: any | null }>(query, {
      postId,
    });
    return postById ? this.mapPost(postById) : null;
  }

  async createPost(input: {
    authorId: string;
    title?: string | null;
    body: string;
    countryName: string;
    countryCode: string;
    cityName?: string | null;
    visibility?: string | null;
    mediaType?: string | null;
    mediaUrl?: string | null;
    thumbUrl?: string | null;
    sharedPostId?: string | null;
    externalRefType?: string | null;
    externalRefId?: string | null;
    linkUrl?: string | null;
    linkTitle?: string | null;
    linkSourceName?: string | null;
    linkPublishedAt?: string | null;
    linkImageUrl?: string | null;
    linkSnippet?: string | null;
  }): Promise<CountryPost> {
    if (!input.authorId) throw new Error('authorId is required to post.');
    const mutation = `
      mutation CreatePost($input: CreatePostInput!) {
        createPost(input: $input) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    const payload = {
      title: input.title?.trim() || null,
      body: input.body.trim(),
      country_name: input.countryName,
      country_code: input.countryCode,
      city_name: input.cityName ?? null,
      visibility: input.visibility ?? null,
      media_type: input.mediaType ?? null,
      media_url: input.mediaUrl ?? null,
      thumb_url: input.thumbUrl ?? null,
      shared_post_id: input.sharedPostId ?? null,
    };

    const { createPost } = await this.gql.request<{ createPost: any }>(mutation, {
      input: payload,
    });
    const mapped = this.mapPost(createPost);
    this.postEvents.emit(mapped);
    return mapped;
  }

  async updatePost(
    postId: string,
    input: { title?: string | null; body?: string | null; visibility?: string | null }
  ): Promise<CountryPost> {
    const mutation = `
      mutation UpdatePost($postId: ID!, $input: UpdatePostInput!) {
        updatePost(post_id: $postId, input: $input) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    const payload = {
      title: input.title?.trim() ?? null,
      body: input.body?.trim() ?? null,
      visibility: input.visibility ?? null,
    };

    const { updatePost } = await this.gql.request<{ updatePost: any }>(mutation, {
      postId,
      input: payload,
    });
    const mapped = this.mapPost(updatePost);
    this.postEvents.emitUpdated(mapped);
    return mapped;
  }

  async deletePost(
    postId: string,
    meta?: { country_code?: string | null; author_id?: string | null }
  ): Promise<boolean> {
    const mutation = `
      mutation DeletePost($postId: ID!) {
        deletePost(post_id: $postId)
      }
    `;

    const { deletePost } = await this.gql.request<{ deletePost: boolean }>(mutation, {
      postId,
    });
    if (deletePost) {
      this.postEvents.emitDeleted({
        id: postId,
        country_code: meta?.country_code ?? null,
        author_id: meta?.author_id ?? null,
      });
    }
    return deletePost;
  }

  async likePost(postId: string): Promise<CountryPost> {
    if (environment.useDemoDataset && (await this.demoData.isDemoPostId(postId))) {
      const updated = await this.demoData.likePost(postId);
      this.postEvents.emitUpdated(updated);
      return updated;
    }
    const mutation = `
      mutation LikePost($postId: ID!) {
        likePost(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    const { likePost } = await this.gql.request<{ likePost: any }>(mutation, { postId });
    const mapped = this.mapPost(likePost);
    this.postEvents.emitUpdated(mapped);
    return mapped;
  }

  async unlikePost(postId: string): Promise<CountryPost> {
    if (environment.useDemoDataset && (await this.demoData.isDemoPostId(postId))) {
      const updated = await this.demoData.unlikePost(postId);
      this.postEvents.emitUpdated(updated);
      return updated;
    }
    const mutation = `
      mutation UnlikePost($postId: ID!) {
        unlikePost(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
          thumb_url
          shared_post_id
          shared_post {
            id
            title
            body
            media_type
            media_url
            thumb_url
            visibility
            like_count
            comment_count
            liked_by_me
            created_at
            updated_at
            author_id
            country_name
            country_code
            city_name
            author {
              user_id
              display_name
              username
              avatar_url
              country_name
              country_code
            }
          }
          visibility
          like_count
          comment_count
          liked_by_me
          created_at
          updated_at
          author_id
          country_name
          country_code
          city_name
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    const { unlikePost } = await this.gql.request<{ unlikePost: any }>(mutation, { postId });
    const mapped = this.mapPost(unlikePost);
    this.postEvents.emitUpdated(mapped);
    return mapped;
  }

  async recordView(post: CountryPost): Promise<void> {
    if (!post?.id) return;
    if (environment.useDemoDataset && (await this.demoData.isDemoPostId(post.id))) {
      await this.demoData.recordView(post.id);
      return;
    }
    post.view_count = Number(post.view_count ?? 0) + 1;
  }

  async listComments(postId: string, limit = 25, before?: string | null): Promise<PostComment[]> {
    if (environment.useDemoDataset && (await this.demoData.isDemoPostId(postId))) {
      const demoLimit = Math.max(limit, 1000);
      return this.demoData.listComments(postId, demoLimit);
    }
    const query = `
      query CommentsByPost($postId: ID!, $limit: Int, $before: String) {
        commentsByPost(post_id: $postId, limit: $limit, before: $before) {
          id
          post_id
          parent_id
          author_id
          body
          like_count
          liked_by_me
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    const { commentsByPost } = await this.gql.request<{ commentsByPost: any[] }>(
      query,
      { postId, limit, before: before ?? null }
    );
    return (commentsByPost ?? []).map((row) => this.mapComment(row));
  }

  async listLikes(postId: string, limit = 25): Promise<PostLike[]> {
    if (!postId) return [];
    if (environment.useDemoDataset && (await this.demoData.isDemoPostId(postId))) {
      return this.demoData.listLikes(postId, limit);
    }
    const query = `
      query PostLikes($postId: ID!, $limit: Int) {
        postLikes(post_id: $postId, limit: $limit) {
          user_id
          created_at
          user {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    const { postLikes } = await this.gql.request<{ postLikes: any[] }>(query, {
      postId,
      limit,
    });
    return (postLikes ?? []).map((row) => this.mapLike(row));
  }

  async addComment(postId: string, body: string, parentId?: string | null): Promise<PostComment> {
    if (environment.useDemoDataset && (await this.demoData.isDemoPostId(postId))) {
      return this.demoData.addComment(postId, body, parentId ?? null);
    }
    const mutation = `
      mutation AddComment($postId: ID!, $body: String!, $parentId: ID) {
        addComment(post_id: $postId, body: $body, parent_id: $parentId) {
          id
          post_id
          parent_id
          author_id
          body
          like_count
          liked_by_me
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;

    const { addComment } = await this.gql.request<{ addComment: any }>(mutation, {
      postId,
      body: body.trim(),
      parentId: parentId ?? null,
    });
    return this.mapComment(addComment);
  }

  async likeComment(commentId: string): Promise<PostComment> {
    if (environment.useDemoDataset && this.demoData.isDemoCommentId(commentId)) {
      return this.demoData.likeComment(commentId);
    }
    const mutation = `
      mutation LikeComment($commentId: ID!) {
        likeComment(comment_id: $commentId) {
          id
          post_id
          parent_id
          author_id
          body
          like_count
          liked_by_me
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;
    const { likeComment } = await this.gql.request<{ likeComment: any }>(mutation, { commentId });
    return this.mapComment(likeComment);
  }

  async unlikeComment(commentId: string): Promise<PostComment> {
    if (environment.useDemoDataset && this.demoData.isDemoCommentId(commentId)) {
      return this.demoData.unlikeComment(commentId);
    }
    const mutation = `
      mutation UnlikeComment($commentId: ID!) {
        unlikeComment(comment_id: $commentId) {
          id
          post_id
          parent_id
          author_id
          body
          like_count
          liked_by_me
          created_at
          updated_at
          author {
            user_id
            display_name
            username
            avatar_url
            country_name
            country_code
          }
        }
      }
    `;
    const { unlikeComment } = await this.gql.request<{ unlikeComment: any }>(mutation, { commentId });
    return this.mapComment(unlikeComment);
  }

  async reportPost(postId: string, reason: string): Promise<boolean> {
    if (environment.useDemoDataset && (await this.demoData.isDemoPostId(postId))) {
      throw new Error('Only live posts can be reported right now.');
    }

    const mutation = `
      mutation ReportPost($postId: ID!, $reason: String!) {
        reportPost(post_id: $postId, reason: $reason)
      }
    `;

    const { reportPost } = await this.gql.request<{ reportPost: boolean }>(mutation, {
      postId,
      reason: reason.trim(),
    });
    return !!reportPost;
  }

  private stripMomentMarkers(body: string | null | undefined): string {
    return String(body ?? '')
      .split('\n')
      .filter((line) => {
        const t = line.trim();
        if (!t) return true;
        if (/__story__/i.test(t)) return false;
        if (/\bstory\b/i.test(t) && /\bexpir/i.test(t)) return false;
        return true;
      })
      .join('\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
  }

  private mapPost(row: any, depth = 0): CountryPost {
    const viewCount =
      row?.view_count != null
        ? Number(row.view_count)
        : this.estimateViewCount(row?.id, row?.like_count, row?.comment_count);
    const sharedPost =
      row?.shared_post && depth < 1 ? this.mapPost(row.shared_post, depth + 1) : null;
    return {
      id: row.id,
      title: row.title ?? null,
      body: this.stripMomentMarkers(row.body ?? ''),
      media_type: row.media_type ?? 'none',
      media_url: row.media_url ?? null,
      thumb_url: row.thumb_url ?? null,
      media_caption: row.media_caption ?? null,
      shared_post_id: row.shared_post_id ?? null,
      shared_post: sharedPost,
      visibility: row.visibility ?? 'public',
      like_count: Number(row.like_count ?? 0),
      comment_count: Number(row.comment_count ?? 0),
      view_count: viewCount,
      liked_by_me: !!row.liked_by_me,
      created_at: row.created_at,
      updated_at: row.updated_at ?? row.created_at,
      author_id: row.author_id,
      country_name: row.country_name ?? null,
      country_code: row.country_code ?? null,
      city_name: row.city_name ?? null,
      author: row.author
        ? {
            user_id: row.author.user_id,
            display_name: row.author.display_name,
            username: row.author.username,
            avatar_url: this.resolveAvatarUrl(
              row.author.avatar_url,
              row.author.user_id,
              row.author.username
            ),
            country_name: row.author.country_name,
            country_code: row.author.country_code,
          }
        : null,
      external_ref_type: row.external_ref_type ?? null,
      external_ref_id: row.external_ref_id ?? null,
      link_url: row.link_url ?? null,
      link_title: row.link_title ?? null,
      link_source_name: row.link_source_name ?? null,
      link_published_at: row.link_published_at ?? null,
      link_image_url: row.link_image_url ?? null,
      link_snippet: row.link_snippet ?? null,
    };
  }

  private mapComment(row: any): PostComment {
    return {
      id: row.id,
      post_id: row.post_id,
      parent_id: row.parent_id ?? null,
      author_id: row.author_id,
      body: row.body ?? '',
      like_count: Number(row.like_count ?? 0),
      liked_by_me: !!row.liked_by_me,
      created_at: row.created_at,
      updated_at: row.updated_at ?? row.created_at,
      author: row.author
        ? {
            user_id: row.author.user_id,
            display_name: row.author.display_name,
            username: row.author.username,
            avatar_url: this.resolveAvatarUrl(
              row.author.avatar_url,
              row.author.user_id,
              row.author.username
            ),
            country_name: row.author.country_name,
            country_code: row.author.country_code,
          }
        : null,
    };
  }

  private mapLike(row: any): PostLike {
    return {
      user_id: row.user_id,
      created_at: row.created_at,
      user: row.user
        ? {
            user_id: row.user.user_id,
            display_name: row.user.display_name,
            username: row.user.username,
            avatar_url: this.resolveAvatarUrl(
              row.user.avatar_url,
              row.user.user_id,
              row.user.username
            ),
            country_name: row.user.country_name,
            country_code: row.user.country_code,
          }
        : null,
    };
  }

  private resolveAvatarUrl(
    url: string | null | undefined,
    userId: string | null | undefined,
    username: string | null | undefined
  ): string {
    return resolveAvatarMediaUrl(url, username || userId);
  }

  private mergePosts(real: CountryPost[], demo: CountryPost[], limit: number): CountryPost[] {
    const combined = [...real, ...demo];
    const seen = new Set<string>();
    const deduped: CountryPost[] = [];
    for (const post of combined) {
      if (!post?.id || seen.has(post.id)) continue;
      seen.add(post.id);
      deduped.push(post);
    }
    if (real.length) {
      const realIds = new Set(real.map((post) => post.id));
      const realOrdered = real
        .filter((post) => realIds.has(post.id))
        .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
      const demoOrdered = deduped.filter((post) => !realIds.has(post.id));
      return [...realOrdered, ...demoOrdered].slice(0, Math.max(1, limit));
    }
    return deduped
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
      .slice(0, Math.max(1, limit));
  }

  private estimateViewCount(id: string | null | undefined, likeCount: any, commentCount: any): number {
    const likes = Number(likeCount ?? 0);
    const comments = Number(commentCount ?? 0);
    if (!likes && !comments) return 0;
    const seed = this.hashSeed(String(id || 'post'));
    const jitter = seed % 1200;
    const base = likes * 12 + comments * 6 + jitter;
    return Math.max(base, likes + comments);
  }

  private hashSeed(value: string): number {
    let h = 2166136261;
    for (let i = 0; i < value.length; i++) {
      h ^= value.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }

  private async withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | null = null;
    try {
      return await Promise.race([
        promise,
        new Promise<T>((_, reject) => {
          timer = setTimeout(() => reject(new Error(`${label} timeout`)), ms);
        }),
      ]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
}
