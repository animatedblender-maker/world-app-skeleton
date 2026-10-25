# Voyage embeddings (for humans)

### What problem this solves
Without embeddings, the app mostly knows posts by **metadata** (country, hub tag, popularity).  
With embeddings, it can say: “this caption is *about the same idea* as that other post” — even if the words differ.

That powers a smarter **Home For You**.

### What we embed today
- **Title + body/caption text** only  
- Model: **voyage-4-lite**  
- ~39,000 existing posts in the first big fill  
- New posts: automatic after upload or seed  

We are **not** embedding every video frame. That would be expensive and slow for little near-term gain.

### Do I have to run the big backfill again?
**No.**  

| Situation | What happens |
|---|---|
| Old posts (first time) | One Mac backfill job |
| New user upload | Auto-queued on the API |
| New pipeline seed | Auto-queued on the API |
| Something missed (rare) | Optional catch-up curl (see checklist) |
| Change AI model later | Then yes — a new backfill for the new model |

### Progress page (on your Mac)
While the historical backfill runs:

**http://127.0.0.1:8789/**

Shows percent done, ETA, running/stopped, recent log lines.

### Voyage account tips
1. Create a key at https://dashboard.voyageai.com → API keys  
2. Put it in Render as `VOYAGE_API_KEY` (web service `matterya-api`)  
3. Add a **payment method** if you want fast rate limits  
   - Credits alone can still look “throttled”  
4. Free token allowance is large enough for this text job  

### Multimodal later?
Possible — for “looks like this Spark” using thumbnails.  
**Not next.** Finish text ANN first, then maybe search rerank, then a small multimodal pilot.
