#!/usr/bin/env python3
"""Strip every [bracket] tag from Masquerade post titles/bodies."""
from __future__ import annotations

import re
from pathlib import Path

import psycopg2
from psycopg2.extras import RealDictCursor

API_ENV = Path(__file__).resolve().parents[1] / "apps/api/.env"
BRACKET = re.compile(r"\[[^\]]*\]")
BARE = re.compile(r"^\s*CONFESS\s*#\s*\d+\s*[:\-–—]?\s*", re.I | re.M)


def load_env() -> dict:
    out = {}
    for line in API_ENV.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def clean(s: str | None) -> str | None:
    if s is None:
        return None
    out = BRACKET.sub("", s)
    out = BARE.sub("", out)
    out = re.sub(r"[ \t]{2,}", " ", out)
    out = re.sub(r"\s+\.", ".", out).strip()
    return out


def main() -> int:
    env = load_env()
    conn = psycopg2.connect(env["DATABASE_URL"], connect_timeout=30)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(
        r"""
        select id::text as id, title, body
        from anonymous.posts
        where state = 'active'
          and (
            coalesce(title, '') ~ '\[[^\]]*\]'
            or coalesce(body, '') ~ '\[[^\]]*\]'
            or coalesce(title, '') ~* 'CONFESS\s*#\s*\d+'
            or coalesce(body, '') ~* 'CONFESS\s*#\s*\d+'
          )
        """
    )
    rows = cur.fetchall()
    print(f"candidates: {len(rows)}")
    fixed = 0
    for r in rows:
        nt = clean(r["title"]) if r["title"] is not None else None
        nb = clean(r["body"]) if r["body"] is not None else None
        if nt == "":
            nt = None
        if nt == r["title"] and nb == r["body"]:
            continue
        cur.execute(
            """
            update anonymous.posts
            set title = %s, body = coalesce(%s, body), updated_at = now()
            where id = %s::uuid
            """,
            (nt, nb, r["id"]),
        )
        fixed += 1
        if fixed % 500 == 0:
            conn.commit()
            print(f"  … {fixed}", flush=True)
    conn.commit()
    cur.execute(
        r"""
        select count(*) as n from anonymous.posts
        where state = 'active'
          and (coalesce(title, '') ~ '\[[^\]]*\]' or coalesce(body, '') ~ '\[[^\]]*\]')
        """
    )
    print(f"done fixed={fixed} still_with_brackets={cur.fetchone()['n']}")
    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
