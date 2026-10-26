import { Router, type Request, type Response, type NextFunction } from 'express';
import { pool } from '../db.js';
import { getUserFromRequest, type AuthedUser } from '../auth/request-user.js';
import {
  attestAge,
  getOrCreateProfile,
  getProfileForAccount,
  sessionForAccount,
} from './identity.js';
import { generateSafeUsername, validateGeneratedCandidate } from './usernames.js';
import {
  createFreeSpace,
  getSpaceDetail,
  joinSpace,
  leaveSpace,
  listSpaces,
} from './spaces.js';
import {
  castVote,
  createComment,
  createPost,
  getPost,
  listComments,
  listSpacePosts,
} from './content.js';
import { getFeed } from './feed.js';
import { blockProfile, createReport } from './moderation.js';
import { checkoutStart, creatorEarnings } from './billing-scaffold.js';
import { isPaidEnabled } from './policy.js';
import {
  listAnonymousNotifications,
  markAllAnonymousNotificationsRead,
  markAnonymousNotificationRead,
} from './notifications.js';

type AuthedReq = Request & { user?: AuthedUser | null };

async function requireUser(req: AuthedReq, res: Response, next: NextFunction) {
  const user = await getUserFromRequest(req);
  if (!user?.id) {
    return res.status(401).json({ ok: false, error: 'unauthenticated', code: 'unauthenticated' });
  }
  req.user = user;
  return next();
}

async function gateAnonymous(accountId: string) {
  const session = await sessionForAccount(accountId);
  return session;
}

/** Simple per-account sliding window for Anonymous writes (abuse / spam). */
const writeBuckets = new Map<string, number[]>();
function rateLimitWrites(maxPerMinute = 30) {
  return (req: AuthedReq, res: Response, next: NextFunction) => {
    const id = req.user?.id;
    if (!id) return next();
    const now = Date.now();
    const windowMs = 60_000;
    const prev = (writeBuckets.get(id) ?? []).filter((t) => now - t < windowMs);
    if (prev.length >= maxPerMinute) {
      return res.status(429).json({
        ok: false,
        error: 'rate_limited',
        code: 'rate_limited',
        reason: 'Too many Anonymous writes. Try again shortly.',
      });
    }
    prev.push(now);
    writeBuckets.set(id, prev);
    return next();
  };
}

