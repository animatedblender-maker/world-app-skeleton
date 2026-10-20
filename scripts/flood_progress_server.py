#!/usr/bin/env python3
"""Live progress page for R2 → Matterya content-pipeline flood (--ingest-only --fast).

  python3 scripts/flood_progress_server.py
  open http://127.0.0.1:8777/
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("FLOOD_PROGRESS_PORT", "8777"))
LOG = Path(os.environ.get("FLOOD_LOG", "/tmp/matterya-pipeline/flood.log"))
PID_FILE = Path(os.environ.get("FLOOD_PID_FILE", "/tmp/matterya-pipeline/flood.pid"))

INGEST_RE = re.compile(r"\[(\d+)/(\d+)\]\s+INGEST\s+(\w+)\s+·\s+(\w+)")
NEW_PACKS_RE = re.compile(r"New packs to ingest:\s+(\d+)\s+\(skipped existing:\s+(\d+)\)")
DONE_RE = re.compile(r"DONE ok=")
CAPTION_RE = re.compile(r"caption:\s+(.+)$")
RESTART_MARK = "===== RESTART"

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Matterya · R2 flood progress</title>
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
  .grid { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); max-width: 980px; }
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
  .bar { height: 12px; background: var(--bar); border-radius: 999px; overflow: hidden; margin-top: 12px; }
  .bar > i {
    display: block; height: 100%;
    background: linear-gradient(90deg, #0088b0, var(--accent), #5eead4);
    border-radius: 999px; width: 0%; transition: width 0.45s ease;
  }
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
  ul.live { list-style: none; margin: 10px 0 0; padding: 0; max-height: 280px; overflow: auto; }
  ul.live li {
    padding: 8px 0; border-bottom: 1px solid rgba(255,255,255,0.05);
    font-size: 13px; line-height: 1.35;
  }
  ul.live .tag { color: var(--accent); font-weight: 700; font-size: 11px; margin-right: 8px; }
  a.link { color: var(--accent); text-decoration: none; font-weight: 600; }
  a.link:hover { text-decoration: underline; }
</style>
</head>
<body>
  <h1>R2 → Matterya flood</h1>
  <p class="sub">Ingest-only · fast · Sparks + ShortForm + LongForm into live posts
    · <a class="link" href="https://matterya.com" target="_blank" rel="noopener">matterya.com</a>
  </p>
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
function esc(t) {
  return String(t ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function render(s) {
  const p = pct(s.current, s.total);
  const statusClass = s.done ? 'done' : (s.running ? 'running' : 'stopped');
  const statusLabel = s.done ? 'Complete' : (s.running ? 'Running' : 'Stopped');
  const recent = (s.recent || []).map(row =>
    `<li><span class="tag">${esc(row.country)} · ${esc(row.kind)}</span>${esc(row.caption || row.raw)}</li>`
  ).join('');
  document.getElementById('root').innerHTML = `
    <div class="card">
      <div class="label">Status</div>
      <div class="value sm"><span class="pill ${statusClass}"><span class="dot"></span>${statusLabel}</span></div>
      <div class="meta">PID ${s.pid || '—'} · uptime ${s.elapsed || '—'}</div>
    </div>
    <div class="card">
      <div class="label">This run</div>
      <div class="value accent">${fmt(s.current)}<span style="font-size:16px;color:var(--muted)"> / ${fmt(s.total)}</span></div>
      <div class="meta">skipped existing ${fmt(s.skipped)}</div>
    </div>
    <div class="card">
      <div class="label">Originals posted</div>
      <div class="value ok">${fmt(s.originals)}</div>
      <div class="meta">since latest restart</div>
    </div>
    <div class="card">
      <div class="label">Rate / ETA</div>
      <div class="value sm">${(s.rate || 0).toFixed(1)}/s</div>
      <div class="meta">ETA ${s.eta || '—'} · remaining ${fmt(Math.max(0, (s.total||0)-(s.current||0)))}</div>
    </div>
    <div class="card wide">
      <div class="label">Progress</div>
      <div class="value sm">${p.toFixed(1)}%</div>
      <div class="bar"><i style="width:${p.toFixed(2)}%"></i></div>
      <div class="meta">Log <code>${esc(s.log_path)}</code></div>
      <div class="meta">Latest: <code>${esc(s.latest || '—')}</code></div>
    </div>
    <div class="card wide">
      <div class="label">On the platform</div>
      <div class="value sm">${fmt(s.db_last_30m)} posts · last 30 min</div>
      <div class="meta">${fmt(s.db_last_2h)} in 2h · open Sparks / Home Feed and pull to refresh</div>
      <div class="meta"><a class="link" href="https://api.matterya.com/v1/sparks?limit=5" target="_blank" rel="noopener">Live /v1/sparks sample</a></div>
    </div>
    <div class="card wide">
      <div class="label">Recently ingested</div>
      <ul class="live">${recent || '<li class="meta">Waiting for first INGEST lines…</li>'}</ul>
    </div>
  `;
}
tick();
setInterval(tick, 2000);
</script>
</body>
</html>
"""


