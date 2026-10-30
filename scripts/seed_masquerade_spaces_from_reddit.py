#!/usr/bin/env python3
"""
Seed Masquerade Spaces from local Reddit packs:

  secrets       ← RedditPosts/OffMyChest/<om_*>
  HighlyStrange ← RedditPosts/Paranormal/<pn_*>
  SecretsStrangeMix (8782) → one Space per source subreddit + hub Spaces

Uses apps/api/.env DATABASE_URL. Idempotent via anonymous.posts.source_ref.

Authors: each post gets a distinct fake persona (adj_noun_####). Prefer one
post per persona; occasionally allow a second; never more than two.

Comments: most new posts get a thread from pack comments.json (or a short
synthetic thread) so the feed has more posts with comments than without.
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

SPACE_SOURCES = {
    "secrets": PACKS_ROOT / "OffMyChest",
    "highlystrange": PACKS_ROOT / "Paranormal",
}

# Mixed high-comment dump (progress :8782) — one Space per source subreddit.
MIX_ROOT = PACKS_ROOT / "SecretsStrangeMix"
CONFESSION_MIX_ROOT = PACKS_ROOT / "ConfessionAdultMix"
# Confession adult mix → Secrets + Confessions (+ any themed slug on the pack).
CONFESSION_MIX_SPACES = ("secrets", "confessions")
# Extra mix roots
EXTRA_MIX_ROOTS = [CONFESSION_MIX_ROOT] if CONFESSION_MIX_ROOT.exists() else []

# Canonical catalog (no duplicate rooms).
# Hubs: secrets + highlystrange. Themed: confessions, offmychest, glitch, paranormal, ghosts.
# slug → (display title, description, category, tags)
THEMED_SPACES: Dict[str, Tuple[str, str, str, List[str]]] = {
    "secrets": (
        "Secrets",
        "Anonymous confessions and things you needed to say out loud. Leave your identity outside.",
        "confessions",
        ["secrets", "confessions", "offmychest"],
    ),
    "highlystrange": (
        "HighlyStrange",
        "Paranormal encounters, unexplained events, and highly strange stories — told under a mask.",
        "paranormal",
        ["paranormal", "strange", "unexplained", "highstrangeness"],
    ),
    "confessions": (
        "Confessions",
        "Anonymous admissions and late-night honesty.",
        "confessions",
        ["confessions", "confession"],
    ),
    "offmychest": (
        "Off My Chest",
        "Say what you couldn't say elsewhere — unfiltered and sincere.",
        "confessions",
        ["offmychest", "trueoffmychest", "confessions"],
    ),
    "glitch": (
        "Glitch",
        "Reality hiccups, impossible coincidences, and matrix moments.",
        "strange",
        ["glitch", "strange"],
    ),
    "paranormal": (
        "Paranormal",
        "Ghosts, visitations, and what won't leave.",
        "paranormal",
        ["paranormal"],
    ),
    "ghosts": (
        "Ghosts",
        "Hauntings, presence stories, and fireside ghost tales.",
        "paranormal",
        ["ghosts", "ghoststories", "paranormal"],
    ),
}

# Legacy slug → canonical slug (seed + merge).
SPACE_MERGE_INTO: Dict[str, str] = {
    "highstrangeness": "highlystrange",
    "highly_strange": "highlystrange",
    "truthishere": "highlystrange",
    "confession": "confessions",
    "trueoffmychest": "offmychest",
    "ghoststories": "ghosts",
}

# Reddit subreddit name → Masquerade space slug (canonical only).
SUBREDDIT_TO_SPACE: Dict[str, str] = {
    "TrueOffMyChest": "offmychest",
    "confessions": "confessions",
    "offmychest": "offmychest",
    "confession": "confessions",
    "Glitch_in_the_Matrix": "glitch",
    "HighStrangeness": "highlystrange",
    "Paranormal": "paranormal",
    "Ghosts": "ghosts",
    "Thetruthishere": "highlystrange",
    "Ghoststories": "ghosts",
}


def canonical_space_slug(slug: str) -> str:
    s = (slug or "").strip().lower()
    return SPACE_MERGE_INTO.get(s, s)

AVATAR_PREFIX = "seed-persona-v1:"
MAX_POSTS_PER_PERSONA = 2
SECOND_POST_CHANCE = 0.12
# Chance a newly seeded post gets comments (keep a minority empty).
SEED_WITH_COMMENTS_CHANCE = 0.85
MAX_SEED_COMMENTS = 12
# Default high enough for full SecretsStrangeMix (~8k) + themed + hub passes.
LIMIT = int(os.environ.get("MASQUERADE_SEED_LIMIT", "25000"))
# Extra personas so mix packs stay near 1 post/author (grow more while seeding).
PERSONA_FLOOR = int(os.environ.get("MASQUERADE_PERSONA_FLOOR", "600"))

FALLBACK_COMMENT_BODIES = [
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
]

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


def generate_safe_username() -> str:
    return f"{random.choice(ADJECTIVES)}_{random.choice(NOUNS)}_{random.randint(1000, 9999)}"


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


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def pack_dirs(folder: Path) -> List[Path]:
    if not folder.is_dir():
        return []
    return sorted(
        [p for p in folder.iterdir() if p.is_dir() and (p / "post.json").exists()],
        key=lambda p: p.name,
    )


_CONFESS_BARE = re.compile(r"^\s*CONFESS\s*#\s*\d+\s*[:\-–—]?\s*", re.I | re.M)
_ANY_BRACKET = re.compile(r"\[[^\]]*\]")
# Reddit NSFW interstitial chrome accidentally scraped as post body.
_MATURE_GATE = re.compile(
    r"(?:(?:u/|@)\w+\s+)?"
    r"This is mature content and may not be appropriate for certain viewers\."
    r"(?:\s*To continue, use the app to verify you're over 18 and browse anonymously\.)?",
    re.I | re.S,
)


def strip_confess_number_tags(text: str) -> str:
    """Remove every `[...]` tag plus bare CONFESS #N prefixes from titles/bodies."""
    if not text:
        return text
    out = _ANY_BRACKET.sub("", text)
    out = _CONFESS_BARE.sub("", out)
    out = _MATURE_GATE.sub("", out)
    # Reddit user/path shorthand → Masquerade (@handle, space/…).
    out = re.sub(r"\bu/", "@", out, flags=re.I)
    out = re.sub(r"\br/", "space/", out, flags=re.I)
    out = re.sub(r"[ \t]{2,}", " ", out)
    out = re.sub(r"\s+\.", ".", out).strip()
    return out.strip()


