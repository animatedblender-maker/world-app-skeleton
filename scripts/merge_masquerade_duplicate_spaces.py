#!/usr/bin/env python3
"""
Merge duplicate Masquerade spaces into the canonical catalog.

  highstrangeness, truthishere  → highlystrange
  confession                    → confessions
  trueoffmychest                → offmychest
  ghoststories                  → ghosts

Moves active posts + memberships, refreshes counts, archives source spaces.
Idempotent. Uses apps/api/.env DATABASE_URL.

  python3 scripts/merge_masquerade_duplicate_spaces.py
  python3 scripts/merge_masquerade_duplicate_spaces.py --dry-run
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import psycopg2
import psycopg2.extras

ROOT = Path(__file__).resolve().parents[1]
API_ENV = ROOT / "apps" / "api" / ".env"

# source normalized_slug → target normalized_slug
MERGE_MAP = {
    "highstrangeness": "highlystrange",
    "highly_strange": "highlystrange",
    "truthishere": "highlystrange",
    "confession": "confessions",
    "trueoffmychest": "offmychest",
    "ghoststories": "ghosts",
}

CANONICAL_TITLES = {
    "secrets": "Secrets",
    "highlystrange": "HighlyStrange",
    "confessions": "Confessions",
    "offmychest": "Off My Chest",
    "glitch": "Glitch",
    "paranormal": "Paranormal",
    "ghosts": "Ghosts",
}

# Orphan rooms to archive (move leftover posts into a hub first).
ARCHIVE_ORPHANS = {
    "haven": "secrets",
}


def load_db_url() -> str:
    if os.environ.get("DATABASE_URL"):
        return os.environ["DATABASE_URL"].strip()
    for line in API_ENV.read_text().splitlines():
        if line.startswith("DATABASE_URL="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("DATABASE_URL missing")


def space_by_norm(cur, norm: str):
    cur.execute(
        """
        select id::text, slug, normalized_slug, title, status,
               coalesce(post_count,0) as post_count
        from anonymous.spaces
        where normalized_slug = %s
        limit 1
        """,
        (norm,),
    )
    return cur.fetchone()


def ensure_target(cur, norm: str):
    row = space_by_norm(cur, norm)
    if row:
        title = CANONICAL_TITLES.get(norm, row["title"])
        cur.execute(
            """
            update anonymous.spaces
            set title = %s,
                status = 'active',
                visibility = 'adult_public',
                admission = 'free',
                billing_mode = 'free',
                updated_at = now()
            where id = %s::uuid
            """,
            (title, row["id"]),
        )
        return row["id"]
    title = CANONICAL_TITLES.get(norm, norm)
    display_slug = "HighlyStrange" if norm == "highlystrange" else norm
    cur.execute(
        """
        insert into anonymous.spaces (
          slug, normalized_slug, title, description, category, tags,
          visibility, admission, billing_mode, status, language
        )
        values (
          %s, %s, %s, %s, %s, %s,
          'adult_public', 'free', 'free', 'active', 'en'
        )
        returning id::text
        """,
        (
            display_slug,
            norm,
            title,
            f"Anonymous stories in {title}.",
            "general",
            [norm],
        ),
    )
    return cur.fetchone()["id"]


def refresh_counts(cur, space_id: str) -> None:
    cur.execute(
        """
        update anonymous.spaces s
        set post_count = (
              select count(*) from anonymous.posts p
              where p.space_id = s.id and p.state = 'active'
            ),
            member_count = (
              select count(*) from anonymous.space_memberships m
              where m.space_id = s.id and m.state = 'active'
            ),
            updated_at = now()
        where s.id = %s::uuid
        """,
        (space_id,),
    )


def merge_one(cur, src_norm: str, dst_norm: str, dry: bool) -> dict:
    src = space_by_norm(cur, src_norm)
    if not src:
        return {"src": src_norm, "dst": dst_norm, "skipped": "missing_src"}
    if src["normalized_slug"] == dst_norm:
        return {"src": src_norm, "dst": dst_norm, "skipped": "same"}
    dst_id = ensure_target(cur, dst_norm)
    src_id = src["id"]
    if src_id == dst_id:
        return {"src": src_norm, "dst": dst_norm, "skipped": "same_id"}

    cur.execute(
        "select count(*)::int as n from anonymous.posts where space_id = %s::uuid and state = 'active'",
        (src_id,),
    )
    posts_n = cur.fetchone()["n"]
    cur.execute(
        "select count(*)::int as n from anonymous.space_memberships where space_id = %s::uuid",
        (src_id,),
    )
    mem_n = cur.fetchone()["n"]

    if dry:
        return {
            "src": src_norm,
            "dst": dst_norm,
            "dry_posts": posts_n,
            "dry_memberships": mem_n,
        }

    cur.execute(
        """
        update anonymous.posts
        set space_id = %s::uuid, updated_at = now()
        where space_id = %s::uuid
        """,
        (dst_id, src_id),
    )
    moved_posts = cur.rowcount

    # Move memberships that don't already exist on target; drop remaining on source.
    cur.execute(
        """
        insert into anonymous.space_memberships (space_id, anon_profile_id, state, joined_at)
        select %s::uuid, m.anon_profile_id, m.state, coalesce(m.joined_at, now())
        from anonymous.space_memberships m
        where m.space_id = %s::uuid
          and not exists (
            select 1 from anonymous.space_memberships x
            where x.space_id = %s::uuid and x.anon_profile_id = m.anon_profile_id
          )
        """,
        (dst_id, src_id, dst_id),
    )
    moved_mem = cur.rowcount
    cur.execute(
        "delete from anonymous.space_memberships where space_id = %s::uuid",
        (src_id,),
    )

    cur.execute(
        """
        update anonymous.spaces
        set status = 'archived',
            post_count = 0,
            member_count = 0,
            updated_at = now()
        where id = %s::uuid
        """,
        (src_id,),
    )
    refresh_counts(cur, dst_id)
    return {
        "src": src_norm,
        "dst": dst_norm,
        "moved_posts": moved_posts,
        "moved_memberships": moved_mem,
        "archived": src_id,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    url = load_db_url()
    conn = psycopg2.connect(url)
    conn.autocommit = False
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SET statement_timeout TO 120000")

    print("== before")
    cur.execute(
        """
        select normalized_slug, title, status, coalesce(post_count,0) as posts
        from anonymous.spaces
        order by 1
        """
    )
    for r in cur.fetchall():
        print(dict(r))

    results = []
    for src, dst in MERGE_MAP.items():
        r = merge_one(cur, src, dst, dry=args.dry_run)
        results.append(r)
        print("merge", r)

    for src, dst in ARCHIVE_ORPHANS.items():
        r = merge_one(cur, src, dst, dry=args.dry_run)
        results.append(r)
        print("orphan", r)

    # Ensure canonical titles on active hubs/rooms
    if not args.dry_run:
        for norm, title in CANONICAL_TITLES.items():
            cur.execute(
                """
                update anonymous.spaces
                set title = %s, status = 'active', updated_at = now()
                where normalized_slug = %s and status <> 'archived'
                """,
                (title, norm),
            )
            row = space_by_norm(cur, norm)
            if row:
                refresh_counts(cur, row["id"])

    if args.dry_run:
        conn.rollback()
        print("DRY RUN — rolled back")
    else:
        conn.commit()
        print("COMMITTED")

    print("== after")
    cur.execute(
        """
        select normalized_slug, title, status, coalesce(post_count,0) as posts
        from anonymous.spaces
        where status = 'active'
        order by 1
        """
    )
    for r in cur.fetchall():
        print(dict(r))
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
