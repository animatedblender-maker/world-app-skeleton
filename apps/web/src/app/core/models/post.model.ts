export type CountryPost = {
  id: string;
  title: string | null;
  body: string;
  media_type: string | null;
  media_url: string | null;
  visibility: string;
  like_count: number;
  comment_count: number;
  liked_by_me: boolean;
  created_at: string;
  updated_at: string;
  author_id: string;
  country_name: string | null;
  country_code: string | null;
  city_name: string | null;
  author: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  } | null;
};

export type PostComment = {
  id: string;
  post_id: string;
  author_id: string;
  body: string;
  created_at: string;
  updated_at: string;
  author: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  } | null;
};

export type PostLike = {
  user_id: string;
  created_at: string;
  user: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  } | null;
};