def pick_body(post: Dict[str, Any]) -> Tuple[str, str]:
    title = strip_confess_number_tags(str(post.get("title") or "").strip())
    body = strip_confess_number_tags(str(post.get("body") or post.get("text") or "").strip())
    if body and title and body == title:
        # Prefer a single caption-style body when title duplicated the text.
        return title, body
    if not body and title:
        return title, title
    return title, body


def first_local_media(pack: Path, post: Dict[str, Any]) -> Tuple[Optional[str], Optional[str]]:
    """Return (media_type, relative hint). URLs are filled later if R2 prefix known."""
    images = post.get("local_images") or []
    videos = post.get("local_videos") or []
    media = pack / "media"
    if media.is_dir():
        for name in sorted(os.listdir(media)):
            lower = name.lower()
            if lower.endswith((".jpg", ".jpeg", ".png", ".webp")):
                return "image", name
            if lower.endswith((".mp4", ".webm", ".mov", ".m4v")):
                return "video", name
    if images:
        return "image", str(images[0])
    if videos:
        return "video", str(videos[0])
    if post.get("has_video"):
        return "video", None
    if int(post.get("image_count") or 0) > 0:
        return "image", None
    return None, None


# Private R2 — prefer 7-day signed GET (same as seed_masquerade_media_posts).
R2_BUCKET_DEFAULT = "matterya-sparks"
PRESIGN_SECONDS = 7 * 24 * 3600
_s3 = None


