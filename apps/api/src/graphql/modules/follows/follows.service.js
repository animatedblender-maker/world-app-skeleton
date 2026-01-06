import { pool } from '../../../db.ts';
export class FollowsService {
    async counts(userId) {
        const { rows } = await pool.query(`
      select
        (select count(*)::int from public.user_follows where following_id = $1) as followers,
        (select count(*)::int from public.user_follows where follower_id = $1) as following
      `, [userId]);
        return {
            followers: rows[0]?.followers ?? 0,
            following: rows[0]?.following ?? 0,
        };
    }
    async followingIds(followerId) {
        const { rows } = await pool.query(`select following_id from public.user_follows where follower_id = $1`, [followerId]);
        return rows.map((row) => row.following_id);
    }
    async isFollowing(followerId, targetId) {
        if (followerId === targetId)
            return false;
        const { rows } = await pool.query(`select 1 from public.user_follows where follower_id = $1 and following_id = $2 limit 1`, [followerId, targetId]);
        return rows.length > 0;
    }
    async follow(followerId, targetId) {
        if (followerId === targetId)
            return;
        await pool.query(`
      insert into public.user_follows (follower_id, following_id)
      values ($1, $2)
      on conflict do nothing
      `, [followerId, targetId]);
    }
    async unfollow(followerId, targetId) {
        if (followerId === targetId)
            return;
        await pool.query(`delete from public.user_follows where follower_id = $1 and following_id = $2`, [followerId, targetId]);
    }
}
