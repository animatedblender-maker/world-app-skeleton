#!/usr/bin/env python3
"""
Convert a Kaggle Reddit conversations dataset into the native seed_social format.

The native iOS app reads:
  apps/mobile/ios/App/App/public/seed_social/
    feeds/{ISO_A2}.jsonl
    comments/{ISO_A2}.jsonl
    users.jsonl
    manifest.json

This importer keeps the app fast by doing all expensive parsing before the app is
built. It accepts either a Kaggle dataset slug through kagglehub or a local input
directory/archive.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
import re
import shutil
import sys
import tarfile
import zipfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Iterator


DEFAULT_DATASET = "jerryqu/reddit-conversations"
ROOT = Path(__file__).resolve().parents[1]
IOS_PUBLIC = ROOT / "apps" / "mobile" / "ios" / "App" / "App" / "public"
COUNTRIES_GEOJSON = IOS_PUBLIC / "countries50m.geojson"
NAMES_BY_COUNTRY = IOS_PUBLIC / "names-by-country.json"
OUTPUT_DIR = IOS_PUBLIC / "seed_social"
CACHE_DIR = ROOT / ".cache" / "kaggle_reddit_conversations"
DEFAULT_NAMES_INPUT = (
    Path.home()
    / ".cache"
    / "kagglehub"
    / "datasets"
    / "amaleshvemula7"
    / "name-and-country-of-origin-dataset"
    / "versions"
    / "1"
)

TEXT_FIELDS = (
    "text",
    "body",
    "comment",
    "message",
    "utterance",
    "content",
    "selftext",
    "title",
)
ROOT_FIELDS = (
    "post",
    "submission",
    "prompt",
    "context",
    "parent",
    "parent_body",
    "parent_text",
    "source",
)
REPLY_FIELDS = (
    "reply",
    "response",
    "target",
    "answer",
    "comment",
    "body",
    "utterance",
)
CONVERSATION_FIELDS = (
    "conversation",
    "conversations",
    "messages",
    "thread",
    "dialogue",
    "dialog",
    "turns",
)
CATEGORY_FIELDS = (
    "subreddit",
    "subreddit_name",
    "topic",
    "category",
    "community",
)

TOPIC_FALLBACKS = [
    "daily life",
    "food",
    "work",
    "travel",
    "relationships",
    "sports",
    "tech",
    "music",
    "nightlife",
    "weather",
    "local news",
    "family",
    "culture",
    "commute",
    "study",
    "fitness",
    "markets",
    "nature",
]

CITY_FALLBACKS = [
    "Central District",
    "Old Town",
    "North Side",
    "West End",
    "Riverside",
    "Market Quarter",
    "University Area",
    "Harbor Side",
]

BIO_PATTERNS = [
    "Usually outside, usually curious.",
    "Local notes, food opinions, and too many photos.",
    "Here for real conversations and small details.",
    "Trying to understand the city one day at a time.",
    "Posts about life, people, and whatever the week brings.",
    "Quiet observer with loud opinions sometimes.",
]

BLOCKED_TEXT_PATTERNS = [
    r"\bkill(?:ed|ing)? myself\b",
    r"\bsuicid(?:e|al)\b",
    r"\bself[- ]?harm\b",
    r"\brape(?:d|s)?\b",
    r"\bchild porn\b",
    r"\bcp\b",
    r"\bnazi(?:s)?\b",
    r"\bfag(?:got)?s?\b",
    r"\bnigg(?:a|er)s?\b",
    r"\bretard(?:ed)?\b",
]


@dataclass
class Country:
    code: str
    iso3: str
    name: str
    formal_name: str
    continent: str
    region: str
    population: int


@dataclass
class SourceThread:
    root: str
    comments: list[str]
    category: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", default=DEFAULT_DATASET)
    parser.add_argument("--input", default="", help="Local dataset directory, file, zip, tar, tgz, or tar.gz.")
    parser.add_argument("--download", action="store_true", help="Download --dataset with kagglehub.")
    parser.add_argument("--output", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--average-posts", type=int, default=1000)
    parser.add_argument("--average-comments", type=float, default=5.0)
    parser.add_argument("--users-per-country", type=int, default=260)
    parser.add_argument("--names-input", default=str(DEFAULT_NAMES_INPUT), help="Local Kaggle names dataset directory/file.")
    parser.add_argument("--max-source-threads", type=int, default=600_000)
    parser.add_argument("--min-text-len", type=int, default=18)
    parser.add_argument("--seed", type=int, default=20260604)
    parser.add_argument("--sample-only", type=int, default=0, help="Only write this many countries for fast testing.")
    return parser.parse_args()


def stable_int(value: str) -> int:
    return int(hashlib.sha1(value.encode("utf-8")).hexdigest()[:12], 16)


def slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return normalized or "general"


def clean_text(value: object) -> str:
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    text = re.sub(r"https?://\S+", "", text).strip()
    if text.lower() in {"[deleted]", "[removed]", "deleted", "removed", "nan", "none", "null"}:
        return ""
    return text


def is_safe_text(text: str) -> bool:
    lowered = text.lower()
    if any(re.search(pattern, lowered, flags=re.IGNORECASE) for pattern in BLOCKED_TEXT_PATTERNS):
        return False
    if len(text) < 18 or len(text) > 520:
        return False
    if len(re.findall(r"[A-Za-z]", text)) < 12:
        return False
    if text.count("?") > 4 or text.count("!") > 4:
        return False
    if re.match(r"^[?.!,;:\-]+", text):
        return False
    return True


def safe_json(value: str) -> object | None:
    try:
        return json.loads(value)
    except Exception:
        return None


def pick_field(row: dict, names: Iterable[str]) -> str:
    lowered = {str(key).lower(): key for key in row.keys()}
    for name in names:
        key = lowered.get(name.lower())
        if key is not None:
            value = clean_text(row.get(key))
            if value:
                return value
    return ""


def country_rows() -> list[Country]:
    data = json.loads(COUNTRIES_GEOJSON.read_text(encoding="utf-8"))
    rows: list[Country] = []
    seen = set()
    for feature in data.get("features", []):
        props = feature.get("properties", {})
        code = str(props.get("ISO_A2") or props.get("WB_A2") or "").strip().upper()
        if not code or code == "-99" or code in seen:
            continue
        seen.add(code)
        name = props.get("NAME_EN") or props.get("NAME") or props.get("ADMIN") or code
        rows.append(
            Country(
                code=code,
                iso3=str(props.get("ISO_A3") or props.get("ADM0_A3") or code).strip().upper(),
                name=str(name),
                formal_name=str(props.get("FORMAL_EN") or props.get("NAME_LONG") or name),
                continent=str(props.get("CONTINENT") or "Unknown"),
                region=str(props.get("REGION_UN") or props.get("REGION_WB") or "Unknown"),
                population=int(float(props.get("POP_EST") or 0)),
            )
        )
    return rows


def clean_person_name(value: object) -> str:
    text = clean_text(value)
    text = re.sub(r"\b(Mr|Mrs|Ms|Miss|Dr|Prof)\.?\s+", "", text, flags=re.IGNORECASE).strip()
    text = re.sub(r"\b(Jr|Sr|DDS|DVM|MD|PhD|II|III|IV)\.?\b", "", text, flags=re.IGNORECASE).strip()
    text = re.sub(r"\s+", " ", text).strip(" ,.-")
    if len(text) < 3 or len(text) > 42:
        return ""
    if not re.search(r"[A-Za-z]", text):
        return ""
    return text


def load_name_pool(path_value: str) -> dict[str, list[str]]:
    source = Path(path_value).expanduser()
    if not source.exists():
        return {}
    files = [source] if source.is_file() else sorted(source.rglob("*.csv"), key=lambda item: item.stat().st_size, reverse=True)
    pools: dict[str, list[str]] = {}
    for path in files:
        with path.open("r", encoding="utf-8", errors="ignore", newline="") as handle:
            reader = csv.DictReader(handle)
            fields = {str(field).lower(): field for field in (reader.fieldnames or [])}
            name_field = fields.get("name")
            country_field = fields.get("country")
            if not name_field or not country_field:
                continue
            for row in reader:
                country = clean_text(row.get(country_field)).upper()
                name = clean_person_name(row.get(name_field))
                if not country or len(country) != 2 or not name:
                    continue
                pools.setdefault(country, []).append(name)
        if pools:
            break
    return pools


def pick_display_name(rng: random.Random, names: dict, code: str) -> str:
    pool = names.get(code) or names.get("GLOBAL") or []
    if pool:
        return str(rng.choice(pool))
    legacy = json.loads(NAMES_BY_COUNTRY.read_text(encoding="utf-8")) if NAMES_BY_COUNTRY.exists() else {}
    country_pool = legacy.get(code) or legacy.get("GLOBAL") or {}
    first = country_pool.get("first") or ["Alex", "Sam", "Maya", "Noah", "Lina", "Omar"]
    last = country_pool.get("last") or ["Khan", "Smith", "Garcia", "Kim", "Nasser", "Ivanov"]
    return f"{rng.choice(first)} {rng.choice(last)}"


def make_user(country: Country, index: int, names: dict) -> dict:
    rng = random.Random(stable_int(f"conv-user|{country.code}|{index}"))
    display_name = pick_display_name(rng, names, country.code)
    username = re.sub(r"[^a-z0-9]+", "_", display_name.lower()).strip("_")[:24]
    suffix = stable_int(f"{country.code}|{index}|conv") % 9999
    username = f"{username}{suffix:04d}"
    return {
        "user_id": f"seed_user_{country.code.lower()}_{index:04d}",
        "email": None,
        "display_name": display_name,
        "username": username,
        "avatar_url": f"https://api.dicebear.com/7.x/thumbs/png?seed={username}",
        "country_name": country.name,
        "country_code": country.code,
        "city_name": rng.choice(CITY_FALLBACKS),
        "bio": rng.choice(BIO_PATTERNS),
        "followers_count": int(rng.random() ** 2 * 16000),
        "following_count": int(rng.random() ** 1.7 * 2400),
    }


def post_count_for_country(country: Country, rng: random.Random, average: int) -> int:
    pop = max(country.population, 50_000)
    pop_factor = math.log10(pop) - 4.5
    base = average * (0.45 + max(0.0, pop_factor) * 0.28)
    jitter = rng.uniform(0.68, 1.42)
    count = int(base * jitter)
    if pop > 100_000_000:
        count = max(count, int(average * rng.uniform(1.4, 2.6)))
    elif pop < 1_000_000:
        count = min(count, int(average * rng.uniform(0.18, 0.55)))
    return max(120, min(3600, count))


def resolve_input(args: argparse.Namespace) -> Path:
    if args.input:
        source = Path(args.input).expanduser().resolve()
    elif args.download:
        try:
            import kagglehub  # type: ignore
        except ImportError as exc:
            raise RuntimeError("Install kagglehub first: pip install kagglehub") from exc
        source = Path(kagglehub.dataset_download(args.dataset)).resolve()
    else:
        raise RuntimeError("Pass --input /path/to/dataset or --download.")

    if source.is_file() and source.suffix.lower() in {".zip", ".tgz", ".gz", ".tar"}:
        return extract_archive(source)
    return source


def extract_archive(path: Path) -> Path:
    target = CACHE_DIR / path.stem.replace(".tar", "")
    marker = target / ".extracted"
    if marker.exists():
        return target
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            archive.extractall(target)
    elif tarfile.is_tarfile(path):
        with tarfile.open(path) as archive:
            archive.extractall(target)
    else:
        raise RuntimeError(f"Unsupported archive: {path}")
    marker.write_text("ok", encoding="utf-8")
    return target


def supported_files(root: Path) -> list[Path]:
    if root.is_file():
        files = [root]
    else:
        files = []
        for pattern in ("*.jsonl", "*.json", "*.csv", "*.tsv", "*.txt", "*.zip", "*.tgz", "*.tar.gz", "*.tar"):
            files.extend(root.rglob(pattern))
    extracted: list[Path] = []
    for path in files:
        if path.name.startswith(".") or not path.is_file():
            continue
        if path.suffix.lower() in {".zip", ".tgz", ".gz", ".tar"} and (zipfile.is_zipfile(path) or tarfile.is_tarfile(path)):
            extracted.extend(supported_files(extract_archive(path)))
        elif path.suffix.lower() in {".jsonl", ".json", ".csv", ".tsv", ".txt"}:
            extracted.append(path)
    extracted.sort(key=lambda item: item.stat().st_size, reverse=True)
    return extracted


def iter_csv_like(path: Path, delimiter: str) -> Iterator[dict]:
    with path.open("r", encoding="utf-8", errors="ignore", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        for row in reader:
            if isinstance(row, dict):
                yield row


def iter_json(path: Path) -> Iterator[dict]:
    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        payload = json.load(handle)
    if isinstance(payload, list):
        for item in payload:
            if isinstance(item, dict):
                yield item
    elif isinstance(payload, dict):
        for key in ("rows", "data", "items", "comments", "conversations"):
            value = payload.get(key)
            if isinstance(value, list):
                for item in value:
                    if isinstance(item, dict):
                        yield item
                return
        yield payload


def iter_jsonl(path: Path) -> Iterator[dict]:
    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            payload = safe_json(line)
            if isinstance(payload, dict):
                yield payload
            elif isinstance(payload, list):
                yield {"conversation": payload}


def iter_txt(path: Path) -> Iterator[dict]:
    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            payload = safe_json(line)
            if isinstance(payload, dict):
                yield payload
            elif isinstance(payload, list):
                yield {"conversation": payload}
            else:
                yield {"conversation": line}


def iter_rows(path: Path) -> Iterator[dict]:
    suffix = path.suffix.lower()
    if suffix == ".jsonl":
        yield from iter_jsonl(path)
    elif suffix == ".json":
        yield from iter_json(path)
    elif suffix == ".csv":
        yield from iter_csv_like(path, ",")
    elif suffix == ".tsv":
        yield from iter_csv_like(path, "\t")
    elif suffix == ".txt":
        yield from iter_txt(path)


def split_conversation_text(value: str) -> list[str]:
    text = clean_text(value)
    if not text:
        return []
    decoded = safe_json(text)
    if isinstance(decoded, list):
        return flatten_turns(decoded)
    separators = [
        r"\s*<eos>\s*",
        r"\s*__eou__\s*",
        r"\s*\|\|\|\s*",
        r"\s*\t+\s*",
        r"\s*\n+\s*",
        r"\s* User \d+:\s*",
        r"\s*Redditor:\s*",
    ]
    for pattern in separators:
        parts = [clean_text(part) for part in re.split(pattern, text, flags=re.IGNORECASE) if clean_text(part)]
        if len(parts) >= 2:
            return parts
    sentences = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9])", text)
    return [clean_text(part) for part in sentences if clean_text(part)]


def flatten_turns(value: object) -> list[str]:
    turns: list[str] = []
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                text = pick_field(item, TEXT_FIELDS + ROOT_FIELDS + REPLY_FIELDS)
                if text:
                    turns.append(text)
            elif isinstance(item, list):
                turns.extend(flatten_turns(item))
            else:
                text = clean_text(item)
                if text:
                    turns.append(text)
    elif isinstance(value, dict):
        for field in CONVERSATION_FIELDS:
            if field in value:
                turns.extend(flatten_turns(value[field]))
        if not turns:
            text = pick_field(value, TEXT_FIELDS + ROOT_FIELDS + REPLY_FIELDS)
            if text:
                turns.append(text)
    elif isinstance(value, str):
        turns.extend(split_conversation_text(value))
    return turns


def thread_from_row(row: dict, min_text_len: int) -> SourceThread | None:
    category = pick_field(row, CATEGORY_FIELDS) or "general"
    turns: list[str] = []

    numeric_turns = []
    for key, value in row.items():
        key_text = str(key).strip()
        if key_text.isdigit():
            numeric_turns.append((int(key_text), clean_text(value)))
    if numeric_turns:
        turns.extend(text for _, text in sorted(numeric_turns) if text)

    for field in CONVERSATION_FIELDS:
        lowered = {str(key).lower(): key for key in row.keys()}
        key = lowered.get(field.lower())
        if key is None:
            continue
        value = row.get(key)
        if isinstance(value, str):
            decoded = safe_json(value)
            turns.extend(flatten_turns(decoded if decoded is not None else value))
        else:
            turns.extend(flatten_turns(value))

    if not turns:
        root = pick_field(row, ROOT_FIELDS)
        reply = pick_field(row, REPLY_FIELDS)
        if root and reply and root != reply:
            turns = [root, reply]
        else:
            text = pick_field(row, TEXT_FIELDS)
            if text:
                turns = split_conversation_text(text)

    cleaned: list[str] = []
    seen = set()
    for turn in turns:
        text = clean_text(turn)
        if len(text) < min_text_len or not is_safe_text(text):
            continue
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(text)

    if len(cleaned) < 2:
        return None
    return SourceThread(root=cleaned[0], comments=cleaned[1:12], category=category)


def load_threads(source: Path, min_text_len: int, max_threads: int) -> list[SourceThread]:
    files = supported_files(source)
    if not files:
        raise RuntimeError(f"No supported dataset files found in {source}")
    print("Reading source files:")
    for path in files[:8]:
        print(f"  - {path} ({path.stat().st_size / 1024 / 1024:.1f} MB)")

    threads: list[SourceThread] = []
    seen_roots = set()
    for path in files:
        for row in iter_rows(path):
            thread = thread_from_row(row, min_text_len)
            if not thread:
                continue
            dedupe_key = hashlib.sha1((thread.root + "|" + thread.comments[0]).encode("utf-8")).hexdigest()
            if dedupe_key in seen_roots:
                continue
            seen_roots.add(dedupe_key)
            threads.append(thread)
            if len(threads) >= max_threads:
                return threads
    return threads


def make_post(country: Country, user: dict, thread: SourceThread, index: int, created_at: datetime) -> dict:
    rng = random.Random(stable_int(f"conv-post|{country.code}|{index}|{thread.root[:80]}"))
    media_roll = rng.random()
    media_type = "none"
    if media_roll < 0.08:
        media_type = "image"
    elif media_roll < 0.11:
        media_type = "video"
    like_count = int((rng.random() ** 2.1) * 6200)
    view_count = max(like_count * rng.randint(8, 34), int((rng.random() ** 1.8) * 160_000))
    title_words = thread.root.split()[:7]
    return {
        "id": f"seed_{country.code.lower()}_{index:05d}",
        "author_id": user["user_id"],
        "country_code": country.code,
        "country_name": country.name,
        "city_name": user["city_name"],
        "category_slug": slug(thread.category or rng.choice(TOPIC_FALLBACKS)),
        "title": " ".join(title_words).strip(" .,!?:;")[:90] if rng.random() < 0.48 else None,
        "body": thread.root,
        "visibility": "public",
        "like_count": like_count,
        "view_count": view_count,
        "created_at": created_at.isoformat().replace("+00:00", "Z"),
        "media": {
            "type": media_type,
            "query": f"{country.name} {thread.category or 'daily life'}",
            "url": None,
            "thumb_url": None,
        },
    }


def make_comments(country: Country, post: dict, users: list[dict], thread: SourceThread, average_comments: float) -> list[dict]:
    rng = random.Random(stable_int(f"conv-comments|{post['id']}"))
    base_time = datetime.fromisoformat(post["created_at"].replace("Z", "+00:00"))
    max_count = min(len(thread.comments), max(1, int(rng.expovariate(1 / average_comments)) + rng.randint(1, 4)))
    rows: list[dict] = []
    root_comment_ids: list[str] = []
    # One Reddit-style speaker = one Matterya user for the whole thread.
    # OP is the post author; a single stable partner leaves top-level comments
    # (and can leave several), so two comments are clearly from the same person.
    op_id = post["author_id"]
    partner = users[stable_int(f"partner|{post['id']}") % max(1, len(users))]
    partner_id = partner["user_id"]
    speaker_of: dict[str, str] = {}
    for index, body in enumerate(thread.comments[:max_count]):
        created = base_time + timedelta(minutes=rng.randint(2, 7200))
        is_reply = bool(root_comment_ids) and rng.random() < 0.32
        comment_id = f"seed_cmt_{post['id']}_{index:02d}"
        parent_id = rng.choice(root_comment_ids) if is_reply else None
        if parent_id is None:
            root_comment_ids.append(comment_id)
            author_id = partner_id
        else:
            parent_speaker = speaker_of.get(parent_id, op_id)
            author_id = partner_id if parent_speaker == op_id else op_id
        speaker_of[comment_id] = author_id
        rows.append(
            {
                "id": comment_id,
                "post_id": post["id"],
                "parent_id": parent_id,
                "author_id": author_id,
                "body": body,
                "like_count": int((rng.random() ** 2) * 220),
                "liked_by_me": False,
                "created_at": created.isoformat().replace("+00:00", "Z"),
            }
        )
    return rows


def write_jsonl(path: Path, rows: Iterable[dict]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
            count += 1
    return count


def import_dataset(args: argparse.Namespace) -> dict:
    source = resolve_input(args)
    threads = load_threads(source, args.min_text_len, args.max_source_threads)
    minimum_threads = 1 if args.sample_only > 0 else 100
    if len(threads) < minimum_threads:
        raise RuntimeError(f"Only found {len(threads)} usable conversations. Check the dataset schema/input.")
    print(f"Usable conversations: {len(threads):,}")

    rng = random.Random(args.seed)
    countries = country_rows()
    countries.sort(key=lambda item: item.name)
    if args.sample_only > 0:
        countries = countries[: args.sample_only]
    names = load_name_pool(args.names_input)
    print(f"Name pools: {sum(len(items) for items in names.values()):,} names across {len(names)} countries")

    output = args.output.expanduser().resolve()
    if output.exists():
        shutil.rmtree(output)
    (output / "feeds").mkdir(parents=True, exist_ok=True)
    (output / "comments").mkdir(parents=True, exist_ok=True)
    (output / "users").mkdir(parents=True, exist_ok=True)

    now = datetime(2026, 6, 1, tzinfo=timezone.utc)
    all_users: list[dict] = []
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": str(source),
        "dataset": args.dataset,
        "average_posts": args.average_posts,
        "countries": [],
        "totals": {"countries": 0, "users": 0, "posts": 0, "comments": 0},
    }

    thread_cursor = 0
    for country in countries:
        country_rng = random.Random(stable_int(f"{args.seed}|conv|{country.code}"))
        user_count = max(60, min(900, int(args.users_per_country * country_rng.uniform(0.55, 1.8))))
        post_count = post_count_for_country(country, country_rng, args.average_posts)
        users = [make_user(country, index, names) for index in range(user_count)]
        all_users.extend(users)

        posts: list[dict] = []
        comments: list[dict] = []
        for index in range(post_count):
            thread = threads[thread_cursor % len(threads)]
            thread_cursor += 1
            user = country_rng.choice(users)
            created = now - timedelta(
                minutes=country_rng.randint(0, 240_000),
                seconds=country_rng.randint(0, 59),
            )
            post = make_post(country, user, thread, index, created)
            post_comments = make_comments(country, post, users, thread, args.average_comments)
            post["comment_count"] = len(post_comments)
            posts.append(post)
            comments.extend(post_comments)

        posts.sort(key=lambda item: item["created_at"], reverse=True)
        comments.sort(key=lambda item: item["created_at"])
        write_jsonl(output / "feeds" / f"{country.code}.jsonl", posts)
        write_jsonl(output / "comments" / f"{country.code}.jsonl", comments)
        write_jsonl(output / "users" / f"{country.code}.jsonl", users)
        manifest["countries"].append(
            {
                "code": country.code,
                "iso3": country.iso3,
                "name": country.name,
                "users": len(users),
                "posts": len(posts),
                "comments": len(comments),
            }
        )

    write_jsonl(output / "users.jsonl", all_users)
    manifest["totals"] = {
        "countries": len(countries),
        "users": len(all_users),
        "posts": sum(item["posts"] for item in manifest["countries"]),
        "comments": sum(item["comments"] for item in manifest["countries"]),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest["totals"]


def main() -> int:
    args = parse_args()
    try:
        totals = import_dataset(args)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(totals, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
