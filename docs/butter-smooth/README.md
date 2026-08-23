# Butter-Smooth Program (Matterya)

**UI rule:** Do not change how the app looks or expected product behavior. This program is latency, reliability, architecture, and observability.

| Doc | Purpose |
|-----|---------|
| [00-LOCKED-DECISIONS.md](./00-LOCKED-DECISIONS.md) | Product owner answers |
| [01-SLOS.md](./01-SLOS.md) | Milestones & targets |
| [02-EPICS.md](./02-EPICS.md) | Epic map |
| [03-ADRs/](./03-ADRs/) | Architecture decisions |
| [04-SERVICE-CONTRACTS.md](./04-SERVICE-CONTRACTS.md) | API contracts |
| [05-TICKETS-90D.md](./05-TICKETS-90D.md) | 90-day tickets |
| [06-INVENTORY-D1.md](./06-INVENTORY-D1.md) | Sync/N+1 inventory |
| [07-GRAFANA-SETUP.md](./07-GRAFANA-SETUP.md) | Grafana — **you: Step 3 Import now** |
| [grafana/matterya-butter-smooth-slos.json](./grafana/matterya-butter-smooth-slos.json) | Importable Step 3 dashboard |
| [08-HUBS-A-Z-AUDIT.md](./08-HUBS-A-Z-AUDIT.md) | Hubs play URL / shelf audit |
| [09-MEDIA-SESSION.md](./09-MEDIA-SESSION.md) | **Locked:** one player, feed poster-only |

## Sequence (current)

1. Media session re-foundation (`09`) — done / in flight  
2. **Grafana Step 3** — dashboard imported (`Matterya Butter-Smooth SLOs`) ✅  
3. Smoke iOS → confirm table rows → use p95s to drive remaining epics / SLOs  

## Your actions (only when agent asks)

1. **Push / deploy API:** `git push origin ios-native` (Render)  
2. **Migrations:** apply SQL file agent names in Supabase  
3. **Grafana:** follow agent step-by-step when metrics endpoint is live  
4. **Smoke:** iPhone 11-class device after major gates  
