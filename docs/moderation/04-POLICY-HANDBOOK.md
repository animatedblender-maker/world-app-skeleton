# Matterya Moderator Policy Handbook

**Audience:** human moderators on Claim-next (`/reports`) and Account review (`/reports/accounts`)  
**Live page:** https://api.matterya.com/management/policy  
**Version:** 2026-10-31 · aligned with `policy-tree.ts` leaves

This handbook trains *how* to answer the decision tree and *why*. Moderators never pick Remove / Mark / Dismiss in the UI — policy maps each leaf to an outcome and severity.

---

## 1. Principles (follow platforms with more experience)

**Default baseline for this queue (Claim-next):** **Meta Community Standards** + **TikTok Community Guidelines**.

When Meta and TikTok agree, Matterya does the same. When they disagree, prefer the **stricter remove / escalate** rule unless a Matterya product exception is listed below.

**YouTube is not the baseline here.** YouTube’s EDSA / longform age-restrict patterns belong in a **separate longform-video moderation queue** (not this tree). Do not keep graphic or violative longform “because YouTube would age-restrict it” on Claim-next.

Also consulted for edge cases: X Rules, Discord, Reddit, Snap — never to loosen Meta/TikTok on CSAM, specific threats, or trafficking.

| Principle | Matterya meaning (Meta + TikTok) |
|---|---|
| **Safety** | Remove content that raises real-world physical harm risk (specific threats with place/time/target, incitement, CSAM, self-harm instructions, scams, forced labor). Escalate when platforms escalate. |
| **Dignity** | Hate / harassment targeting people → remove. Critique of ideas / public figures can stay when not a personal attack. |
| **Privacy** | Hard PII, NCII, workplace doxxing → remove + severe. Public-record info alone is usually OK. |
| **Expression** | Satire, recovery stories, clear condemnation, reclaimed in-group speech → dismiss or mark. News/graphic: **mark** (TikTok-like age-gate analogue), not YouTube EDSA keep. |
| **Authenticity** | Phishing, brand impersonation, malware → remove; malware/phishing → severe / escalate accounts. |

**Matterya product exceptions (intentional):**
- Masquerade labeled adult Spaces: consensual adult porn/nudity may be **marked** (TikTok would often remove or age-restrict platform-wide; Matterya allows adult Spaces).
- Unlabeled porn in general feed → **remove** (Meta/TikTok-aligned).

---

## 2. How Matterya enforcement works

### Content queue (`/reports`)

1. Answer questions with keyboard shortcuts (1–9, letters).
2. Confirm the leaf. Policy applies **remove**, **mark**, or **dismiss** invisibly.
3. Flash always says “Decision recorded” — never leak Remove/Mark to the mod UI.

| Outcome | Effect |
|---|---|
| **remove** | Content archived / taken down. Author + reporters notified. Strike recorded. |
| **mark** | Content stays; tagged for mature/sensitive surfaces. No strike. |
| **dismiss** | False positive / allowed. Clear auto flags. No strike. |

### Severity → account queue (`/reports/accounts`)

| Severity | On remove |
|---|---|
| **severe** | Instant account-review ticket |
| **mild** | +1 open strike; at **3** open strikes → account ticket |

Account actions: clear strikes · warn · restrict · suspend · pass.

### Pass

`P` hands the ticket to another moderator (`passed_by`). Use when unsure or conflicted on an ordinary ticket.

### Escalation (decision-tree leaves — specific cases only)

Like Meta / Discord / TikTok / X, escalation is **not** a general “I’m unsure of the category” button. It appears only for special safety cases:

| Leaf | When | Outcome |
|---|---|---|
| `escalation.child_safety` | Sexual content involving a minor (incl. AI/drawn), grooming, minor NCII / sextortion | remove · **severe** |
| `escalation.imminent_violence` | Credible threat with **place, time, target, and/or method** (terror attack threat, swatting, ops planning) | remove · **severe** |
| `escalation.suicide_crisis` | Active suicide/self-harm crisis with a concrete plan | remove · **severe** |
| `escalation.second_look` | High-stakes but outcome still unclear after reading the content | mark |

**Where the tree asks:**

- Root → **Escalate — special safety case** (lists the four above)
- CSAM category → confirmed/suspected cases escalate  
- Mature → gate redirects minors to CSAM escalate, solicitation to Adult solicitation
- Harassment threats / stalking → imminent?
- Sexual blackmail → minor involved?
- Self-harm → active crisis with plan?
- Violence extremist → active recruitment/ops?
- Doxxing hard PII / NCII → imminent harm or minor?