def get_s3(env: Dict[str, str]):
    global _s3
    if _s3 is not None:
        return _s3
    try:
        import boto3
        from botocore.config import Config
    except ImportError:
        return None
    account = env.get("R2_ACCOUNT_ID") or ""
    access = env.get("R2_ACCESS_KEY_ID") or ""
    secret = env.get("R2_SECRET_ACCESS_KEY") or ""
    if not (account and access and secret):
        return None
    _s3 = boto3.client(
        "s3",
        endpoint_url=f"https://{account}.r2.cloudflarestorage.com",
        aws_access_key_id=access,
        aws_secret_access_key=secret,
        region_name="auto",
        config=Config(signature_version="s3v4"),
    )
    return _s3


def media_ref(env: Dict[str, str], key: str) -> str:
    """Durable R2 ref — API re-signs on feed read (never store expiring https)."""
    clean = key.lstrip("/")
    bucket = env.get("R2_BUCKET") or R2_BUCKET_DEFAULT
    return f"r2:{bucket}/{clean}"


def load_upload_log_index(log_path: Path) -> Dict[str, Dict[str, Any]]:
    """Index R2 upload log by post_id once (per-pack scans were O(n²) and skipped media)."""
    out: Dict[str, Dict[str, Any]] = {}
    if not log_path.exists():
        return out
    for line in log_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        try:
            row = json.loads(line)
        except Exception:
            continue
        pid = row.get("post_id")
        if not pid or not row.get("ok"):
            continue
        out[str(pid)] = row
    return out


def media_from_upload_row(
    row: Optional[Dict[str, Any]], env: Dict[str, str]
) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    if not row:
        return None, None, None
    prefix = row.get("r2_prefix") or ""
    image_keys = row.get("r2_image_keys") or []
    video_key = row.get("r2_video_key")
    if video_key:
        url = media_ref(env, str(video_key))
        thumb = None
        if image_keys:
            thumb = media_ref(env, str(image_keys[0]))
        return "video", url, thumb
    if image_keys:
        url = media_ref(env, str(image_keys[0]))
        return "image", url, url
    if prefix and row.get("has_video"):
        url = media_ref(env, f"{prefix}/video.mp4")
        return "video", url, None
    if prefix and int(row.get("image_count") or 0) > 0:
        # Prefer real keys from media/ layout used by secretsstrange uploader.
        for cand in (
            f"{prefix}/media/01.jpg",
            f"{prefix}/media/01.png",
            f"{prefix}/media/01.webp",
            f"{prefix}/image_001.jpg",
        ):
            url = media_ref(env, cand)
            return "image", url, url
    return None, None, None


def media_from_upload_log(
    pack_id: str, log_path: Path, env: Dict[str, str]
) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """Legacy single-pack lookup — prefer load_upload_log_index in hot loops."""
    idx = load_upload_log_index(log_path)
    return media_from_upload_row(idx.get(pack_id), env)


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
    # Reddit user/path shorthand → Masquerade.
    t = re.sub(r"\bu/", "@", t, flags=re.I)
    t = re.sub(r"\br/", "space/", t, flags=re.I)
    t = re.sub(r"\s+", " ", t).strip()
    return t[:2000] if len(t) >= 4 else ""


def load_pack_comment_bodies(pack: Path) -> List[Dict[str, Any]]:
    path = pack / "comments.json"
    if not path.is_file():
        return []
    try:
        data = read_json(path)
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
            }
        )
    return out[:MAX_SEED_COMMENTS]


def clamp_comment_created(
    raw: Optional[datetime],
    post_created: datetime,
    index: int,
    total: int,
) -> datetime:
    """Keep replies after the post. Seeded posts are restamped into ~14d; raw
    Reddit comment times can be years earlier and must not survive as-is."""
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


