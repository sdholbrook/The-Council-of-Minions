# Architecture: Council Native Operator Surface (council-native-app)

- **Status: final** (gauntlet stage 5) · governs epic-6 · delta to
  `architecture-The-Council-of-Minions-2026-07-06` (which remains authoritative for the
  Dataverse spine, model-driven app, and epics 1–5).
- **Adversarial review:** `adversarial-review-receipt.md` (same folder) — 7 findings,
  all resolved into this spine before finalization. No unreviewed spine.

## 1. System context

```
                    ┌─────────────────────────────────────────┐
                    │       Dataverse (sdhdev environment)     │
                    │  existing MVP tables · views · receipts  │
                    └──────┬──────────────┬──────────────┬────┘
                           │              │              │
              ┌────────────┴───┐  ┌───────┴────────┐  ┌──┴───────────────┐
              │ Council Queue  │  │ Track M: mobile │  │ Track C: Code App │
              │ (model-driven) │  │ Expo/RN         │  │ desktop curation  │
              │ ADMIN/FALLBACK │  │ native-host     │  │ @microsoft/       │
              │  — unchanged   │  │ DAILY LOOP      │  │ power-apps SDK    │
              └────────────────┘  └─────────────────┘  └───────────────────┘
```

Three surfaces, one spine. Nothing in this document adds tables, columns, views,
connectors, or automations.

## 2. Invariants (the spine — everything else is derived)

- **I1 — One mutation contract.** Every write from any surface produces the SAME
  receipt-backed state change: deterministic work-item state + a `com_councilreceipt`
  row with a **deterministic receipt ID** (`CR-<workitem-natural-id>-<STATE>` — the
  pattern proven in `state-transition-demo-evidence.json`, `idempotencyBasis:
  "deterministic Work Item IDs and Receipt IDs"`). Retries are upserts on the natural
  key, so a flaky mobile network cannot double-write (epic-2 story 2-4's intent,
  consumed ahead of its formal implementation — see §6 sequencing).
- **I2 — Existing schema only.** Track M/C bind to existing tables and their views. A
  schema need exits epic-6 into normal planning. No exceptions for "just one column."
- **I3 — Toolchain-generated baseline.** Scaffolds come from the `power-platform-skills`
  plugins; auth comes from `-native-auth`'s Wrap registration. We do not hand-roll what
  the toolchain generates (auth flows, hosting glue, project layout). Custom code lives
  ABOVE the scaffold line: screens, data mappers, mutation module.
- **I4 — Pin manifest is the version authority.** `apps/council-mobile/PINS.md` (and the
  Track C equivalent) records every `@microsoft/*`, Expo, RN, React version. Upgrades
  are deliberate rebase commits citing the manifest diff. Nothing floats.
- **I5 — Tenant gates precede tenant touches.** PRD T1–T5 rows, in order, each with
  committed evidence. Container sessions stop above T1; home/tenant work proceeds
  gate-by-gate.
- **I6 — Receipts in the repo.** Every gate answer, every `/create-mobile-app` approval,
  every `npx power-apps push` output → committed evidence file. The repo is the flight
  recorder, matching the Council's own receipt culture.
- **I7 — Preview posture.** Private Preview stack: dev tenant, single operator, halt on
  the forge die-condition (any second user before GA). No production affordances.
- **I8 — Public-repo hygiene.** This repo is public. Committable: app ids, environment
  URLs (already public in existing evidence), pin manifests, receipts. NEVER
  committable: client secrets, tokens, certificates (Wrap flow is public-client — if
  any generated artifact contains a secret, it is gitignored and its existence recorded
  instead). A pre-commit scan step in the apply kit enforces this.

## 3. Track M — mobile app (`apps/council-mobile/`)

| Layer | Choice | Notes |
|---|---|---|
| Shell | Expo Router per scaffold | scaffold-owned; not customized in MVP |
| UI | Tamagui (baked into native-host) | queue list, item detail, brief reader |
| Data read | TanStack Query over the native-host Dataverse client | **view-driven**: screens render the columns the SAVED VIEWS define (fetched via the SDK's view/savedQuery metadata when available; else a generated `view-columns.json` emitted from the ALM unpack by the docs renderer's parser — single source, no hand-typed column lists) |
| Data write | one `mutations.ts` module | approve/decline only; implements I1 (receipt-first ordering, see §5); no other write paths exist in MVP |
| Auth | `-native-auth` Wrap registration | token lifecycle entirely SDK-owned; no custom token storage (I3) |
| State | server-state only via Query | no offline cache layer in MVP (NA-NFR3) |

Screens (MVP): `QueueScreen` ("Needs Human Approval" + "Proposed Work Items" toggle),
`ItemScreen` (fields + rationale + Approve/Decline), `BriefScreen` (read-only).

## 4. Track C — code app (desktop curation)

Same invariants, smaller surface: scaffold via code-apps plugin; one curation surface in
MVP (Knowledge rail: memory candidates → approved instructions promotion flow, the
worst model-driven fit). Sequenced strictly AFTER Track M's T4 (first data read) proves
the data path, so Track C reuses a proven client configuration.

## 5. Write path (the only one)

```
tap Approve/Decline
  → mutations.approveOrDecline(workItem, decision, rationale)
      1. upsert com_councilreceipt  id = CR-<wi-id>-<TARGET-STATE>   (receipt-first)
      2. update com_councilworkitem state → target state
      3. invalidate Query caches (queue + item)
```

Receipt-first ordering: a crash between 1 and 2 leaves an orphan receipt naming an
intended transition — detectable and reconcilable (the reconciliation query is part of
story 6.3's acceptance) — never a state change without its receipt. Both operations use
deterministic natural IDs (I1), so retry of either step is idempotent. If tenant
evidence at T5 shows `ExecuteTransaction` is available to the SDK client, 1+2 collapse
into one transaction and the orphan case disappears; the receipt-first contract is the
portable fallback. **Decline in MVP maps to the demo-proven `held` state with a decline
rationale field on the receipt — introducing a new terminal state would violate I2** (a
`declined` choice value is a schema change → exits to normal planning if wanted).

## 6. Sequencing dependency (found by adversarial review — A1)

Epic-2's formal stories (2-3 receipt-backed changes, 2-4 idempotent mutations) are
`backlog`. Story 6.3 does NOT wait: it implements against the **demo-proven contract**
(state-transition demo, 12 receipts, deterministic IDs) and records that choice in its
receipt. When epic-2 lands its formal implementation, 6.3's mutation module conforms or
is refactored to the formal contract — that reconciliation is an explicit epic-2
acceptance item, not a silent drift. The alternative (block 6.3 on epic-2) was
rejected: it makes the phone surface hostage to backlog Doug hasn't scheduled.

## 7. Deployment / ALM

Dev environment only. Track M: Metro dev server + QR preview (Developer app) for the
whole MVP; `npx power-apps push` when the flow supports mobile assets — each push's
output committed (I6). Track C: `npx power-apps push` per deploy. Solution packaging of
Mobile App assets: WATCHED, adopted only when the plugin flow emits it natively.
Registration inventory lives in the 5-3 evidence record (NA-NFR4).

## 8. What this architecture refuses to decide now

Offline sync design (packages exist, flows don't — revisit at GA) · Android · push
notifications · any Track C surface beyond the first · production distribution. Each
gets its own gauntlet run or epic-6 extension when reality (GA, Android runtime,
second user) changes.
