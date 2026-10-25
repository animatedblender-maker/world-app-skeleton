# Start here (developers)

Repo: `/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton`  
Branch: **`ios-native`**  
API root: `apps/api` (Render Root Directory)

### Read order
1. [Architecture](./01-architecture.md)  
2. [MIND phases](./02-mind-phases.md)  
3. [Voyage & embeddings](./03-voyage-and-embeddings.md)  
4. [Feed attribution fix](./04-feed-attribution-fix.md)  
5. [Ops runbook](./05-ops-runbook.md)  
6. [Env & deploy](./06-env-and-deploy.md)  
7. [File map](./07-file-map.md)  

### Key commits (ios-native)
| Commit | What |
|---|---|
| `cde80f7` | `/mind` admin console |
| `815b20a` | Disk-IO-safe `/mind` status cache |
| `f475f8e` | §1 purpose/surfaces (`mind.phase1.v7`) |
| `3554fed` | Phase 2a media features (`mind.phase2.v1`) |
| `cb549f7` | Phase 2b Voyage + pgvector ANN (`mind.phase2.v2`) |
| `fa44852` | Auto embeds + `/cron/mind-embeddings` + render.yaml cron stub |

### Local API
```bash
cd apps/api
npx tsx src/main.ts
# MIND: http://127.0.0.1:3000/mind
```

### Docs sync (Render serves from apps/api)
```bash
# from repo root
rsync -a --delete docs/mind/ apps/api/docs/mind/
# matterya pack is under docs/matterya (optional rsync if you want it on /mind later)
```

### Human-readable twin
See [`../for-humans/`](../for-humans/) for operator checklists.
