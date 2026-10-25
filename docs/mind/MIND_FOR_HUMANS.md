# Matterya MIND — explained like you’re new here

This is a plain-language story of **what MIND is**, **what we built**, and **what we did not finish yet**.  
No assumed jargon. If a technical name appears, it gets a one-line meaning.

---

## What is MIND?

**MIND** is Matterya’s “recommendation brain.”

When someone opens the app and scrolls **Home**, **Hubs**, **Sparks**, or similar feeds, the app has to decide:

> Which video should show up next?

MIND is the system that tries to answer that in a smart, fair, measurable way — instead of showing random clutter or the same viral clip forever.

Think of it like a helpful librarian who:

1. Notices what you liked before  
2. Looks at a big shelf of videos  
3. Picks a mix that feels relevant **and** fresh  
4. Remembers what it already showed you so it doesn’t repeat the same thing endlessly  

---

## The pieces (in normal words)

| Everyday idea | Name in Matterya |
|---|---|
| The brain’s rulebook version | `mind.phase2.v1` (policy version) |
| “We already showed you this video on this screen” log | **Exposure ledger** (`feed_video_delivery`) |
| “Here’s why we ranked this way” record | **Recommendation decisions** |
| Anonymous Reddit-like community | **Masquerade** (communities are called **spaces**, never “subreddits”) |
| Long-form video home (Netflix-ish) | **Hubs** |
| Short / sparkly vertical feed | **Sparks** / Home For You |
| Admin website for engineers | **https://api.matterya.com/mind** (password protected) |
| Engineering bible | `Matterya_MIND_Engineering_Handbook.md` |

---

## What we already shipped (Phase 0 → Phase 2a)

### Phase 0 — “Can we even see what’s going on?”

We stood up an **admin console** at `/mind` so humans can open a browser and see:

- Live health of the brain  
- Gap checklist (what’s done vs missing)  
- Docs, architecture sketches, seed progress  

Also: a **password gate** so random people can’t poke production internals.

### Phase 1 — The foundation of a real recommender

We closed the big “must have” rows of the gap matrix:

1. **Purpose / surfaces** — Named the feeds MIND owns (Home For You, Hubs, Sparks, Explore, Masquerade, etc.) and how they map to APIs.  
2. **Invariants** — Hard rules, e.g. don’t double-count the same delivery; if ranking fails, still return *something* usable.  
3. **Architecture** — Documented how pieces connect (events → features → candidates → rank → ledger).  
5. **Events** — Cleaner ingest of “user watched / liked / skipped” style signals; strip junk metadata.  
6. **Masquerade isolation** — Public ranking must never leak into / steal preference from anonymous Masquerade data (privacy + product boundary).  
8. **Interest features** — Remember creator affinity + rough “personality” / hub interests.  
9. **Candidates** — Pull videos from several lanes (fresh, popular, following, …) then mix them.  
10. **Rank + diversity** — Score candidates, then diversify so one creator/family doesn’t own the whole feed.  
11. **Exposure ledger** — Log deliveries on For You–style surfaces so we can avoid dumb repeats.  
19. **Observability** — Live panels on `/mind` for events, decisions, ledger, seed.

**Result:** Production health reports policy **`mind.phase2.v1`** (Phase 1 complete, plus media Phase 2a below).

### Phase 2a — “Does the video *say* something we can use?”

Videos have sound and words. Humans use captions (CC). The brain can also use those words for **topics**.

We built:

- Reuse of existing **`video_transcripts`** (speech → text, historically via **Groq Whisper**)  
- A new table **`mind_content_features`**: language, topic tags (comedy, food, travel, …), a fingerprint of the text  
- A **soft boost** in ranking when topics match what the viewer seems to like  
- Rule: **missing transcript = UNKNOWN**, never “this video is bad / boring”  
- A **Media understanding** card on `/mind`  

Gap matrix **§7 Media understanding** is marked **shipped** for this thin slice.  
True “meaning vectors” (embeddings + pgvector ANN) were planned as **Phase 2b** and **paused** (see below).

---

## What we tried next (Phase 2b) — and why it paused

**Idea:** Turn each video’s text into a list of numbers (**embedding**) that capture *meaning*, store them with **pgvector** in Postgres, then find “videos like this one” even when keywords don’t match.

**What went well:**

- **pgvector** extension is enabled on the Matterya Supabase database  
- You created a SpaceXAI (`XAI_API_KEY`) Explore account with ~$5 credit  

**What we did instead (Phase 2b live):**