Ordinary uncertainty inside a category: pick the best fitting leaf, or Pass (`P`). Do **not** use escalation for spam vs promo debates.

---

## 3. Cross-cutting rules (read before category guides)

1. **Minors always win.** Anything sexual involving anyone under 18 → Step 2 **CSAM** (always severe). Confirmed CSAM / grooming / minor NCII → `escalation.child_safety`. Do not mark. Do not dismiss as “art.”
2. **News / documentary / EDSA.** Graphic violence or sensitive imagery with clear public-interest framing → `violence.news` (mark) or artistic/educational leaves — not gore-remove — unless it glorifies or recruits.
3. **Satire / clearly labeled fiction.** Prefer dismiss (`misinfo.satire`, `violence.fictional`) when intent is obvious.
4. **Reclaimed speech.** In-group reclaimed slurs without attacking others → `hate.reclaimed` (dismiss). Out-group weaponization → hate remove leaves.
5. **Survivors.** People describing their own assault/self-harm for support → prefer mark/dismiss recovery paths, never pile-on remove for the survivor’s own post.
6. **Hyperbole vs threat.** “I’m gonna kill this exam” → not a threat. “I’m going to your house at 9 with a knife” → `harassment.threats.credible` (severe).
7. **When torn.** Pass (`P`) for ordinary doubt. Use `escalation.second_look` only when stakes are high and the outcome is still unclear after reading. Do not invent a leaf that doesn’t fit.

---

## 4. Category decision guides

### Spam

| Leaf | Pick when | Outcome |
|---|---|---|
| `spam.commercial` | Unsolicited ads, crypto pumps, “DM for deals” | remove · mild |
| `spam.flooding` | Same post/comment pasted repeatedly | remove · mild |
| `spam.engagement_bait` | “Like for secret,” clickfarms, fake giveaways as bait | remove · mild |
| `spam.malware` | Phishing links, credential stealers, malware | remove · **severe** |
| `spam.borderline_promo` | Self-promo that fits community norms | mark |

**Industry note:** Discord/YouTube treat phishing and platform manipulation as high severity — Matterya escalates malware/phishing to the account queue immediately.

### Harassment / bullying

| Leaf | Pick when | Outcome |
|---|---|---|
| `…targeted_cursing` | Insults aimed at a specific person | remove · mild |
| `…slurs` | Slurs used to bully a person (not group-hate) | remove · mild |
| `…humiliation` | Shame campaigns, body mockery of a private person | remove · mild |
| `…pile_on` | Calling others to flood/abuse someone | remove · mild |
| `…mild_rude` | Rude but not targeted harassment | dismiss |
| `…threats.credible` | Specific, believable plan to harm | remove · **severe** |
| `…threats.hyperbolic` | Rage jokes with no plan/capability | mark |
| `…threats.wish_harm` | “Hope you die / get cancer” | remove · **severe** |
| `…sexual.unsolicited` | Unwanted sexual DMs/comments to a person | remove · mild |
| `…sexual.blackmail` | Sextortion / coerce with intimate media | remove · **severe** |
| `…sexual.creepy` | Persistent non-explicit interest after no | mark |
| `harassment.stalking` | Repeated unwanted contact across posts | remove · **severe** |
| `harassment.impersonation` | Fake identity used to harass | remove · mild |

Aligns with Meta bullying tiers, X abuse/harassment, Reddit Rule 1, Discord §§1–2.

### Hate

Protected characteristics (Matterya practice, Meta/X/TikTok-aligned): race, ethnicity, national origin, religion, caste, sex, gender identity, sexual orientation, disability, serious disease.

| Leaf | Pick when | Outcome |
|---|---|---|
| `hate.protected.dehumanizing` | Calling a group animals/subhuman | remove · **severe** |
| `hate.protected.slurs` | Slurs attacking a protected group | remove · **severe** |
| `hate.protected.exclusion` | Segregation / “go back” / deny rights | remove · **severe** |
| `hate.protected.stereotype` | Demeaning stereotypes of a protected group | remove · mild |
| `hate.praise` | Praise of hate groups / atrocities | remove · **severe** |
| `hate.conspiracy` | Blood libel–style group conspiracies | remove · mild |
| `hate.reclaimed` | In-group reclaimed usage | dismiss |

### CSAM (standalone Step-2 #1 — always severe)

