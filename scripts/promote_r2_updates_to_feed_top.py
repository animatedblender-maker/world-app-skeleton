#!/usr/bin/env python3
"""
Go-live / ops: float recently R2-synced posts to the top of the home feed.

The API home feed ranks by greatest(updated_at, created_at). Content-pipeline
resign / caption / comment repairs already bump updated_at. This script is for
an immediate pre-deploy bump: set created_at (and updated_at) on R2 media so
even created_at-only clients and caches show latest R2 updates first.

Targets media_path like:
  r2:% | r2-share:% | r2-hubshare:%

How to run
  export SUPABASE_URL=https://bpdkltgikgbnfjswdbaj.supabase.co   # optional
  export SUPABASE_SERVICE_ROLE_KEY=...

  # Preview
  python3 scripts/promote_r2_updates_to_feed_top.py --dry-run

  # Apply (stagger created_at/updated_at into the recent past, newest first)
  python3 scripts/promote_r2_updates_to_feed_top.py --apply

  # Only posts updated in the last N hours (default: all R2, capped by --limit)
  python3 scripts/promote_r2_updates_to_feed_top.py --apply --since-hours 168

  # Focus countries
  python3 scripts/promote_r2_updates_to_feed_top.py --apply --countries US,DE,EG,AL
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_SUPABASE_URL = "https://bpdkltgikgbnfjswdbaj.supabase.co"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--supabase-url", default=os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL))
    p.add_argument("--service-role-key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""))
    p.add_argument("--countries", default="", help="Comma ISO codes; empty = all")
    p.add_argument("--limit", type=int, default=5000, help="Max posts to promote")
    p.add_argument(
        "--since-hours",
        type=float,
        default=0,
        help="Only posts with updated_at within this many hours (0 = ignore)",
    )
    p.add_argument(
        "--spacing-seconds",
        type=float,
        default=2.0,
        help="Seconds between stamped timestamps (newest = now)",
    )
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--apply", action="store_true")
    return p.parse_args()


def http_json(
    method: str,
    url: str,
    headers: Dict[str, str],
    body: Any = None,
) -> Tuple[int, Any]:
    data = None
    hdrs = dict(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(req, timeout=90) as resp:
            raw = resp.read()
            if not raw:
                return resp.status, None
            try:
                return resp.status, json.loads(raw.decode("utf-8"))
            except Exception:
                return resp.status, raw.decode("utf-8", errors="replace")
    except HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw
    except URLError as e:
        return 0, str(e)


def fetch_r2_posts(
    url: str,
    key: str,
    countries: List[str],
    limit: int,
    since_hours: float,
) -> List[dict]:
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    out: List[dict] = []
    # PostgREST or() for media_path prefixes
    path_filter = "or=(media_path.like.r2:*,media_path.like.r2-share:*,media_path.like.r2-hubshare:*)"
    page = 500
    offset = 0
    since_iso: Optional[str] = None
    if since_hours and since_hours > 0:
        since_iso = (datetime.now(timezone.utc) - timedelta(hours=since_hours)).isoformat()

    while len(out) < limit:
        want = min(page, limit - len(out))
        q = (
            f"{url.rstrip('/')}/rest/v1/posts"
            f"?{path_filter}"
            f"&visibility=eq.public"
            f"&moderation_status=eq.active"
            f"&select=id,media_path,country_code,created_at,updated_at,title"
            f"&order=updated_at.desc.nullslast"
            f"&limit={want}&offset={offset}"
        )
        if countries:
            q += f"&country_code=in.({','.join(countries)})"
        if since_iso:
            q += f"&updated_at=gte.{since_iso}"
        st, rows = http_json("GET", q, headers)
        if st != 200 or not isinstance(rows, list) or not rows:
            if st != 200:
                print(f"list failed st={st} {str(rows)[:240]}", file=sys.stderr)
            break
        out.extend(rows)
        if len(rows) < want:
            break
        offset += len(rows)
    return out[:limit]


def main() -> int:
    args = parse_args()
    key = (args.service_role_key or "").strip()
    if not args.apply and not args.dry_run:
        print("Pass --dry-run or --apply", file=sys.stderr)
        return 2
    if not key:
        print("SUPABASE_SERVICE_ROLE_KEY required", file=sys.stderr)
        return 2

    countries = [c.strip().upper() for c in args.countries.split(",") if c.strip()]
    rows = fetch_r2_posts(
        args.supabase_url,
        key,
        countries,
        args.limit,
        args.since_hours,
    )
    print(f"R2 candidates: {len(rows)}" + (f" countries={countries}" if countries else ""))
    if not rows:
        return 0

    # Already ordered by updated_at desc — stamp newest = now, step back.
    now = datetime.now(timezone.utc)
    spacing = max(0.1, float(args.spacing_seconds))
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }

    patched = 0
    for i, row in enumerate(rows):
        ts = now - timedelta(seconds=i * spacing)
        iso = ts.isoformat().replace("+00:00", "Z")
        if patched < 8:
            print(
                f"  {row.get('id', '')[:8]}… {row.get('media_path', '')[:48]} "
                f"updated={row.get('updated_at')} → {iso}"
            )
        if args.dry_run and not args.apply:
            patched += 1
            continue
        st, payload = http_json(
            "PATCH",
            f"{args.supabase_url.rstrip('/')}/rest/v1/posts?id=eq.{row['id']}",
            headers,
            {"created_at": iso, "updated_at": iso},
        )
        if st not in (200, 204):
            print(f"  patch fail {row.get('id')}: {st} {payload}")
            continue
        patched += 1

    print(f"{'Would promote' if not args.apply else 'Promoted'} {patched}/{len(rows)} R2 posts to feed top")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
