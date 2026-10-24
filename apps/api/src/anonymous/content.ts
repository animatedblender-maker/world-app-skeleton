import { pool } from '../db.js';
import { canAccess } from './policy.js';
import { getSpaceById } from './spaces.js';
import type { AnonymousProfilePublic } from './identity.js';
import { withResolvedMedia, withResolvedMediaMany } from './media.js';

export type PostPublic = {
  id: string;
  space_id: string;
  space_slug?: string;
  space_title?: string;
  author: { id: string; username: string; avatar_seed: string };
  title: string | null;
  body: string;
  state: string;
  score: number;
  comment_count: number;
  created_at: string;
  edited_at: string | null;
  my_vote?: number;
  media_type?: string | null;
  media_url?: string | null;
  thumb_url?: string | null;
};

export type CommentPublic = {
  id: string;
  post_id: string;
  parent_id: string | null;
  author: { id: string; username: string; avatar_seed: string };
  body: string;
  depth: number;
  state: string;
  score: number;
  created_at: string;
  my_vote?: number;
};

function iso(v: Date | string | null | undefined): string | null {
  if (v == null) return null;
  return v instanceof Date ? v.toISOString() : String(v);
}

export async function listSpacePosts(opts: {
  profile: AnonymousProfilePublic;
  spaceId: string;
  sort: string;
  cursor?: string | null;
  limit: number;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true; posts: PostPublic[]; next_cursor: string | null }
  | { ok: false; code: string; reason: string; status: number }
> {
  const space = await getSpaceById(opts.spaceId);
  if (!space) {
    return { ok: false, code: 'not_found', reason: 'Space not found.', status: 404 };
  }
  const decision = await canAccess({
    profile: {
      id: opts.profile.id,
      state: opts.profile.state,
      age_attested_at: opts.profile.age_attested_at,
    },
    space,
    action: 'VIEW_CONTENT',
    ageEligible: opts.ageEligible,
    ageAttested: opts.ageAttested,
  });
  if (!decision.allow) {
    return { ok: false, code: decision.code, reason: decision.reason, status: 403 };
  }

  const limit = Math.min(Math.max(opts.limit || 20, 1), 50);
  const sort = (opts.sort || 'new').toLowerCase();
  let order = `p.created_at desc, p.id desc`;
  if (sort === 'top') order = `p.score desc, p.created_at desc, p.id desc`;
  if (sort === 'hot') {
    order = `(p.score::float / power(extract(epoch from (now() - p.created_at))/3600.0 + 2.0, 1.5)) desc, p.created_at desc`;
  }

  const params: unknown[] = [opts.spaceId, opts.profile.id];
  let cursorClause = '';
  if (opts.cursor) {
    try {
      const raw = Buffer.from(opts.cursor, 'base64url').toString('utf8');
      const [created_at, id] = raw.split('|');
      if (created_at && id) {
        params.push(created_at, id);
        cursorClause = ` and (p.created_at, p.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
      }
    } catch {
      /* ignore bad cursor */
    }
  }
  params.push(limit + 1);

  const { rows } = await pool.query<any>(
    `
    select p.id, p.space_id, p.title, p.body, p.state, p.score, p.comment_count,
           p.created_at, p.edited_at, p.media_type, p.media_url, p.thumb_url,
           a.id as author_id, a.username as author_username, a.avatar_seed as author_avatar_seed,
           coalesce(v.value, 0) as my_vote
    from anonymous.posts p
    join anonymous.profiles a on a.id = p.author_profile_id
    left join anonymous.votes v
      on v.target_type = 'post' and v.target_id = p.id and v.anon_profile_id = $2::uuid
    left join anonymous.blocks b
      on b.blocker_profile_id = $2::uuid and b.blocked_profile_id = p.author_profile_id
    where p.space_id = $1::uuid
      and p.state = 'active'
      and b.id is null
      ${cursorClause}
    order by ${order}
    limit $${params.length}
    `,
    params
  );

  let page = rows.slice(0, limit);

  // First page: pin the viewer's own recent posts so Hot score-0 cards don't vanish.
  if (!opts.cursor) {
    const { rows: own } = await pool.query<any>(
      `
      select p.id, p.space_id, p.title, p.body, p.state, p.score, p.comment_count,
             p.created_at, p.edited_at, p.media_type, p.media_url, p.thumb_url,
             a.id as author_id, a.username as author_username, a.avatar_seed as author_avatar_seed,
             coalesce(v.value, 0) as my_vote
      from anonymous.posts p
      join anonymous.profiles a on a.id = p.author_profile_id
      left join anonymous.votes v
        on v.target_type = 'post' and v.target_id = p.id and v.anon_profile_id = $2::uuid
      where p.space_id = $1::uuid
        and p.author_profile_id = $2::uuid
        and p.state = 'active'
        and p.created_at > now() - interval '3 days'
      order by p.created_at desc
      limit 3
      `,
      [opts.spaceId, opts.profile.id]
    );
    if (own.length) {
      const ownIds = new Set(own.map((r: any) => String(r.id)));
      page = [...own, ...page.filter((r: any) => !ownIds.has(String(r.id)))].slice(0, limit);
    }
  }

  const posts: PostPublic[] = await withResolvedMediaMany(
    page.map((r) => ({
      id: r.id,
      space_id: r.space_id,
      author: {
        id: r.author_id,
        username: r.author_username,
        avatar_seed: r.author_avatar_seed,
      },
      title: r.title,
      body: r.body,
      state: r.state,
      score: Number(r.score) || 0,
      comment_count: Number(r.comment_count) || 0,
      created_at: iso(r.created_at)!,
      edited_at: iso(r.edited_at),
      my_vote: Number(r.my_vote) || 0,
      media_type: r.media_type ?? null,
      media_url: r.media_url ?? null,
      thumb_url: r.thumb_url ?? null,
    }))
  );

  let next_cursor: string | null = null;
  if (rows.length > limit) {
    const last = page[page.length - 1];
    next_cursor = Buffer.from(`${iso(last.created_at)}|${last.id}`, 'utf8').toString(
      'base64url'
    );
  }
  return { ok: true, posts, next_cursor };
}

export async function createPost(opts: {
  profile: AnonymousProfilePublic;
  spaceId: string;
  title?: string;
  body: string;
  mediaType?: string | null;
  mediaUrl?: string | null;
  thumbUrl?: string | null;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true; post: PostPublic }
  | { ok: false; code: string; reason: string; status: number }
> {
  const space = await getSpaceById(opts.spaceId);
  if (!space) {
    return { ok: false, code: 'not_found', reason: 'Space not found.', status: 404 };
  }
  const decision = await canAccess({
    profile: {
      id: opts.profile.id,
      state: opts.profile.state,
      age_attested_at: opts.profile.age_attested_at,
    },
    space,
    action: 'POST',
    ageEligible: opts.ageEligible,
    ageAttested: opts.ageAttested,
  });
  if (!decision.allow) {
    return { ok: false, code: decision.code, reason: decision.reason, status: 403 };
  }

  const body = String(opts.body || '').trim().slice(0, 10000);
  const title = opts.title != null ? String(opts.title).trim().slice(0, 200) : null;
  const mediaTypeRaw = opts.mediaType != null ? String(opts.mediaType).trim().toLowerCase() : '';
  let mediaType =
    mediaTypeRaw === 'image' || mediaTypeRaw === 'video' || mediaTypeRaw === 'gif'
      ? mediaTypeRaw
      : null;
  let mediaUrl =
    opts.mediaUrl != null && String(opts.mediaUrl).trim()
      ? String(opts.mediaUrl).trim().slice(0, 2000)
      : null;
  const thumbUrl =
    opts.thumbUrl != null && String(opts.thumbUrl).trim()
      ? String(opts.thumbUrl).trim().slice(0, 2000)
      : null;
  // Infer type from URL when the client sent a URL without media_type.
  if (mediaUrl && !mediaType) {
    const lower = mediaUrl.toLowerCase();
    if (/\.(mp4|mov|webm|m4v)(\?|$)/i.test(lower) || lower.includes('/video')) {
      mediaType = 'video';
    } else if (/\.(gif)(\?|$)/i.test(lower)) {
      mediaType = 'gif';
    } else if (/\.(jpe?g|png|webp|heic)(\?|$)/i.test(lower) || lower.includes('/object/public/posts/')) {
      mediaType = 'image';
    }
  }
  if (!body && !title && !mediaUrl) {
    return {
      ok: false,
      code: 'empty',
      reason: 'Write something or attach a photo/video.',
      status: 400,
    };
  }
  if (mediaUrl && !mediaType) {
    return {
      ok: false,
      code: 'bad_media',
      reason: 'media_type required with media_url.',
      status: 400,
    };
  }

  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows } = await client.query<any>(
      `
      insert into anonymous.posts (
        space_id, author_profile_id, title, body, media_type, media_url, thumb_url
      )
      values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7)
      returning id, space_id, title, body, state, score, comment_count, created_at, edited_at,
                media_type, media_url, thumb_url
      `,
      [
        space.id,
        opts.profile.id,
        title || null,
        body || title || '',
        mediaType,
        mediaUrl,
        thumbUrl,
      ]
    );
    await client.query(
      `update anonymous.spaces set post_count = post_count + 1, updated_at = now() where id = $1::uuid`,
      [space.id]
    );
    await client.query('commit');
    const r = rows[0];
    const post = await withResolvedMedia({
      id: r.id,
      space_id: r.space_id,
      space_slug: space.slug,
      space_title: space.title,
      author: {
        id: opts.profile.id,
        username: opts.profile.username,
        avatar_seed: opts.profile.avatar_seed,
      },
      title: r.title,
      body: r.body,
      state: r.state,
      score: 0,
      comment_count: 0,
      created_at: iso(r.created_at)!,
      edited_at: null,
      my_vote: 0,
      media_type: r.media_type ?? null,
      media_url: r.media_url ?? null,
      thumb_url: r.thumb_url ?? null,
    });
    return { ok: true, post };
  } catch (err) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    throw err;
  } finally {
    client.release();
  }
}

export async function getPost(opts: {
  profile: AnonymousProfilePublic;
  postId: string;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true; post: PostPublic }
  | { ok: false; code: string; reason: string; status: number }
> {
  const { rows } = await pool.query<any>(
    `
    select p.id, p.space_id, p.title, p.body, p.state, p.score, p.comment_count,
           p.created_at, p.edited_at, p.media_type, p.media_url, p.thumb_url,
           s.slug as space_slug, s.title as space_title,
           a.id as author_id, a.username as author_username, a.avatar_seed as author_avatar_seed,
           coalesce(v.value, 0) as my_vote
    from anonymous.posts p
    join anonymous.spaces s on s.id = p.space_id
    join anonymous.profiles a on a.id = p.author_profile_id
    left join anonymous.votes v
      on v.target_type = 'post' and v.target_id = p.id and v.anon_profile_id = $2::uuid
    where p.id = $1::uuid
    limit 1
    `,
    [opts.postId, opts.profile.id]
  );
  const r = rows[0];
  if (!r || r.state === 'deleted') {
    return { ok: false, code: 'not_found', reason: 'Post not found.', status: 404 };
  }
  const space = await getSpaceById(r.space_id);
  if (!space) {
    return { ok: false, code: 'not_found', reason: 'Post not found.', status: 404 };
  }
  const decision = await canAccess({
    profile: {
      id: opts.profile.id,
      state: opts.profile.state,
      age_attested_at: opts.profile.age_attested_at,
    },
    space,
    action: 'VIEW_CONTENT',
    ageEligible: opts.ageEligible,
    ageAttested: opts.ageAttested,
  });
  if (!decision.allow) {
    return { ok: false, code: decision.code, reason: decision.reason, status: 403 };
  }

  const post = await withResolvedMedia({
    id: r.id,
    space_id: r.space_id,
    space_slug: r.space_slug,
    space_title: r.space_title,
    author: {
      id: r.author_id,
      username: r.author_username,
      avatar_seed: r.author_avatar_seed,
    },
    title: r.title,
    body: r.body,
    state: r.state,
    score: Number(r.score) || 0,
    comment_count: Number(r.comment_count) || 0,
    created_at: iso(r.created_at)!,
    edited_at: iso(r.edited_at),
    my_vote: Number(r.my_vote) || 0,
    media_type: r.media_type ?? null,
    media_url: r.media_url ?? null,
    thumb_url: r.thumb_url ?? null,
  });

  return {
    ok: true,
    post,
  };
}

export async function createComment(opts: {
  profile: AnonymousProfilePublic;
  postId: string;
  body: string;
  parentId?: string | null;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true; comment: CommentPublic }
  | { ok: false; code: string; reason: string; status: number }
> {
  const postRes = await getPost(opts);
  if (!postRes.ok) return postRes as any;
  const space = await getSpaceById(postRes.post.space_id);
  if (!space) {
    return { ok: false, code: 'not_found', reason: 'Space not found.', status: 404 };
  }
  const decision = await canAccess({
    profile: {
      id: opts.profile.id,
      state: opts.profile.state,
      age_attested_at: opts.profile.age_attested_at,
    },
    space,
    action: 'COMMENT',
    ageEligible: opts.ageEligible,
    ageAttested: opts.ageAttested,
  });
  if (!decision.allow) {
    return { ok: false, code: decision.code, reason: decision.reason, status: 403 };
  }

  const body = String(opts.body || '').trim().slice(0, 5000);
  if (!body) {
    return { ok: false, code: 'empty', reason: 'Comment body required.', status: 400 };
  }

  let depth = 0;
  let parentId: string | null = opts.parentId ? String(opts.parentId) : null;
  if (parentId) {
    const { rows: parents } = await pool.query<{ depth: number; post_id: string; state: string }>(
      `select depth, post_id, state from anonymous.comments where id = $1::uuid limit 1`,
      [parentId]
    );
    const parent = parents[0];
    if (!parent || parent.post_id !== opts.postId || parent.state !== 'active') {
      return { ok: false, code: 'bad_parent', reason: 'Invalid parent comment.', status: 400 };
    }
    depth = Number(parent.depth) + 1;
    if (depth > 8) {
      return { ok: false, code: 'depth_exceeded', reason: 'Reply depth limit.', status: 400 };
    }
  }

  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows } = await client.query<any>(
      `
      insert into anonymous.comments (post_id, parent_comment_id, author_profile_id, body, depth)
      values ($1::uuid, $2::uuid, $3::uuid, $4, $5)
      returning id, post_id, parent_comment_id, body, depth, state, score, created_at
      `,
      [opts.postId, parentId, opts.profile.id, body, depth]
    );
    await client.query(
      `update anonymous.posts set comment_count = comment_count + 1, updated_at = now() where id = $1::uuid`,
      [opts.postId]
    );
    await client.query('commit');
    const r = rows[0];
    return {
      ok: true,
      comment: {
        id: r.id,
        post_id: r.post_id,
        parent_id: r.parent_comment_id,
        author: {
          id: opts.profile.id,
          username: opts.profile.username,
          avatar_seed: opts.profile.avatar_seed,
        },
        body: r.body,
        depth: r.depth,
        state: r.state,
        score: 0,
        created_at: iso(r.created_at)!,
        my_vote: 0,
      },
    };
  } catch (err) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    throw err;
  } finally {
    client.release();
  }
}

export async function listComments(opts: {
  profile: AnonymousProfilePublic;
  postId: string;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true; comments: CommentPublic[] }
  | { ok: false; code: string; reason: string; status: number }
> {
  const postRes = await getPost(opts);
  if (!postRes.ok) return postRes as any;

  const { rows } = await pool.query<any>(
    `
    select c.id, c.post_id, c.parent_comment_id, c.body, c.depth, c.state, c.score, c.created_at,
           a.id as author_id, a.username as author_username, a.avatar_seed as author_avatar_seed,
           coalesce(v.value, 0) as my_vote
    from anonymous.comments c
    join anonymous.profiles a on a.id = c.author_profile_id
    left join anonymous.votes v
      on v.target_type = 'comment' and v.target_id = c.id and v.anon_profile_id = $2::uuid
    left join anonymous.blocks b
      on b.blocker_profile_id = $2::uuid and b.blocked_profile_id = c.author_profile_id
    where c.post_id = $1::uuid
      and c.state = 'active'
      and b.id is null
    order by c.created_at asc, c.id asc
    limit 500
    `,
    [opts.postId, opts.profile.id]
  );

  return {
    ok: true,
    comments: rows.map((r) => ({
      id: r.id,
      post_id: r.post_id,
      parent_id: r.parent_comment_id,
      author: {
        id: r.author_id,
        username: r.author_username,
        avatar_seed: r.author_avatar_seed,
      },
      body: r.body,
      depth: Number(r.depth) || 0,
      state: r.state,
      score: Number(r.score) || 0,
      created_at: iso(r.created_at)!,
      my_vote: Number(r.my_vote) || 0,
    })),
  };
}

export async function castVote(opts: {
  profile: AnonymousProfilePublic;
  targetType: string;
  targetId: string;
  value: number;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true; value: number; score: number }
  | { ok: false; code: string; reason: string; status: number }
> {
  const targetType = opts.targetType === 'comment' ? 'comment' : 'post';
  const value = opts.value === 1 || opts.value === -1 ? opts.value : 0;

  let spaceId: string | null = null;
  if (targetType === 'post') {
    const { rows } = await pool.query<{ space_id: string; state: string }>(
      `select space_id, state from anonymous.posts where id = $1::uuid limit 1`,
      [opts.targetId]
    );
    if (!rows[0] || rows[0].state !== 'active') {
      return { ok: false, code: 'not_found', reason: 'Target not found.', status: 404 };
    }
    spaceId = rows[0].space_id;
  } else {
    const { rows } = await pool.query<{ space_id: string; state: string }>(
      `
      select p.space_id, c.state
      from anonymous.comments c
      join anonymous.posts p on p.id = c.post_id
      where c.id = $1::uuid
      limit 1
      `,
      [opts.targetId]
    );
    if (!rows[0] || rows[0].state !== 'active') {
      return { ok: false, code: 'not_found', reason: 'Target not found.', status: 404 };
    }
    spaceId = rows[0].space_id;
  }

  const space = await getSpaceById(spaceId!);
  if (!space) {
    return { ok: false, code: 'not_found', reason: 'Space not found.', status: 404 };
  }
  const decision = await canAccess({
    profile: {
      id: opts.profile.id,
      state: opts.profile.state,
      age_attested_at: opts.profile.age_attested_at,
    },
    space,
    action: 'VOTE',
    ageEligible: opts.ageEligible,
    ageAttested: opts.ageAttested,
  });
  if (!decision.allow) {
    return { ok: false, code: decision.code, reason: decision.reason, status: 403 };
  }

  const client = await pool.connect();
  try {
    await client.query('begin');
    const prev = await client.query<{ value: number }>(
      `
      select value from anonymous.votes
      where target_type = $1 and target_id = $2::uuid and anon_profile_id = $3::uuid
      limit 1
      `,
      [targetType, opts.targetId, opts.profile.id]
    );
    const oldVal = prev.rows[0]?.value ?? 0;

    if (value === 0) {
      await client.query(
        `delete from anonymous.votes
         where target_type = $1 and target_id = $2::uuid and anon_profile_id = $3::uuid`,
        [targetType, opts.targetId, opts.profile.id]
      );
    } else {
      await client.query(
        `
        insert into anonymous.votes (target_type, target_id, anon_profile_id, value)
        values ($1, $2::uuid, $3::uuid, $4)
        on conflict (target_type, target_id, anon_profile_id) do update
          set value = excluded.value, updated_at = now()
        `,
        [targetType, opts.targetId, opts.profile.id, value]
      );
    }

    const delta = value - oldVal;
    let score = 0;
    if (targetType === 'post') {
      const { rows } = await client.query<{ score: number }>(
        `update anonymous.posts set score = score + $2, updated_at = now()
         where id = $1::uuid returning score`,
        [opts.targetId, delta]
      );
      score = Number(rows[0]?.score) || 0;
    } else {
      const { rows } = await client.query<{ score: number }>(
        `update anonymous.comments set score = score + $2
         where id = $1::uuid returning score`,
        [opts.targetId, delta]
      );
      score = Number(rows[0]?.score) || 0;
    }
    await client.query('commit');
    return { ok: true, value, score };
  } catch (err) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    throw err;
  } finally {
    client.release();
  }
}