| Leaf | Pick when | Outcome |
|---|---|---|
| `escalation.child_safety` | Confirmed CSAM, grooming, minor NCII, sexualization, or suspected CSAM | remove · **severe** + escalate |
| `csam.child_endangerment` | Non-sexual endangerment of minors | remove · **severe** |

### Adult solicitation (standalone)

| Leaf | Pick when | Outcome |
|---|---|---|
| `solicitation.services` | Offering paid sex / escort / sexual services | remove · mild |
| `solicitation.seeking` | Requesting adult sexual services | remove · mild |
| `solicitation.unsolicited` | Unsolicited sexual advances to an adult | remove · mild |
| → **escalate** | Adult sextortion with concrete demand | `escalation.sextortion` · **severe** |
| `solicitation.sextortion` | Sexual blackmail language without concrete demand | remove · **severe** |
| → CSAM escalate | Anything involving a minor | `escalation.child_safety` |

### Servitude / domestic helpers (standalone)

| Leaf | Pick when | Outcome |
|---|---|---|
| `servitude.forced` | Forced domestic servitude / forced labor | remove · **severe** |
| `escalation.trafficking` | Confirmed / organized trafficking of helpers | remove · **severe** + escalate |
| `servitude.trafficking` | Strong trafficking indicators | remove · **severe** |
| `servitude.debt_bondage` | Debt bondage / passport confiscation / coercive wage theft | remove · **severe** |
| `servitude.recruitment` | Deceptive domestic-helper recruitment | remove · mild |
| `servitude.legit_job` | Ordinary helper job ad, no coercion | dismiss |
| → CSAM escalate | Minor used as worker / helper | `escalation.child_safety` |

### Mature / sexual (adult media only)

| Leaf | Pick when | Outcome |
|---|---|---|
| `mature.porn.unlabeled` | Explicit sex outside expected adult context | remove · mild |
| `mature.porn.labeled_space` | Explicit in clearly adult Masquerade Space | mark |
| `mature.porn.animated` | Animated/drawn adult porn (adults only) | mark |
| `mature.nudity.sexualized` | Sexualized adult nudity | mark |
| `mature.nudity.artistic` | Art / medical / educational | dismiss |
| `mature.nudity.shock` | Unwanted flash / shock nudity | remove · mild |
| `mature.fetish` | Consensual adult fetish | mark |
| `mature.suggestive` | Suggestive, not explicit | mark |
| `mature.false_positive` | Auto NSFW wrong | dismiss |

**Adult NCII** → `doxxing.intimate` (severe). **Minor NCII** → CSAM escalate.

### Violence

| Leaf | Pick when | Outcome |
|---|---|---|
| `violence.gore` | Real gore for shock | remove · **severe** |
| `violence.animal` | Animal cruelty | remove · **severe** |
| `violence.incitement` | Calls to commit violent crime (non-terror) | remove · **severe** |
| `violence.fictional` | Games / movies clearly fiction | dismiss |
| `violence.news` | Newsworthy graphic with context | mark |

Terrorism / violent extremist orgs are a **standalone Step-2 category** (not under Violence).

### Terrorism

| Leaf | Pick when | Outcome |
|---|---|---|
| `terrorism.ops` | Recruitment, fundraising, or operational planning | remove · **severe** |
| `terrorism.praise` | Praise / propaganda for a terrorist org or attack | remove · **severe** |
| → **escalate** | Terror threat with **place / time / target / method** | `escalation.imminent_violence` · **severe** |
| `terrorism.threat` | Vague terror threat only (no place, time, target, or method) | remove · **severe** |
| `terrorism.news` | News / documentary / clear condemnation | mark |
| `terrorism.historical` | Historical or educational, no glorification | dismiss |

### Self-harm

| Leaf | Pick when | Outcome |
|---|---|---|
| `self_harm.promotion` | Instructions / encouragement to self-harm or suicide | remove · **severe** |
| `self_harm.graphic` | Graphic self-injury imagery | remove · mild |
| `self_harm.ideation_help` | Person in crisis asking for help | mark |
| `self_harm.recovery` | Recovery / awareness, non-graphic | dismiss |
| `self_harm.eating_disorder` | Tips/praise for disordered eating or dangerous weight methods | remove · mild |

### Misinformation

| Leaf | Pick when | Outcome |
|---|---|---|
| `misinfo.health_harm` | False medical claims with serious harm risk | remove · mild |
| `misinfo.civic` | Election / voting process falsehoods | mark |
| `misinfo.manipulated` | Deepfake / doctored media presented as real | remove · mild |
| `misinfo.satire` | Clearly labeled satire | dismiss |
| `misinfo.low_harm` | Unverified rumor, low stakes | mark |
| `misinfo.crisis_panic` | Fake disaster / resource hoax that can cause panic | remove · mild |

