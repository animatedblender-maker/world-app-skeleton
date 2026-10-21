# Matterya Anonymous

Adult-only pseudonymous Spaces inside Matterya. Replaces the Globe tab on iOS and web.

**Spec:** `~/Downloads/Matterya_Anonymous_Full_Product_and_Technical_Spec.md`  
**Migration:** `supabase/migrations/20261022120000_anonymous_foundation.sql` (paste into Supabase SQL Editor — Manual apply)  
**API:** `GET/POST https://api.matterya.com/v1/anonymous/*` (Bearer JWT)  
**Flag:** `ANONYMOUS_PAID_ENABLED=true` enables paid checkout scaffolding (default off — StoreKit/legal gate)

## Product rules (locked)

1. 18+ via `profiles.birthdate` + first-entry attestation.
2. Exactly one persistent generated Anonymous username per account (`adjective_noun_####`), immutable.
3. No public link to ordinary Matterya identity; vault mapping in `identity_vault` (service-only).
4. Free Spaces launch first; paid Spaces scaffolded, not live until billing/legal.
5. Text posts/comments/votes in v1 (no media).

## Surfaces

- **iOS:** `AppTab.anonymous` → `AnonymousRootView` (Spaces / Feed / Search / Inbox / Me)
- **Web:** `/anonymous` (Globe routes redirect here)
- **API module:** `apps/api/src/anonymous/`

## Launch gate (paid)

Do not enable paid Spaces until App Store billing route, creator terms, refund process, and privacy tests pass (spec §16).
