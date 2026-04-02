import { Injectable } from '@angular/core';

import { ExternalNewsComment, ExternalNewsItem, CountryPost } from '@world/shared';

import { GqlService } from './gql.service';

@Injectable({ providedIn: 'root' })
export class NewsService {
  constructor(private gql: GqlService) {}

  async countryConflictUpdates(
    countryCode: string,
    limit = 10,
    offset = 0
  ): Promise<ExternalNewsItem[]> {
    const query = `
      query CountryConflictUpdates($country_code: String!, $limit: Int, $offset: Int) {
        countryConflictUpdates(country_code: $country_code, limit: $limit, offset: $offset) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          comment_count
          shared_post_count
        }
      }
    `;

    const { countryConflictUpdates } = await this.gql.request<{
      countryConflictUpdates: ExternalNewsItem[];
    }>(query, {
      country_code: countryCode,
      limit,
      offset,
    });

    return countryConflictUpdates ?? [];
  }

  async globalConflictUpdates(limit = 10, offset = 0): Promise<ExternalNewsItem[]> {
    const query = `
      query GlobalConflictUpdates($limit: Int, $offset: Int) {
        globalConflictUpdates(limit: $limit, offset: $offset) {
          id
          provider
          provider_item_id
          title
          url
          source_name
          published_at
          country_codes
          country_names
          disaster_types
          theme_names
          format
          language
          snippet
          image_url
          comment_count
          shared_post_count
        }
      }
    `;

    const { globalConflictUpdates } = await this.gql.request<{
      globalConflictUpdates: ExternalNewsItem[];
    }>(query, {
      limit,
      offset,
    });

    return globalConflictUpdates ?? [];
  }

  async comments(
    newsItemId: string,
    limit = 25,
    before?: string | null
  ): Promise<ExternalNewsComment[]> {
    const query = `
      query ExternalNewsComments($news_item_id: ID!, $limit: Int, $before: String) {
        externalNewsComments(news_item_id: $news_item_id, limit: $limit, before: $before) {
          id
          news_item_id
          parent_id
          author_id
          body
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

    const { externalNewsComments } = await this.gql.request<{
      externalNewsComments: ExternalNewsComment[];
    }>(query, {
      news_item_id: newsItemId,
      limit,
      before: before ?? null,
    });

    return externalNewsComments ?? [];
  }

  async addComment(
    newsItemId: string,
    body: string,
    parentId?: string | null
  ): Promise<ExternalNewsComment> {
    const mutation = `
      mutation AddExternalNewsComment($news_item_id: ID!, $body: String!, $parent_id: ID) {
        addExternalNewsComment(news_item_id: $news_item_id, body: $body, parent_id: $parent_id) {
          id
          news_item_id
          parent_id
          author_id
          body
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

    const { addExternalNewsComment } = await this.gql.request<{
      addExternalNewsComment: ExternalNewsComment;
    }>(mutation, {
      news_item_id: newsItemId,
      body: String(body ?? '').trim(),
      parent_id: parentId ?? null,
    });

    return addExternalNewsComment;
  }

  async shareToCountry(newsItemId: string, body?: string | null): Promise<CountryPost> {
    const mutation = `
      mutation ShareExternalNewsToCountry($news_item_id: ID!, $body: String, $visibility: String) {
        shareExternalNewsToCountry(news_item_id: $news_item_id, body: $body, visibility: $visibility) {
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
          external_ref_type
          external_ref_id
          link_url
          link_title
          link_source_name
          link_published_at
          link_image_url
          link_snippet
        }
      }
    `;

    const { shareExternalNewsToCountry } = await this.gql.request<{
      shareExternalNewsToCountry: CountryPost;
    }>(mutation, {
      news_item_id: newsItemId,
      body: body ?? null,
      visibility: 'country',
    });

    return shareExternalNewsToCountry;
  }
}
