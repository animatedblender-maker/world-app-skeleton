#!/usr/bin/env python3
"""
Reassign Masquerade seed posts off archive_whisper onto diverse fake personas.

Policy matches seed_masquerade_spaces_from_reddit.py / seed-personas.ts:
  - prefer one post per persona
  - occasionally allow a second (~12%)
  - never more than two
  - never touch account-linked (real) profiles

Uses apps/api/.env DATABASE_URL. Dry-run by default; pass --apply to write.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
API_ENV = ROOT / "apps" / "api" / ".env"

AVATAR_PREFIX = "seed-persona-v1:"
MAX_POSTS_PER_PERSONA = 2
SECOND_POST_CHANCE = 0.12

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


def insert_persona(cur) -> Optional[Dict[str, Any]]:
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
            returning id::text as id, username
            """,
            (username, username, avatar),
        )
        row = cur.fetchone()
        if row:
            return {"id": row["id"], "username": row["username"], "post_count": 0}
    return None


def main() -> int:
    apply = "--apply" in sys.argv
    env = load_env(API_ENV)
    db_url = env.get("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL missing in apps/api/.env", file=sys.stderr)
        return 2

    import psycopg2
    from psycopg2.extras import RealDictCursor

    conn = psycopg2.connect(db_url, connect_timeout=20)
    conn.autocommit = False
    cur = conn.cursor(cursor_factory=RealDictCursor)

    # Posts currently owned by archive_whisper (or any seed persona over the cap)
    cur.execute(
        """
        select a.id::text as id, a.author_profile_id::text as author_id, p.username
        from anonymous.posts a
        join anonymous.profiles p on p.id = a.author_profile_id
        where a.state = 'active'
          and p.username = 'archive_whisper'
        order by a.created_at asc
        """
    )
    mono_posts = list(cur.fetchall())
    print(f"archive_whisper posts to reassign: {len(mono_posts)}")

    # Existing seed personas (exclude archive_whisper for new assignments)
    cur.execute(
        """
        select p.id::text as id,
               p.username,
               coalesce((
                 select count(*)::int
                 from anonymous.posts a
                 where a.author_profile_id = p.id and a.state = 'active'
               ), 0) as post_count
        from anonymous.profiles p
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
    personas: List[Dict[str, Any]] = list(cur.fetchall())
    print(f"existing seed personas (excl archive_whisper): {len(personas)}")

    # Create enough empty personas so most posts get a unique author
    needed = max(0, len(mono_posts) - sum(
        1 for p in personas if int(p["post_count"]) < MAX_POSTS_PER_PERSONA
    ))
    # Prefer ~1 post each → create roughly one persona per remaining post
    to_create = max(needed, len(mono_posts) - len([p for p in personas if int(p["post_count"]) == 0]))
    to_create = max(0, to_create)
    print(f"creating ~{to_create} new personas…")
    created_n = 0
    for _ in range(to_create + 8):
        if created_n >= to_create:
            break
        row = insert_persona(cur)
        if not row:
            continue
        personas.append(row)
        created_n += 1
    print(f"created personas: {created_n}; pool size: {len(personas)}")

    random.shuffle(mono_posts)
    assignments: List[tuple[str, str, str]] = []  # post_id, author_id, username

    for post in mono_posts:
        zero = [p for p in personas if int(p["post_count"]) == 0]
        one = [p for p in personas if int(p["post_count"]) == 1]
        pool = zero
        if not zero or (one and random.random() < SECOND_POST_CHANCE):
            pool = one if one else zero
        if not pool:
            row = insert_persona(cur)
            if not row:
                print("FAILED: could not create persona for remaining posts", file=sys.stderr)
                conn.rollback()
                return 1
            personas.append(row)
            pool = [row]
        pick = random.choice(pool)
        pick["post_count"] = int(pick["post_count"]) + 1
        assignments.append((post["id"], pick["id"], pick["username"]))

    # Stats
    from collections import Counter
    by_user = Counter(u for _, _, u in assignments)
    doubles = sum(1 for c in by_user.values() if c == 2)
    singles = sum(1 for c in by_user.values() if c == 1)
    over = sum(1 for c in by_user.values() if c > 2)
    print(
        f"plan: reassign={len(assignments)} authors={len(by_user)} "
        f"singles={singles} doubles={doubles} over_cap={over}"
    )
    print("sample authors:", list(by_user.most_common(8)))

    if not apply:
        conn.rollback()
        print("dry-run only — re-run with --apply to write")
        return 0

    for post_id, author_id, _username in assignments:
        cur.execute(
            """
            update anonymous.posts
            set author_profile_id = %s::uuid, updated_at = now()
            where id = %s::uuid
            """,
            (author_id, post_id),
        )

    conn.commit()
    cur.execute(
        """
        select count(*) as posts, count(distinct author_profile_id) as authors
        from anonymous.posts where state = 'active'
        """
    )
    summary = cur.fetchone()
    cur.execute(
        """
        select p.username, count(*) as n
        from anonymous.posts a
        join anonymous.profiles p on p.id = a.author_profile_id
        where a.state = 'active'
        group by p.username
        order by n desc
        limit 15
        """
    )
    top = cur.fetchall()
    print(f"applied: posts={summary['posts']} authors={summary['authors']}")
    print("top authors:")
    for row in top:
        print(f"  {row['username']}: {row['n']}")

    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
