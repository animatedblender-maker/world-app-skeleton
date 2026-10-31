/**
 * Moderator Policy Handbook — password-gated training page.
 * https://api.matterya.com/management/policy
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Request, Response } from 'express';
import {
  hasReportsAccess,
  renderReportsLoginHtml,
} from './reports-page.js';
import {
  leafSeverity,
  listPolicyLeaves,
  type PolicyLeaf,
} from '../moderation/policy-tree.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function escapeHtml(s: string): string {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Minimal markdown → HTML for our handbook (headings, tables, lists, bold, code, hr). */
function markdownToHtml(md: string): string {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const out: string[] = [];
  let i = 0;
  let inUl = false;
  let inTable = false;

  const flushUl = () => {
    if (inUl) {
      out.push('</ul>');
      inUl = false;
    }
  };
  const flushTable = () => {
    if (inTable) {
      out.push('</tbody></table>');
      inTable = false;
    }
  };

  const inline = (t: string) =>
    escapeHtml(t)
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, '<a href="$2" rel="noopener" target="_blank">$1</a>');

  while (i < lines.length) {
    const line = lines[i] ?? '';
    const trimmed = line.trim();

    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      flushUl();
      const cells = trimmed
        .slice(1, -1)
        .split('|')
        .map((c) => c.trim());
      const isSep = cells.every((c) => /^:?-{3,}:?$/.test(c));
      if (isSep) {
        i += 1;
        continue;
      }
      if (!inTable) {
        out.push('<table><thead><tr>');
        for (const c of cells) out.push(`<th>${inline(c)}</th>`);
        out.push('</tr></thead><tbody>');
        inTable = true;
        i += 1;
        continue;
      }
      out.push('<tr>');
      for (const c of cells) out.push(`<td>${inline(c)}</td>`);
      out.push('</tr>');
      i += 1;
      continue;
    }

    flushTable();

    if (trimmed === '---') {
      flushUl();
      out.push('<hr/>');
      i += 1;
      continue;
    }
    if (trimmed.startsWith('# ')) {
      flushUl();
      out.push(`<h1>${inline(trimmed.slice(2))}</h1>`);
      i += 1;
      continue;
    }
    if (trimmed.startsWith('## ')) {
      flushUl();
      const title = trimmed.slice(3);
      const id = title
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '');
      out.push(`<h2 id="${id}">${inline(title)}</h2>`);
      i += 1;
      continue;
    }
    if (trimmed.startsWith('### ')) {
      flushUl();
      out.push(`<h3>${inline(trimmed.slice(4))}</h3>`);
      i += 1;
      continue;
    }
    if (/^\d+\.\s/.test(trimmed) || trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      if (!inUl) {
        out.push('<ul>');
        inUl = true;
      }
      const body = trimmed.replace(/^\d+\.\s/, '').replace(/^[-*]\s/, '');
      out.push(`<li>${inline(body)}</li>`);
      i += 1;
      continue;
    }
    if (!trimmed) {
      flushUl();
      i += 1;
      continue;
    }
    flushUl();
    out.push(`<p>${inline(trimmed)}</p>`);
    i += 1;
  }
  flushUl();
  flushTable();
  return out.join('\n');
}

function loadHandbookMarkdown(): string {
  const candidates = [
    path.resolve(__dirname, '../../docs/moderation/04-POLICY-HANDBOOK.md'),
    path.resolve(process.cwd(), 'docs/moderation/04-POLICY-HANDBOOK.md'),
    path.resolve(process.cwd(), '../../docs/moderation/04-POLICY-HANDBOOK.md'),
  ];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) return fs.readFileSync(p, 'utf8');
    } catch {
      /* try next */
    }
  }
  return '# Policy handbook unavailable\n\nDeploy is missing `docs/moderation/04-POLICY-HANDBOOK.md`.';
}

