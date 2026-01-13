import { PostAuthor } from './post.model';

export type Message = {
  id: string;
  conversation_id: string;
  sender_id: string;
  body: string;
  created_at: string;
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
