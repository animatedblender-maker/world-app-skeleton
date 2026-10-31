# Matterya Moderator Policy Handbook

**Audience:** human moderators on Claim-next (`/reports`) and Account review (`/reports/accounts`)  
**Live page:** https://api.matterya.com/management/policy  
**Version:** 2026-10-31 · aligned with `policy-tree.ts` leaves

This handbook trains *how* to answer the decision tree and *why*. Moderators never pick Remove / Mark / Dismiss in the UI — policy maps each leaf to an outcome and severity.

---

## 1. Principles (industry-aligned)

Drawn from Meta Community Standards (Safety / Dignity / Privacy / Authenticity), YouTube Community Guidelines (incl. EDSA exceptions), TikTok Community Guidelines (remove / age-restrict / FYF-ineligible), X Rules, Reddit Content Policy, Discord Guidelines, and Snap Community Guidelines.

| Principle | Matterya meaning |
|---|---|
| **Safety** | Prefer removing content that raises real-world physical harm risk (threats, incitement, CSAM, self-harm instructions, scams that steal money). |
| **Dignity** | Target people for abuse, hate, or humiliation → remove. Critique of ideas / public figures can stay when not a personal attack. |
| **Privacy** | Hard PII, NCII, workplace doxxing → remove + severe account path. Public-record info alone is usually OK. |
| **Expression** | Satire, recovery stories, news/documentary graphic (labeled), artistic nudity, reclaimed in-group speech → dismiss or mark, not remove. |
| **Authenticity** | Phishing, brand impersonation, fake engagement, malware → remove; malware/phishing escalate accounts. |

**Matterya product note:** Masquerade is adult-oriented. Labeled mature content in an adult Space may be **marked** rather than removed. Unlabeled porn in general feed / non-adult contexts is **removed**.

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
| `escalation.imminent_violence` | Credible threat that is imminent/ongoing, swatting, extremist ops planning | remove · **severe** |
| `escalation.suicide_crisis` | Active suicide/self-harm crisis with a concrete plan | remove · **severe** |
| `escalation.second_look` | High-stakes but outcome still unclear after reading the content | mark |

**Where the tree asks:**

- Root → **Escalate — special safety case** (lists the four above)
- Mature → first question: involves a minor sexually?
- Harassment threats / stalking → imminent?
- Sexual blackmail → minor involved?
- Self-harm → active crisis with plan?
- Violence extremist → active recruitment/ops?
- Doxxing hard PII / NCII → imminent harm or minor?

Ordinary uncertainty inside a category: pick the best fitting leaf, or Pass (`P`). Do **not** use escalation for spam vs promo debates.

---

## 3. Cross-cutting rules (read before category guides)

1. **Minors always win.** Anything sexual involving anyone under 18 (real, AI, drawn, text solicitation, grooming) → `escalation.child_safety` (severe). Do not mark. Do not dismiss as “art.”
2. **News / documentary / EDSA.** Graphic violence or sensitive imagery with clear public-interest framing → `violence.news` (mark) or artistic/educational leaves — not gore-remove — unless it glorifies or recruits.
3. **Satire / clearly labeled fiction.** Prefer dismiss (`misinfo.satire`, `violence.fictional`) when intent is obvious.
4. **Reclaimed speech.** In-group reclaimed slurs without attacking others → `hate.reclaimed` (dismiss). Out-group weaponization → hate remove leaves.
5. **Survivors.** People describing their own assault/self-harm for support → prefer mark/dismiss recovery paths, never pile-on remove for the survivor’s own post.
6. **Hyperbole vs threat.** “I’m gonna kill this exam” → not a threat. “I’m going to your house at 9 with a knife” → `harassment.threats.credible` (severe).
7. **When torn.** Pass (`P`) or `escalation.second_look`. Do not invent a leaf that doesn’t fit.

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
| `hate.protected.stereotype` | Lazy stereotype without call to harm | mark |
| `hate.praise` | Praise of hate groups / atrocities | remove · **severe** |
| `hate.conspiracy` | Blood libel–style group conspiracies | remove · mild |
| `hate.reclaimed` | In-group reclaimed usage | dismiss |

### Mature / sexual

| Leaf | Pick when | Outcome |
|---|---|---|
| `mature.porn.unlabeled` | Explicit sex outside expected adult context | remove · mild |
| `mature.porn.labeled_space` | Explicit in clearly adult Masquerade Space | mark |
| `mature.porn.animated` | Animated/drawn adult porn (no minors) | mark |
| `escalation.child_safety` | Any sexual content involving minors (incl. AI/drawn) or grooming — use escalate path | remove · **severe** |
| `mature.child_endangerment` | Non-sexual endangerment of minors (dangerous challenges, trafficking facilitation, physical abuse) | remove · **severe** |
| `mature.nudity.sexualized` | Sexualized adult nudity | mark |
| `mature.nudity.artistic` | Art / medical / educational | dismiss |
| `mature.nudity.shock` | Unwanted flash / shock nudity | remove · mild |
| `mature.fetish` | Consensual adult fetish | mark |
| `mature.suggestive` | Suggestive, not explicit | mark |
| `mature.false_positive` | Auto NSFW wrong | dismiss |

**NCII** (non-consensual intimate imagery of adults) lives under **doxxing.intimate** (severe) — same as X / Discord / Meta / Snap.

### Violence

| Leaf | Pick when | Outcome |
|---|---|---|
| `violence.gore` | Real gore for shock | remove · **severe** |
| `violence.animal` | Animal cruelty | remove · **severe** |
| `violence.incitement` | Calls to commit violent crime | remove · **severe** |
| `violence.extremist` | Praise / recruit for violent extremist orgs (Meta DOI / YouTube VCO style) | remove · **severe** |
| `violence.fictional` | Games / movies clearly fiction | dismiss |
| `violence.news` | Newsworthy graphic with context | mark |

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
| `escalation.second_look` | Needs another human | mark |

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

Official / primary pages used for alignment (2024–2026):

- Meta Community Standards — https://transparency.meta.com/policies/community-standards/
- YouTube Community Guidelines — https://support.google.com/youtube/answer/9288567
- TikTok Community Guidelines — https://www.tiktok.com/community-guidelines
- X Rules — https://help.x.com/en/rules-and-policies/x-rules
- Reddit Content Policy — https://www.reddit.com/help/contentpolicy
- Discord Community Guidelines — https://discord.com/guidelines/
- Snap Community Guidelines — https://www.snap.com/community-guidelines

Matterya is not a copy of any one platform. We borrow **decision patterns** (remove vs age-gate/mark vs allow; severe vs accumulate; child safety zero-tolerance; EDSA/news exceptions) and encode them in our tree.

---

## 7. Changelog

| Date | Change |
|---|---|
| 2026-10-31 | First handbook. Tree adds: `violence.extremist`, `mature.grooming`, `mature.child_endangerment`, `self_harm.eating_disorder`, `misinfo.crisis_panic`, `scam.regulated_goods`. Severity flips: `spam.malware`, `hate.protected.exclusion`, `scam.romance` → severe. NCII label clarified on `doxxing.intimate`. |
| 2026-10-31 | Escalation leaves for specific cases only: `escalation.child_safety`, `escalation.imminent_violence`, `escalation.suicide_crisis`, `escalation.second_look`. Wired into mature/threats/stalking/blackmail/self-harm/extremist/doxxing gates. |
