# Forge verdict — council-native-app (stage 1)

## Verdict: SURVIVE — as a gated two-track exploration, not a rewrite

The idea survives the forge because every fatal-looking objection resolves to a **gate we
can name**, not a contradiction. It dies instantly if treated as "replace the working
model-driven app this month" — that shape is rejected below.

## Pressure applied, and what held

- **"Private Preview — do not use this in production."** Held: the Council is a
  single-operator tool on Doug's own tenant; there is no production SLA to violate. The
  epic proposal carries the preview label on every story, and story 5-4's
  `VERIFY IN TENANT` discipline already exists for exactly this. **Die condition (named):
  if Council acquires real users beyond Doug before the stack GAs, mobile-native work
  stops at the preview line.**
- **"You already have a working app — why touch it?"** Held: the model-driven app was
  accepted as the MVP *admin* surface (app-curation + screen-gate evidence, 2026-07-11).
  The daily loop Doug actually lives in — triage on the phone, approve/decline, read the
  Minion Brief — is where model-driven UX is weakest and where the native track is aimed.
  The model-driven app is retained, not rebuilt; zero schema change.
- **"The stack moved 4 days ago; pins will churn."** Held, as a cost not a blocker:
  native-host 0.2.25 pins Expo 55/RN 0.83/React 19.2 tightly. Mitigation is per-app
  pinning and treating scaffold rebases as routine. This is why the epic is exploration
  (spike-shaped stories with evidence receipts), not committed product scope.
- **"Android gap."** Held: preview runtime is iOS-only (Developer app id 6753083462;
  Android "coming soon"). Doug is iOS-first for this loop — `VERIFY IN TENANT` row
  confirms device reality before story 6.2.
- **"Offline?"** Deferred honestly: `@microsoft/power-apps-native-offline` exists
  (extracted from the battle-tested HostingSDK) but plugin flows don't drive it yet.
  Offline is OUT of MVP scope; a watch item, not a promise.

## Rejected shapes (recorded so they stay rejected)

1. **Full replacement / decommission model-driven now** — discards accepted evidence for
   zero gain; admin surface still needed.
2. **Canvas app** — the direction Microsoft is visibly moving away from for pro-code;
   worse dev loop than Code Apps, no native mobile story.
3. **Custom React Native app straight at the Dataverse Web API** — violates FR27/NFR2
   (custom substrate where a Microsoft-native track exists: auth, hosting, lifecycle all
   hand-rolled). This is the shape the forge most wants to sneak in; explicitly dead.
4. **Wait for GA** — abandons the evaluation duty FR27 imposes; the point of 5-3 evidence
   is to engage while the platform moves, with gates.

## Remaining risk (carried forward)

Licensing for any second user (Premium/PAYG/app-pass; per-app SKU retired Jan 2026) and
ALM immaturity (push-only deployment today) are real costs the brief and evidence record
carry explicitly. Neither blocks a dev-tenant exploration.