export function createAnonymousRouter(): Router {
  const router = Router();
  router.use(requireUser);
  router.use((req, res, next) => {
    if (req.method === 'POST' || req.method === 'PUT' || req.method === 'PATCH' || req.method === 'DELETE') {
      return rateLimitWrites(40)(req as AuthedReq, res, next);
    }
    return next();
  });

  router.get('/session', async (req: AuthedReq, res: Response) => {
    try {
      const session = await gateAnonymous(req.user!.id);
      const birthdateMissing =
        session.code === 'birthdate_required'
        || session.code === 'birthdate_missing'
        || session.code === 'under_18';
      const suspended = String(session.profile?.state ?? '').toLowerCase() === 'suspended';
      return res.json({
        ok: true,
        // Dual keys — iOS AnonymousSession reads eligibleAdult / ageAttested (snake or camel).
        eligible: session.eligible,
        eligible_adult: session.eligible,
        eligibleAdult: session.eligible,
        reason: session.reason,
        code: session.code,
        profile: session.profile,
        age_attested: session.age_attested,
        ageAttested: session.age_attested,
        birthdate_missing: birthdateMissing,
        birthdateMissing,
        suspended,
        paid_enabled: session.paid_enabled,
        paidEnabled: session.paid_enabled,
      });
    } catch (err: any) {
      const msg = String(err?.message ?? err ?? '');
      console.error('[anonymous/session]', msg);
      // Schema not migrated yet — clearer than opaque session_failed.
      if (/relation .* does not exist|schema .* does not exist/i.test(msg)) {
        return res.status(503).json({
          ok: false,
          error: 'schema_missing',
          code: 'schema_missing',
          message: 'Masquerade database migration is not applied yet.',
        });
      }
      return res.status(500).json({
        ok: false,
        error: 'session_failed',
        code: 'session_failed',
        message: msg.slice(0, 180),
      });
    }
  });

  router.post('/attest', async (req: AuthedReq, res: Response) => {
    try {
      if (req.body?.attest !== true && req.body?.confirmed !== true) {
        return res.status(400).json({
          ok: false,
          error: 'attest_required',
          code: 'attest_required',
          reason: 'Body must include { attest: true }.',
        });
      }
      const result = await attestAge(req.user!.id);
      if (!result.ok) {
        return res.status(403).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({
        ok: true,
        profile: result.profile,
        age_attested: result.age_attested,
      });
    } catch (err: any) {
      console.error('[anonymous/attest]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'attest_failed' });
    }
  });

  async function handleProfileClaim(req: AuthedReq, res: Response) {
    try {
      const session = await gateAnonymous(req.user!.id);
      if (!session.eligible) {
        return res.status(403).json({
          ok: false,
          error: session.code,
          code: session.code,
          reason: session.reason,
        });
      }
      const regenerate = req.body?.regenerate === true;
      const username =
        typeof req.body?.username === 'string' ? String(req.body.username).trim() : null;
      const result = await getOrCreateProfile(req.user!.id, { regenerate, username });
      if (!result.ok) {
        const status =
          result.code === 'username_immutable' || result.code === 'username_taken'
            ? 409
            : result.code === 'username_invalid' ||
                result.code === 'invalid_syntax' ||
                result.code === 'reserved' ||
                result.code === 'disallowed' ||
                result.code === 'real_name_heuristic'
              ? 422
              : 403;
        return res.status(status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
          message: result.reason,
        });
      }
      return res.json({ ok: true, profile: result.profile, created: result.created });
    } catch (err: any) {
      console.error('[anonymous/profile]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'profile_failed' });
    }
  }

  router.post('/profile', handleProfileClaim);
  // Alias — older iOS builds posted /profile/claim.
  router.post('/profile/claim', handleProfileClaim);

  async function handleProfileMe(req: AuthedReq, res: Response) {
    try {
      const session = await gateAnonymous(req.user!.id);
      if (!session.eligible) {
        return res.status(403).json({
          ok: false,
          error: session.code,
          code: session.code,
          reason: session.reason,
        });
      }
      const profile = await getProfileForAccount(req.user!.id);
      if (!profile) {
        return res.status(404).json({
          ok: false,
          error: 'profile_required',
          code: 'profile_required',
          reason: 'Claim an Anonymous username first.',
        });
      }
      return res.json({ ok: true, profile, age_attested: !!profile.age_attested_at });
    } catch (err: any) {
      console.error('[anonymous/profile/me]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'profile_failed' });
    }
  }

  router.get('/profile/me', handleProfileMe);
  // Alias — older iOS builds used /me.
  router.get('/me', handleProfileMe);

  router.get('/username/suggest', async (req: AuthedReq, res: Response) => {
    try {
      const session = await gateAnonymous(req.user!.id);
      if (!session.eligible) {
        return res.status(403).json({
          ok: false,
          error: session.code,
          code: session.code,
          reason: session.reason,
        });
      }
      // Endless recommendations: large vocab × suffix, skip taken + tombstoned.
      const tried = new Set<string>();
      for (let i = 0; i < 80; i++) {
        const candidate = generateSafeUsername();
        const validated = validateGeneratedCandidate(candidate);
        if (!validated.ok) continue;
        if (tried.has(validated.normalized)) continue;
        tried.add(validated.normalized);
        const taken = await pool.query(
          `
          select 1
          where exists (
            select 1 from anonymous.profiles
            where normalized_username = $1
          )
          or exists (
            select 1 from anonymous.username_tombstones
            where normalized_username = $1
          )
          limit 1
          `,
          [validated.normalized]
        );
        if (taken.rows.length) continue;
        return res.json({
          ok: true,
          username: validated.normalized,
          suggestedUsername: validated.normalized,
          suggested_username: validated.normalized,
        });
      }
      return res.status(500).json({
        ok: false,
        error: 'username_unavailable',
        code: 'username_unavailable',
        reason: 'Could not suggest a username. Try again.',
      });
    } catch (err: any) {
      console.error('[anonymous/username/suggest]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'suggest_failed' });
    }
  });

  async function requireReady(req: AuthedReq, res: Response) {
    const session = await gateAnonymous(req.user!.id);
    if (!session.eligible) {
      res.status(403).json({
        ok: false,
        error: session.code,
        code: session.code,
        reason: session.reason,
      });
      return null;
    }
    if (!session.profile) {
      res.status(403).json({
        ok: false,
        error: 'profile_required',
        code: 'profile_required',
        reason: 'Claim an Anonymous username first.',
      });
      return null;
    }
    if (!session.age_attested) {
      res.status(403).json({
        ok: false,
        error: 'age_attestation_required',
        code: 'age_attestation_required',
        reason: 'Age attestation required.',
      });
      return null;
    }
    return session;
  }

  router.get('/spaces', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const filter = String(req.query.filter ?? 'popular');
      const cursor = req.query.cursor ? String(req.query.cursor) : null;
      const limit = Number(req.query.limit ?? 20);
      const result = await listSpaces({
        profile: session.profile,
        filter,
        cursor,
        limit,
        ageEligible: true,
        ageAttested: true,
      });
      return res.json({ ok: true, ...result });
    } catch (err: any) {
      console.error('[anonymous/spaces]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'spaces_failed' });
    }
  });

  router.get('/spaces/:slug', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await getSpaceDetail(
        String(req.params.slug),
        session.profile,
        true,
        true
      );
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true, space: result.space });
    } catch (err: any) {
      console.error('[anonymous/spaces/:slug]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'space_failed' });
    }
  });

  router.post('/spaces', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await createFreeSpace({
        profile: session.profile!,
        title: String(req.body?.title ?? ''),
        description: req.body?.description,
        category: req.body?.category,
        slug: req.body?.slug,
        visibility: req.body?.visibility,
        rules: Array.isArray(req.body?.rules) ? req.body.rules.map(String) : undefined,
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.status(201).json({ ok: true, space: result.space });
    } catch (err: any) {
      console.error('[anonymous/spaces create]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'create_space_failed' });
    }
  });

  router.post('/spaces/:id/join', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await joinSpace({
        profile: session.profile!,
        spaceId: String(req.params.id),
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true, membership: result.membership });
    } catch (err: any) {
      console.error('[anonymous/join]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'join_failed' });
    }
  });

  router.post('/spaces/:id/leave', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await leaveSpace({
        profile: session.profile!,
        spaceId: String(req.params.id),
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true });
    } catch (err: any) {
      console.error('[anonymous/leave]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'leave_failed' });
    }
  });

  router.get('/spaces/:id/posts', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await listSpacePosts({
        profile: session.profile!,
        spaceId: String(req.params.id),
        sort: String(req.query.sort ?? 'new'),
        cursor: req.query.cursor ? String(req.query.cursor) : null,
        limit: Number(req.query.limit ?? 20),
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true, posts: result.posts, next_cursor: result.next_cursor });
    } catch (err: any) {
      console.error('[anonymous/space posts]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'posts_failed' });
    }
  });

  router.post('/spaces/:id/posts', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await createPost({
        profile: session.profile!,
        spaceId: String(req.params.id),
        title: req.body?.title,
        body: String(req.body?.body ?? ''),
        mediaType: req.body?.media_type ?? req.body?.mediaType ?? null,
        mediaUrl: req.body?.media_url ?? req.body?.mediaUrl ?? null,
        thumbUrl: req.body?.thumb_url ?? req.body?.thumbUrl ?? null,
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.status(201).json({ ok: true, post: result.post });
    } catch (err: any) {
      console.error('[anonymous/create post]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'create_post_failed' });
    }
  });

  router.get('/posts/:id', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await getPost({
        profile: session.profile!,
        postId: String(req.params.id),
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true, post: result.post });
    } catch (err: any) {
      console.error('[anonymous/post]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'post_failed' });
    }
  });

  router.post('/posts/:id/comments', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await createComment({
        profile: session.profile!,
        postId: String(req.params.id),
        body: String(req.body?.body ?? ''),
        parentId: req.body?.parent_id ?? null,
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.status(201).json({ ok: true, comment: result.comment });
    } catch (err: any) {
      console.error('[anonymous/comment]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'comment_failed' });
    }
  });

  router.get('/posts/:id/comments', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await listComments({
        profile: session.profile!,
        postId: String(req.params.id),
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true, comments: result.comments });
    } catch (err: any) {
      console.error('[anonymous/comments]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'comments_failed' });
    }
  });

  router.post('/votes', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await castVote({
        profile: session.profile!,
        targetType: String(req.body?.target_type ?? req.body?.targetType ?? ''),
        targetId: String(req.body?.target_id ?? req.body?.targetId ?? ''),
        value: Number(req.body?.value ?? 0),
        ageEligible: true,
        ageAttested: true,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true, value: result.value, score: result.score });
    } catch (err: any) {
      console.error('[anonymous/votes]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'vote_failed' });
    }
  });

  async function handleReport(req: AuthedReq, res: Response) {
    const session = await requireReady(req, res);
    if (!session) return;
    const result = await createReport({
      profile: session.profile!,
      targetType: String(req.body?.target_type ?? req.body?.targetType ?? ''),
      targetId: String(req.body?.target_id ?? req.body?.targetId ?? ''),
      reason: String(req.body?.reason ?? ''),
    });
    if (!result.ok) {
      return res.status(result.status).json({
        ok: false,
        error: result.code,
        code: result.code,
        reason: result.reason,
      });
    }
    return res.status(201).json({ ok: true, report_id: result.report_id });
  }

  router.post('/reports', async (req: AuthedReq, res: Response) => {
    try {
      return await handleReport(req, res);
    } catch (err: any) {
      console.error('[anonymous/reports]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'report_failed' });
    }
  });

  // Alias — older clients posted /report.
  router.post('/report', async (req: AuthedReq, res: Response) => {
    try {
      return await handleReport(req, res);
    } catch (err: any) {
      console.error('[anonymous/report]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'report_failed' });
    }
  });

  router.post('/blocks', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const blockedProfileId = String(
        req.body?.blocked_profile_id ?? req.body?.blockedProfileId ?? req.body?.profileId ?? ''
      ).trim();
      const result = await blockProfile({
        profile: session.profile!,
        blockedProfileId,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true });
    } catch (err: any) {
      console.error('[anonymous/blocks]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'block_failed' });
    }
  });

  // Alias — older clients posted /block with profileId.
  router.post('/block', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const blockedProfileId = String(
        req.body?.blocked_profile_id ?? req.body?.blockedProfileId ?? req.body?.profileId ?? ''
      ).trim();
      const result = await blockProfile({
        profile: session.profile!,
        blockedProfileId,
      });
      if (!result.ok) {
        return res.status(result.status).json({
          ok: false,
          error: result.code,
          code: result.code,
          reason: result.reason,
        });
      }
      return res.json({ ok: true });
    } catch (err: any) {
      console.error('[anonymous/block]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'block_failed' });
    }
  });

  router.get('/feed', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await getFeed({
        profile: session.profile!,
        sort: String(req.query.sort ?? 'for_you'),
        cursor: req.query.cursor ? String(req.query.cursor) : null,
        limit: Number(req.query.limit ?? 20),
      });
      return res.json({ ok: true, ...result });
    } catch (err: any) {
      console.error('[anonymous/feed]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'feed_failed' });
    }
  });

  router.get('/search', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const { searchMasquerade } = await import('./search.js');
      const result = await searchMasquerade({
        profile: session.profile!,
        q: String(req.query.q ?? ''),
        limit: Number(req.query.limit ?? 12),
      });
      return res.json({ ok: true, ...result });
    } catch (err: any) {
      console.error('[anonymous/search]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'search_failed' });
    }
  });

  router.get('/profiles/:username', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const { getProfileByUsername } = await import('./identity.js');
      const profile = await getProfileByUsername(String(req.params.username || ''));
      if (!profile) {
        return res.status(404).json({ ok: false, error: 'not_found', reason: 'Profile not found.' });
      }
      const counts = await pool.query<{ posts: string; spaces: string }>(
        `
        select
          (select count(*)::text from anonymous.posts p
             join anonymous.spaces s on s.id = p.space_id
            where p.author_profile_id = $1::uuid and p.state = 'active'
              and s.visibility = 'adult_public' and s.admission = 'free'
              and s.status in ('active','read_only')) as posts,
          (select count(*)::text from anonymous.space_memberships m
             join anonymous.spaces s on s.id = m.space_id
            where m.anon_profile_id = $1::uuid and m.state = 'active'
              and s.visibility = 'adult_public' and s.admission = 'free') as spaces
        `,
        [profile.id]
      );
      return res.json({
        ok: true,
        profile,
        post_count: Number(counts.rows[0]?.posts ?? 0) || 0,
        space_count: Number(counts.rows[0]?.spaces ?? 0) || 0,
      });
    } catch (err: any) {
      console.error('[anonymous/profiles/:username]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'profile_failed' });
    }
  });

  router.get('/profiles/:username/posts', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const { getProfileByUsername } = await import('./identity.js');
      const { listAuthorPosts } = await import('./content.js');
      const profile = await getProfileByUsername(String(req.params.username || ''));
      if (!profile) {
        return res.status(404).json({ ok: false, error: 'not_found', reason: 'Profile not found.' });
      }
      const result = await listAuthorPosts({
        viewer: session.profile!,
        authorProfileId: profile.id,
        cursor: req.query.cursor ? String(req.query.cursor) : null,
        limit: Number(req.query.limit ?? 24),
      });
      return res.json({ ok: true, ...result });
    } catch (err: any) {
      console.error('[anonymous/profiles/:username/posts]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'posts_failed' });
    }
  });

  router.get('/notifications', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const result = await listAnonymousNotifications({
        profileId: session.profile!.id,
        cursor: req.query.cursor ? String(req.query.cursor) : null,
        limit: Number(req.query.limit ?? 40),
      });
      return res.json({
        ok: true,
        notifications: result.notifications,
        next_cursor: result.next_cursor,
        unread_count: result.unread_count,
      });
    } catch (err: any) {
      console.error('[anonymous/notifications]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'notifications_failed' });
    }
  });

  router.post('/notifications/:id/read', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const id = String(req.params.id || '').trim();
      if (!id) {
        return res.status(400).json({ ok: false, error: 'invalid_id' });
      }
      const ok = await markAnonymousNotificationRead({
        profileId: session.profile!.id,
        notificationId: id,
      });
      return res.json({ ok: true, updated: ok });
    } catch (err: any) {
      console.error('[anonymous/notifications/read]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'notifications_read_failed' });
    }
  });

  router.post('/notifications/read-all', async (req: AuthedReq, res: Response) => {
    try {
      const session = await requireReady(req, res);
      if (!session) return;
      const updated = await markAllAnonymousNotificationsRead({
        profileId: session.profile!.id,
      });
      return res.json({ ok: true, updated });
    } catch (err: any) {
      console.error('[anonymous/notifications/read-all]', err?.message ?? err);
      return res.status(500).json({ ok: false, error: 'notifications_read_all_failed' });
    }
  });

  router.post('/checkout/start', async (req: AuthedReq, res: Response) => {
    const result = checkoutStart(req.body);
    return res.status(result.status).json({
      ok: false,
      error: result.code,
      code: result.code,
      reason: result.reason,
      paid_enabled: isPaidEnabled(),
    });
  });

  router.get('/creator/earnings', async (req: AuthedReq, res: Response) => {
    const result = creatorEarnings(
      req.query.space_id ? String(req.query.space_id) : undefined
    );
    return res.status(result.status).json({
      ok: false,
      error: result.code,
      code: result.code,
      reason: result.reason,
      paid_enabled: isPaidEnabled(),
    });
  });

  return router;
}

export const anonymousRouter = createAnonymousRouter();
