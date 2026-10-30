#!/usr/bin/env python3
"""
Seed realistic Masquerade Space memberships.

- Ensures every post author is a member of their Space
- Adds lurker personas so member_count looks lived-in (not 0–1)
- Updates anonymous.spaces.member_count from live memberships

Uses apps/api/.env DATABASE_URL.
"""

from __future__ import annotations

import os
import random
import sys
from pathlib import Path
from typing import Any, Dict, List, Set

ROOT = Path(__file__).resolve().parents[1]
API_ENV = ROOT / "apps" / "api" / ".env"
AVATAR_PREFIX = "seed-persona-v1:"

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
    "archive", "brook", "cipher", "dusk", "echo", "fjord", "grove", "haven",
    "inkwell", "junction", "keel", "ledge", "mosaic", "nightfall", "onyx", "petal",
    "quarry", "ridge", "sigil", "thicket", "undertow", "vault", "wick", "zephyr",
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


def target_member_count(slug: str, post_count: int) -> int:
    """Reddit-ish lurker ratio: many more members than posts."""
    slug = slug.lower()
    # Hub shelves — large, sticky communities
    if slug in ("secrets", "highlystrange"):
        base = 1400 + post_count * 3
        jitter = random.randint(-80, 160)
        return max(900, base + jitter)
    # Busy themed Spaces
    if post_count >= 80:
        return max(280, int(post_count * 4.2) + random.randint(60, 180))
    if post_count >= 20:
        return max(120, int(post_count * 5.0) + random.randint(40, 100))
    if post_count >= 1:
        return max(64, int(post_count * 8) + random.randint(24, 72))
    # Empty but open — never look abandoned
    return random.randint(48, 140)


def main() -> int:
    env = load_env(API_ENV)
    db_url = env.get("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL missing", file=sys.stderr)
        return 2

    import psycopg2
    from psycopg2.extras import RealDictCursor, execute_values

    random.seed()
    conn = psycopg2.connect(db_url, connect_timeout=20)
    conn.autocommit = False
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute(
        """
        select id::text as id, normalized_slug, title, post_count, member_count
        from anonymous.spaces
        where status = 'active'
        order by post_count desc, normalized_slug
        """
    )
    spaces = list(cur.fetchall())
    if not spaces:
        print("no active spaces")
        return 1

    targets = {
        s["id"]: target_member_count(s["normalized_slug"], int(s["post_count"] or 0))
        for s in spaces
    }
    need_total = max(targets.values()) if targets else 0
    # Enough personas to cover the biggest Space + overlap across Spaces
    want_pool = max(need_total + 200, sum(1 for _ in spaces) * 80, 1800)

    cur.execute(
        """
        select id::text as id
        from anonymous.profiles
        where state = 'active'
          and (
            avatar_seed like %s
            or avatar_seed = 'seed-archive-whisper-v1'
          )
        """,
        (f"{AVATAR_PREFIX}%",),
    )
    pool: List[str] = [r["id"] for r in cur.fetchall()]
    print(f"seed personas available: {len(pool)}; want ≥ {want_pool}", flush=True)

    created = 0
    guard = 0
    while len(pool) < want_pool and guard < want_pool + 100:
        guard += 1
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
            pool.append(row["id"])
            created += 1
            if created % 100 == 0:
                conn.commit()
                print(f"  lurkers …{created} (pool={len(pool)})", flush=True)
    conn.commit()
    print(f"lurkers created={created}; pool={len(pool)}", flush=True)

    for space in spaces:
        sid = space["id"]
        slug = space["normalized_slug"]
        target = min(targets[sid], len(pool))

        # Authors of posts in this Space must be members
        cur.execute(
            """
            select distinct author_profile_id::text as id
            from anonymous.posts
            where space_id = %s::uuid and state = 'active'
            """,
            (sid,),
        )
        authors: Set[str] = {r["id"] for r in cur.fetchall() if r.get("id")}

        cur.execute(
            """
            select anon_profile_id::text as id
            from anonymous.space_memberships
            where space_id = %s::uuid and state = 'active'
            """,
            (sid,),
        )
        already: Set[str] = {r["id"] for r in cur.fetchall() if r.get("id")}

        need = authors - already
        rows = [(sid, pid) for pid in need]
        if rows:
            execute_values(
                cur,
                """
                insert into anonymous.space_memberships (space_id, anon_profile_id, state)
                values %s
                on conflict (space_id, anon_profile_id) do update
                set state = 'active', left_at = null, joined_at = coalesce(anonymous.space_memberships.joined_at, now())
                """,
                rows,
                template="(%s::uuid, %s::uuid, 'active')",
            )
            already |= need

        missing = target - len(already)
        if missing > 0:
            candidates = [pid for pid in pool if pid not in already]
            random.shuffle(candidates)
            pick = candidates[:missing]
            if pick:
                execute_values(
                    cur,
                    """
                    insert into anonymous.space_memberships (space_id, anon_profile_id, state)
                    values %s
                    on conflict (space_id, anon_profile_id) do update
                    set state = 'active', left_at = null
                    """,
                    [(sid, pid) for pid in pick],
                    template="(%s::uuid, %s::uuid, 'active')",
                )
                already |= set(pick)

        cur.execute(
            """
            update anonymous.spaces
            set member_count = (
              select count(*)::int from anonymous.space_memberships
              where space_id = %s::uuid and state = 'active'
            ),
            updated_at = now()
            where id = %s::uuid
            returning member_count
            """,
            (sid, sid),
        )
        mc = cur.fetchone()["member_count"]
        conn.commit()
        print(
            f"  {slug}: target≈{target} → members={mc} (posts={space['post_count']})",
            flush=True,
        )

    cur.close()
    conn.close()
    print("done", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