- SpaceXAI Explore had **no embedding models** for the team, so we used **Voyage `voyage-4-lite`**  
- Enabled **pgvector**, table **`mind_content_embeddings`**, title/body embed for ~39k posts  
- Soft **ANN** boost in Public ranking (`ann` / lane `home_ann_title`)  
- Policy **`mind.phase2.v2`**

---

## Side quests that touched MIND / the database

While MIND work was ongoing we also:

- Scrubbed live Masquerade text so **subreddit → space**, **reddit → Masquerade**  
- Lightened **Hubs** first open (less freezy) on iOS  
- Trimmed a huge **`kafka_outbox`** table and slowed `/mind` polling after a **Supabase Disk IO budget** warning  
- Agreed: **upgrade Supabase compute when necessary**, prefer trim/cache first  

---

## Gap matrix snapshot (how to read it)

On `/mind` → Gap matrix you’ll see rows like:

| Status | Meaning |
|---|---|
| **shipped** | Live enough for Matterya’s current phase |
| **missing** | Intentionally later (ads, GraphQL FeedItem, ML eval lab, …) |
| **partial** | Doc/UI exists but product depth still thin |

Shipped today includes §1–3, §5–11, §19 (and §7 as Phase 2a).  
Still missing on purpose: ads economy, GraphQL FeedItem, full ML evaluation lab, embeddings ANN.

---

## Your question: Can $5 transcribe ALL Matterya videos for CC?

### Short answer

**No — $5 is not enough to speech-to-text the whole Matterya video library.**

### Why (simple math)

SpaceXAI **Speech to Text** (batch) is about **$0.10 per hour of audio**.

Your wallet:

- **$5 ÷ $0.10 = about 50 hours** of audio total  

Matterya roughly has **~36,000** video-ish posts.

| If average video length is… | Hours of audio | Cost at $0.10/hr |
|---|---:|---:|
| 30 seconds | ~300 hours | **~$30** |
| 1 minute | ~600 hours | **~$60** |
| 2 minutes | ~1,200 hours | **~$120** |
| ~8.5 minutes (like today’s small “ready” sample average) | thousands of hours | **hundreds of $** |

So **$5 might cover a few thousand short clips**, not the whole catalog.

### The good news (you’re not starting from zero)

Matterya already has plumbing for this idea:

1. Table **`video_transcripts`** — stores status + text per post  
2. Worker that can call **Groq Whisper** when `GROQ_API_KEY` is set  
3. Today: **38 ready**, plus pending/skipped/failed rows  
4. iOS captions were moved toward **on-device WhisperKit** for live CC; server transcripts remain useful for MIND topics + optional server CC  

**Your product idea is right:**

> Transcribe once → save with the video → when the user taps CC, show the saved text (and let MIND use it too).

That’s exactly what `video_transcripts` is for. The limit is **money + time + Disk IO**, not the idea.

### Smarter ways to spend money

1. **Hubs-only / popular-only first** — transcribe the videos people actually watch  
2. **On demand** — first time someone hits CC (or a video gets traction), transcribe then cache  
3. Compare **Groq Whisper** vs **xAI Speech-to-Text** prices for your mix (both can write into the same `video_transcripts` table)  
4. Keep **$5 Explore** for experiments; budget a separate pool when you decide to bulk-transcribe  

---

## How a video travels through MIND (cartoon)

```
User opens Home
    ↓
App asks API for a shelf of videos
    ↓
MIND gathers CANDIDATES (several lanes)
    ↓
MIND loads FEATURES (who you like, topics if any, …)
    ↓
MIND RANKS + diversifies
    ↓
MIND returns ordered list
    ↓
MIND writes EXPOSURE LEDGER (“we showed these”)
    ↓
User watches / skips / likes → EVENTS → future MIND gets smarter
```

Masquerade stays in its own lane so anonymous community behavior doesn’t get mixed into public identity ranking.

---

## Where to click

| Want… | Go here |
|---|---|
| Live admin | https://api.matterya.com/mind |
| Deep engineering rules | `docs/mind/Matterya_MIND_Engineering_Handbook.md` |
| Checkbox of gaps | `docs/mind/01-gap-matrix.md` |
| What shipped when | `docs/mind/IMPLEMENTATION_LOG.md` |
| This friendly story | `docs/mind/MIND_FOR_HUMANS.md` (this file) |

---

## One-sentence summary

**MIND is Matterya’s feed brain; Phase 1 made it real and observable; Phase 2a taught it simple topics from transcripts; Phase 2b (meaning vectors) waits on SpaceXAI embedding access; $5 won’t transcribe the whole catalog, but saving transcripts for CC is the right design and we already have the table for it.**
