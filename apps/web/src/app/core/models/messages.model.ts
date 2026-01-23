import { PostAuthor } from './post.model';

export type Message = {
  id: string;
  conversation_id: string;
  sender_id: string;
  body: string;
  media_type?: string | null;
  media_path?: string | null;
  media_url?: string | null;
  media_name?: string | null;
  media_mime?: string | null;
  media_size?: number | null;
  created_at: string;
  updated_at?: string | null;
  sender?: PostAuthor | null;
};

export type Conversation = {
  id: string;
  is_direct: boolean;
  created_at: string;
  updated_at: string;
  last_message_at?: string | null;
  members: PostAuthor[];
  last_message?: Message | null;
};
