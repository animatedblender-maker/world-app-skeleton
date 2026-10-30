#!/usr/bin/env python3
"""
Populate Masquerade (anonymous) comments so most posts have threads.

- Prefer real Reddit pack comments.json when source_ref matches.
- Fill remaining empty posts from a pooled comment corpus (synthetic assign).
- Target: ~85% of active posts have ≥1 comment (more with than without).
- Comment authors are seed personas (adj_noun_####); not limited to 2 posts.

Uses apps/api/.env DATABASE_URL. Dry-run by default; pass --apply to write.
"""

from __future__ import annotations

import json
import os
import random
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
API_ENV = ROOT / "apps" / "api" / ".env"
PACKS_ROOT = Path("/Volumes/MatteryaSSD/Development/RedditPosts")

SPACE_FOLDERS = {
    "secrets": PACKS_ROOT / "OffMyChest",
    "highlystrange": PACKS_ROOT / "Paranormal",
}

AVATAR_PREFIX = "seed-persona-v1:"
# Share of posts that should end up with comments (rest stay empty on purpose).
WITH_COMMENTS_TARGET = 0.85
MIN_COMMENTS = 2
MAX_COMMENTS = 12

ADJECTIVES = [
    "quiet", "bright", "swift", "calm", "bold", "keen", "soft", "wild",
    "clear", "noble", "brave", "clever", "gentle", "lucky", "mellow", "nimble",
    "proud", "rapid", "silent", "steady", "sunny", "vivid", "witty", "zesty",
    "amber", "azure", "coral", "cosmic", "crimson", "distant", "frosty", "golden",
    "hidden", "ivory", "jade", "lunar", "misty", "neon", "orbit", "polar",
    "radiant", "silver", "solar", "steel", "tidal", "velvet", "violet", "winter",
    "ancient", "arctic", "blooming", "copper", "drift", "ember", "feral", "glinting",
    "hollow", "indigo", "jolly", "kindled", "luminous", "mossy", "northern", "opal",
    "pale", "quieted", "rustic", "sable", "teal", "umber", "veiled", "woven",
    "ambered", "brisk", "cedar", "dusk", "eerie", "faint", "gilded", "hushed",
]
NOUNS = [
    "orbit", "comet", "river", "forest", "harbor", "meadow", "nebula", "pebble",
    "phoenix", "quartz", "raven", "spark", "summit", "thunder", "valley", "willow",
    "anchor", "beacon", "canyon", "delta", "ember", "falcon", "glacier", "horizon",
    "island", "jasper", "kite", "lantern", "mirror", "nova", "oasis", "prism",
    "quill", "reef", "shadow", "temple", "umbra", "voyage", "whisper", "zenith",
    "archive", "brook", "cipher", "dusk", "echo", "fjord", "grove", "haven",
    "inkwell", "junction", "keel", "ledge", "mosaic", "nightfall", "onyx", "petal",
    "quarry", "ridge", "sigil", "thicket", "undertow", "vault", "wick", "zephyr",
    "atlas", "bough", "cradle", "driftwood", "emberlit", "foghorn", "glyph", "hearth",
]

FALLBACK_BODIES = [
    "I felt this more than I expected.",
    "Thank you for putting this into words.",
    "You’re not alone in this.",
    "That took courage to share.",
    "Sending quiet support from here.",
    "I needed to read this today.",
    "Been there. It gets lighter, slowly.",
    "This hit hard. Take care of yourself.",
    "Appreciate the honesty.",
    "Wild story — thanks for sharing it.",
    "Same energy. Glad you spoke up.",
    "Holding space for you.",
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
    # Reddit scrape chrome: "• 10h ago … Reply Share"
    t = re.sub(r"^[\s•·]+", "", t)
    t = re.sub(r"^\d+\s*[smhdwy]\s+ago\s+", "", t, flags=re.I)
    t = re.sub(r"\s*Reply\s+Share\s*$", "", t, flags=re.I)
    # Matterya term: never Reddit "OP" — use Author.
    t = re.sub(r"\boriginal\s+poster\b", "author", t, flags=re.I)
    t = re.sub(r"\bOP\b", "Author", t)
    t = re.sub(r"\b[Oo]p\b", "Author", t)
    t = re.sub(r"\s+", " ", t).strip()
    if len(t) < 4:
        return ""
    return t[:2000]


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


def load_pack_comments(slug: str, pack_id: str) -> List[Dict[str, Any]]:
    folder = SPACE_FOLDERS.get(slug)
    if not folder:
        return []
    path = folder / pack_id / "comments.json"
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    items = data.get("comments") if isinstance(data, dict) else data
    if not isinstance(items, list):
        return []
    out: List[Dict[str, Any]] = []
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
                "created": parse_ts(row.get("timestamp") or row.get("created_at")),
                "parent": str(row.get("parent") or "root"),
            }
        )
    return out


