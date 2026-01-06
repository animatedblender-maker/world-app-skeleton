import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';

@Injectable({ providedIn: 'root' })
export class FollowService {
  constructor(private gql: GqlService) {}

  async counts(userId: string): Promise<{ followers: number; following: number }> {
    const query = `
      query FollowCounts($userId: ID!) {
        followCounts(user_id: $userId) {
          followers
          following
        }
      }
    `;
    const { followCounts } = await this.gql.request<{ followCounts: { followers: number; following: number } }>(query, {
      userId,
    });
    return followCounts ?? { followers: 0, following: 0 };
  }

  async isFollowing(meId: string, targetId: string): Promise<boolean> {
    if (meId === targetId) return false;
    const query = `
      query IsFollowing($target: ID!) {
        isFollowing(user_id: $target)
      }
    `;
    const { isFollowing } = await this.gql.request<{ isFollowing: boolean }>(query, {
      target: targetId,
    });
    return !!isFollowing;
  }

  async follow(meId: string, targetId: string): Promise<void> {
    if (meId === targetId) return;
    const mutation = `
      mutation FollowUser($target: ID!) {
        followUser(target_id: $target)
      }
    `;
    await this.gql.request(mutation, { target: targetId });
  }

  async unfollow(meId: string, targetId: string): Promise<void> {
    if (meId === targetId) return;
    const mutation = `
      mutation UnfollowUser($target: ID!) {
        unfollowUser(target_id: $target)
      }
    `;
    await this.gql.request(mutation, { target: targetId });
  }

  async listFollowingIds(meId: string): Promise<string[]> {
    void meId;
    const query = `
      query FollowingIds {
        followingIds
      }
    `;
    const { followingIds } = await this.gql.request<{ followingIds: string[] }>(query);
    return followingIds ?? [];
  }
}
