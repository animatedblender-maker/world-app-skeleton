# Start here (non-developer)

Welcome. This folder explains **what we built for Matterya**, in plain language, with steps you can follow.

### Read in this order
1. [What is MIND?](./01-what-is-matterya-mind.md) — the “brain” of the feed  
2. [What we built](./02-what-we-built.md) — checklist of shipped work  
3. [Voyage embeddings](./03-voyage-embeddings.md) — how posts get “understood”  
4. [Feed names / The Archive](./04-feed-names-the-archive.md) — the naming bug and fix  
5. [Your checklists](./05-checklists-and-steps.md) — clicks, dashboards, env keys  
6. [What’s next](./06-whats-next.md) — near-future product path  

### One-sentence summary
Matterya can now **rank and relate posts by meaning** (not only likes/hashtags), using Voyage AI + MIND — and new posts keep getting that treatment automatically.

### Important links (bookmark these)
| What | Where |
|---|---|
| MIND admin console | https://api.matterya.com/mind (Ops password) |
| Content pipeline | https://api.matterya.com/pipeline |
| Local embed progress (Mac) | http://127.0.0.1:8789/ |
| Voyage dashboard | https://dashboard.voyageai.com |
| Render (API hosting) | https://dashboard.render.com |
| App repo | `world-app-skeleton` branch `ios-native` |

### Words you’ll see
| Word | Meaning |
|---|---|
| **MIND** | Matterya’s recommendation system (what to show whom) |
| **Sparks** | Short videos / reels users upload or share |
| **Hubs** | Longer / channel-style video shelves |
| **Embedding** | A list of numbers that represent “what this post is about” |
| **Voyage** | The AI company that turns text into embeddings |
| **ANN** | “Find posts similar to this one” using those numbers |
| **The Archive** | One special channel for Internet Archive seed videos — **not** every Hub |
| **Backfill** | One-time job that embeds old posts already in the database |
