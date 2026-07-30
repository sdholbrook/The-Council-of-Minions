# Product brief — Council native operator surface (stage 2)

## Problem

The Council's decision loop lives where Doug is: on the phone between meetings, at a
desk when curating. The model-driven app serves the desk-admin case but is a poor phone
surface — navigation-heavy, form-first, no native affordances. Result: the highest-value
loop (see flagged item → approve/decline delegation → skim the Minion Brief) pays a UX
tax exactly where speed matters most.

## Users

Doug. (Single-operator by design; FR22-family approval boundaries assume one human.)

## Goals

1. The daily loop — triage queue, approve/decline with receipts, Minion Brief — usable
   in under a minute from a phone, native feel (gesture, offline-tolerant reads later).
2. A pro-code desktop surface (Code App) for curation flows that outgrow model-driven
   forms, developed in-repo with real version control instead of designer state.
3. Zero schema drift: both surfaces bind to the EXISTING Dataverse MVP tables; every
   mutation stays receipt-backed through the same patterns epic 2 defines.
4. Evaluation evidence (5-3) and tenant gates (5-4) satisfied BEFORE build — this
   program is the Microsoft-first discipline working, not an exception to it.

## Non-goals

- Decommissioning the model-driven app (stays as admin/fallback).
- Offline sync (packages exist; plugin flows don't drive them — watch item).
- Android (preview runtime is iOS-only today).
- Any new Dataverse tables, columns, or connectors beyond what epics 1–4 already define.
- Production posture of any kind while the stack is Private Preview.

## Shape (two tracks, one schema)

- **Track M — mobile-native:** scaffold via `power-platform-skills` mobile-apps plugin
  (`/create-mobile-app`, four approval gates, Wrap-generated Entra registration),
  Expo/RN on `@microsoft/power-apps-native-host` (Tamagui + TanStack Query baked in),
  QR-preview through the Power Apps Developer iOS app, deploy via `npx power-apps push`.
- **Track C — code app (desktop web):** code-apps plugin, `@microsoft/power-apps` SDK
  1.2.7; owns curation views the model-driven app renders poorly.
- **Sequencing:** M first (it is the pain point and the novel capability); C follows
  once M's auth + data patterns are proven. Both tracks are stories under one epic
  (epic-6 proposal, staged alongside) so sprint status stays honest.

## MVP scope cut (what "working when I get home" means)

Phone: sign in → see the prioritized source-record queue (epic-1 data) → open an item →
approve/decline the proposed work item with a receipt (epic-2 rules) → read the current
Minion Brief snapshot (epic-3 projection). Everything else is later.

## Risks (carried, not hidden)

Preview churn (tight Expo/RN pins — rebases expected) · iOS-only · licensing for any
second user · ALM is push-only (no solution packaging in plugin flows yet) · plugin
marketplace + MCP servers are new moving parts in the toolchain. Mitigations named in
the forge verdict and the 5-3 evidence record.

## Success criteria

- Stage-4+ gauntlet resumes only on Doug's approval of this plan (D-15 stop line).
- 5-4-style tenant evidence exists before the first `/create-mobile-app` run.
- First scaffold reaches the Developer app on Doug's phone with live Dataverse reads.
- Approve/decline round-trip writes the same receipt shape epic-2 specifies.
