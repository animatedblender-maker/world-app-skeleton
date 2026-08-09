#!/usr/bin/env python3
"""Live progress page for R2 → Matterya (Supabase) four-country seed.

  python3 scripts/seed_progress_server.py
  open http://127.0.0.1:8770/
"""

from __future__ import annotations

import collections
import json
import os
import re
import subprocess
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOG = ROOT / "scripts" / "seed_r2_focus_log.jsonl"
SR_KEY = Path("/tmp/matterya_sr.key")
SUPABASE = os.environ.get("SUPABASE_URL", "https://bpdkltgikgbnfjswdbaj.supabase.co").rstrip("/")

# Expected complete packs (from last R2 list — refreshed soft via log + known totals)
R2_EXPECTED = {
    "spark:US": 1362,
    "spark:DE": 825,
    "spark:EG": 866,
    "spark:AL": 653,
    "longform:US": 46,
    "longform:DE": 44,
    "longform:EG": 44,
    "longform:AL": 38,
}
TOTAL_EXPECTED = sum(R2_EXPECTED.values())

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Matterya · R2 seed progress</title>
<style>
  :root {
    --bg: #0a0c12;
    --card: #12151e;
    --ink: #e8ecf4;
    --muted: #8b93a7;
    --accent: #00b4e4;
    --ok: #3dd68c;
    --warn: #f5a524;
    --err: #ff6b81;
    --bar: #1c2230;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
    background: radial-gradient(1200px 600px at 10% -10%, #0d3a4a 0%, transparent 50%),
                radial-gradient(900px 500px at 100% 0%, #1a1040 0%, transparent 45%),
                var(--bg);
    color: var(--ink); min-height: 100vh; padding: 28px 20px 48px;
  }
  h1 { font-size: 22px; font-weight: 700; letter-spacing: -0.02em; margin: 0 0 4px; }
  .sub { color: var(--muted); font-size: 13px; margin-bottom: 22px; }
  .grid { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); max-width: 960px; }
  .card {
    background: linear-gradient(180deg, #161a26, var(--card));
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 16px; padding: 16px 18px;
  }
  .card.wide { grid-column: 1 / -1; }
  .label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); font-weight: 700; }
  .value { font-size: 28px; font-weight: 800; margin-top: 6px; font-variant-numeric: tabular-nums; }
  .value.sm { font-size: 18px; }
  .ok { color: var(--ok); } .warn { color: var(--warn); } .err { color: var(--err); } .accent { color: var(--accent); }
  .bar {
    height: 12px; background: var(--bar); border-radius: 999px; overflow: hidden; margin-top: 12px;
  }
  .bar > i {
    display: block; height: 100%; background: linear-gradient(90deg, #0088b0, var(--accent), #5eead4);
    border-radius: 999px; width: 0%; transition: width 0.5s ease;
  }
  table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 10px; }
  th, td { text-align: left; padding: 8px 6px; border-bottom: 1px solid rgba(255,255,255,0.05); }
  th { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; }
  td.num { font-variant-numeric: tabular-nums; text-align: right; }
  .pill {
    display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 999px;
    font-size: 12px; font-weight: 700; background: rgba(0,180,228,0.12); color: var(--accent);
  }
  .pill.running { background: rgba(61,214,140,0.12); color: var(--ok); }
  .pill.done { background: rgba(61,214,140,0.18); color: var(--ok); }
  .pill.stopped { background: rgba(255,107,129,0.12); color: var(--err); }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: currentColor; box-shadow: 0 0 8px currentColor; }
  .meta { color: var(--muted); font-size: 12px; margin-top: 8px; line-height: 1.5; }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11px; color: #b8c0d4; }
</style>
</head>
<body>
  <h1>R2 → Matterya seed</h1>
  <p class="sub">Egypt · Germany · Albania · America — Sparks + LongForm into feed posts + comments</p>

  <div class="grid" id="root">
    <div class="card wide"><div class="label">Loading…</div></div>
  </div>

