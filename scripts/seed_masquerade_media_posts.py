#!/usr/bin/env python3
"""
Seed Masquerade Spaces with image/video posts from R2 upload logs.

OffMyChest / Paranormal packs are text-only — media cards come from:
  HighlyStrange ← Memes (images) + Funny (images + videos)
  secrets       ← Funny GIFs/images (anonymous photo energy)

Uses apps/api/.env DATABASE_URL. Idempotent via source_ref.
Diverse seed personas + comment threads (same policy as text seeds).

Dry-run by default; pass --apply to write.
  MASQUERADE_MEDIA_LIMIT  (default 100000 — take every logged R2 pack)
"""

from __future__ import annotations

import json
import os
import random
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
API_ENV = ROOT / "apps" / "api" / ".env"
PACKS_ROOT = Path("/Volumes/MatteryaSSD/Development/RedditPosts")

# Private bucket. Persist durable r2: refs; API re-signs on read.
R2_BUCKET = "matterya-sparks"


def media_ref(env: Dict[str, str], key: str) -> str:
    clean = key.lstrip("/")
    return f"r2:{env.get('R2_BUCKET') or R2_BUCKET}/{clean}"


_CONFESS_TAG = re.compile(r"\[\s*CONFESS\s*#\s*\d+\s*\]\s*", re.I)
_CONFESS_BARE = re.compile(r"^\s*CONFESS\s*#\s*\d+\s*[:\-–—]?\s*", re.I | re.M)
_NUM_BRACKET = re.compile(r"^\s*\[\s*#?\s*\d+\s*\]\s*")


def strip_confess_number_tags(text: str) -> str:
    """Remove [CONFESS #01774] / CONFESS #N / leading [12] number tags."""
    if not text:
        return text
    out = _CONFESS_TAG.sub("", text)
    out = _CONFESS_BARE.sub("", out)
    out = _NUM_BRACKET.sub("", out)
    out = re.sub(r"[ \t]{2,}", " ", out).strip()
    return out or text.strip()

SOURCES = [
    # (space_slug, upload_log, local_folder, want_video, limit_share)
    # Shares are soft caps when LIMIT is below inventory; with LIMIT>=100k we take all.
    ("highlystrange", PACKS_ROOT / "uploaded_memes_r2.jsonl", PACKS_ROOT / "Memes", False, 0.55),
    ("highlystrange", PACKS_ROOT / "uploaded_funny_r2.jsonl", PACKS_ROOT / "Funny", True, 0.25),
    ("secrets", PACKS_ROOT / "uploaded_funny_r2.jsonl", PACKS_ROOT / "Funny", False, 0.20),
]

AVATAR_PREFIX = "seed-persona-v1:"
# Media dump is large (~50k). Reuse personas more heavily than text seeds so we
# do not stall creating tens of thousands of profiles over the pooler.
MAX_POSTS_PER_PERSONA = int(os.environ.get("MASQUERADE_MEDIA_POSTS_PER_PERSONA", "12"))
SECOND_POST_CHANCE = 0.55
# Keep media dump lean — text seed already attaches rich comment threads.
SEED_WITH_COMMENTS_CHANCE = float(os.environ.get("MASQUERADE_MEDIA_COMMENT_CHANCE", "0.12"))
MAX_SEED_COMMENTS = int(os.environ.get("MASQUERADE_MEDIA_MAX_COMMENTS", "4"))
LIMIT = int(os.environ.get("MASQUERADE_MEDIA_LIMIT", "100000"))
PERSONA_POOL = int(os.environ.get("MASQUERADE_MEDIA_PERSONA_POOL", "800"))

