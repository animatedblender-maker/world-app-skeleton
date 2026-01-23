import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { GqlService } from './gql.service';
import { Conversation, Message } from '../models/messages.model';
import { PostAuthor } from '../models/post.model';
import { supabase } from '../../supabase/supabase.client';

const CONVERSATIONS_QUERY = `
query Conversations($limit: Int) {
  conversations(limit: $limit) {
    id
    is_direct
    created_at
    updated_at
    last_message_at
    members {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
      last_read_at
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      media_type
      media_path
      media_name
      media_mime
      media_size
      created_at
      updated_at
      sender {
        user_id
        display_name
        username
        avatar_url
        country_name
        country_code
      }
    }
  }
}
`;

const CONVERSATION_BY_ID_QUERY = `
query ConversationById($conversationId: ID!) {
  conversationById(conversation_id: $conversationId) {
    id
    is_direct
    created_at
    updated_at
    last_message_at
    members {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
      last_read_at
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      media_type
      media_path
      media_name
      media_mime
      media_size
      created_at
      updated_at
      sender {
        user_id
        display_name
        username
        avatar_url
        country_name
        country_code
      }
    }
  }
}
`;

const MESSAGES_QUERY = `
query MessagesByConversation($conversationId: ID!, $limit: Int, $before: String) {
  messagesByConversation(conversation_id: $conversationId, limit: $limit, before: $before) {
    id
    conversation_id
    sender_id
    body
    media_type
    media_path
    media_name
    media_mime
    media_size
    created_at
    updated_at
    sender {
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

const START_CONVERSATION_MUTATION = `
mutation StartConversation($targetId: ID!) {
  startConversation(target_id: $targetId) {
    id
    is_direct
    created_at
    updated_at
    last_message_at
    members {
      user_id
      display_name
      username
      avatar_url
      country_name
      country_code
      last_read_at
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      created_at
      updated_at
      sender {
        user_id
        display_name
        username
        avatar_url
        country_name
        country_code
      }
    }
  }
}
`;

const SEND_MESSAGE_MUTATION = `
mutation SendMessage($conversationId: ID!, $body: String, $mediaType: String, $mediaPath: String, $mediaName: String, $mediaMime: String, $mediaSize: Int) {
  sendMessage(
    conversation_id: $conversationId,
    body: $body,
    media_type: $mediaType,
    media_path: $mediaPath,
    media_name: $mediaName,
    media_mime: $mediaMime,
    media_size: $mediaSize
  ) {
    id
    conversation_id
    sender_id
    body
    media_type
    media_path
    media_name
    media_mime
    media_size
    created_at
    updated_at
    sender {
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

const UPDATE_MESSAGE_MUTATION = `
mutation UpdateMessage($messageId: ID!, $body: String!) {
  updateMessage(message_id: $messageId, body: $body) {
    id
    conversation_id
    sender_id
    body
    media_type
    media_path
    media_name
    media_mime
    media_size
    created_at
    updated_at
    sender {
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

const DELETE_MESSAGE_MUTATION = `
mutation DeleteMessage($messageId: ID!) {
  deleteMessage(message_id: $messageId)
}
`;

@Injectable({ providedIn: 'root' })
export class MessagesService {
  private pendingStorageKey = 'worldapp.pendingConversation';
  private pendingConversation: Conversation | null = null;
  private pendingConversationSubject = new BehaviorSubject<Conversation | null>(null);
  readonly pendingConversation$ = this.pendingConversationSubject.asObservable();
  private mediaCache = new Map<string, { url: string; expiresAt: number }>();

  constructor(private gql: GqlService) {
    const stored = this.readPendingStorage();
    if (stored) {
      this.pendingConversation = stored;
    }
    this.pendingConversationSubject.next(this.pendingConversation);
  }

  setPendingConversation(convo: Conversation): void {
    this.pendingConversation = convo;
    this.writePendingStorage(convo);
    this.pendingConversationSubject.next(convo);
  }

  getPendingConversation(): Conversation | null {
    return this.pendingConversation;
  }

  clearPendingConversation(): void {
    this.pendingConversation = null;
    this.clearPendingStorage();
    this.pendingConversationSubject.next(null);
  }

  async listConversations(limit = 30): Promise<Conversation[]> {
    const { conversations } = await this.gql.request<{ conversations: any[] }>(
      CONVERSATIONS_QUERY,
      { limit }
    );
    const mapped = (conversations ?? []).map((row) => this.mapConversation(row));
    return await Promise.all(mapped.map((convo) => this.hydrateConversation(convo)));
  }

  async getConversationById(conversationId: string): Promise<Conversation | null> {
    const { conversationById } = await this.gql.request<{ conversationById: any }>(
      CONVERSATION_BY_ID_QUERY,
      { conversationId }
    );
    if (!conversationById) return null;
    return await this.hydrateConversation(this.mapConversation(conversationById));
  }

  async listMessages(conversationId: string, limit = 40, before?: string | null): Promise<Message[]> {
    const { messagesByConversation } = await this.gql.request<{ messagesByConversation: any[] }>(
      MESSAGES_QUERY,
      { conversationId, limit, before: before ?? null }
    );
    const mapped = (messagesByConversation ?? []).map((row) => this.mapMessage(row));
    return await Promise.all(mapped.map((message) => this.hydrateMessageMedia(message)));
  }

  async startConversation(targetId: string): Promise<Conversation> {
    const { startConversation } = await this.gql.request<{ startConversation: any }>(
      START_CONVERSATION_MUTATION,
      { targetId }
    );
    return this.mapConversation(startConversation);
  }

  async sendMessage(
    conversationId: string,
    body: string,
    media?: {
      type: string;
      path: string;
      name?: string | null;
      mime?: string | null;
      size?: number | null;
    }
  ): Promise<Message> {
    const trimmed = String(body ?? '').trim();
    const payload = {
      conversationId,
      body: trimmed || null,
      mediaType: media?.type ?? null,
      mediaPath: media?.path ?? null,
      mediaName: media?.name ?? null,
      mediaMime: media?.mime ?? null,
      mediaSize: media?.size ?? null,
    };
    const { sendMessage } = await this.gql.request<{ sendMessage: any }>(
      SEND_MESSAGE_MUTATION,
      payload
    );
    return await this.hydrateMessageMedia(this.mapMessage(sendMessage));
  }

  async updateMessage(messageId: string, body: string): Promise<Message> {
    const trimmed = String(body ?? '').trim();
    const { updateMessage } = await this.gql.request<{ updateMessage: any }>(
      UPDATE_MESSAGE_MUTATION,
      { messageId, body: trimmed }
    );
    return await this.hydrateMessageMedia(this.mapMessage(updateMessage));
  }

  async deleteMessage(messageId: string): Promise<boolean> {
    const { deleteMessage } = await this.gql.request<{ deleteMessage: boolean }>(
      DELETE_MESSAGE_MUTATION,
      { messageId }
    );
    return !!deleteMessage;
  }

  private mapAuthor(row: any): PostAuthor | null {
    if (!row) return null;
    return {
      user_id: row.user_id,
      display_name: row.display_name ?? null,
      username: row.username ?? null,
      avatar_url: row.avatar_url ?? null,
      country_name: row.country_name ?? null,
      country_code: row.country_code ?? null,
      last_read_at: row.last_read_at ?? null,
    };
  }

  private mapMessage(row: any): Message {
    return {
      id: row.id,
      conversation_id: row.conversation_id,
      sender_id: row.sender_id,
      body: row.body ?? '',
      media_type: row.media_type ?? null,
      media_path: row.media_path ?? null,
      media_name: row.media_name ?? null,
      media_mime: row.media_mime ?? null,
      media_size: row.media_size ?? null,
      created_at: row.created_at,
      updated_at: row.updated_at ?? null,
      sender: row.sender ? this.mapAuthor(row.sender) : null,
    };
  }

  private mapConversation(row: any): Conversation {
    return {
      id: row.id,
      is_direct: !!row.is_direct,
      created_at: row.created_at,
      updated_at: row.updated_at ?? row.created_at,
      last_message_at: row.last_message_at ?? null,
      members: Array.isArray(row.members) ? row.members.map((m: any) => this.mapAuthor(m) as PostAuthor) : [],
      last_message: row.last_message ? this.mapMessage(row.last_message) : null,
    };
  }

  private async hydrateConversation(convo: Conversation): Promise<Conversation> {
    if (!convo.last_message) return convo;
    const last_message = await this.hydrateMessageMedia(convo.last_message);
    return { ...convo, last_message };
  }

  private async hydrateMessageMedia(message: Message): Promise<Message> {
    if (!message.media_path) return message;
    const url = await this.getSignedUrl(message.media_path);
    return { ...message, media_url: url };
  }

  private async getSignedUrl(path: string): Promise<string | null> {
    if (!path) return null;
    const cached = this.mediaCache.get(path);
    if (cached && cached.expiresAt > Date.now()) return cached.url;
    const { data, error } = await supabase.storage.from('messages').createSignedUrl(path, 60 * 60);
    if (error || !data?.signedUrl) return null;
    this.mediaCache.set(path, { url: data.signedUrl, expiresAt: Date.now() + 55 * 60_000 });
    return data.signedUrl;
  }

  private readPendingStorage(): Conversation | null {
    if (typeof window === 'undefined') return null;
    try {
      const raw = window.sessionStorage.getItem(this.pendingStorageKey);
      if (!raw) return null;
      return JSON.parse(raw) as Conversation;
    } catch {
      this.clearPendingStorage();
      return null;
    }
  }

  private writePendingStorage(convo: Conversation): void {
    if (typeof window === 'undefined') return;
    try {
      window.sessionStorage.setItem(this.pendingStorageKey, JSON.stringify(convo));
    } catch {
      // ignore storage errors (private mode, quota, etc.)
    }
  }

  private clearPendingStorage(): void {
    if (typeof window === 'undefined') return;
    try {
      window.sessionStorage.removeItem(this.pendingStorageKey);
    } catch {
      // ignore storage errors
    }
  }
}
