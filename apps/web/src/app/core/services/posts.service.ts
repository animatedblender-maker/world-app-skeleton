import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';

export type CountryPost = {
  id: string;
  title: string | null;
  body: string;
  media_type: string | null;
  media_url: string | null;
  created_at: string;
  author_id: string;
  author: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  } | null;
};

@Injectable({ providedIn: 'root' })
export class PostsService {
  constructor(private gql: GqlService) {}

  async listByCountry(countryCode: string, limit = 25): Promise<CountryPost[]> {
    const query = `
      query PostsByCountry($code: String!, $limit: Int) {
        postsByCountry(country_code: $code, limit: $limit) {
          id
          title
          body
          media_type
          media_url
          created_at
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

  async createPost(input: {
    authorId: string;
    title?: string | null;
    body: string;
    countryName: string;
    countryCode: string;
    cityName?: string | null;
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
          created_at
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
    };

    const { createPost } = await this.gql.request<{ createPost: any }>(mutation, {
      input: payload,
    });
    return this.mapPost(createPost);
  }

  private mapPost(row: any): CountryPost {
    return {
      id: row.id,
      title: row.title ?? null,
      body: row.body ?? '',
      media_type: row.media_type ?? 'none',
      media_url: row.media_url ?? null,
      created_at: row.created_at,
      author_id: row.author_id,
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
