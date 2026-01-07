import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';
import { CountryPost } from '../models/post.model';
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

  async createPost(input: {
    authorId: string;
    title?: string | null;
    body: string;
    countryName: string;
    countryCode: string;
    cityName?: string | null;
    visibility?: string | null;
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

  private mapPost(row: any): CountryPost {
    return {
      id: row.id,
      title: row.title ?? null,
      body: row.body ?? '',
      media_type: row.media_type ?? 'none',
      media_url: row.media_url ?? null,
      visibility: row.visibility ?? 'public',
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
}
