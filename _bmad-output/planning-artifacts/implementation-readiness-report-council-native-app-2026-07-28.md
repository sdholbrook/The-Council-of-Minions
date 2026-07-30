# Implementation Readiness Report — council-native-app (gauntlet stage 7)

**Verdict: READY-WITH-GATES.** Planning is complete and internally consistent; the
gates are tenant-bound preconditions (`VERIFY IN TENANT`, honestly not container
failures) that flip inside the stories that own them. Container sessions stop above
T1 — everything below the line is Doug's home machine + tenant.

## 1. Artifact chain (all exist, all validated)

| Stage | Artifact | Validation |
|---|---|---|
| 0–2 | intake / forge SURVIVE / product brief | structural, receipts in state.jsonl |
| 3 | PRFAQ skipped | intake opt-out receipt |
| 4 | PRD final (9 NA-FRs, 6 NA-NFRs, T1–T5) | non-vacuous numbering + cross-ref check |
| 5 | architecture I1–I8 + adversarial receipt (7 findings resolved) | cross-consistency check |
| 6 | epics addendum + stories 6-1..6-6 | this report §3 |

## 2. Requirement → story coverage (no orphans either direction)

- NA-FR1 → 6.2 (AC4) · NA-FR2 → 6.3 · NA-FR3 → 6.4 · NA-FR4 → out-of-MVP read
  surfaces documented in USING guide (intake read is model-driven today; PRD scope §5
  keeps phone intake read-only OUT — recorded, not dropped) · NA-FR5 → 6.2 (AC2 hard
  fail) · NA-FR6 → 6.5 · NA-FR7 → 6.2 (AC1) + 6.5 · NA-FR8 → 6.1/6.2/6.3/6.6 ·
  NA-FR9 → 6.5/6.6.
- NA-NFR1 → 6.6 (AC3 halt/watch) · NFR2 → 6.1 · NFR3 → arch §8 refusal ·
  NFR4 → 6.2 (AC3) · NFR5 → measured per milestone (6.2 T4 evidence) · NFR6 → 6.6.
- Invariants: I1→6.3, I2→6.2(AC2)+6.3(AC2), I3→6.1/6.2, I4→6.1, I5→every story's
  Gates line, I6→every evidence file, I7→6.6, I8→apply kit (C-e) + evidence rules.

## 3. Story quality gate (stage-6 contract)

- **Markers:** all six carry `ringer-check` / `ringer-owned` / `ringer-expect`.
- **Disjoint ownership:** `apps/` is absent at baseline `7d6ff79` (verified) —
  greenfield; 6.2 explicitly carves out 6.3/6.4's paths; 6.3 vs 6.4 disjoint by
  directory; 6.5 in `apps/council-desktop/`; 6.6 in evidence + the 5-3 record.
  No two stories own a common path.
- **Dependency order:** 6.1 → 6.2 → {6.3 ∥ 6.4} → 6.5 → 6.6 — encoded in each
  story's Gates line and the sprint snippet's comments.
- **Lanes:** all native (tenant/judgment-coupled) with the mechanical residue named
  per story — honest per reflex-orchestrate §3; nothing pretends to be
  ringer-dispatchable from a container.

## 4. Adversarial findings re-walk (stage-5 receipt promise)

A1 → 6.3 Dev Notes carries the demo-contract choice + epic-2 reconciliation ·
A2/A3 → 6.3 AC1/AC3/AC4 · A4 → 6.2 AC5 + 6.4 view-driven columns · A5 → 6.3 AC2
(decline=held, hard fail on new state) · A6 → I8 + apply-kit secret scan (C-e,
pending — the ONLY open planning item, owned by P-C7) · A7 → 6.1 AC2 (plugins in
PINS.md). All seven findings land in enforceable story text, not prose.

## 5. Known unknowns (named, owned, non-blocking to staging)

- **K1:** `/create-mobile-app` may insist on CREATING tables. Guard: 6.2 AC2 hard
  stop + escalation. If K1 bites, fallback path: scaffold with throwaway tables in a
  dev sandbox, then rebind data layer to existing tables — requires its own receipt
  and Doug's nod (recorded here so the option is pre-thought, not improvised).
- **K2:** SDK view-metadata availability. Fallback already specced: generated
  `view-columns.json` from the ALM unpack (6.2 AC5).
- **K3:** `ExecuteTransaction` availability to the SDK client. Portable receipt-first
  fallback is the contract either way (6.3).
- **K4:** live forms may be richer than the export (form-state audit in docs) — no
  epic-6 impact; re-export remedy documented in the USING guide.

## 6. What blocks a `ready` → `in-progress` flip

Nothing in planning. Sequence for Doug: apply kit lands this tree on Council main →
run 6.1 (T1) → 6.2 (T2–T4) → then the phone has the queue. First hour home, per the
apply kit's runbook.
