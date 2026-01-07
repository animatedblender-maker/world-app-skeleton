export type CountryPost = {
  id: string;
  title: string | null;
  body: string;
  media_type: string | null;
  media_url: string | null;
  visibility: string;
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