def _read_pid() -> int | None:
    try:
        if PID_FILE.exists():
            pid = int(PID_FILE.read_text().strip())
            os.kill(pid, 0)
            return pid
    except Exception:
        pass
    # Fallback: find content-pipeline flood
    try:
        out = subprocess.check_output(["ps", "aux"], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return None
    for line in out.splitlines():
        if "content-pipeline/cli.ts" in line and "--ingest-only" in line and "grep" not in line:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    return int(parts[1])
                except ValueError:
                    continue
    return None


def _etime(pid: int | None) -> str:
    if not pid:
        return "—"
    try:
        out = subprocess.check_output(
            ["ps", "-p", str(pid), "-o", "etime="], text=True, stderr=subprocess.DEVNULL
        ).strip()
        return out or "—"
    except Exception:
        return "—"


def _tail_section(path: Path) -> list[str]:
    """Return lines after the latest RESTART marker (or whole file)."""
    if not path.exists():
        return []
    try:
        # Read last ~2MB to keep it snappy on large logs
        size = path.stat().st_size
        with path.open("rb") as f:
            if size > 2_000_000:
                f.seek(size - 2_000_000)
                f.readline()
            text = f.read().decode("utf-8", errors="ignore")
    except Exception:
        return []
    lines = text.splitlines()
    last_restart = -1
    for i, line in enumerate(lines):
        if RESTART_MARK in line:
            last_restart = i
    if last_restart >= 0:
        return lines[last_restart + 1 :]
    return lines


def parse_flood(lines: list[str]) -> dict:
    total = 0
    current = 0
    skipped = 0
    originals = 0
    done = False
    latest = ""
    recent: list[dict] = []
    last_ingest: dict | None = None
    first_ingest_t: float | None = None
    # Approximate rate from ingest index growth vs wall time of log parse — use mtime deltas via count
    for line in lines:
        if "New packs to ingest:" in line:
            m = NEW_PACKS_RE.search(line)
            if m:
                total = int(m.group(1))
                skipped = int(m.group(2))
        if "→ original" in line or "original + feed share created" in line:
            originals += 1
        if DONE_RE.search(line):
            done = True
        m = INGEST_RE.search(line)
        if m:
            current = int(m.group(1))
            total = max(total, int(m.group(2)))
            last_ingest = {
                "n": current,
                "total": int(m.group(2)),
                "kind": m.group(3),
                "country": m.group(4),
                "raw": line.strip()[-160:],
                "caption": "",
            }
            if first_ingest_t is None:
                first_ingest_t = time.time()  # weak; refined below
            latest = line.strip()[-180:]
        cm = CAPTION_RE.search(line)
        if cm and last_ingest is not None:
            last_ingest["caption"] = cm.group(1).strip()[:120]
            # push into recent (newest first)
            recent.insert(0, dict(last_ingest))
            recent = recent[:18]
            last_ingest = None

    rate = 0.0
    eta = "—"
    # Prefer originals-based rate if we have a pid uptime
    return {
        "current": current,
        "total": total,
        "skipped": skipped,
        "originals": originals,
        "done": done,
        "latest": latest,
        "recent": recent,
        "rate": rate,
        "eta": eta,
        "_first_ingest_t": first_ingest_t,
    }


_db_cache = {"t": 0.0, "last_30m": 0, "last_2h": 0}


def db_recent_counts() -> tuple[int, int]:
    now = time.time()
    if now - _db_cache["t"] < 8:
        return _db_cache["last_30m"], _db_cache["last_2h"]
    db_url = os.environ.get("DATABASE_URL") or ""
    if not db_url:
        # Try apps/api/.env
        env_path = Path(__file__).resolve().parents[1] / "apps" / "api" / ".env"
        if env_path.exists():
            for line in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
                if line.startswith("DATABASE_URL="):
                    db_url = line.split("=", 1)[1].strip().strip('"').strip("'")
                    break
    if not db_url:
        return _db_cache["last_30m"], _db_cache["last_2h"]
    try:
        out = subprocess.check_output(
            [
                "psql",
                db_url,
                "-t",
                "-A",
                "-c",
                "select count(*) filter (where created_at > now() - interval '30 minutes'),"
                " count(*) filter (where created_at > now() - interval '2 hours') from posts;",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=15,
        ).strip()
        parts = out.split("|")
        if len(parts) >= 2:
            _db_cache["last_30m"] = int(parts[0])
            _db_cache["last_2h"] = int(parts[1])
            _db_cache["t"] = now
    except Exception:
        pass
    return _db_cache["last_30m"], _db_cache["last_2h"]


def status_payload() -> dict:
    lines = _tail_section(LOG)
    parsed = parse_flood(lines)
    pid = _read_pid()
    running = pid is not None and not parsed["done"]
    elapsed = _etime(pid)

    # Rate from originals / process elapsed seconds
    rate = 0.0
    eta = "—"
    try:
        # parse etime like [[dd-]hh:]mm:ss
        secs = 0
        if elapsed and elapsed != "—":
            parts = elapsed.replace("-", ":").split(":")
            parts = [int(p) for p in parts]
            while len(parts) < 3:
                parts.insert(0, 0)
            if len(parts) == 4:  # days
                secs = parts[0] * 86400 + parts[1] * 3600 + parts[2] * 60 + parts[3]
            else:
                secs = parts[0] * 3600 + parts[1] * 60 + parts[2]
        if secs > 5 and parsed["originals"] > 0:
            rate = parsed["originals"] / secs
            rem = max(0, parsed["total"] - parsed["current"])
            if rate > 0 and rem > 0:
                left = rem / rate
                if left < 90:
                    eta = f"{int(left)}s"
                elif left < 3600:
                    eta = f"{int(left // 60)}m {int(left % 60)}s"
                else:
                    eta = f"{int(left // 3600)}h {int((left % 3600) // 60)}m"
    except Exception:
        pass

    last_30m, last_2h = db_recent_counts()

    return {
        "running": running,
        "done": parsed["done"],
        "pid": pid,
        "elapsed": elapsed,
        "current": parsed["current"],
        "total": parsed["total"],
        "skipped": parsed["skipped"],
        "originals": parsed["originals"],
        "latest": parsed["latest"],
        "recent": parsed["recent"],
        "rate": rate,
        "eta": eta,
        "log_path": str(LOG),
        "db_last_30m": last_30m,
        "db_last_2h": last_2h,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:  # quieter
        pass

    def _wants_html(self) -> bool:
        accept = (self.headers.get("Accept") or "").lower()
        # Browsers send text/html first; curl/fetch for JSON usually send */* or application/json.
        if "application/json" in accept and "text/html" not in accept:
            return False
        if "text/html" in accept:
            return True
        # No Accept / navigations → HTML page.
        return True

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0] or "/"
        # Only the explicit JSON API path returns JSON — and only when the client
        # is not a browser document navigation.
        if path == "/api/status" and not self._wants_html():
            payload = json.dumps(status_payload()).encode("utf-8")
            self._send(200, payload, "application/json; charset=utf-8")
            return
        if path == "/api/status.json":
            payload = json.dumps(status_payload()).encode("utf-8")
            self._send(200, payload, "application/json; charset=utf-8")
            return
        # Everything else (including /, /index.html, and browser hits on /api/status) → HTML UI.
        # Page JS fetches /api/status.json so the document URL never shows raw JSON.
        body = HTML.replace("fetch('/api/status?", "fetch('/api/status.json?").encode("utf-8")
        self._send(200, body, "text/html; charset=utf-8")


def main() -> None:
    # Free stale listener if any
    try:
        out = subprocess.check_output(
            ["lsof", f"-tiTCP:{PORT}", "-sTCP:LISTEN"], text=True, stderr=subprocess.DEVNULL
        ).strip()
        for p in out.splitlines():
            try:
                os.kill(int(p), 15)
            except Exception:
                pass
        time.sleep(0.4)
    except Exception:
        pass

    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Flood progress → http://127.0.0.1:{PORT}/", flush=True)
    print(f"Log: {LOG}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
