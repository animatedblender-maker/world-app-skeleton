#!/usr/bin/env python3
"""Repair Masquerade posts stuck on body='Shared anonymously.' using R2 upload logs.

Secrets / HighlyStrange media was seeded from Funny + Memes packs (fy_*),
so those upload logs are required. Also restores posts we previously hid
when titles were missing from the wrong log set.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import psycopg2
from psycopg2.extras import RealDictCursor

PACKS = Path("/Volumes/MatteryaSSD/Development/RedditPosts")
API_ENV = Path(
    "/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton/apps/api/.env"
)
LOGS = [
    # Primary sources for Secrets / HighlyStrange media seeds
    PACKS / "uploaded_funny_r2.jsonl",
    PACKS / "uploaded_memes_r2.jsonl",
    # Text / confession style packs
    PACKS / "uploaded_secretsstrange_r2.jsonl",
    PACKS / "uploaded_offmychest_r2.jsonl",
    PACKS / "uploaded_paranormal_r2.jsonl",
    PACKS / "uploaded_confession_mix_r2.jsonl",
]
DISK_FOLDERS = [PACKS / "Funny", PACKS / "Memes"]


def load_env() -> dict:
    out = {}
    for line in API_ENV.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def pack_id_from_ref(ref: str) -> str:
    m = re.search(r"(fy_[a-z0-9]+|[a-z0-9_]{6,})$", ref, re.I)
    if m:
        return m.group(1)
    if ":" in ref:
        return ref.rsplit(":", 1)[-1]
    return ""


def title_from_disk(pack_id: str) -> str:
    if not pack_id:
        return ""
    for folder in DISK_FOLDERS:
        pj = folder / pack_id / "post.json"
        if not pj.is_file():
            continue
        try:
            post = json.loads(pj.read_text(encoding="utf-8"))
        except Exception:
            continue
        title = str(post.get("title") or "").strip()
        if title:
            return title
        body = str(post.get("body") or post.get("text") or "").strip()
        if body:
            return body[:200]
    return ""


def main() -> int:
    title_by_id: dict[str, str] = {}
    for log in LOGS:
        if not log.exists():
            print(f"  skip missing log: {log.name}")
            continue
        n = 0
        for line in log.open(encoding="utf-8", errors="ignore"):
            try:
                row = json.loads(line)
            except Exception:
                continue
            pid = str(row.get("post_id") or "").strip()
            title = str(row.get("title") or row.get("post_title") or "").strip()
            if pid and title and pid not in title_by_id:
                title_by_id[pid] = title
                n += 1
        print(f"  {log.name}: +{n} titles")
    print(f"titles indexed: {len(title_by_id)}")

    env = load_env()
    conn = psycopg2.connect(env["DATABASE_URL"], connect_timeout=30)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    # Active placeholders + previously-removed Shared anonymously. cards.
    cur.execute(
        """
        select p.id::text as id, p.source_ref, p.title, p.body, p.state
        from anonymous.posts p
        where coalesce(p.body, '') = 'Shared anonymously.'
           or (
             p.state = 'active'
             and nullif(trim(coalesce(p.title, '')), '') is null
             and length(trim(coalesce(p.body, ''))) < 3
           )
        """
    )
    rows = cur.fetchall()
    print(f"candidates: {len(rows)}")
    fixed = 0
    removed = 0
    for row in rows:
        ref = str(row["source_ref"] or "")
        pack_id = pack_id_from_ref(ref)
        title = title_by_id.get(pack_id, "").strip() or title_from_disk(pack_id)
        if title:
            cur.execute(
                """
                update anonymous.posts
                set title = %s,
                    body = case
                      when coalesce(body, '') in ('', 'Shared anonymously.') then %s
                      else body
                    end,
                    state = 'active',
                    updated_at = now()
                where id = %s::uuid
                """,
                (title[:200], title[:10000], row["id"]),
            )
            fixed += 1
        elif row["state"] == "active":
            # Hide lifeless placeholder cards so Spaces aren't a wall of "Shared anonymously."
            cur.execute(
                """
                update anonymous.posts
                set state = 'removed', updated_at = now()
                where id = %s::uuid
                """,
                (row["id"],),
            )
            removed += 1
        if (fixed + removed) % 200 == 0 and (fixed + removed) > 0:
            conn.commit()
            print(f"  … fixed={fixed} removed={removed}", flush=True)
    conn.commit()
    print(f"done fixed={fixed} removed={removed}")
    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
