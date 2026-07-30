---
baseline_commit: 7d6ff79
---

# Story 6.4: Minion Brief Read Surface (Mobile)

Status: ready-for-dev
Gates: depends on 6.2 (T4 green). Parallel-safe with 6.3 — ownership disjoint by path.

<!-- Staged via Meridian council-staging 2026-07-28 (gauntlet stage 6). -->
<!-- ringer-check: node apps/council-mobile/scripts/check-brief-readonly.mjs -->
<!-- ringer-owned: apps/council-mobile/src/screens/brief/**; apps/council-mobile/scripts/check-brief-readonly.mjs -->
<!-- ringer-expect: apps/council-mobile/src/screens/brief/BriefScreen.tsx; apps/council-mobile/scripts/check-brief-readonly.mjs -->

Lane: native for the live render proof; the read-only guarantee is MECHANICAL — the
check statically asserts no `src/mutations` import and no write verbs in the brief
screen dir, so a ringer can hold the boundary forever.

## Story

As Doug,
I want the active Minion Brief readable on my phone,
so that the standing picture travels with me.

## Acceptance Criteria

1. Given the T4-proven scaffold, when BriefScreen renders, then it shows the current
   "Active Council Briefs" record's content live (NA-FR3), read-only.
2. Given the read-only promise, when `check-brief-readonly.mjs` runs, then it proves
   `src/screens/brief/**` imports nothing from `src/mutations/**` and calls no
   create/update/delete SDK verbs — a violation fails the story mechanically.
3. Given no active brief exists, when BriefScreen renders, then it shows an explicit
   empty state naming where briefs come from (epic-3 flows) — never a crash or spinner
   loop.

## Tasks / Subtasks

- [ ] Implement `src/screens/brief/BriefScreen.tsx` on view-driven columns
      ("Active Council Briefs").
- [ ] Author `scripts/check-brief-readonly.mjs` (AC2 static assertions).
- [ ] Handle the empty state (AC3); commit device render evidence alongside 6.2's T4
      file pattern.

## Dev Notes

Arch §3 screens row. Deliberately the smallest story in the epic — it exists to prove
a second screen lands cheaply on the proven data path, and to pin the read-only
boundary mechanically before Track C copies the pattern.
