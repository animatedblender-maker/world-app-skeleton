import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { GqlService } from './gql.service';
import { Conversation, Message } from '../models/messages.model';
import { PostAuthor } from '../models/post.model';

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
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      created_at
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
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      created_at
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
    created_at
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
    }
    last_message {
      id
      conversation_id
      sender_id
      body
      created_at
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
mutation SendMessage($conversationId: ID!, $body: String!) {
  sendMessage(conversation_id: $conversationId, body: $body) {
    id
    conversation_id
    sender_id
    body
    created_at
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

@Injectable({ providedIn: 'root' })
export class MessagesService {
  private pendingStorageKey = 'worldapp.pendingConversation';
  private pendingConversation: Conversation | null = null;
  private pendingConversationSubject = new BehaviorSubject<Conversation | null>(null);
  readonly pendingConversation$ = this.pendingConversationSubject.asObservable();

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
    return (conversations ?? []).map((row) => this.mapConversation(row));
  }

  async getConversationById(conversationId: string): Promise<Conversation | null> {
    const { conversationById } = await this.gql.request<{ conversationById: any }>(
      CONVERSATION_BY_ID_QUERY,
      { conversationId }
    );
    return conversationById ? this.mapConversation(conversationById) : null;
  }

  async listMessages(conversationId: string, limit = 40, before?: string | null): Promise<Message[]> {
    const { messagesByConversation } = await this.gql.request<{ messagesByConversation: any[] }>(
      MESSAGES_QUERY,
      { conversationId, limit, before: before ?? null }
    );
    return (messagesByConversation ?? []).map((row) => this.mapMessage(row));
  }

  async startConversation(targetId: string): Promise<Conversation> {
    const { startConversation } = await this.gql.request<{ startConversation: any }>(
      START_CONVERSATION_MUTATION,
      { targetId }
    );
    return this.mapConversation(startConversation);
  }

  async sendMessage(conversationId: string, body: string): Promise<Message> {
    const { sendMessage } = await this.gql.request<{ sendMessage: any }>(
      SEND_MESSAGE_MUTATION,
      { conversationId, body: body.trim() }
    );
    return this.mapMessage(sendMessage);
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
    };
  }

  private mapMessage(row: any): Message {
    return {
      id: row.id,
      conversation_id: row.conversation_id,
      sender_id: row.sender_id,
      body: row.body ?? '',
      created_at: row.created_at,
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
