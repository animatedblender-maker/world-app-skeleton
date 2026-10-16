#!/usr/bin/env python3
"""Patch STATUS.json for the launch progress page.

Examples:
  python3 update_status.py --headline "Auditing chat" --phase audit
  python3 update_status.py --surface feed --status in_progress --pct 40 --notes "..."
  python3 update_status.py --check feed_focus --done 1
  python3 update_status.py --log "Fixed focus autoplay"
  python3 update_status.py --overall 42 --running 1
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

STATUS = Path(__file__).resolve().parent / "STATUS.json"


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--headline")
    ap.add_argument("--phase")
    ap.add_argument("--overall", type=float)
    ap.add_argument("--running", type=int, choices=[0, 1])
    ap.add_argument("--surface")
    ap.add_argument("--status")
    ap.add_argument("--pct", type=float)
    ap.add_argument("--notes")
    ap.add_argument("--goal")
    ap.add_argument("--check")
    ap.add_argument("--done", type=int, choices=[0, 1])
    ap.add_argument("--log")
    args = ap.parse_args()

    data = json.loads(STATUS.read_text(encoding="utf-8"))
    data["updated_at"] = now()
    if args.headline is not None:
        data["headline"] = args.headline
    if args.phase is not None:
        data["phase"] = args.phase
    if args.overall is not None:
        data["overall_pct"] = args.overall
    if args.running is not None:
        data["running"] = bool(args.running)

    if args.surface:
        for s in data.get("surfaces", []):
            if s.get("id") == args.surface:
                if args.status is not None:
                    s["status"] = args.status
                if args.pct is not None:
                    s["pct"] = args.pct
                if args.notes is not None:
                    s["notes"] = args.notes
                if args.goal is not None:
                    s["goal"] = args.goal
                break

    if args.check is not None and args.done is not None:
        for c in data.get("checklist", []):
            if c.get("id") == args.check:
                c["done"] = bool(args.done)
                break

    if args.log:
        data.setdefault("log", []).append({"t": now(), "msg": args.log})
        data["log"] = data["log"][-80:]

    # Recompute overall from surfaces if not explicitly set
    if args.overall is None and data.get("surfaces"):
        data["overall_pct"] = round(
            sum(float(s.get("pct") or 0) for s in data["surfaces"]) / len(data["surfaces"]), 1
        )

    STATUS.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"updated overall={data.get('overall_pct')} headline={data.get('headline')}")


if __name__ == "__main__":
    main()
