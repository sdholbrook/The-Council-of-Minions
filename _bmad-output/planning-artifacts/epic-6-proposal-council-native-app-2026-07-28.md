# PROPOSAL — Epic 6: Council Native Operator Surface (Code-First)

**Status: PROPOSAL.** Not appended to `epics.md`, not in `sprint-status.yaml`. If Doug
approves the staged plan, this enters the repo through the gauntlet's normal stages 4–6
(PRD delta → architecture + adversarial review → epics/stories with ringer markers) —
this document is the shape he's approving, not a finished epic.

**Requirements grounding:** FR26 (Microsoft-first surfaces), FR27/NFR2 (native planes
before custom substrate — honored via the 5-3 evidence record), FR28 (evidence record
staged: `implementation-artifacts/5-3-evidence-operator-surface-code-first-2026-07-28.md`),
FR29 (every story below inherits `VERIFY IN TENANT` gates).

**Epic goal:** Doug's daily loop (triage → approve/decline → Minion Brief) native on his
phone, plus a pro-code desktop curation surface — both on the existing Dataverse MVP
schema, model-driven app retained as admin/fallback, everything Private-Preview-labeled.

## Proposed stories (sketches, dependency order)

### 6.1 Pin and verify the code-first toolchain
Install the power-platform-skills marketplace + mobile-apps/code-apps plugins; pin Node
22 LTS / npm 10+; record plugin + package versions (native-host 0.2.25 era) in a
toolchain manifest. **Gate:** tenant-gate rows 1–2 of the 5-3 evidence record green,
versions committed. *(Preview-churn defense: the manifest is the rebase baseline.)*

### 6.2 Scaffold Track M against existing tables
`/create-mobile-app` run with its four approval gates recorded as receipts (data model =
EXISTING tables only, native capabilities minimal, no new connectors, screens = queue /
item / brief); Wrap-generated Entra registration inventoried; QR preview reaches the
Developer app on Doug's iPhone with live Dataverse reads. **Gate:** tenant-gate rows 3–5
green; scaffold committed; zero schema drift proven (no new Dataverse objects).

### 6.3 Triage queue + approve/decline slice (mobile)
Epic-1 source-record queue rendered natively (TanStack Query reads); approve/decline
writes the SAME receipt-backed state changes epic-2 specifies (2-3/2-4 patterns:
idempotent mutation + receipt). **Gate:** round-trip demo evidence JSON, model-driven
app shows the same state (single source of truth proof).

### 6.4 Minion Brief read surface (mobile)
Epic-3 brief snapshot projected read-only to the phone. **Gate:** brief renders from
live data; no write path.

### 6.5 Scaffold Track C (Code App) for curation
Code-apps plugin scaffold; port the curation views that fight model-driven forms;
`npx power-apps push` to the dev environment. **Gate:** curation round-trip evidence;
push receipt committed.

### 6.6 ALM + preview-posture evidence
Record the deployment story honestly: push-based deploys, app registration inventory,
licensing state, solution-awareness watch item (platform Solutions accepting Mobile App
assets vs plugin flow's gap); update the 5-3 record with outcomes. **Gate:** evidence
file committed; epic-5 governance stories (5-4/5-5) cited, not bypassed.

## Explicit boundaries

- Stories 6.2+ do not start while the stack's "do not use in production" label matters
  to how Council is used (single-operator dev tenant today = acceptable).
- Any need for a new table/column/connector exits this epic and goes through the normal
  planning flow first.
- Android and offline are watch items, absent from every gate above.
