# Web client hardening (anti reverse-engineering)

## Honest limits

A **web app cannot be cryptographically encrypted against reverse engineering** while still running in a normal browser.

The browser must download HTML/CSS/JS and execute it. Anyone with DevTools can:

- save network responses
- pretty-print minified JS
- step through runtime behavior
- inspect GraphQL/API traffic

**Do not put secrets in the web client** (private API keys, admin tokens, signing secrets). Supabase **anon** keys and public GraphQL endpoints are expected to be client-visible; protect data with RLS/auth on the server.

## What we do ship (production)

| Control | Purpose |
|---------|---------|
| Angular `production` build | Tree-shake, minify, AOT compile TS → JS |
| `sourceMap: false` | **Critical** — no original TypeScript mapping |
| `outputHashing: all` | Cache-bust; harder to track stable filenames |
| `extractLicenses: true` | License text not mixed into main bundle |
| `scripts/harden-dist.mjs` | Delete `*.map`, strip `sourceMappingURL`, Terser re-minify, `drop_console` |
| Deploy script | Always runs harden before `gh-pages` push |

## Commands

```bash
cd apps/web
npm run build:prod          # production build + harden
npm run harden              # harden existing dist only
npm run deploy:gh-pages     # build + harden + push gh-pages
```

## What this does *not* do

- Encrypt business logic so it cannot be read
- Stop a determined attacker from reconstructing flows
- Protect private keys if they were embedded in the client
- Replace server-side authorization

## Server-side is the real security boundary

- Supabase RLS policies
- GraphQL auth checks
- Never trust the client for permissions
- Rate limits / abuse controls on the API

## Optional further friction (not enabled by default)

Heavy tools like `javascript-obfuscator` with control-flow flattening often **break Angular**. If you need more friction later, test thoroughly; prefer server-side secrets over client obfuscation.