<script>
async function tick() {
  try {
    const r = await fetch('/api/status?t=' + Date.now());
    const s = await r.json();
    render(s);
  } catch (e) {
    document.getElementById('root').innerHTML =
      '<div class="card wide"><div class="label err">Cannot reach progress API</div><div class="meta">'+e+'</div></div>';
  }
}
function pct(n, d) { return d > 0 ? Math.min(100, (100 * n / d)) : 0; }
function fmt(n) { return (n ?? 0).toLocaleString(); }
function render(s) {
  const p = pct(s.seeded, s.expected);
  const statusClass = s.running ? 'running' : (s.seeded >= s.expected * 0.99 ? 'done' : 'stopped');
  const statusLabel = s.running ? 'Running' : (s.seeded >= s.expected * 0.99 ? 'Complete' : 'Not running');
  const rows = (s.by_key || []).map(row => {
    const rp = pct(row.seeded, row.expected);
    return `<tr>
      <td>${row.kind}</td><td>${row.country}</td>
      <td class="num">${fmt(row.seeded)}</td>
      <td class="num">${fmt(row.expected)}</td>
      <td class="num">${rp.toFixed(0)}%</td>
    </tr>`;
  }).join('');
  document.getElementById('root').innerHTML = `
    <div class="card">
      <div class="label">Status</div>
      <div class="value sm"><span class="pill ${statusClass}"><span class="dot"></span>${statusLabel}</span></div>
      <div class="meta">PID ${s.pid || '—'} · ${s.elapsed || '—'}</div>
    </div>
    <div class="card">
      <div class="label">Seeded posts</div>
      <div class="value accent">${fmt(s.seeded)}</div>
      <div class="meta">of ~${fmt(s.expected)} R2 packs</div>
    </div>
    <div class="card">
      <div class="label">Comments written</div>
      <div class="value">${fmt(s.comments)}</div>
      <div class="meta">from country user pool</div>
    </div>
    <div class="card">
      <div class="label">Errors</div>
      <div class="value ${s.errors ? 'err' : 'ok'}">${fmt(s.errors)}</div>
      <div class="meta">log lines ${fmt(s.log_lines)}</div>
    </div>
    <div class="card wide">
      <div class="label">Overall progress</div>
      <div class="value sm">${p.toFixed(1)}%</div>
      <div class="bar"><i style="width:${p.toFixed(2)}%"></i></div>
      <div class="meta">Rate ~${(s.rate || 0).toFixed(1)} posts/s · ETA ${s.eta || '—'}</div>
    </div>
    <div class="card wide">
      <div class="label">By market</div>
      <table>
        <thead><tr><th>Kind</th><th>Country</th><th class="num">Seeded</th><th class="num">R2</th><th class="num">%</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>
    <div class="card wide">
      <div class="label">Live DB (Supabase)</div>
      <div class="value sm">${fmt(s.db_r2_posts)} r2 posts · ${fmt(s.db_video_posts)} video posts total</div>
      <div class="meta">Profiles US ${s.profiles?.US ?? '—'} · DE ${s.profiles?.DE ?? '—'} · EG ${s.profiles?.EG ?? '—'} · AL ${s.profiles?.AL ?? '—'}</div>
      <div class="meta" style="margin-top:10px">Log <code>${s.log_path || ''}</code></div>
      <div class="meta">Latest: <code>${(s.latest || '—').replace(/</g,'&lt;')}</code></div>
    </div>
  `;
}
tick();
setInterval(tick, 2000);
</script>
</body>
</html>
"""


def seed_process_info():
    try:
        out = subprocess.check_output(
            ["ps", "aux"], text=True, stderr=subprocess.DEVNULL
        )
    except Exception:
        return None, None
    for line in out.splitlines():
        if "seed_r2_focus_four_countries.py" in line and "grep" not in line:
            parts = line.split()
            if len(parts) >= 11:
                pid = parts[1]
                etime = parts[9] if len(parts) > 9 else ""
                # ps aux: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
                # TIME is parts[9], etime not shown — use START
                return pid, parts[9]
    return None, None


def parse_log():
    stats = collections.Counter()
    by = collections.Counter()
    comments = 0
    latest = ""
    lines = 0
    if not LOG.exists():
        return stats, by, comments, latest, lines
    with LOG.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            lines += 1
            try:
                o = json.loads(line)
            except json.JSONDecodeError:
                continue
            st = o.get("status") or "?"
            stats[st] += 1
            if st == "ok":
                key = f"{o.get('kind')}:{o.get('country')}"
                by[key] += 1
                comments += int(o.get("comments") or 0)
            latest = line[-180:]
    return stats, by, comments, latest, lines


def db_counts():
    if not SR_KEY.exists():
        return {}, None, None
    key = SR_KEY.read_text().strip()
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Prefer": "count=exact",
    }

    def count(path: str) -> int:
        req = urllib.request.Request(SUPABASE + path, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                cr = resp.headers.get("Content-Range") or resp.headers.get("content-range") or ""
                if "/" in cr:
                    return int(cr.split("/")[-1])
        except Exception:
            return -1
        return -1

    profiles = {}
    for cc in ("US", "DE", "EG", "AL"):
        profiles[cc] = count(
            f"/rest/v1/profiles?select=user_id&country_code=eq.{cc}&limit=1"
        )
    r2_posts = count(
        "/rest/v1/posts?select=id&media_path=like.r2:matterya-sparks/*&limit=1"
    )
    video_posts = count(
        "/rest/v1/posts?select=id&media_type=eq.video&limit=1"
    )
    return profiles, r2_posts, video_posts


_db_cache = {"t": 0.0, "data": ({}, None, None)}


def status_payload():
    stats, by, comments, latest, lines = parse_log()
    seeded = stats.get("ok", 0)
    errors = stats.get("error", 0)
    pid, etime = seed_process_info()
    running = pid is not None

    # Soft DB poll every 8s
    now = time.time()
    if now - _db_cache["t"] > 8:
        _db_cache["data"] = db_counts()
        _db_cache["t"] = now
    profiles, r2_posts, video_posts = _db_cache["data"]

    # Prefer live DB count when available
    if isinstance(r2_posts, int) and r2_posts >= 0:
        seeded_display = r2_posts
    else:
        seeded_display = seeded

    remaining = max(0, TOTAL_EXPECTED - seeded_display)
    # crude rate from log growth if running
    rate = 0.0
    eta = "—"
    if running and LOG.exists():
        try:
            age = max(1.0, time.time() - LOG.stat().st_mtime + 1)
            # better: use process start approximation via log line count / elapsed
            rate = seeded / max(1.0, lines / max(seeded, 1) * 0.35)  # fallback
        except Exception:
            pass
        # simpler rate estimate: ok / minutes of log file growth
        try:
            # file mtime vs first line age not easy — use lines/seeded as proxy
            if seeded > 50:
                # assume ~3 posts/s from earlier pilot
                rate = 3.0
                secs = remaining / rate
                if secs < 90:
                    eta = f"{int(secs)}s"
                else:
                    eta = f"{int(secs // 60)}m {int(secs % 60)}s"
        except Exception:
            pass

    by_key = []
    order = [
        ("spark", "US"),
        ("spark", "DE"),
        ("spark", "EG"),
        ("spark", "AL"),
        ("longform", "US"),
        ("longform", "DE"),
        ("longform", "EG"),
        ("longform", "AL"),
    ]
    for kind, cc in order:
        k = f"{kind}:{cc}"
        by_key.append(
            {
                "kind": kind,
                "country": cc,
                "seeded": by.get(k, 0),
                "expected": R2_EXPECTED.get(k, 0),
            }
        )

    return {
        "running": running,
        "pid": pid,
        "elapsed": etime,
        "seeded": seeded_display,
        "log_ok": seeded,
        "expected": TOTAL_EXPECTED,
        "comments": comments,
        "errors": errors,
        "log_lines": lines,
        "rate": rate,
        "eta": eta,
        "by_key": by_key,
        "profiles": profiles,
        "db_r2_posts": r2_posts,
        "db_video_posts": video_posts,
        "log_path": str(LOG),
        "latest": latest,
        "ts": time.time(),
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            body = HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/status":
            payload = json.dumps(status_payload()).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_error(404)


def main():
    port = int(os.environ.get("SEED_PROGRESS_PORT", "8770"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Seed progress → http://127.0.0.1:{port}/")
    print(f"Log: {LOG}")
    server.serve_forever()


if __name__ == "__main__":
    main()