def seed_comments_for_post(
    cur,
    post_id: str,
    post_author_id: str,
    pack: Path,
    personas: List[Dict[str, Any]],
    post_created: Optional[datetime] = None,
) -> int:
    """Insert a comment thread for a newly created post. Returns comment count."""
    if random.random() > SEED_WITH_COMMENTS_CHANCE:
        return 0
    bodies = load_pack_comment_bodies(pack)
    if not bodies:
        n = random.randint(2, 6)
        bodies = [
            {
                "body": random.choice(FALLBACK_COMMENT_BODIES),
                "score": random.randint(0, 8),
                "created": None,
            }
            for _ in range(n)
        ]
    commenters = [p for p in personas if p.get("username") != "archive_whisper"]
    if not commenters:
        created = insert_persona(cur)
        if created:
            personas.append(created)
            commenters = [created]
    if post_created is None:
        post_created = datetime.now(timezone.utc)
    inserted = 0
    root_ids: List[str] = []
    for idx, item in enumerate(bodies):
        pool = [p for p in commenters if p["id"] != post_author_id] or commenters
        author = random.choice(pool)
        parent_id = None
        depth = 0
        if root_ids and random.random() < 0.18:
            parent_id = random.choice(root_ids)
            depth = 1
        created = clamp_comment_created(
            item.get("created"), post_created, idx, len(bodies)
        )
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
                author["id"],
                item["body"],
                depth,
                max(0, int(item.get("score") or 0)),
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
            set comment_count = %s, updated_at = now()
            where id = %s::uuid
            """,
            (inserted, post_id),
        )
    return inserted


def list_seed_personas(cur) -> List[Dict[str, Any]]:
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
          and (
            p.avatar_seed like %s
            or p.avatar_seed = 'seed-archive-whisper-v1'
          )
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


def ensure_seed_personas(cur, min_available: int = 32) -> List[Dict[str, Any]]:
    personas = list_seed_personas(cur)
    available = sum(1 for p in personas if int(p["post_count"]) < MAX_POSTS_PER_PERSONA)
    guard = 0
    # Allow creating up to min_available personas (mix dump needs hundreds).
    while available < min_available and guard < min_available + 80:
        guard += 1
        created = insert_persona(cur)
        if not created:
            break
        personas.append(created)
        available += 1
    return personas


def ensure_space(cur, slug: str) -> Optional[Dict[str, Any]]:
    """Create or revive an adult_public free Space for Masquerade (canonical slug).

    Unknown slugs get a new room (title-cased) instead of collapsing into secrets —
    confession mix and themed packs may need extra Spaces on the fly.
    """
    slug = canonical_space_slug(slug)
    meta = THEMED_SPACES.get(slug)
    if not meta:
        # Create a fresh themed room when required (do not silently dump into secrets).
        pretty = slug.replace("_", " ").replace("-", " ").strip().title() or "Community"
        meta = (
            pretty,
            f"Anonymous posts in {pretty}. Leave your identity outside.",
            "confessions",
            [slug, "confessions"],
        )
        print(f"  creating new space: {slug} ({pretty})", flush=True)
    title, description, category, tags = meta
    display_slug = "HighlyStrange" if slug == "highlystrange" else slug
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
        on conflict (normalized_slug) do update
        set title = excluded.title,
            description = excluded.description,
            category = excluded.category,
            tags = excluded.tags,
            visibility = 'adult_public',
            admission = 'free',
            billing_mode = 'free',
            status = 'active',
            updated_at = now()
        returning id, title
        """,
        (display_slug, slug.lower(), title, description, category, tags),
    )
    row = cur.fetchone()
    if not row:
        return None
    # Default rules once per Space
    cur.execute(
        """
        insert into anonymous.space_rules (space_id, position, text, version)
        select %s::uuid, r.position, r.text, 1
        from (
          values
            (0, 'Be 18+. This entire section is adult-only.'),
            (1, 'No doxxing, threats, scams, or illegal content.'),
            (2, 'Do not share real names, contact info, or your ordinary Matterya identity.'),
            (3, 'Report abuse. Blocking and reporting are available to everyone.'),
            (4, 'Keep it real for this Space — kind to bystanders, sincere in strange stories.')
        ) as r(position, text)
        where not exists (
          select 1 from anonymous.space_rules sr where sr.space_id = %s::uuid
        )
        """,
        (row["id"], row["id"]),
    )
    return {"id": row["id"], "title": row["title"]}


