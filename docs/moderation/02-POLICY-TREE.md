# Matterya moderation policy tree

Mods at `https://api.matterya.com/reports` only **answer questions** (keyboard shortcuts).  
They do **not** choose Remove vs Mark. Each leaf in `apps/api/src/moderation/policy-tree.ts` has an `outcome`:

| outcome | Effect |
|--------|--------|
| `remove` | Take content down / archive |
| `mark` | Keep live, tagged |
| `dismiss` | False positive / allowed — clear flags |

## Tuning together

1. Edit leaves in `policy-tree.ts` (labels, nesting, `outcome`).
2. Deploy API (`ios-native`).
3. Audit via `moderation_tickets.mod_note` (`policy:<leaf>|outcome:<…>`) and action log.

Client JSON from `policyTreeForClient()` never includes outcomes.

## Keyboard

- `1`–`9` / `0` / letters — choose option at current step  
- `Backspace` / `Esc` — go back  
- `Enter` — confirm leaf  
- `P` — pass ticket to another mod  

## Flow

**Step 1:** Is it actionable? → **Yes** | **Ignore**  
- **Ignore** = clear false alarm / nothing wrong only.  
- Content that stays for a policy reason (recovery, news mark, labeled mature, satire) = **Yes** → matching leaf.

**Step 2** (after Yes): issue kinds ordered by harm priority (CSAM → Self-harm → Terrorism → Violence → Servitude → Harassment → Hate → Doxxing → Scam → Misinfo → Adult solicitation → Mature → Spam → Other).

## Escalation (inside a violation only)

Escalate is **not** its own Step 2 category. Follow-up questions inside CSAM, self-harm, terrorism threats, harassment threats/stalking, servitude trafficking, solicitation sextortion, and doxxing lead to escalate leaves when needed. Specialist second look lives under **Other**.

| Leaf | Outcome |
|------|---------|
| `escalation.child_safety` | remove · severe |
| `escalation.imminent_violence` | remove · severe |
| `escalation.suicide_crisis` | remove · severe |
| `escalation.trafficking` | remove · severe |
| `escalation.sextortion` | remove · severe |
| `escalation.second_look` | mark (via Other) |

Ordinary doubt → Pass (`P`).

## Training

Moderator handbook:  
https://api.matterya.com/management/policy · source `docs/moderation/04-POLICY-HANDBOOK.md`