### Scam / fraud / regulated goods

| Leaf | Pick when | Outcome |
|---|---|---|
| `scam.financial` | Fake giveaways, investment fraud | remove · **severe** |
| `scam.impersonation` | Fake Matterya / brand support | remove · **severe** |
| `scam.romance` | Romance / social-engineering scams | remove · **severe** |
| `scam.unclear` | Fishy but not proven | mark |
| `scam.regulated_goods` | Selling weapons, drugs, other regulated/dangerous goods | remove · **severe** |

### Doxxing / privacy

| Leaf | Pick when | Outcome |
|---|---|---|
| `doxxing.pii_hard` | Home address, phone, gov ID, financial accounts | remove · **severe** |
| `doxxing.intimate` | NCII / private messages shared without consent | remove · **severe** |
| `doxxing.workplace` | School/work identifiers used to harass | remove · **severe** |
| `doxxing.public_record` | Already public official pages / news | dismiss |

### Other

| Leaf | Pick when | Outcome |
|---|---|---|
| `other.unlisted` | Real violation, no better leaf yet | mark |
| `allowed.false_positive` | No violation | dismiss |
| `escalation.second_look` | High-stakes specialist review (see Escalation section) | mark |

---

## 5. Account review training

Open when severe remove fires or mild strikes hit 3.

| Action | Use when |
|---|---|
| **Clear strikes** | Content action was enough; account looks OK |
| **Warn** | Pattern starting; educate |
| **Restrict** | Repeat mild abuse; temporary friction |
| **Suspend** | Severe pattern, malware/scam rings, child safety, credible threats |
| **Pass** | Another mod should decide |

Never tell the content-queue flash what account action you took.

---

## 6. Sources consulted (external)

**Primary (this queue):**
- Meta Community Standards — https://transparency.meta.com/policies/community-standards/
- TikTok Community Guidelines — https://www.tiktok.com/community-guidelines

**Secondary (edge cases only):**
- X Rules — https://help.x.com/en/rules-and-policies/x-rules
- Discord Community Guidelines — https://discord.com/guidelines/
- Reddit Content Policy — https://www.reddit.com/help/contentpolicy
- Snap Community Guidelines — https://www.snap.com/community-guidelines

**Not used for Claim-next:**
- YouTube Community Guidelines / EDSA — reserved for the **longform video** moderation queue.

## 6b. Longform video queue (YouTube-shaped — separate)

Longform videos get their own queue later. That queue may use YouTube-like patterns: EDSA (educational/documentary/scientific/artistic) exceptions, age-restrict vs remove, and public-interest keeps that Claim-next must not apply to short posts/clips.

Until that queue exists, treat longform the same as any other ticket in Claim-next under Meta + TikTok rules.

---

## 7. Changelog

| Date | Change |
|---|---|
| 2026-10-31 | First handbook. Tree adds: `violence.extremist`, `mature.grooming`, `mature.child_endangerment`, `self_harm.eating_disorder`, `misinfo.crisis_panic`, `scam.regulated_goods`. Severity flips: `spam.malware`, `hate.protected.exclusion`, `scam.romance` → severe. NCII label clarified on `doxxing.intimate`. |
| 2026-10-31 | Escalation leaves for specific cases only: `escalation.child_safety`, `escalation.imminent_violence`, `escalation.suicide_crisis`, `escalation.second_look`. Wired into mature/threats/stalking/blackmail/self-harm/extremist/doxxing gates. |
| 2026-10-31 | Step-2 standalone **Terrorism** category (`terrorism.ops` / `praise` / `threat` / `news` / `historical`). Removed `violence.extremist` in favor of this path. |
| 2026-10-31 | Step-2 ordered by harm priority: Self-harm → Terrorism → Violence → Harassment → Hate → Doxxing → Scam → Misinfo → Mature → Spam → Other. |
| 2026-10-31 | Standalone **CSAM** (#1, always severe, escalate on confirmed/suspected) and **Adult solicitation**. Mature is adult media only. |
| 2026-10-31 | Standalone **Servitude / domestic helpers** (forced labor, trafficking escalate, debt bondage, recruitment, legit job dismiss). |
| 2026-10-31 | Claim-next baseline = **Meta + TikTok** only. YouTube/EDSA deferred to a separate longform-video queue. Hate stereotypes → remove; CSAM sexualization → escalate; concrete sextortion → escalate. |