def resolve_mix_space_slug(pack: Path) -> Tuple[str, str]:
    """Return (themed_sub_slug, hub_slug secrets|highlystrange) — always canonical."""
    hub = "secrets"
    sub_slug = "confessions"
    try:
        meta = read_json(pack / "meta.json") if (pack / "meta.json").exists() else {}
        post = read_json(pack / "post.json")
        hub = str(
            meta.get("masquerade_space") or post.get("masquerade_space") or "secrets"
        ).lower()
        hub = canonical_space_slug(hub)
        if hub not in ("secrets", "highlystrange"):
            hub = "secrets"
        sub = str(meta.get("subreddit") or meta.get("sub") or "").strip()
        sub_slug = SUBREDDIT_TO_SPACE.get(sub) or SUBREDDIT_TO_SPACE.get(
            sub.replace(" ", "")
        )
        if not sub_slug:
            sub_slug = "secrets" if hub == "secrets" else "highlystrange"
        else:
            sub_slug = canonical_space_slug(sub_slug)
    except Exception:
        pass
    return sub_slug, hub


def pick_seed_author(cur, personas: List[Dict[str, Any]]) -> Tuple[str, List[Dict[str, Any]]]:
    """Prefer 0-post authors; rarely allow a second; never a third. Mutates local counts."""
    # Never grow archive_whisper again — it was the monoculture dump.
    usable = [p for p in personas if p.get("username") != "archive_whisper"]
    zero = [p for p in usable if int(p["post_count"]) == 0]
    one = [p for p in usable if int(p["post_count"]) == 1]
    pool = zero
    if not zero or (one and random.random() < SECOND_POST_CHANCE):
        pool = one if one else zero
    if not pool:
        created = insert_persona(cur)
        if not created:
            raise RuntimeError("could not create seed persona")
        personas.append(created)
        pool = [created]
    pick = random.choice(pool)
    pick["post_count"] = int(pick["post_count"]) + 1
    return pick["id"], personas


