import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';
import { CountryPost, PostComment, PostLike } from '../models/post.model';
import { PostEventsService } from './post-events.service';

@Injectable({ providedIn: 'root' })
export class PostsService {
  constructor(private gql: GqlService, private postEvents: PostEventsService) {}

  async listByCountry(countryCode: string, limit = 25): Promise<CountryPost[]> {
    const query = `
      query PostsByCountry($code: String!, $limit: Int) {
        postsByCountry(country_code: $code, limit: $limit) {
          id
          title
          body
          media_type
          media_url
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

    const { postsByCountry } = await this.gql.request<{ postsByCountry: any[] }>(query, {
      code: countryCode,
      limit,
    });
    return (postsByCountry ?? []).map((row) => this.mapPost(row));
  }

  async listForAuthor(userId: string, limit = 25): Promise<CountryPost[]> {
    if (!userId) return [];
    const query = `
      query PostsByAuthor($authorId: ID!, $limit: Int) {
        postsByAuthor(user_id: $authorId, limit: $limit) {
          id
          title
          body
          media_type
          media_url
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

    const { postsByAuthor } = await this.gql.request<{ postsByAuthor: any[] }>(
      query,
      { authorId: userId, limit }
    );
    return (postsByAuthor ?? []).map((row) => this.mapPost(row));
  }

  async getPostById(postId: string): Promise<CountryPost | null> {
    if (!postId) return null;
    const query = `
      query PostById($postId: ID!) {
        postById(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
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
    const mutation = `
      mutation LikePost($postId: ID!) {
        likePost(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
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
    const mutation = `
      mutation UnlikePost($postId: ID!) {
        unlikePost(post_id: $postId) {
          id
          title
          body
          media_type
          media_url
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

  async listComments(postId: string, limit = 25, before?: string | null): Promise<PostComment[]> {
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

  private mapPost(row: any): CountryPost {
    return {
      id: row.id,
      title: row.title ?? null,
      body: row.body ?? '',
      media_type: row.media_type ?? 'none',
      media_url: row.media_url ?? null,
      visibility: row.visibility ?? 'public',
      like_count: Number(row.like_count ?? 0),
      comment_count: Number(row.comment_count ?? 0),
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
            avatar_url: row.author.avatar_url,
            country_name: row.author.country_name,
            country_code: row.author.country_code,
          }
        : null,
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
            avatar_url: row.author.avatar_url,
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
            avatar_url: row.user.avatar_url,
            country_name: row.user.country_name,
            country_code: row.user.country_code,
          }
        : null,
    };
  }
}
