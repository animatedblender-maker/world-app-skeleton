# What is Matterya MIND?

MIND is the **recommendation brain** behind Matterya’s feeds.

When someone opens Home, Sparks, or Hubs, MIND helps decide:
- which posts to show
- in what order
- how to avoid showing the same thing twice
- how to keep Public feed and Masquerade (anonymous) separate

### Why it matters
Big platforms (TikTok, YouTube, Instagram) win partly because the feed **feels smart**.  
MIND is how Matterya gets that feeling — without building a huge AI lab from scratch.

### The three layers (simple)
1. **Events** — likes, watches, hides, scrolls (what people do)  
2. **Understanding** — topics from transcripts + Voyage embeddings from titles/captions  
3. **Ranking** — combine those signals → serve a page of posts → remember what was shown  

### Surfaces MIND cares about
| Surface | Everyday name |
|---|---|
| `home_for_you` | Home “For You” |
| `hubs_for_you` | Hubs personalized shelf |
| `masquerade_for_you` | Anonymous / Masquerade feed |

Public and Masquerade **must never mix preferences**. That isolation is already built in.

### Where you look at it
Open **https://api.matterya.com/mind** (same Ops password as Pipeline / Reports).

Tabs you’ll see:
- Overview  
- Live system  
- Architecture  
- Gap matrix  
- Masquerade  
- Docs & handbook  
- Roadmap  

### Phases (where we are)
| Phase | Status | Plain meaning |
|---|---|---|
| Phase 1 | Done | Ledger, events, candidates, interest, isolation, admin console |
| Phase 2a | Done | Topics from video transcripts |
| Phase 2b | Done (shipping) | Voyage embeddings + “similar posts” for Home |
| Later | Not yet | Ads, heavy ML eval, GraphQL feed rewrite |

### What MIND is *not*
- Not a chatbot  
- Not “embed every frame of every long video”  
- Not a replacement for butter-smooth video playback or creator tools  

Those are separate pillars — see [What’s next](./06-whats-next.md).
