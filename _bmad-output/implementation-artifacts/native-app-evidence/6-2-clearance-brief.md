# Clearance brief — story 6-2 (Scaffold Track M) · tower handoff

*Committed by Meridian per ADR-0012 clause 3 (warm handoff = the clearance
record). This is also, knowingly, the fleet's first EXPLICIT handoff packet —
the D1 engine will generate briefs like this; this one is hand-made.*

## The packet

- **WHY (meaning ref):** Council program → operator workflow on Doug's phone
  (PRD council-native-app; J1 receipt round-trip is the success criterion).
- **WHAT-FOR-WHOM:** Doug approves/declines queue items from an iPhone against
  the EXISTING `com_council*` tables — zero schema changes.
- **DONE-MEANS:** story 6-2 ACs 1–5; gates T2 (Wrap/Entra registration record),
  T3 (Developer-app sign-in receipt), T4 (live "Needs Human Approval" rows on
  device). **K1 HARD STOP:** if `/create-mobile-app`'s data-model gate cannot
  bind to existing tables and insists on creating any, STOP, record the
  constraint verbatim in `gate-answers-create-mobile-app.md`, escalate to Doug
  (AC2 — a parallel table set is a hard fail, not a workaround).
- **FROM (provenance):** T1 GREEN `aed9b2d` (toolchain pinned —
  `apps/council-mobile/PINS.md`); pac profile `council` →
  **Doug Holbrook's Environment** `https://sdhdev.crm.dynamics.com/`
  (org `0c0fa4db-8614-ef11-9f83-000d3a342d36`), verified 2026-07-31;
  `CouncilOfMinionsMVP 0.1.0.0` present.
- **RETURN (evidence address):** `native-app-evidence/T2-registration.md`,
  `T3-device.md`, `T4-first-read.md`, `gate-answers-create-mobile-app.md`;
  sprint key `6-2-scaffold-track-m-against-existing-tables` flips on done.

## Venue (ADR-0012)

Run in a session rooted HERE (`The-Council-of-Minions`) — `/create-mobile-app`
writes into this repo and its write guard is correct to demand that. The tower
stays available for routing questions; it does not fly this plane.

## Binding target (AC2) — the 14 existing tables

com_council, com_councilapprovedinstruction, com_councilbrief,
com_councilgraphedge, com_councilgraphentity, com_councilmemorycandidate,
com_councilminion, com_councilplatformevaluation, com_councilreceipt,
com_councilreceiptsource, com_councilskill, com_councilsourcerecord,
com_counciltenantevidence, com_councilworkitem (+ com_councilworkitemsource).

## Preflight facts (so the session starts warm, not cold)

- Node v22.23.1 · npm 10.9.8 · pac 2.9.3 · plugins mobile-app 0.2.0 /
  code-apps-preview 1.1.0 @ marketplace c8455ac (pins: PINS.md).
- `pac org who` should show sdhdev BEFORE launching the flow; if the default
  environment drifted, `pac env select --environment https://sdhdev.crm.dynamics.com`.
- View columns: prefer SDK view metadata; fallback generator = the ALM unpack
  parser (`tools/docs-render/render_screens.py` pattern) → `view-columns.json`
  (AC5 — hand-typed column lists fail review).
- Receiver test (engine law): if you cannot restate this brief's WHY in one
  sentence without asking, the handoff failed — say so before scaffolding.
