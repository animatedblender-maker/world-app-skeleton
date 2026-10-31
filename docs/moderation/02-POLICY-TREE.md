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

## Escalation (specific cases only)

Step 2 includes a standalone **Terrorism** kind (separate from Violence).

Root option **Escalate — special safety case**, plus gates inside mature / threats / stalking / blackmail / self-harm / terrorism threats / doxxing:

| Leaf | Outcome |
|------|---------|
| `escalation.child_safety` | remove · severe |
| `escalation.imminent_violence` | remove · severe |
| `escalation.suicide_crisis` | remove · severe |
| `escalation.second_look` | mark |

Not a general uncertainty shortcut — use Pass (`P`) or the best category leaf for ordinary doubt.

## Training

Moderator handbook (principles, leaf guides, industry alignment):  
https://api.matterya.com/management/policy · source `docs/moderation/04-POLICY-HANDBOOK.md`