ADJECTIVES = [
    "quiet", "bright", "swift", "calm", "bold", "keen", "soft", "wild",
    "clear", "noble", "brave", "clever", "gentle", "lucky", "mellow", "nimble",
    "proud", "rapid", "silent", "steady", "sunny", "vivid", "witty", "zesty",
    "amber", "azure", "coral", "cosmic", "crimson", "distant", "frosty", "golden",
    "hidden", "ivory", "jade", "lunar", "misty", "neon", "orbit", "polar",
    "radiant", "silver", "solar", "steel", "tidal", "velvet", "violet", "winter",
]
NOUNS = [
    "orbit", "comet", "river", "forest", "harbor", "meadow", "nebula", "pebble",
    "phoenix", "quartz", "raven", "spark", "summit", "thunder", "valley", "willow",
    "anchor", "beacon", "canyon", "delta", "ember", "falcon", "glacier", "horizon",
    "island", "jasper", "kite", "lantern", "mirror", "nova", "oasis", "prism",
    "quill", "reef", "shadow", "temple", "umbra", "voyage", "whisper", "zenith",
    "archive", "brook", "cipher", "dusk", "echo", "fjord", "grove", "haven",
]

FALLBACK_COMMENT_BODIES = [
    "This is wild.",
    "I felt that.",
    "Okay this one got me.",
    "Saving this.",
    "Perfect timing.",
    "Lmao the comments will be good.",
    "Need more of these.",
    "Sending this to a friend.",
    "Mood.",
    "Unreal.",
]


def load_env(path: Path) -> Dict[str, str]:
    env = dict(os.environ)
    if not path.exists():
        return env
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def generate_safe_username() -> str:
    return f"{random.choice(ADJECTIVES)}_{random.choice(NOUNS)}_{random.randint(1000, 9999)}"


