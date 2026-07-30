---
baseline_commit: 7d6ff79
---

# Story 6.3: Approve/Decline Slice (Mobile)

Status: ready-for-dev
Gates: depends on 6.2 (T4 green); flips T5 (receipt-backed write) inside this story.
Home-machine + tenant execution for the live proof; the mutation-contract check runs
offline.

<!-- Staged via Meridian council-staging 2026-07-28 (gauntlet stage 6). -->
<!-- ringer-check: node apps/council-mobile/scripts/check-mutations-contract.mjs -->
<!-- ringer-owned: apps/council-mobile/src/mutations/**; apps/council-mobile/src/screens/queue/**; apps/council-mobile/src/screens/item/**; apps/council-mobile/scripts/check-mutations-contract.mjs; _bmad-output/implementation-artifacts/native-app-evidence/T5-receipt-write.md -->
<!-- ringer-expect: apps/council-mobile/src/mutations/index.ts; apps/council-mobile/scripts/check-mutations-contract.mjs; _bmad-output/implementation-artifacts/native-app-evidence/T5-receipt-write.md -->

Lane: native — the write path is the product's riskiest judgment surface; the
deterministic-ID contract check (`check-mutations-contract.mjs`, authored IN this
story) is the mechanical residue a ringer can re-run forever.

## Story

As Doug,
I want to approve or decline a proposed work item from my phone with a receipt,
so that the daily decision loop is truly mobile.

## Acceptance Criteria

1. Given a work item in "Needs Human Approval", when Approve or Decline is tapped,
   then `mutations.approveOrDecline()` writes receipt-FIRST with deterministic IDs
   (`CR-<wi-natural-id>-<TARGET-STATE>` — the state-transition-demo basis), then the
   state change, both idempotent on natural keys (NA-FR2; arch I1/§5, A2/A3).
2. Given Decline, when the receipt is written, then the target state is `held` with a
   decline rationale on the receipt — introducing a new state value is out of scope
   and fails this story (arch A5; I2).
3. Given the two-write path, when `check-mutations-contract.mjs` runs (offline unit
   check over the mutation module), then it proves: deterministic ID derivation,
   receipt-before-state ordering, retry idempotency, and the `held` decline mapping.
4. Given a possible crash between writes, when the reconciliation query runs, then
   orphan receipts (receipt naming a transition whose state didn't land) are listed;
   clean run = empty list (arch A3).
5. Given T5, when the same transition is made in the model-driven app, then the
   receipt shapes are identical — evidence in `T5-receipt-write.md` shows both rows
   side by side (PRD success criterion 1).

## Tasks / Subtasks

- [ ] Implement `src/mutations/` per arch §5 (receipt-first, natural keys, Query cache
      invalidation); check tenant evidence for `ExecuteTransaction` availability —
      collapse to one transaction if proven, keep receipt-first as portable fallback.
- [ ] Implement QueueScreen ("Needs Human Approval" + "Proposed Work Items" toggle)
      and ItemScreen (fields + rationale + Approve/Decline) on view-driven columns.
- [ ] Author `scripts/check-mutations-contract.mjs` (AC3) — no tenant needed.
- [ ] Author + run the orphan-receipt reconciliation query; wire it into the check
      where offline-testable.
- [ ] Prove T5 live; commit side-by-side receipt evidence.

## Dev Notes

Epic-2 stories 2-3/2-4 are `backlog`: this story implements against the demo-proven
contract (`state-transition-demo-evidence.json`, 12 receipts, deterministic IDs) and
records that choice; when epic-2 formalizes the contract, reconciliation is an epic-2
acceptance item — divergence is never silent (arch §6, adversarial A1).