def main() -> int:
    env = load_env(API_ENV)
    db_url = env.get("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL missing in apps/api/.env", file=sys.stderr)
        return 2

    import psycopg2
    from psycopg2.extras import RealDictCursor

    def open_conn():
        c = psycopg2.connect(
            db_url,
            connect_timeout=30,
            keepalives=1,
            keepalives_idle=30,
            keepalives_interval=10,
            keepalives_count=5,
        )
        c.autocommit = False
        # Drop idle-in-transaction killers on long comment inserts.
        with c.cursor() as kcur:
            kcur.execute("set statement_timeout = 0")
            kcur.execute("set idle_in_transaction_session_timeout = 0")
        c.commit()
        return c

    conn = open_conn()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    def reconnect(reason: str = "") -> None:
        nonlocal conn, cur
        print(f"  reconnecting DB… {reason}", flush=True)
        try:
            conn.close()
        except Exception:
            pass
        for attempt in range(1, 8):
            try:
                conn = open_conn()
                cur = conn.cursor(cursor_factory=RealDictCursor)
                print(f"  reconnected (attempt {attempt})", flush=True)
                return
            except Exception as exc:
                wait = min(60, 2 ** attempt)
                print(f"  reconnect failed ({exc}); sleep {wait}s", flush=True)
                import time as _time

                _time.sleep(wait)
        raise RuntimeError("could not reconnect to DATABASE_URL")

    def safe_commit() -> None:
        try:
            conn.commit()
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as exc:
            reconnect(str(exc))

    # Create personas in a short txn first — never hold the whole mix open.
    print(f"ensuring personas (floor={PERSONA_FLOOR})…", flush=True)
    try:
        personas = ensure_seed_personas(cur, min_available=PERSONA_FLOOR)
        safe_commit()
    except (psycopg2.OperationalError, psycopg2.InterfaceError) as exc:
        reconnect(str(exc))
        personas = ensure_seed_personas(cur, min_available=PERSONA_FLOOR)
        safe_commit()
    print(f"seed personas ready: {len(personas)}", flush=True)

    def backfill_missing_media() -> int:
        """Attach signed media to already-seeded mix posts that lost their images."""
        mix_idx = upload_indexes["mix"]
        cur.execute(
            """
            select id::text as id, source_ref, media_url, media_type
            from anonymous.posts
            where state = 'active'
              and (
                source_ref like 'reddit:mix:%'
                or source_ref like 'reddit:mixhub:%'
                or source_ref like 'reddit:secrets:%'
                or source_ref like 'reddit:highlystrange:%'
              )
            """
        )
        rows = list(cur.fetchall())
        fixed = 0
        for row in rows:
            ref = str(row["source_ref"] or "")
            pack_id = ref.split(":")[-1]
            # Prefer mix log; fall back to secrets/highlystrange logs by pack prefix.
            log_row = mix_idx.get(pack_id)
            if not log_row:
                for idx in upload_indexes.values():
                    if pack_id in idx:
                        log_row = idx[pack_id]
                        break
            media_type, media_url, thumb_url = media_from_upload_row(log_row, env)
            if not media_url:
                continue
            existing = row.get("media_url") or ""
            needs = (
                not existing
                or str(existing).startswith("r2://")
                or (str(existing).startswith("r2:") and "X-Amz-" not in str(existing))
            )
            if not needs and row.get("media_type") == media_type:
                continue
            cur.execute(
                """
                update anonymous.posts
                set media_type = %s,
                    media_url = %s,
                    thumb_url = coalesce(%s, thumb_url),
                    updated_at = now()
                where id = %s::uuid
                """,
                (media_type, media_url, thumb_url, row["id"]),
            )
            fixed += 1
            if fixed % 40 == 0:
                conn.commit()
                print(f"  media backfill …{fixed}", flush=True)
        conn.commit()
        return fixed

    upload_logs = {
        "secrets": PACKS_ROOT / "uploaded_offmychest_r2.jsonl",
        "highlystrange": PACKS_ROOT / "uploaded_paranormal_r2.jsonl",
        "mix": PACKS_ROOT / "uploaded_secretsstrange_r2.jsonl",
        "confession_mix": PACKS_ROOT / "uploaded_confession_mix_r2.jsonl",
    }
    upload_indexes = {k: load_upload_log_index(p) for k, p in upload_logs.items()}
    print(
        "upload log indexes: "
        + ", ".join(f"{k}={len(v)}" for k, v in upload_indexes.items()),
        flush=True,
    )

    print("backfilling media onto existing Masquerade posts…", flush=True)
    n_fixed = backfill_missing_media()
    print(f"media backfill fixed={n_fixed}", flush=True)

    total_inserted = 0
    total_skipped = 0
    COMMIT_EVERY = 40

    def seed_pack_list(
        slug: str,
        space: dict,
        packs: List[Path],
        log_key: str,
        source_prefix: Optional[str] = None,
    ) -> Tuple[int, int]:
        nonlocal personas
        inserted = 0
        skipped = 0
        log_idx = (
            upload_indexes.get(log_key)
            or upload_indexes.get(slug)
            or upload_indexes["mix"]
        )
        prefix = source_prefix or f"reddit:{slug}"
        since_commit = 0
        for pack in packs:
            post_path = pack / "post.json"
            try:
                post = read_json(post_path)
            except Exception as exc:
                print(f"  bad pack {pack.name}: {exc}")
                continue

            pack_id = str(post.get("post_id") or pack.name)
            source_ref = f"{prefix}:{pack_id}"
            title, body = pick_body(post)
            if not title and not body:
                skipped += 1
                continue

            media_type, media_url, thumb_url = media_from_upload_row(
                log_idx.get(pack_id), env
            )
            # Keep relative pack order from Reddit time, but land inside the last
            # ~14 days so Hot / For you actually surfaces the catalog.
            original = parse_ts(post.get("timestamp") or post.get("scraped_at"))
            now = datetime.now(timezone.utc)
            if original is not None:
                # Map original epoch into [now-14d, now] with light jitter.
                span = 14 * 24 * 3600
                bucket = int(original.timestamp()) % span
                created = now - timedelta(seconds=(span - bucket))
                created = created + timedelta(seconds=(hash(pack_id) % 600) - 300)
                if created > now:
                    created = now - timedelta(seconds=30)
            else:
                created = now
            score = int(post.get("score") or post.get("like_count") or 0)

            try:
                author_id, personas = pick_seed_author(cur, personas)
                cur.execute(
                    """
                    insert into anonymous.posts (
                      space_id, author_profile_id, title, body, state, score,
                      media_type, media_url, thumb_url, source_ref, created_at, updated_at
                    )
                    values (
                      %s, %s::uuid, %s, %s, 'active', %s,
                      %s, %s, %s, %s, %s, now()
                    )
                    on conflict (source_ref) do nothing
                    returning id
                    """,
                    (
                        space["id"],
                        author_id,
                        title[:200] if title else None,
                        body[:10000] or (title[:10000] if title else ""),
                        score,
                        media_type,
                        media_url,
                        thumb_url,
                        source_ref,
                        created,
                    ),
                )
                row = cur.fetchone()
            except (psycopg2.OperationalError, psycopg2.InterfaceError) as exc:
                reconnect(str(exc))
                # Pack may already be inserted — count as skip and continue.
                skipped += 1
                continue
            if row:
                inserted += 1
                try:
                    seed_comments_for_post(
                        cur, row["id"], author_id, pack, personas, post_created=created
                    )
                except (psycopg2.OperationalError, psycopg2.InterfaceError) as exc:
                    reconnect(str(exc))
                    # Post landed; comments can catch up on a later pass.
                    print(
                        f"    …{slug} comment seed interrupted after post {row['id']}: {exc}",
                        flush=True,
                    )
                since_commit += 1
                if since_commit >= COMMIT_EVERY:
                    safe_commit()
                    since_commit = 0
                    print(
                        f"    …{slug} inserted={inserted} skipped={skipped}",
                        flush=True,
                    )
            else:
                for p in personas:
                    if p["id"] == author_id:
                        p["post_count"] = max(0, int(p["post_count"]) - 1)
                        break
                skipped += 1
        if since_commit:
            safe_commit()
        return inserted, skipped

    def refresh_space_count(space: dict) -> None:
        cur.execute(
            """
            update anonymous.spaces
            set post_count = (
              select count(*)::int from anonymous.posts
              where space_id = %s and state = 'active'
            ),
            updated_at = now()
            where id = %s
            """,
            (space["id"], space["id"]),
        )

    # Ensure full themed catalog (8782 subs + hub Spaces).
    spaces_by_slug: Dict[str, dict] = {}
    for slug in THEMED_SPACES:
        space = ensure_space(cur, slug)
        if space:
            spaces_by_slug[slug] = space
            print(f"space ready: {slug} → {space['title']}", flush=True)
    conn.commit()

    for slug, folder in SPACE_SOURCES.items():
        space = spaces_by_slug.get(slug)
        if not space:
            print(f"skip {slug}: space missing")
            continue
        packs = pack_dirs(folder)[:LIMIT]
        print(f"{slug}: {len(packs)} local packs in {folder}")
        inserted, skipped = seed_pack_list(slug, space, packs, slug)
        refresh_space_count(space)
        print(f"  {slug}: inserted={inserted} skipped={skipped}")
        total_inserted += inserted
        total_skipped += skipped

    # 8782 SecretsStrangeMix → themed Space per subreddit (+ hub Space for feed density).
    if MIX_ROOT.exists():
        mix_packs = pack_dirs(MIX_ROOT)[:LIMIT]
        print(f"mix: {len(mix_packs)} packs in {MIX_ROOT}")
        by_themed: Dict[str, List[Path]] = {}
        by_hub: Dict[str, List[Path]] = {"secrets": [], "highlystrange": []}
        for pack in mix_packs:
            themed, hub = resolve_mix_space_slug(pack)
            by_themed.setdefault(themed, []).append(pack)
            by_hub.setdefault(hub, []).append(pack)

        for slug, packs in sorted(by_themed.items(), key=lambda x: x[0]):
            space = spaces_by_slug.get(slug) or ensure_space(cur, slug)
            if not space or not packs:
                continue
            spaces_by_slug[slug] = space
            inserted, skipped = seed_pack_list(
                slug, space, packs, "mix", source_prefix=f"reddit:mix:{slug}"
            )
            refresh_space_count(space)
            print(
                f"  mix→{slug}: inserted={inserted} skipped={skipped} packs={len(packs)}",
                flush=True,
            )
            total_inserted += inserted
            total_skipped += skipped

        # Also land packs on hub Spaces (secrets / HighlyStrange) for familiar shelves.
        for slug, packs in by_hub.items():
            space = spaces_by_slug.get(slug)
            if not space or not packs:
                continue
            inserted, skipped = seed_pack_list(
                slug, space, packs, "mix", source_prefix=f"reddit:mixhub:{slug}"
            )
            refresh_space_count(space)
            print(
                f"  mixhub→{slug}: inserted={inserted} skipped={skipped} packs={len(packs)}",
                flush=True,
            )
            total_inserted += inserted
            total_skipped += skipped

    # Confession adult mix → Secrets + Confessions (and any pack-declared themed space).
    # Anonymous adult-interest + ~40% legal NSFW. Create missing Spaces on the fly.
    if CONFESSION_MIX_ROOT.exists():
        conf_packs = pack_dirs(CONFESSION_MIX_ROOT)[:LIMIT]
        targets = list(CONFESSION_MIX_SPACES)
        print(
            f"confession_mix: {len(conf_packs)} packs in {CONFESSION_MIX_ROOT} → {', '.join(targets)}",
            flush=True,
        )
        if "confession_mix" not in upload_indexes:
            upload_indexes["confession_mix"] = load_upload_log_index(
                PACKS_ROOT / "uploaded_confession_mix_r2.jsonl"
            )
        # Extra rooms only when the pack explicitly names a Masquerade space
        # (or maps to a known themed slug). Raw Reddit sub names do not mint rooms.
        by_extra: Dict[str, List[Path]] = {}
        known = set(THEMED_SPACES) | set(SPACE_MERGE_INTO.values()) | set(targets)
        for pack in conf_packs:
            post_path = pack / "post.json"
            if not post_path.exists():
                continue
            try:
                post = json.loads(post_path.read_text(encoding="utf-8"))
            except Exception:
                continue
            explicit = post.get("masquerade_space") or post.get("space")
            raw = str(explicit or post.get("subreddit") or "").strip().lower()
            if not raw:
                continue
            extra = canonical_space_slug(raw)
            if not extra or extra in targets or extra == "confession_mix":
                continue
            # Explicit field → create room if needed. Subreddit → only known themes.
            if explicit or extra in known:
                by_extra.setdefault(extra, []).append(pack)

        for slug in targets:
            space = spaces_by_slug.get(slug) or ensure_space(cur, slug)
            if not space or not conf_packs:
                continue
            spaces_by_slug[slug] = space
            inserted, skipped = seed_pack_list(
                slug,
                space,
                conf_packs,
                "confession_mix",
                source_prefix=f"reddit:confession_mix:{slug}",
            )
            refresh_space_count(space)
            print(
                f"  confession_mix→{slug}: inserted={inserted} skipped={skipped} packs={len(conf_packs)}",
                flush=True,
            )
            total_inserted += inserted
            total_skipped += skipped

        for slug, packs in sorted(by_extra.items()):
            space = spaces_by_slug.get(slug) or ensure_space(cur, slug)
            if not space or not packs:
                continue
            spaces_by_slug[slug] = space
            inserted, skipped = seed_pack_list(
                slug,
                space,
                packs,
                "confession_mix",
                source_prefix=f"reddit:confession_mix:{slug}",
            )
            refresh_space_count(space)
            print(
                f"  confession_mix→{slug} (extra): inserted={inserted} skipped={skipped} packs={len(packs)}",
                flush=True,
            )
            total_inserted += inserted
            total_skipped += skipped

    safe_commit()
    cur.close()
    conn.close()
    print(f"done inserted={total_inserted} skipped={total_skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