def clean_comment_text(raw: Any) -> str:
    t = str(raw or "").strip()
    if not t:
        return ""
    t = re.sub(r"^[\s•·]+", "", t)
    t = re.sub(r"^\d+\s*[smhdwy]\s+ago\s+", "", t, flags=re.I)
    t = re.sub(r"\s*Reply\s+Share\s*$", "", t, flags=re.I)
    # Matterya term: never Reddit "OP" — use Author.
    t = re.sub(r"\boriginal\s+poster\b", "author", t, flags=re.I)
    t = re.sub(r"\bOP\b", "Author", t)
    t = re.sub(r"\b[Oo]p\b", "Author", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t[:2000] if len(t) >= 4 else ""


def parse_ts(raw: Any) -> Optional[datetime]:
    if not raw:
        return None
    s = str(raw).strip()
    try:
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        return datetime.fromisoformat(s)
    except Exception:
        return None


def insert_persona(cur) -> Optional[Dict[str, Any]]:
    for _ in range(12):
        username = generate_safe_username()
        avatar = f"{AVATAR_PREFIX}{username}"
        cur.execute(
            """
            insert into anonymous.profiles (
              username, normalized_username, avatar_seed, state, age_attested_at
            )
            values (%s, %s, %s, 'active', now())
            on conflict (normalized_username) do nothing
            returning id::text as id, username
            """,
            (username, username, avatar),
        )
        row = cur.fetchone()
        if row:
            return {"id": row["id"], "username": row["username"], "post_count": 0}
    return None


def list_seed_personas(cur) -> List[Dict[str, Any]]:
    cur.execute(
        """
        select p.id::text as id, p.username,
               coalesce(pc.cnt, 0)::int as post_count
        from anonymous.profiles p
        left join (
          select author_profile_id, count(*)::int as cnt
          from anonymous.posts
          where state = 'active'
          group by author_profile_id
        ) pc on pc.author_profile_id = p.id
        where p.state = 'active'
          and p.avatar_seed like %s
          and p.username <> 'archive_whisper'
          and not exists (
            select 1 from identity_vault.account_anonymous_links al
            where al.anon_profile_id = p.id
            limit 1
          )
        order by post_count asc, p.created_at asc
        """,
        (f"{AVATAR_PREFIX}%",),
    )
    return list(cur.fetchall())


def ensure_seed_personas(cur, min_available: int = 64) -> List[Dict[str, Any]]:
    """Keep a modest reusable pool; create on demand while inserting posts."""
    personas = list_seed_personas(cur)
    available = sum(1 for p in personas if int(p["post_count"]) < MAX_POSTS_PER_PERSONA)
    guard = 0
    target = min(min_available, PERSONA_POOL)
    while available < target and guard < target + 40:
        guard += 1
        created = insert_persona(cur)
        if not created:
            break
        personas.append(created)
        available += 1
        if guard % 50 == 0:
            print(f"  personas… available={available}/{target}", flush=True)
    return personas


def pick_seed_author(cur, personas: List[Dict[str, Any]]) -> Tuple[str, List[Dict[str, Any]]]:
    usable = [p for p in personas if p.get("username") != "archive_whisper"]
    under = [p for p in usable if int(p["post_count"]) < MAX_POSTS_PER_PERSONA]
    # Prefer lighter authors; still allow reuse within the cap.
    light = [p for p in under if int(p["post_count"]) <= 2]
    mid = [p for p in under if int(p["post_count"]) > 2]
    if light and (not mid or random.random() > SECOND_POST_CHANCE):
        pool = light
    else:
        pool = under or light
    if not pool:
        created = insert_persona(cur)
        if not created:
            raise RuntimeError("could not create seed persona")
        personas.append(created)
        pool = [created]
    pick = random.choice(pool)
    pick["post_count"] = int(pick["post_count"]) + 1
    return pick["id"], personas


def load_pack_comments(pack: Path) -> List[Dict[str, Any]]:
    path = pack / "comments.json"
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    items = data.get("comments") if isinstance(data, dict) else data
    if not isinstance(items, list):
        return []
    out = []
    for row in items:
        if not isinstance(row, dict):
            continue
        body = clean_comment_text(row.get("text") or row.get("body"))
        if not body:
            continue
        out.append(
            {
                "body": body,
                "score": int(row.get("like_count") or row.get("score") or 0),
                "created": parse_ts(row.get("timestamp")),
            }
        )
    return out[:MAX_SEED_COMMENTS]


def seed_comments(cur, post_id: str, author_id: str, pack: Optional[Path], personas: List[Dict[str, Any]]) -> int:
    if random.random() > SEED_WITH_COMMENTS_CHANCE:
        return 0
    bodies = load_pack_comments(pack) if pack else []
    if not bodies:
        n = random.randint(2, 6)
        bodies = [
            {"body": random.choice(FALLBACK_COMMENT_BODIES), "score": random.randint(0, 10), "created": None}
            for _ in range(n)
        ]
    commenters = [p for p in personas if p.get("username") != "archive_whisper"]
    inserted = 0
    root_ids: List[str] = []
    for item in bodies:
        pool = [p for p in commenters if p["id"] != author_id] or commenters
        if not pool:
            break
        author = random.choice(pool)
        parent_id = None
        depth = 0
        if root_ids and random.random() < 0.15:
            parent_id = random.choice(root_ids)
            depth = 1
        cur.execute(
            """
            insert into anonymous.comments (
              post_id, parent_comment_id, author_profile_id, body, depth, state, score, created_at
            )
            values (
              %s::uuid,
              CASE WHEN %s::text IS NULL THEN NULL ELSE %s::uuid END,
              %s::uuid, %s, %s, 'active', %s, coalesce(%s::timestamptz, now())
            )
            returning id::text as id
            """,
            (
                post_id,
                parent_id,
                parent_id,
                author["id"],
                item["body"],
                depth,
                max(0, int(item.get("score") or 0)),
                item.get("created"),
            ),
        )
        row = cur.fetchone()
        if not row:
            continue
        inserted += 1
        if parent_id is None:
            root_ids.append(row["id"])
    if inserted:
        cur.execute(
            "update anonymous.posts set comment_count = %s, updated_at = now() where id = %s::uuid",
            (inserted, post_id),
        )
    return inserted


def iter_media_candidates(
    log_path: Path,
    local_folder: Path,
    allow_video: bool,
    env: Dict[str, str],
) -> List[Dict[str, Any]]:
    if not log_path.exists():
        return []
    out: List[Dict[str, Any]] = []
    seen = set()
    for line in log_path.open(encoding="utf-8", errors="ignore"):
        try:
            row = json.loads(line)
        except Exception:
            continue
        if not row.get("ok"):
            continue
        pack_id = str(row.get("post_id") or "").strip()
        if not pack_id or pack_id in seen:
            continue
        video_key = row.get("r2_video_key")
        image_keys = row.get("r2_image_keys") or []
        media_type = None
        media_url = None
        thumb_url = None
        if allow_video and video_key:
            media_type = "video"
            media_url = media_ref(env, video_key)
            if image_keys:
                thumb_url = media_ref(env, image_keys[0])
        elif image_keys:
            key = image_keys[0]
            low = key.lower()
            media_type = "gif" if low.endswith(".gif") else "image"
            media_url = media_ref(env, key)
            thumb_url = media_url
        else:
            continue
        seen.add(pack_id)
        pack = local_folder / pack_id
        title = body = ""
        created = None
        score = 0
        post_path = pack / "post.json"
        if post_path.is_file():
            try:
                post = json.loads(post_path.read_text(encoding="utf-8"))
                title = strip_confess_number_tags(str(post.get("title") or "").strip())
                body = strip_confess_number_tags(
                    str(post.get("body") or post.get("text") or "").strip()
                )
                if body and title and body == title:
                    pass
                elif not body and title:
                    body = title
                created = parse_ts(post.get("timestamp") or post.get("scraped_at"))
                score = int(post.get("score") or post.get("like_count") or 0)
            except Exception:
                pass
        if not title and not body:
            title = None
            body = "Shared anonymously."
        out.append(
            {
                "pack_id": pack_id,
                "pack": pack if pack.is_dir() else None,
                "media_type": media_type,
                "media_url": media_url,
                "thumb_url": thumb_url,
                "title": title[:200] if title else None,
                "body": (body or "Shared anonymously.")[:10000],
                "created": created or datetime.now(timezone.utc),
                "score": max(0, score),
            }
        )
    random.shuffle(out)
    return out


def main() -> int:
    apply = "--apply" in sys.argv
    env = load_env(API_ENV)
    db_url = env.get("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL missing", file=sys.stderr)
        return 2

    import psycopg2
    from psycopg2.extras import RealDictCursor

    # Soft share caps; when LIMIT is huge, take every candidate per source.
    quotas = []
    remaining = LIMIT
    for i, (slug, log, folder, allow_vid, share) in enumerate(SOURCES):
        n = int(LIMIT * share) if i < len(SOURCES) - 1 else remaining
        remaining -= n
        quotas.append((slug, log, folder, allow_vid, max(0, n)))

    planned: List[Tuple[str, Dict[str, Any]]] = []
    for slug, log, folder, allow_vid, n in quotas:
        cands = iter_media_candidates(log, folder, allow_vid, env)
        take = cands[:n]
        print(
            f"{slug} from {log.name}: candidates={len(cands)} take={len(take)} video_ok={allow_vid}",
            flush=True,
        )
        for c in take:
            planned.append((slug, c))

    random.shuffle(planned)
    print(f"planned inserts: {len(planned)}", flush=True)

    if not apply:
        print("dry-run only — re-run with --apply to write")
        return 0

    def connect():
        c = psycopg2.connect(
            db_url,
            connect_timeout=30,
            keepalives=1,
            keepalives_idle=30,
            keepalives_interval=10,
            keepalives_count=5,
            options="-c statement_timeout=120000",
        )
        c.autocommit = False
        return c

    def reconnect(reason: str):
        nonlocal conn, cur
        print(f"  reconnecting after: {reason}", flush=True)
        try:
            conn.close()
        except Exception:
            pass
        import time

        for attempt in range(1, 9):
            try:
                time.sleep(min(60, 2**attempt))
                conn = connect()
                cur = conn.cursor(cursor_factory=RealDictCursor)
                print(f"  reconnected (attempt {attempt})", flush=True)
                return
            except Exception as exc:
                print(f"  reconnect failed {attempt}: {exc}", flush=True)
        raise RuntimeError(f"could not reconnect after: {reason}")

    conn = connect()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    # Resolve spaces
    space_ids: Dict[str, str] = {}
    for slug, *_ in quotas:
        if slug in space_ids:
            continue
        cur.execute(
            "select id::text as id from anonymous.spaces where lower(normalized_slug)=lower(%s) and status='active'",
            (slug,),
        )
        row = cur.fetchone()
        if not row:
            cur.execute(
                "select id::text as id, normalized_slug from anonymous.spaces where status='active' and (normalized_slug=%s or slug=%s)",
                (slug, "HighlyStrange" if slug == "highlystrange" else slug),
            )
            row = cur.fetchone()
        if not row:
            print(f"space missing: {slug}", file=sys.stderr)
            return 1
        space_ids[slug] = row["id"]

    # Modest pool — pick_seed_author creates more on demand if needed.
    personas = ensure_seed_personas(cur, min_available=PERSONA_POOL)
    conn.commit()
    print(f"personas: {len(personas)} (cap {MAX_POSTS_PER_PERSONA} posts each)", flush=True)

    inserted = 0
    skipped = 0
    comments_n = 0
    for i, (slug, cand) in enumerate(planned, 1):
        source_ref = f"r2media:{slug}:{cand['pack_id']}"
        author_id, personas = pick_seed_author(cur, personas)
        try:
            cur.execute(
                """
                insert into anonymous.posts (
                  space_id, author_profile_id, title, body, state, score,
                  media_type, media_url, thumb_url, source_ref, created_at, updated_at
                )
                values (
                  %s::uuid, %s::uuid, %s, %s, 'active', %s,
                  %s, %s, %s, %s, %s, now()
                )
                on conflict (source_ref) do nothing
                returning id::text as id
                """,
                (
                    space_ids[slug],
                    author_id,
                    cand["title"],
                    cand["body"],
                    cand["score"],
                    cand["media_type"],
                    cand["media_url"],
                    cand["thumb_url"],
                    source_ref,
                    cand["created"],
                ),
            )
            row = cur.fetchone()
            if not row:
                skipped += 1
                for p in personas:
                    if p["id"] == author_id:
                        p["post_count"] = max(0, int(p["post_count"]) - 1)
                        break
            else:
                inserted += 1
                comments_n += seed_comments(cur, row["id"], author_id, cand.get("pack"), personas)
        except Exception as exc:
            msg = str(exc)
            print(f"  error {cand['pack_id']}: {msg}", file=sys.stderr)
            transient = any(
                x in msg.lower()
                for x in (
                    "ssl",
                    "eof",
                    "timeout",
                    "timed out",
                    "can't assign",
                    "eaddrnotavail",
                    "enotfound",
                    "connection",
                    "server closed",
                    "could not receive",
                    "could not send",
                )
            )
            try:
                conn.rollback()
            except Exception:
                transient = True
            if transient:
                try:
                    reconnect(msg[:120])
                    personas = ensure_seed_personas(cur, min_available=32)
                    conn.commit()
                except Exception as recon_exc:
                    print(f"  FATAL reconnect: {recon_exc}", file=sys.stderr)
                    return 1
            else:
                try:
                    personas = ensure_seed_personas(cur, min_available=32)
                except Exception:
                    reconnect(msg[:120])
                    personas = ensure_seed_personas(cur, min_available=32)
                    conn.commit()
            continue

        if i % 50 == 0:
            try:
                conn.commit()
            except Exception as exc:
                reconnect(str(exc)[:120])
                continue
            print(
                f"  … {i}/{len(planned)} inserted={inserted} skipped={skipped} comments={comments_n}",
                flush=True,
            )

    # refresh space counts
    for slug, sid in space_ids.items():
        cur.execute(
            """
            update anonymous.spaces
            set post_count = (
              select count(*)::int from anonymous.posts
              where space_id = %s::uuid and state = 'active'
            ),
            updated_at = now()
            where id = %s::uuid
            """,
            (sid, sid),
        )
    conn.commit()

    cur.execute(
        """
        select
          count(*) posts,
          count(*) filter (where media_type in ('image','gif')) images,
          count(*) filter (where media_type = 'video') videos,
          count(*) filter (where media_type is null) text_only
        from anonymous.posts where state='active'
        """
    )
    s = cur.fetchone()
    print(
        f"done inserted={inserted} skipped={skipped} comments={comments_n} | "
        f"live posts={s['posts']} images={s['images']} videos={s['videos']} text={s['text_only']}"
    )
    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
