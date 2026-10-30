#!/usr/bin/env python3
"""Soft-hide r/funny (fy_*) posts from the Matterya feed (reversible).

Sets moderation_status='hidden' with actor system:hide_r_funny.
Does NOT delete rows or R2 objects.

Usage:
  python3 scripts/hide_r_funny_posts.py           # dry-run counts
  python3 scripts/hide_r_funny_posts.py --apply   # apply hide
  python3 scripts/hide_r_funny_posts.py --undo    # restore rows we hid
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API_ENV = ROOT / "apps" / "api" / ".env"


def load_env() -> None:
    if not API_ENV.exists():
        return
    for line in API_ENV.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Apply soft-hide")
    ap.add_argument("--undo", action="store_true", help="Unhide rows we previously hid")
    args = ap.parse_args()
    load_env()
    db = os.environ.get("DATABASE_URL", "").strip()
    if not db:
        print("DATABASE_URL missing", file=sys.stderr)
        return 1

    try:
        import psycopg2
        import psycopg2.extras
    except ImportError:
        import subprocess

        subprocess.check_call([sys.executable, "-m", "pip", "install", "psycopg2-binary", "-q"])
        import psycopg2
        import psycopg2.extras

    conn = psycopg2.connect(db)
    conn.autocommit = False
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    cur.execute(
        """
        select
          count(*) filter (
            where media_path ~ '/fy_'
              and coalesce(moderation_status, 'active') not in ('hidden', 'deleted')
          ) as visible_fy,
          count(*) filter (
            where media_path ~ '/fy_'
              and moderation_status = 'hidden'
              and coalesce(moderation_actor, '') = 'system:hide_r_funny'
          ) as hidden_by_us,
          count(*) filter (where media_path ~ '/fy_') as total_fy
        from public.posts
        """
    )
    row = cur.fetchone()
    print(
        f"fy_* totals: total={row['total_fy']} visible={row['visible_fy']} "
        f"hidden_by_us={row['hidden_by_us']}"
    )

    if args.undo:
        if not args.apply and True:
            # undo always needs --apply for safety? Keep --undo implying apply,
            # but require explicit --apply too.
            pass
        if not args.apply:
            print("Dry-run undo: would restore hidden_by_us rows to active. Pass --apply --undo.")
            conn.close()
            return 0
        cur.execute(
            """
            update public.posts
            set moderation_status = 'active',
                moderation_note = nullif(
                  regexp_replace(coalesce(moderation_note, ''), '(^|,\\s*)auto:hide_r_funny(,|$)', '\\2', 'g'),
                  ''
                ),
                moderation_actor = null,
                updated_at = now()
            where media_path ~ '/fy_'
              and moderation_status = 'hidden'
              and coalesce(moderation_actor, '') = 'system:hide_r_funny'
            """
        )
        print(f"UNDO applied: restored {cur.rowcount} row(s)")
        conn.commit()
        conn.close()
        return 0

    if not args.apply:
        print("Dry-run only. Pass --apply to soft-hide visible fy_* posts.")
        conn.close()
        return 0

    cur.execute(
        """
        update public.posts
        set moderation_status = 'hidden',
            moderation_note = case
              when coalesce(moderation_note, '') = '' then 'auto:hide_r_funny'
              when position('auto:hide_r_funny' in moderation_note) > 0 then moderation_note
              else moderation_note || ',auto:hide_r_funny'
            end,
            moderation_actor = 'system:hide_r_funny',
            updated_at = now()
        where media_path ~ '/fy_'
          and coalesce(moderation_status, 'active') not in ('hidden', 'deleted')
          and coalesce(moderation_actor, '') not like 'admin%'
        """
    )
    print(f"HIDE applied: soft-hid {cur.rowcount} row(s)")
    conn.commit()
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