def build_corpus() -> List[str]:
    texts: List[str] = []
    seen = set()
    for folder in SPACE_FOLDERS.values():
        if not folder.is_dir():
            continue
        for path in folder.glob("*/comments.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except Exception:
                continue
            items = data.get("comments") if isinstance(data, dict) else data
            if not isinstance(items, list):
                continue
            for row in items:
                if not isinstance(row, dict):
                    continue
                body = clean_comment_text(row.get("text") or row.get("body"))
                if body and body not in seen:
                    seen.add(body)
                    texts.append(body)
    if len(texts) < 40:
        texts.extend(FALLBACK_BODIES)
    return texts


def insert_persona(cur) -> Optional[str]:
    for _ in range(16):
        username = generate_safe_username()
        avatar = f"{AVATAR_PREFIX}{username}"
        cur.execute(
            """
            insert into anonymous.profiles (
              username, normalized_username, avatar_seed, state, age_attested_at
            )
            values (%s, %s, %s, 'active', now())
            on conflict (normalized_username) do nothing
            returning id::text as id
            """,
            (username, username, avatar),
        )
        row = cur.fetchone()
        if row:
            return row["id"]
    return None


def load_commenter_ids(cur, min_n: int = 80) -> List[str]:
    cur.execute(
        """
        select p.id::text as id
        from anonymous.profiles p
        where p.state = 'active'
          and p.avatar_seed like %s
          and p.username <> 'archive_whisper'
          and not exists (
            select 1 from identity_vault.account_anonymous_links al
            where al.anon_profile_id = p.id
            limit 1
          )
        order by p.created_at asc
        """,
        (f"{AVATAR_PREFIX}%",),
    )
    ids = [r["id"] for r in cur.fetchall()]
    while len(ids) < min_n:
        created = insert_persona(cur)
        if not created:
            break
        ids.append(created)
    return ids


def pick_commenter(ids: List[str], avoid: Optional[str] = None) -> str:
    pool = [i for i in ids if i != avoid] or ids
    return random.choice(pool)


def clamp_comment_created(
    raw: Optional[datetime],
    post_created: datetime,
    index: int,
    total: int,
) -> datetime:
    """Replies must be after the post — restamped seed posts vs old Reddit times."""
    now = datetime.now(timezone.utc)
    if post_created.tzinfo is None:
        post_created = post_created.replace(tzinfo=timezone.utc)
    n = max(1, total)
    span_secs = max(30 * n, min(48 * 3600, max(300, 8 * 60 * n)))
    frac = (index + 1) / (n + 1)
    fallback = post_created + timedelta(seconds=int(span_secs * frac) + (index % 17))
    if raw is None:
        return min(fallback, now)
    created = raw if raw.tzinfo else raw.replace(tzinfo=timezone.utc)
    if created <= post_created or created > now:
        return min(fallback, now)
    return created


def insert_comments_for_post(
    cur,
    post_id: str,
    author_id: str,
    bodies: List[Dict[str, Any]],
    commenter_ids: List[str],
    post_created: Optional[datetime] = None,
) -> int:
    if not bodies:
        return 0
    inserted = 0
    root_ids: List[str] = []
    base = post_created or datetime.now(timezone.utc)
    for idx, item in enumerate(bodies):
        body = item["body"]
        commenter = pick_commenter(commenter_ids, avoid=author_id)
        parent_id = None
        depth = 0
        # ~18% of comments after the first become a reply to a prior root.
        if root_ids and random.random() < 0.18:
            parent_id = random.choice(root_ids)
            depth = 1
        created = clamp_comment_created(item.get("created"), base, idx, len(bodies))
        score = max(0, int(item.get("score") or 0))
        cur.execute(
            """
            insert into anonymous.comments (
              post_id, parent_comment_id, author_profile_id, body, depth, state, score, created_at
            )
            values (
              %s::uuid,
              CASE WHEN %s::text IS NULL THEN NULL ELSE %s::uuid END,
              %s::uuid, %s, %s, 'active', %s, %s
            )
            returning id::text as id
            """,
            (
                post_id,
                parent_id,
                parent_id,
                commenter,
                body,
                depth,
                score,
                created,
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
            """
            update anonymous.posts
            set comment_count = comment_count + %s,
                updated_at = now()
            where id = %s::uuid
            """,
            (inserted, post_id),
        )
    return inserted


def bodies_from_corpus(corpus: List[str], n: int) -> List[Dict[str, Any]]:
    if not corpus:
        corpus = FALLBACK_BODIES
    picks = random.sample(corpus, k=min(n, len(corpus))) if len(corpus) >= n else [
        random.choice(corpus) for _ in range(n)
    ]
    return [{"body": b, "score": random.randint(0, 12), "created": None} for b in picks]


def main() -> int:
    apply = "--apply" in sys.argv
    env = load_env(API_ENV)
    db_url = env.get("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL missing in apps/api/.env", file=sys.stderr)
        return 2

    import psycopg2
    from psycopg2.extras import RealDictCursor

    corpus = build_corpus()
    print(f"comment corpus size: {len(corpus)}")

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

    conn = connect()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("set statement_timeout = '120s'")
    cur.execute("set lock_timeout = '30s'")

    cur.execute(
        """
        select a.id::text as id,
               a.author_profile_id::text as author_id,
               a.source_ref,
               a.created_at,
               coalesce(a.comment_count, 0) as comment_count
        from anonymous.posts a
        where a.state = 'active'
        order by a.created_at asc
        """
    )
    posts = list(cur.fetchall())
    empty = [p for p in posts if int(p["comment_count"]) <= 0]
    already = len(posts) - len(empty)
    target_with = max(already, int(round(len(posts) * WITH_COMMENTS_TARGET)))
    need = max(0, target_with - already)
    print(
        f"posts={len(posts)} already_with_comments={already} "
        f"empty={len(empty)} target_with={target_with} will_fill={need}"
    )

    commenter_ids = load_commenter_ids(cur, min_n=max(80, need // 2 + 20))
    conn.commit()  # persist any new commenter personas even on dry-run planning
    print(f"commenter personas: {len(commenter_ids)}")

    random.shuffle(empty)
    to_fill = empty[:need]
    leave_empty = len(empty) - len(to_fill)

    # Plan first (no inserts) so dry-run is cheap and apply can resume.
    plans: List[Tuple[Dict[str, Any], List[Dict[str, Any]], str]] = []
    from_reddit = 0
    from_corpus = 0
    for post in to_fill:
        bodies: List[Dict[str, Any]] = []
        ref = post.get("source_ref") or ""
        source = "corpus"
        if ref.startswith("reddit:"):
            parts = ref.split(":", 2)
            if len(parts) == 3:
                bodies = load_pack_comments(parts[1], parts[2])
                if bodies:
                    source = "reddit"
                    from_reddit += 1
        if not bodies:
            n = random.randint(MIN_COMMENTS, MAX_COMMENTS)
            bodies = bodies_from_corpus(corpus, n)
            from_corpus += 1
        elif len(bodies) > MAX_COMMENTS:
            bodies = bodies[:MAX_COMMENTS]
        plans.append((post, bodies, source))

    planned_comments = sum(len(b) for _, b, _ in plans)
    print(
        f"plan: fill_posts={len(plans)} comments≈{planned_comments} "
        f"from_reddit={from_reddit} from_corpus={from_corpus} leave_empty={leave_empty}"
    )

    if not apply:
        cur.close()
        conn.close()
        print("dry-run only — re-run with --apply to write")
        return 0

    filled_posts = 0
    total_comments = 0
    batch = 0
    for post, bodies, _source in plans:
        try:
            n = insert_comments_for_post(
                cur,
                post["id"],
                post["author_id"],
                bodies,
                commenter_ids,
                post_created=post.get("created_at"),
            )
        except Exception as exc:
            print(f"  retry after error on {post['id']}: {exc}", file=sys.stderr)
            try:
                conn.rollback()
            except Exception:
                pass
            try:
                cur.close()
                conn.close()
            except Exception:
                pass
            conn = connect()
            cur = conn.cursor(cursor_factory=RealDictCursor)
            n = insert_comments_for_post(
                cur,
                post["id"],
                post["author_id"],
                bodies,
                commenter_ids,
                post_created=post.get("created_at"),
            )
        if n:
            filled_posts += 1
            total_comments += n
        batch += 1
        if batch % 15 == 0:
            conn.commit()
            print(f"  … committed {batch}/{len(plans)} posts ({total_comments} comments)")

    conn.commit()
    cur.execute(
        """
        select
          count(*) as posts,
          count(*) filter (where coalesce(comment_count,0) > 0) as with_comments,
          count(*) filter (where coalesce(comment_count,0) = 0) as without,
          coalesce(sum(comment_count),0) as comment_count_sum
        from anonymous.posts where state = 'active'
        """
    )
    s = cur.fetchone()
    cur.execute("select count(*) as n from anonymous.comments where state = 'active'")
    c = cur.fetchone()
    print(
        f"applied: filled_posts={filled_posts} comments={total_comments} | "
        f"posts={s['posts']} with_comments={s['with_comments']} "
        f"without={s['without']} comment_rows={c['n']} sum_counts={s['comment_count_sum']}"
    )
    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
