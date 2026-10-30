#!/usr/bin/env python3
"""
Go-live: give seed / entity profiles realistic display names + usernames.

Who gets fixed
  - Seed accounts: email like %@seed.matterya.internal
  - Bad/generic names: User123, User 000123, user_*, Member, Hubs, Channel,
    bare country names, empty / junk tokens, bot-looking handles

Name sources (country-appropriate when possible)
  1) fake_users_60k_real_names/fake_users_60k.jsonl  (skip userNNNN usernames)
  2) apps/web/public/names-by-country.json           (script-matched first+last)
  Never invent User# / country / Hubs fallbacks.

Also rewrites `__hub_origin__|…|an=BadName` stamps on share bodies so
“Shared from …” shows a real person/channel name after profiles are fixed.

How to run
  export SUPABASE_URL=https://bpdkltgikgbnfjswdbaj.supabase.co   # optional
  export SUPABASE_SERVICE_ROLE_KEY=...

  # Preview only
  python3 scripts/fix_seed_entity_profile_names.py --dry-run

  # Write profiles + hub_origin stamps
  python3 scripts/fix_seed_entity_profile_names.py --apply

  # Focus countries only
  python3 scripts/fix_seed_entity_profile_names.py --apply --countries US,DE,EG,AL

  # Skip post-body stamp repair
  python3 scripts/fix_seed_entity_profile_names.py --apply --profiles-only
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
FAKE_USERS = ROOT / "fake_users_60k_real_names" / "fake_users_60k.jsonl"
NAMES_BY_COUNTRY = ROOT / "apps" / "web" / "public" / "names-by-country.json"
DEFAULT_SUPABASE_URL = "https://bpdkltgikgbnfjswdbaj.supabase.co"
EMAIL_DOMAIN = "seed.matterya.internal"

BAD_TOKENS = {
    "ابو", "انا", "ام", "ana", "om", "abu", "umm", "امم", "ال", "بن", "بنت",
    "mr", "mrs", "ms", "miss", "dr", "user", "member", "hubs", "channel",
    "admin", "bot", "test", "demo", "null", "undefined",
}

# Exact display_name / username values that must never ship as a person.
GENERIC_EXACT = {
    "hubs", "channel", "member", "user", "admin", "bot", "test", "demo",
    "unknown", "anonymous", "matterya",
}

COUNTRY_NAME_ALIASES = {
    "united states", "united states of america", "usa", "us", "america",
    "germany", "deutschland", "de",
    "egypt", "مصر", "eg",
    "albania", "shqipëria", "shqiperia", "al",
    "france", "fr", "united kingdom", "uk", "great britain",
    "japan", "jp", "brazil", "br", "canada", "ca", "mexico", "mx",
    "saudi arabia", "sa", "greece", "gr", "south korea", "korea", "kr",
}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--supabase-url", default=os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL))
    p.add_argument("--service-role-key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""))
    p.add_argument("--countries", default="", help="Comma ISO codes; empty = all seed profiles")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--limit", type=int, default=0, help="Max profiles to fix (0 = all)")
    p.add_argument("--profiles-only", action="store_true", help="Skip hub_origin body repair")
    p.add_argument("--bodies-only", action="store_true", help="Skip profile patches; only repair stamps")
    return p.parse_args()


def http_json(method: str, url: str, headers: dict, body: Any = None, timeout: int = 90):
    data = None
    hdrs = dict(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = Request(url, data=data, headers=hdrs, method=method)
    try:
        with urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8") or "null"
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw
    except HTTPError as e:
        raw = e.read().decode("utf-8", errors="ignore")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"message": raw}
        return e.code, payload
    except URLError as e:
        return 0, {"message": str(e.reason)}


def name_script(token: str) -> str:
    if any("\u0600" <= ch <= "\u06FF" for ch in token):
        return "arabic"
    return "latin"


def split_name(display: str) -> Tuple[str, str]:
    parts = re.sub(r"\s+", " ", (display or "").strip()).split()
    if not parts:
        return "", ""
    if len(parts) == 1:
        return parts[0], ""
    return parts[0], " ".join(parts[1:])


def is_user_number_username(uname: str) -> bool:
    u = (uname or "").strip()
    if re.fullmatch(r"user_?\d+", u, flags=re.I):
        return True
    if re.fullmatch(r"user\s+\d+", u, flags=re.I):
        return True
    return False


def is_bad_display(display: str, country_name: str = "", country_code: str = "") -> bool:
    raw = (display or "").strip()
    if not raw:
        return True
    low = raw.casefold()
    if low in GENERIC_EXACT or low in COUNTRY_NAME_ALIASES:
        return True
    if country_name and low == country_name.strip().casefold():
        return True
    if country_code and low == country_code.strip().casefold():
        return True
    if re.fullmatch(r"user[_\s]?\d+", raw, flags=re.I):
        return True
    if raw.lower().startswith("user_"):
        return True
    first, last = split_name(raw)
    if first.casefold() in BAD_TOKENS:
        return True
    if last and last.casefold() in BAD_TOKENS:
        return True
    if not last and len(first) <= 2:
        return True
    # Mixed Arabic/Latin script pair
    if first and last and name_script(first) != name_script(last):
        return True
    return False


def is_bad_username(uname: str) -> bool:
    u = (uname or "").strip()
    if not u:
        return True
    if is_user_number_username(u):
        return True
    low = u.casefold()
    if low in GENERIC_EXACT or low in COUNTRY_NAME_ALIASES:
        return True
    if not re.search(r"[a-zA-Z\u0600-\u06FF]", u):
        return True
    return False


def ascii_slug(display: str, country: str, user_id: str) -> str:
    base = unicodedata.normalize("NFKD", display)
    base = "".join(c for c in base if not unicodedata.combining(c))
    base = base.lower()
    base = re.sub(r"[^a-z0-9]+", "_", base).strip("_")
    base = re.sub(r"_+", "_", base)[:18]
    if not base or base in GENERIC_EXACT or is_user_number_username(base):
        base = f"m{(country or 'xx').lower()}"
    h = (user_id or "").replace("-", "")[:4] or "seed"
    return f"{base}_{h}"


def load_fake_user_pools() -> Dict[str, List[dict]]:
    pools: Dict[str, List[dict]] = defaultdict(list)
    if not FAKE_USERS.exists():
        print(f"WARN missing {FAKE_USERS}", file=sys.stderr)
        return pools
    with FAKE_USERS.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            cc = str(row.get("country_code") or "").upper()
            if not cc:
                continue
            first = str(row.get("first_name") or "").strip()
            last = str(row.get("last_name") or "").strip()
            uname = str(row.get("username") or "").strip()
            display = f"{first} {last}".strip()
            if is_bad_display(display) or is_user_number_username(uname):
                continue
            if first and last and name_script(first) != name_script(last):
                continue
            pools[cc].append(
                {
                    "first": first,
                    "last": last,
                    "display": display,
                    "username": uname,
                }
            )
    return pools


def load_names_by_country() -> Dict[str, Dict[str, List[str]]]:
    out: Dict[str, Dict[str, List[str]]] = {}
    if not NAMES_BY_COUNTRY.exists():
        print(f"WARN missing {NAMES_BY_COUNTRY}", file=sys.stderr)
        return out
    data = json.loads(NAMES_BY_COUNTRY.read_text(encoding="utf-8"))
    for code, block in data.items():
        if not isinstance(block, dict):
            continue
        firsts = [str(x).strip() for x in (block.get("first") or []) if str(x).strip()]
        lasts = [str(x).strip() for x in (block.get("last") or []) if str(x).strip()]
        firsts = [f for f in firsts if f.casefold() not in BAD_TOKENS and len(f) > 1]
        lasts = [l for l in lasts if l.casefold() not in BAD_TOKENS and len(l) > 1]
        out[str(code).upper()] = {
            "first_ar": [f for f in firsts if name_script(f) == "arabic"],
            "first_lat": [f for f in firsts if name_script(f) == "latin"],
            "last_ar": [l for l in lasts if name_script(l) == "arabic"],
            "last_lat": [l for l in lasts if name_script(l) == "latin"],
            "first": firsts,
            "last": lasts,
        }
    return out


def pick_from_names_by_country(
    country: str,
    pools: Dict[str, Dict[str, List[str]]],
    rng: random.Random,
) -> Optional[Tuple[str, str]]:
    p = pools.get(country) or pools.get("US") or pools.get("DE") or {}
    # Prefer script-matched pairs
    if p.get("first_ar") and p.get("last_ar") and rng.random() < 0.45 and country in ("EG", "SA", "AE", "DZ", "MA"):
        return rng.choice(p["first_ar"]), rng.choice(p["last_ar"])
    if p.get("first_lat") and p.get("last_lat"):
        return rng.choice(p["first_lat"]), rng.choice(p["last_lat"])
    if p.get("first_ar") and p.get("last_ar"):
        return rng.choice(p["first_ar"]), rng.choice(p["last_ar"])
    if p.get("first") and p.get("last"):
        # Last resort: same-script filter
        for _ in range(40):
            f = rng.choice(p["first"])
            l = rng.choice(p["last"])
            if name_script(f) == name_script(l):
                return f, l
    return None


def pick_real_name(
    country: str,
    fake_pools: Dict[str, List[dict]],
    nbc: Dict[str, Dict[str, List[str]]],
    rng: random.Random,
    used_displays: Set[str],
) -> Tuple[str, str, str]:
    """Return (display, first, last). Never User# / country / Hubs.

    Prefer names-by-country (country-appropriate) first; fake_users_60k as
    secondary diversity when that pool is exhausted.
    """
    # 1) Country-appropriate lists (AL, EG Arabic/Latin matched, DE, US, …)
    for _ in range(80):
        picked = pick_from_names_by_country(country, nbc, rng)
        if not picked:
            break
        first, last = picked
        display = f"{first} {last}".strip()
        if is_bad_display(display) or display.casefold() in used_displays:
            continue
        used_displays.add(display.casefold())
        return display, first, last

    # 2) fake_users_60k rows tagged with this country_code
    candidates = list(fake_pools.get(country) or [])
    rng.shuffle(candidates)
    for row in candidates:
        display = row["display"]
        key = display.casefold()
        if key in used_displays:
            continue
        if is_bad_display(display):
            continue
        used_displays.add(key)
        return display, row["first"], row["last"]

    # Absolute last resort — still a real-looking Latin pair, never User#
    fallbacks = [
        ("Maya", "Nguyen"),
        ("Omar", "Hassan"),
        ("Lina", "Keller"),
        ("Noah", "Silva"),
        ("Aisha", "Rahman"),
        ("Jonas", "Berg"),
    ]
    for first, last in fallbacks:
        display = f"{first} {last}"
        if display.casefold() not in used_displays:
            used_displays.add(display.casefold())
            return display, first, last
    n = rng.randint(1000, 9999)
    first, last = "Elena", f"Costa{n}"
    return f"{first} {last}", first, last


def fetch_seed_profiles(url: str, key: str, countries: List[str], limit: int) -> List[dict]:
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    out: List[dict] = []
    page = 1000
    offset = 0
    while True:
        q = (
            f"{url.rstrip('/')}/rest/v1/profiles"
            f"?email=like.*@{EMAIL_DOMAIN}"
            f"&select=user_id,display_name,username,country_code,country_name,email,bio,city_name"
            f"&order=user_id.asc&limit={page}&offset={offset}"
        )
        if countries:
            q += f"&country_code=in.({','.join(countries)})"
        status, payload = http_json("GET", q, headers)
        if status != 200 or not isinstance(payload, list):
            print(f"fetch profiles failed: {status} {payload}", file=sys.stderr)
            break
        if not payload:
            break
        out.extend(payload)
        if limit and len(out) >= limit:
            return out[:limit]
        if len(payload) < page:
            break
        offset += page
    return out


def patch_profile(
    url: str,
    key: str,
    user_id: str,
    display: str,
    username: str,
    first: str,
    last: str,
) -> bool:
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    body = {"display_name": display, "username": username}
    status, payload = http_json(
        "PATCH",
        f"{url.rstrip('/')}/rest/v1/profiles?user_id=eq.{user_id}",
        headers,
        body,
    )
    if status not in (200, 204):
        print(f"  profile patch fail {user_id[:8]}: {status} {payload}")
        return False
    http_json(
        "PUT",
        f"{url.rstrip('/')}/auth/v1/admin/users/{user_id}",
        {
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        {
            "user_metadata": {
                "display_name": display,
                "username": username,
                "first_name": first,
                "last_name": last,
            }
        },
    )
    return True


_AN_RE = re.compile(r"(\|an=)([^|\n]*)", re.I)
_AU_RE = re.compile(r"(\|au=)([^|\n]*)", re.I)
_AID_RE = re.compile(r"\|aid=([^|\n]+)", re.I)


def repair_hub_origin_bodies(
    url: str,
    key: str,
    id_to_profile: Dict[str, dict],
    dry_run: bool,
) -> int:
    """Replace bad an=/au= on __hub_origin__ shares using fixed origin profiles."""
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    fixed = 0
    offset = 0
    page = 500
    while True:
        q = (
            f"{url.rstrip('/')}/rest/v1/posts"
            f"?body=like.*__hub_origin__*"
            f"&select=id,body"
            f"&order=id.asc&limit={page}&offset={offset}"
        )
        status, rows = http_json("GET", q, headers)
        if status != 200 or not isinstance(rows, list) or not rows:
            break
        for row in rows:
            body = str(row.get("body") or "")
            if "__hub_origin__|" not in body:
                continue
            m_aid = _AID_RE.search(body)
            if not m_aid:
                continue
            aid = m_aid.group(1).strip()
            prof = id_to_profile.get(aid)
            if not prof:
                continue
            new_an = str(prof.get("display_name") or "").strip()
            new_au = str(prof.get("username") or "").strip()
            if is_bad_display(new_an):
                continue
            m_an = _AN_RE.search(body)
            old_an = (m_an.group(2).strip() if m_an else "")
            if old_an and not is_bad_display(old_an, str(prof.get("country_name") or ""), str(prof.get("country_code") or "")):
                # already looks real
                continue
            new_body = body
            if m_an:
                new_body = _AN_RE.sub(lambda m: m.group(1) + new_an.replace("|", " "), new_body, count=1)
            else:
                # insert an= after aid=
                new_body = re.sub(
                    r"(\|aid=[^|\n]+)",
                    rf"\1|an={new_an.replace('|', ' ')}",
                    new_body,
                    count=1,
                )
            if new_au:
                if _AU_RE.search(new_body):
                    new_body = _AU_RE.sub(lambda m: m.group(1) + new_au.replace("|", ""), new_body, count=1)
                else:
                    new_body = re.sub(
                        r"(\|an=[^|\n]+)",
                        rf"\1|au={new_au.replace('|', '')}",
                        new_body,
                        count=1,
                    )
            if new_body == body:
                continue
            fixed += 1
            if fixed <= 8:
                print(f"  body {row['id'][:8]} an={old_an!r} → {new_an!r}")
            if dry_run:
                continue
            st, payload = http_json(
                "PATCH",
                f"{url.rstrip('/')}/rest/v1/posts?id=eq.{row['id']}",
                headers,
                {"body": new_body},
            )
            if st not in (200, 204):
                print(f"  body patch fail {row['id'][:8]}: {st} {payload}")
        if len(rows) < page:
            break
        offset += page
    return fixed


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
    rng = random.Random(args.seed)
    fake_pools = load_fake_user_pools()
    nbc = load_names_by_country()
    print(
        f"Name pools: fake_users countries={len(fake_pools)} "
        f"names-by-country={len(nbc)} "
        f"(US fake={len(fake_pools.get('US', []))}, AL nbc first_lat={len((nbc.get('AL') or {}).get('first_lat') or [])})"
    )

    profiles = fetch_seed_profiles(args.supabase_url, key, countries, args.limit)
    print(f"Loaded {len(profiles)} seed profiles" + (f" for {countries}" if countries else ""))

    used_usernames = {str(p.get("username") or "").lower() for p in profiles if p.get("username")}
    used_displays: Set[str] = set()
    for p in profiles:
        dn = str(p.get("display_name") or "").strip()
        if dn and not is_bad_display(dn, str(p.get("country_name") or ""), str(p.get("country_code") or "")):
            used_displays.add(dn.casefold())

    to_fix: List[dict] = []
    for pr in profiles:
        display = str(pr.get("display_name") or "").strip()
        uname = str(pr.get("username") or "").strip()
        cc = str(pr.get("country_code") or "").upper()
        cname = str(pr.get("country_name") or "")
        if is_bad_display(display, cname, cc) or is_bad_username(uname):
            to_fix.append(pr)

    print(f"Need name fix: {len(to_fix)}")
    print("Examples before:", [p.get("display_name") for p in to_fix[:12]])

    id_to_profile: Dict[str, dict] = {str(p["user_id"]): dict(p) for p in profiles}

    if not args.bodies_only:
        if args.dry_run and not args.apply:
            print("Dry-run profiles (pass --apply to write).")
        else:
            fixed = 0
            for pr in to_fix:
                uid = pr["user_id"]
                country = (pr.get("country_code") or "US").upper()
                old_display = str(pr.get("display_name") or "").strip()
                display, first, last = pick_real_name(country, fake_pools, nbc, rng, used_displays)
                uname = str(pr.get("username") or "")
                if is_bad_username(uname) or uname.lower() in used_usernames - {uname.lower()}:
                    uname = ascii_slug(
                        display if name_script(first) == "latin" else f"{country}_{uid[:6]}",
                        country,
                        uid,
                    )
                base = uname
                n = 0
                while uname.lower() in used_usernames and uname.lower() != str(pr.get("username") or "").lower():
                    n += 1
                    uname = f"{base[:16]}_{n}"
                used_usernames.add(uname.lower())

                if args.apply:
                    ok = patch_profile(args.supabase_url, key, uid, display, uname, first, last)
                    if not ok:
                        continue
                fixed += 1
                id_to_profile[uid] = {
                    **pr,
                    "display_name": display,
                    "username": uname,
                }
                if fixed <= 10:
                    print(f"  {old_display!r} → {display!r} (@{uname}) [{country}]")
            print(f"{'Would fix' if not args.apply else 'Fixed'} profiles: {fixed}/{len(to_fix)}")

    if not args.profiles_only:
        print("Repairing __hub_origin__ an=/au= stamps…")
        n_bodies = repair_hub_origin_bodies(
            args.supabase_url,
            key,
            id_to_profile,
            dry_run=not args.apply,
        )
        print(f"{'Would repair' if not args.apply else 'Repaired'} hub_origin bodies: {n_bodies}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