function leafInventoryHtml(): string {
  const leaves = listPolicyLeaves().slice().sort((a, b) => a.id.localeCompare(b.id));
  const rows = leaves
    .map((l: PolicyLeaf) => {
      const sev =
        l.outcome === 'remove' ? leafSeverity(l) : '—';
      return `<tr>
        <td><code>${escapeHtml(l.id)}</code></td>
        <td>${escapeHtml(l.root)}</td>
        <td><span class="pill ${escapeHtml(l.outcome)}">${escapeHtml(l.outcome)}</span></td>
        <td>${escapeHtml(sev)}</td>
        <td>${escapeHtml(l.label)}</td>
      </tr>`;
    })
    .join('');
  return `
  <h2 id="live-leaf-inventory">Live leaf inventory</h2>
  <p class="muted">Generated from <code>policy-tree.ts</code> at request time (${leaves.length} leaves).</p>
  <table>
    <thead><tr><th>Leaf id</th><th>Root</th><th>Outcome</th><th>Severity</th><th>Label</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

function renderHandbookHtml(bodyHtml: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Matterya · Policy handbook</title>
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
    color: var(--ink); min-height: 100vh; line-height: 1.5;
  }
  header {
    position: sticky; top: 0; z-index: 5;
    background: rgba(255,252,248,.94); backdrop-filter: blur(10px);
    border-bottom: 1px solid var(--border);
    padding: 14px 20px; display: flex; flex-wrap: wrap; gap: 12px 18px; align-items: center;
  }
  .mark {
    font-size: 11px; font-weight: 700; letter-spacing: .2em;
    text-transform: uppercase; color: var(--accent);
  }
  h1.page {
    margin: 0; font-size: 1.3rem; font-weight: 500;
    font-family: ui-serif, Georgia, serif;
  }
  a.nav { color: var(--accent); text-decoration: none; font-size: .85rem; margin-left: 10px; }
  a.nav:hover { text-decoration: underline; }
  .muted { color: var(--muted); font-size: .9rem; }
  main {
    max-width: 880px; margin: 0 auto; padding: 28px 16px 72px;
    background: transparent;
  }
  article {
    background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
    padding: 28px 26px 36px; box-shadow: 0 12px 32px rgba(44,40,37,.06);
  }
  article h1 { font-family: ui-serif, Georgia, serif; font-weight: 500; font-size: 1.75rem; margin: 0 0 8px; }
  article h2 {
    font-family: ui-serif, Georgia, serif; font-weight: 500; font-size: 1.25rem;
    margin: 28px 0 10px; padding-top: 8px; border-top: 1px solid var(--border);
  }
  article h2:first-of-type { border-top: 0; }
  article h3 { font-size: 1.02rem; margin: 18px 0 8px; color: var(--accent); }
  article p { margin: 0 0 12px; }
  article ul { margin: 0 0 14px; padding-left: 1.2rem; }
  article li { margin: 4px 0; }
  article hr { border: 0; border-top: 1px solid var(--border); margin: 22px 0; }
  code {
    font-family: ui-monospace, Menlo, monospace; font-size: .84em;
    background: var(--wash); border: 1px solid var(--border); border-radius: 6px;
    padding: 1px 5px;
  }
  table {
    width: 100%; border-collapse: collapse; font-size: .88rem; margin: 0 0 16px;
  }
  th, td {
    border: 1px solid var(--border); padding: 8px 10px; text-align: left; vertical-align: top;
  }
  th { background: var(--wash); font-size: .78rem; letter-spacing: .04em; text-transform: uppercase; color: var(--accent); }
  .pill {
    display: inline-block; padding: 1px 8px; border-radius: 999px; font-size: .75rem; font-weight: 700;
    border: 1px solid var(--border); background: #fff;
  }
  .pill.remove { color: #b91c1c; border-color: #fecaca; background: #fef2f2; }
  .pill.mark { color: #9a3412; border-color: #fdba74; background: #fff7ed; }
  .pill.dismiss { color: #166534; border-color: #bbf7d0; background: #dcfce7; }
  a { color: var(--accent); }
</style>
</head>
<body>
<header>
  <div>
    <div class="mark">Matterya</div>
    <h1 class="page">Policy handbook</h1>
  </div>
  <span class="muted">Moderator training</span>
  <span style="flex:1"></span>
  <a class="nav" href="/management/policy.pdf">Download PDF</a>
  <a class="nav" href="/management">Management</a>
  <a class="nav" href="/reports">Content queue</a>
  <a class="nav" href="/reports/logout">Log out</a>
</header>
<main>
  <article>
    ${bodyHtml}
    ${leafInventoryHtml()}
  </article>
</main>
</body>
</html>`;
}

function findHandbookPdf(): string | null {
  const candidates = [
    path.resolve(__dirname, '../../public/moderation/Matterya-Moderator-Handbook.pdf'),
    path.resolve(process.cwd(), 'public/moderation/Matterya-Moderator-Handbook.pdf'),
    path.resolve(process.cwd(), '../../docs/moderation/Matterya-Moderator-Handbook.pdf'),
  ];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) return p;
    } catch {
      /* try next */
    }
  }
  return null;
}

export async function handlePolicyHandbookGet(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(
      renderReportsLoginHtml({
        next: '/management/policy',
        titleMode: 'management',
      })
    );
    return;
  }
  const md = loadHandbookMarkdown();
  // Drop the first H1 from markdown — page header already titles it.
  const stripped = md.replace(/^# [^\n]+\n+/, '');
  const body = markdownToHtml(stripped);
  res.type('html').send(renderHandbookHtml(body));
}

/** Password-gated PDF download for offline / print training. */
export async function handlePolicyHandbookPdfGet(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(
      renderReportsLoginHtml({
        next: '/management/policy.pdf',
        titleMode: 'management',
      })
    );
    return;
  }
  const pdfPath = findHandbookPdf();
  if (!pdfPath) {
    res.status(404).type('text').send('Handbook PDF not found on this deploy.');
    return;
  }
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader(
    'Content-Disposition',
    'inline; filename="Matterya-Moderator-Handbook.pdf"'
  );
  fs.createReadStream(pdfPath).pipe(res);
}
