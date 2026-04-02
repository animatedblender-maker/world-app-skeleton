#!/usr/bin/env python3
"""Convert the Kaggle Reddit comments dataset into the app demo JSONL format.

The web app already reads:
  - demo_social_dataset_30k/posts.jsonl
  - demo_social_dataset_30k/comments.jsonl
  - demo_social_dataset_30k/video_captions.jsonl

This script keeps that contract and only replaces the data generation step.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import random
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional


DEFAULT_DATASET = "smagnan/1-million-reddit-comments-from-40-subreddits"
ROOT = Path(__file__).resolve().parents[1]
FAKE_USERS_PATH = ROOT / "fake_users_60k_real_names" / "fake_users_60k.jsonl"
OUTPUT_DIR = ROOT / "demo_social_dataset_30k"
WEB_PUBLIC_DIR = ROOT / "apps" / "web" / "public" / "demo_social_dataset_30k"

BODY_FIELDS = ("body", "comment", "text", "selftext")
AUTHOR_FIELDS = ("author", "username", "user", "author_name")
SUBREDDIT_FIELDS = ("subreddit", "subreddit_name", "subreddit_display_name")
COMMENT_ID_FIELDS = ("id", "comment_id", "name")
PARENT_ID_FIELDS = ("parent_id", "parent", "reply_to")
LINK_ID_FIELDS = ("link_id", "submission_id", "thread_id", "post_id")
TIMESTAMP_FIELDS = ("created_utc", "created_at", "created", "timestamp", "date")


@dataclass
class FakeUser:
  user_id: str
  country_code: str
  country_name: str


@dataclass
class SourceComment:
  comment_id: str
  root_id: str
  parent_id: Optional[str]
  author_key: str
  subreddit: str
  body: str
  created_at: str


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser()
  parser.add_argument("--dataset", default=DEFAULT_DATASET)
  parser.add_argument("--input-dir", default="")
  parser.add_argument("--output-dir", default=str(OUTPUT_DIR))
  parser.add_argument("--web-public-dir", default=str(WEB_PUBLIC_DIR))
  parser.add_argument("--download", action="store_true")
  parser.add_argument("--post-limit", type=int, default=30000)
  parser.add_argument("--comment-limit", type=int, default=90000)
  parser.add_argument("--max-comments-per-post", type=int, default=12)
  parser.add_argument("--min-body-len", type=int, default=24)
  return parser.parse_args()


def jsonl_rows(path: Path) -> Iterator[dict]:
  with path.open("r", encoding="utf-8", errors="ignore") as handle:
    for line in handle:
      line = line.strip()
      if not line:
        continue
      try:
        row = json.loads(line)
      except json.JSONDecodeError:
        continue
      if isinstance(row, dict):
        yield row


def json_rows(path: Path) -> Iterator[dict]:
  with path.open("r", encoding="utf-8", errors="ignore") as handle:
    try:
      payload = json.load(handle)
    except json.JSONDecodeError:
      return
  if isinstance(payload, list):
    for row in payload:
      if isinstance(row, dict):
        yield row
  elif isinstance(payload, dict):
    for key in ("rows", "data", "items", "comments"):
      value = payload.get(key)
      if isinstance(value, list):
        for row in value:
          if isinstance(row, dict):
            yield row
        return


def csv_rows(path: Path) -> Iterator[dict]:
  with path.open("r", encoding="utf-8", errors="ignore", newline="") as handle:
    reader = csv.DictReader(handle)
    for row in reader:
      if isinstance(row, dict):
        yield row


def iter_rows(path: Path) -> Iterator[dict]:
  suffix = path.suffix.lower()
  if suffix == ".jsonl":
    yield from jsonl_rows(path)
    return
  if suffix == ".csv":
    yield from csv_rows(path)
    return
  if suffix == ".json":
    yield from json_rows(path)
    return
  raise ValueError(f"Unsupported file type: {path}")


def pick_field(row: dict, names: Iterable[str]) -> Optional[str]:
  for name in names:
    if name in row and row[name] not in (None, ""):
      return str(row[name])
  return None


def clean_text(value: str) -> str:
  text = re.sub(r"\s+", " ", str(value or "")).strip()
  if text.lower() in {"[deleted]", "[removed]", "removed", "deleted"}:
    return ""
  return text


def slugify(value: str) -> str:
  slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
  return slug or "general"


def normalize_ref(value: Optional[str]) -> Optional[str]:
  if not value:
    return None
  text = str(value).strip()
  if not text:
    return None
  text = text.split("/")[-1]
  text = re.sub(r"^(t1_|t3_|comment_|post_)", "", text, flags=re.IGNORECASE)
  return text or None


def normalize_timestamp(row: dict) -> str:
  for field in TIMESTAMP_FIELDS:
    if field not in row or row[field] in (None, ""):
      continue
    raw = row[field]
    if isinstance(raw, (int, float)):
      dt = datetime.fromtimestamp(float(raw), tz=timezone.utc)
      return dt.isoformat()
    text = str(raw).strip()
    if not text:
      continue
    try:
      if re.fullmatch(r"\d+", text):
        dt = datetime.fromtimestamp(float(text), tz=timezone.utc)
        return dt.isoformat()
      dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
      if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
      return dt.astimezone(timezone.utc).isoformat()
    except ValueError:
      continue
  return datetime.now(timezone.utc).isoformat()


def short_title(body: str) -> Optional[str]:
  words = body.split()
  if len(words) < 4:
    return None
  title = " ".join(words[: min(6, len(words))]).strip(" .,!?:;\"'()[]{}")
  if not title:
    return None
  return title[:80]


def stable_index(key: str, size: int) -> int:
  digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
  return int(digest[:16], 16) % size


def load_fake_users(path: Path) -> List[FakeUser]:
  users: List[FakeUser] = []
  for row in jsonl_rows(path):
    user_id = str(row.get("user_id") or "").strip()
    country_code = str(row.get("country_code") or "").strip().upper()
    country_name = str(row.get("country") or "").strip()
    if not user_id or not country_code or not country_name:
      continue
    users.append(FakeUser(user_id=user_id, country_code=country_code, country_name=country_name))
  if not users:
    raise RuntimeError(f"No fake users loaded from {path}")
  return users


def pick_user(author_key: str, users: List[FakeUser]) -> FakeUser:
  return users[stable_index(author_key or "anonymous", len(users))]


def detect_source_file(input_dir: Path) -> Path:
  candidates: List[Path] = []
  for pattern in ("*.jsonl", "*.csv", "*.json"):
    candidates.extend(input_dir.rglob(pattern))
  candidates = [path for path in candidates if path.is_file()]
  if not candidates:
    raise RuntimeError(f"No supported dataset files found in {input_dir}")
  candidates.sort(key=lambda path: path.stat().st_size, reverse=True)
  return candidates[0]


def download_dataset(dataset: str) -> Path:
  try:
    import kagglehub  # type: ignore
  except ImportError as exc:
    raise RuntimeError("Install kagglehub first: pip install kagglehub") from exc
  return Path(kagglehub.dataset_download(dataset))


def normalize_comment(row: dict, min_body_len: int) -> Optional[SourceComment]:
  body = clean_text(pick_field(row, BODY_FIELDS) or "")
  if len(body) < min_body_len:
    return None

  subreddit = clean_text(pick_field(row, SUBREDDIT_FIELDS) or "general")
  author = clean_text(pick_field(row, AUTHOR_FIELDS) or "")
  comment_id = normalize_ref(pick_field(row, COMMENT_ID_FIELDS))
  if not comment_id:
    comment_id = hashlib.sha1(body.encode("utf-8")).hexdigest()[:16]
  if not author:
    author = f"anon_{hashlib.sha1((body + '|' + subreddit).encode('utf-8')).hexdigest()[:16]}"

  parent_id = normalize_ref(pick_field(row, PARENT_ID_FIELDS))
  root_id = normalize_ref(pick_field(row, LINK_ID_FIELDS)) or parent_id or comment_id
  created_at = normalize_timestamp(row)

  return SourceComment(
    comment_id=comment_id,
    root_id=root_id,
    parent_id=parent_id,
    author_key=author.lower(),
    subreddit=subreddit,
    body=body,
    created_at=created_at,
  )


def build_caption(comment: SourceComment) -> Optional[str]:
  words = comment.body.split()
  if len(words) < 5:
    return None
  lead = " ".join(words[: min(10, len(words))]).strip()
  return f"{lead[:100]}"


def make_post_row(index: int, comment: SourceComment, user: FakeUser) -> dict:
  return {
    "id": f"post_{index:08d}",
    "author_id": user.user_id,
    "country_code": user.country_code,
    "country_name": user.country_name,
    "category_slug": slugify(comment.subreddit),
    "title": short_title(comment.body),
    "body": comment.body,
    "visibility": "public",
    "created_at": comment.created_at,
    "media": None,
  }


def make_comment_row(index: int, post_id: str, comment: SourceComment, user: FakeUser, parent_id: Optional[str]) -> dict:
  return {
    "id": f"cmt_{index:08d}",
    "post_id": post_id,
    "author_id": user.user_id,
    "parent_id": parent_id,
    "body": comment.body,
    "created_at": comment.created_at,
  }


def write_jsonl(path: Path, rows: Iterable[dict]) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  with path.open("w", encoding="utf-8") as handle:
    for row in rows:
      handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def import_dataset(args: argparse.Namespace) -> None:
  users = load_fake_users(FAKE_USERS_PATH)

  if args.input_dir:
    input_dir = Path(args.input_dir).expanduser().resolve()
  elif args.download:
    input_dir = download_dataset(args.dataset).resolve()
  else:
    raise RuntimeError("Pass --input-dir or use --download.")

  source_file = detect_source_file(input_dir)
  print(f"Using source file: {source_file}")

  all_comments: List[SourceComment] = []
  for raw_row in iter_rows(source_file):
    comment = normalize_comment(raw_row, max(8, args.min_body_len // 2))
    if comment:
      all_comments.append(comment)

  if not all_comments:
    raise RuntimeError("No usable rows found in the dataset.")

  post_rows: List[dict] = []
  comment_rows: List[dict] = []
  caption_rows: List[dict] = []
  selected_post_comments: List[SourceComment] = []

  by_subreddit: Dict[str, List[SourceComment]] = {}
  for comment in all_comments:
    by_subreddit.setdefault(comment.subreddit, []).append(comment)

  post_index = 1
  used_for_posts: set[str] = set()
  source_iter = (comment for comment in all_comments if len(comment.body) >= args.min_body_len)
  for comment in source_iter:
    user = pick_user(comment.author_key, users)
    post_row = make_post_row(post_index, comment, user)
    post_rows.append(post_row)
    used_for_posts.add(comment.comment_id)
    selected_post_comments.append(comment)
    caption = build_caption(comment)
    if caption and post_index % 3 == 0:
      caption_rows.append(
        {
          "post_id": post_row["id"],
          "country_code": user.country_code,
          "category_slug": slugify(comment.subreddit),
          "caption": caption,
        }
      )
    post_index += 1
    if len(post_rows) >= args.post_limit:
      break

  posts_by_subreddit: Dict[str, List[dict]] = {}
  for post_row, comment in zip(post_rows, selected_post_comments):
    posts_by_subreddit.setdefault(comment.subreddit, []).append(post_row)

  comments_per_post: Dict[str, int] = {}
  comment_index = 1
  thread_comments: Dict[str, List[str]] = {}
  for subreddit, comments in by_subreddit.items():
    target_posts = posts_by_subreddit.get(subreddit, [])
    if not target_posts:
      continue
    post_ptr = 0
    for comment in comments:
      if comment.comment_id in used_for_posts:
        continue
      post = target_posts[post_ptr % len(target_posts)]
      post_id = post["id"]
      count_for_post = comments_per_post.get(post_id, 0)
      if count_for_post >= args.max_comments_per_post:
        post_ptr += 1
        continue
      parent_id = None
      existing = thread_comments.get(post_id, [])
      if existing and (comment_index % 5 == 0):
        parent_id = existing[-1]
      user = pick_user(comment.author_key, users)
      comment_row = make_comment_row(comment_index, post_id, comment, user, parent_id)
      comment_rows.append(comment_row)
      thread_comments.setdefault(post_id, []).append(comment_row["id"])
      comments_per_post[post_id] = count_for_post + 1
      comment_index += 1
      post_ptr += 1
      if len(comment_rows) >= args.comment_limit:
        break
    if len(comment_rows) >= args.comment_limit:
      break

  output_dir = Path(args.output_dir).expanduser().resolve()
  write_jsonl(output_dir / "posts.jsonl", post_rows)
  write_jsonl(output_dir / "comments.jsonl", comment_rows)
  write_jsonl(output_dir / "video_captions.jsonl", caption_rows)

  web_public_dir = Path(args.web_public_dir).expanduser().resolve()
  if web_public_dir != output_dir:
    web_public_dir.mkdir(parents=True, exist_ok=True)
    for name in ("posts.jsonl", "comments.jsonl", "video_captions.jsonl"):
      shutil.copy2(output_dir / name, web_public_dir / name)

  print(f"Wrote {len(post_rows)} posts to {output_dir / 'posts.jsonl'}")
  print(f"Wrote {len(comment_rows)} comments to {output_dir / 'comments.jsonl'}")
  print(f"Wrote {len(caption_rows)} captions to {output_dir / 'video_captions.jsonl'}")
  if web_public_dir != output_dir:
    print(f"Mirrored dataset into {web_public_dir}")


def main() -> int:
  args = parse_args()
  try:
    import_dataset(args)
  except Exception as exc:  # pragma: no cover - CLI path
    print(f"error: {exc}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
