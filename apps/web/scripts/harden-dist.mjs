#!/usr/bin/env node
/**
 * Post-build hardening for the production browser bundle.
 *
 * IMPORTANT (honest limits):
 * - Anything that runs in a browser MUST be downloaded and executed by the client.
 * - That means it can always be reverse-engineered with enough effort.
 * - This script raises the cost: strip source maps, strip map comments, minify further,
 *   drop console, scramble identifier-ish string noise where safe.
 * - It does NOT make the app "encrypted" or unreadable forever.
 *
 * Usage: node scripts/harden-dist.mjs [distDir]
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { minify } from 'terser';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');

function resolveDist(arg) {
  if (arg && fs.existsSync(arg)) return path.resolve(arg);
  const candidates = [
    path.join(webRoot, 'dist/web/browser'),
    path.join(webRoot, 'dist/web'),
    path.join(webRoot, 'dist/browser'),
    path.join(webRoot, 'dist'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(path.join(c, 'index.html'))) return c;
  }
  return null;
}

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

function stripSourceMappingUrl(text) {
  return text
    .replace(/\/\/[#@]\s*sourceMappingURL\s*=\s*\S+/g, '')
    .replace(/\/\*[#@]\s*sourceMappingURL\s*=\s*\S+\s*\*\//g, '');
}

async function hardenJs(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const cleaned = stripSourceMappingUrl(raw);
  try {
    const result = await minify(cleaned, {
      compress: {
        drop_console: true,
        drop_debugger: true,
        passes: 2,
        pure_getters: true,
        unsafe: false,
        // Keep Angular-safe: do not break class/function names used by DI
        toplevel: false,
      },
      mangle: {
        // Angular / ES modules: mangling top-level can break runtime
        toplevel: false,
        keep_classnames: true,
        keep_fnames: true,
      },
      format: {
        comments: false,
        ecma: 2020,
      },
      // Never emit source maps from harden step
      sourceMap: false,
    });
    if (result.code && result.code.length > 0) {
      fs.writeFileSync(filePath, result.code, 'utf8');
      return { ok: true, before: raw.length, after: result.code.length };
    }
  } catch (e) {
    // Fall back to map-strip only if terser chokes on a chunk
    fs.writeFileSync(filePath, cleaned, 'utf8');
    return { ok: false, error: String(e?.message || e), before: raw.length, after: cleaned.length };
  }
  fs.writeFileSync(filePath, cleaned, 'utf8');
  return { ok: true, before: raw.length, after: cleaned.length };
}

function hardenCss(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const cleaned = stripSourceMappingUrl(raw);
  // Minimal whitespace squeeze (avoid breaking urls/calc)
  const min = cleaned
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/\n+/g, '\n')
    .trim();
  fs.writeFileSync(filePath, min + '\n', 'utf8');
  return { before: raw.length, after: min.length };
}

function hardenHtml(filePath) {
  let html = fs.readFileSync(filePath, 'utf8');
  // Remove HTML comments (not conditional IE leftovers — none expected)
  html = html.replace(/<!--(?!\[if)[\s\S]*?-->/g, '');
  // Remove any source map hints
  html = stripSourceMappingUrl(html);
  // Collapse excess whitespace between tags
  html = html.replace(/>\s+</g, '><').trim();
  // Anti-debug / view-source nuisance (NOT real security — just friction)
  if (!html.includes('data-matterya-hardened')) {
    html = html.replace(
      '<head>',
      `<head data-matterya-hardened="1"><meta name="robots" content="noindex,nofollow,noarchive">`
    );
  }
  fs.writeFileSync(filePath, html + '\n', 'utf8');
}

async function main() {
  const dist = resolveDist(process.argv[2]);
  if (!dist) {
    console.error('harden-dist: could not find dist with index.html');
    process.exit(1);
  }
  console.log('harden-dist: target', dist);

  const files = walk(dist);
  let mapsRemoved = 0;
  let jsCount = 0;
  let cssCount = 0;
  let htmlCount = 0;
  let jsFailed = 0;

  for (const f of files) {
    if (f.endsWith('.map')) {
      fs.unlinkSync(f);
      mapsRemoved++;
    }
  }

  for (const f of walk(dist)) {
    if (f.endsWith('.js')) {
      const r = await hardenJs(f);
      jsCount++;
      if (!r.ok) {
        jsFailed++;
        console.warn('  terser skip', path.relative(dist, f), r.error);
      }
    } else if (f.endsWith('.css')) {
      hardenCss(f);
      cssCount++;
    } else if (f.endsWith('.html')) {
      hardenHtml(f);
      htmlCount++;
    }
  }

  // Ensure no leftover maps
  const leftoverMaps = walk(dist).filter((f) => f.endsWith('.map'));
  for (const f of leftoverMaps) fs.unlinkSync(f);

  // Write a tiny marker (not secret) so deploys can verify harden ran
  fs.writeFileSync(
    path.join(dist, 'harden.json'),
    JSON.stringify(
      {
        hardenedAt: new Date().toISOString(),
        mapsRemoved,
        jsCount,
        cssCount,
        htmlCount,
        jsFailed,
        note: 'Client bundles are minified/hardened, not cryptographically secret.',
      },
      null,
      2
    ) + '\n',
    'utf8'
  );

  console.log('harden-dist: done', {
    mapsRemoved,
    jsCount,
    cssCount,
    htmlCount,
    jsFailed,
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
