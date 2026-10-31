/**
 * Matterya management hub — index of all ops surfaces.
 * https://api.matterya.com/management
 */
import type { Request, Response } from 'express';
import {
  hasReportsAccess,
  renderReportsLoginHtml,
  REPORTS_PAGE_PASSWORD,
} from './reports-page.js';

function escapeHtml(s: string): string {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

type HubLink = {
  href: string;
  title: string;
  blurb: string;
  group: string;
};

const LINKS: HubLink[] = [
  {
    group: 'Moderation',
    href: '/reports',
    title: 'Content queue',
    blurb: 'Claim-next review for posts and comments.',
  },
  {
    group: 'Moderation',
    href: '/reports/accounts',
    title: 'Account review',
    blurb: 'Strikes, warnings, and account actions.',
  },
  {
    group: 'Moderation',
    href: '/reports/masquerade',
    title: 'Masquerade queue',
    blurb: 'Legacy Remove / Flag / Skip for anonymous posts.',
  },
  {
    group: 'Analytics',
    href: '/reports/analytics',
    title: 'Insights',
    blurb: 'Activity, uploads, people, and ranking windows.',
  },
  {
    group: 'Content ops',
    href: '/pipeline',
    title: 'Pipeline',
    blurb: 'R2 ingest → owned posts and feed shares.',
  },
  {
    group: 'Content ops',
    href: '/frame0',
    title: 'Frame 0',
    blurb: 'Poster / thumbnail backfill progress.',
  },
  {
    group: 'Recommendations',
    href: '/mind',
    title: 'MIND',
    blurb: 'Ranker status, people dossier, handbook.',
  },
];

function renderHubHtml(): string {
  const groups = [...new Set(LINKS.map((l) => l.group))];
  const sections = groups
    .map((group) => {
      const cards = LINKS.filter((l) => l.group === group)
        .map(
          (l) => `
      <a class="card" href="${escapeHtml(l.href)}">
        <div class="title">${escapeHtml(l.title)}</div>
        <div class="blurb">${escapeHtml(l.blurb)}</div>
        <div class="path">${escapeHtml(l.href)}</div>
      </a>`
        )
        .join('');
      return `
    <section>
      <h2>${escapeHtml(group)}</h2>
      <div class="grid">${cards}</div>
    </section>`;
    })
    .join('');

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Matterya · Management</title>
<style>
  :root {
    --paper: #f8f6f2; --ink: #2c2825; --muted: #7a736c; --accent: #7b6347;
    --border: #ddd6cc; --surface: #fffcf8; --wash: #f3efe8;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
    background: radial-gradient(1200px 600px at 20% 0%, #efe8dc 0%, var(--paper) 55%);
    color: var(--ink); min-height: 100vh;
  }
  header {
    position: sticky; top: 0; z-index: 5;
    background: rgba(255,252,248,.92); backdrop-filter: blur(10px);
    border-bottom: 1px solid var(--border);
    padding: 14px 20px; display: flex; flex-wrap: wrap; gap: 12px 18px; align-items: center;
  }
  .mark {
    font-size: 11px; font-weight: 700; letter-spacing: .2em;
    text-transform: uppercase; color: var(--accent);
  }
  h1 {
    margin: 0; font-size: 1.35rem; font-weight: 500;
    font-family: ui-serif, Georgia, serif;
  }
  .muted { color: var(--muted); font-size: .85rem; }
  a.nav { color: var(--accent); text-decoration: none; font-size: .85rem; margin-left: 10px; }
  a.nav:hover { text-decoration: underline; }
  main { max-width: 960px; margin: 0 auto; padding: 28px 16px 64px; display: grid; gap: 28px; }
  section h2 {
    margin: 0 0 12px; font-size: 11px; font-weight: 700;
    letter-spacing: .14em; text-transform: uppercase; color: var(--accent);
  }
  .grid {
    display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px;
  }
  a.card {
    display: grid; gap: 6px; text-decoration: none; color: inherit;
    background: var(--surface); border: 1px solid var(--border); border-radius: 14px;
    padding: 16px 16px 14px; box-shadow: 0 10px 28px rgba(44,40,37,.05);
  }
  a.card:hover { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(123,99,71,.12); }
  .title { font-weight: 650; font-size: 1.02rem; }
  .blurb { color: var(--muted); font-size: .88rem; line-height: 1.4; }
  .path {
    margin-top: 4px; font-family: ui-monospace, Menlo, monospace;
    font-size: .72rem; color: #a8a29e;
  }
</style>
</head>
<body>
<header>
  <div>
    <div class="mark">Matterya</div>
    <h1>Management</h1>
  </div>
  <span class="muted">Ops surfaces</span>
  <span style="flex:1"></span>
  <a class="nav" href="/reports/logout">Log out</a>
</header>
<main>
  ${sections}
</main>
</body>
</html>`;
}

export async function handleManagementGet(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(
      renderReportsLoginHtml({
        next: '/management',
        titleMode: 'management',
      })
    );
    return;
  }
  res.type('html').send(renderHubHtml());
}

export { REPORTS_PAGE_PASSWORD };
