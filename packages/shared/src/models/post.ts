export type PostVisibility = 'public' | 'followers' | 'private' | 'country';

export type PostAuthor = {
  user_id: string;
  display_name: string | null;
  username: string | null;
  avatar_url: string | null;
  country_name: string | null;
  country_code: string | null;
};

export type CountryPost = {
  id: string;
  title: string | null;
  body: string;
  media_type: string | null;
  media_url: string | null;
  visibility: PostVisibility;
  like_count: number;
  comment_count: number;
  liked_by_me: boolean;
  created_at: string;
  updated_at: string;
  author_id: string;
  country_name: string | null;
  country_code: string | null;
  city_name: string | null;
  author: PostAuthor | null;
};

export type PostComment = {
  id: string;
  post_id: string;
  author_id: string;
  body: string;
  created_at: string;
  updated_at: string;
  author: PostAuthor | null;
};

export type PostLike = {
  user_id: string;
  created_at: string;
  user: PostAuthor | null;
};
