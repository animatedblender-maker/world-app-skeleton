export type PostVisibility = 'public' | 'followers' | 'private' | 'country';

export type PostAuthor = {
  user_id: string;
  display_name: string | null;
  username: string | null;
  avatar_url: string | null;
  country_name: string | null;
  country_code: string | null;
  last_read_at?: string | null;
};

export type CountryPost = {
  id: string;
  title: string | null;
  body: string;
  media_type: string | null;
  media_url: string | null;
  thumb_url?: string | null;
  media_caption?: string | null;
  shared_post_id?: string | null;
  shared_post?: CountryPost | null;
  visibility: PostVisibility;
  like_count: number;
  comment_count: number;
  view_count: number;
  liked_by_me: boolean;
  created_at: string;
  updated_at: string;
  author_id: string;
  country_name: string | null;
  country_code: string | null;
  city_name: string | null;
  author: PostAuthor | null;
  // External news link fields
  external_ref_type?: 'news' | null;
  external_ref_id?: string | null;
  link_url?: string | null;
  link_title?: string | null;
  link_source_name?: string | null;
  link_published_at?: string | null;
  link_image_url?: string | null;
  link_snippet?: string | null;
};

export type PostComment = {
  id: string;
  post_id: string;
  parent_id: string | null;
  author_id: string;
  body: string;
  like_count: number;
  liked_by_me: boolean;
  created_at: string;
  updated_at: string;
  author: PostAuthor | null;
};

export type PostLike = {
  user_id: string;
  created_at: string;
  user: PostAuthor | null;
};

export type ExternalNewsItem = {
  id: string;
  provider: string;
  provider_item_id: string;
  title: string;
  url: string;
  source_name?: string | null;
  published_at?: string | null;
  country_codes: string[];
  country_names: string[];
  disaster_types: string[];
  theme_names: string[];
  format?: string | null;
  language?: string | null;
  snippet?: string | null;
  image_url?: string | null;
  comment_count: number;
  shared_post_count: number;
};

export type ExternalNewsComment = {
  id: string;
  news_item_id: string;
  parent_id?: string | null;
  author_id: string;
  body: string;
  created_at: string;
  updated_at: string;
  author: PostAuthor | null;
};
