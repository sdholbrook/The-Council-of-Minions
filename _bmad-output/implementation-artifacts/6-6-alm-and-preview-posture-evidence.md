---
baseline_commit: 7d6ff79
---

# Story 6.6: ALM and Preview-Posture Evidence

Status: ready-for-dev
Gates: depends on 6.1–6.5 receipts existing. Mostly mechanical; tenant reads only.

<!-- Staged via Meridian council-staging 2026-07-28 (gauntlet stage 6). -->
<!-- ringer-check: python3 -c "import json,glob,sys; fs=glob.glob('_bmad-output/implementation-artifacts/native-app-evidence/*'); assert fs, 'no evidence files'; [json.load(open(f,encoding='utf-8-sig')) for f in fs if f.endswith('.json')]; print('evidence-dir-valid', len(fs))" -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/native-app-evidence/alm-summary.md; _bmad-output/implementation-artifacts/5-3-evidence-operator-surface-code-first-2026-07-28.md -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/native-app-evidence/alm-summary.md -->

Lane: native for tenant reads (licensing state, registration list); evidence
validation is mechanical.

## Story

As the Council's governance layer,
I want the deployment story recorded honestly,
so that epic-5 discipline survives the new toolchain.

## Acceptance Criteria

1. Given stories 6.1–6.5 receipts, when `native-app-evidence/alm-summary.md` is
   written, then it consolidates: Entra registration inventory (app ids, created-by
   story), licensing state (Premium/PAYG/app-pass posture, NA-NFR6), every deploy
   receipt path, and the solution-packaging watch item (arch §7).
2. Given the 5-3 evidence record, when this story completes, then it gains an
   **OUTCOMES** section: which tenant gates held, which assumptions broke, what the
   preview stack actually cost (updates the FR28 record; NA-FR8).
3. Given the preview posture, when the halt condition (NA-NFR1) or Android/offline
   status changes upstream, then alm-summary.md names the re-evaluation trigger — the
   watch has an owner (Doug) and a check (next platform-evaluation pass).

## Tasks / Subtasks

- [ ] Consolidate evidence into `alm-summary.md` (AC1).
- [ ] Append OUTCOMES to the 5-3 record (AC2) — append-only; no rewriting of the
      pre-build evaluation.
- [ ] Record re-evaluation triggers (AC3).

## Dev Notes

This story is the epic's exit interview: it exists so that six months from now the
repo explains what the preview adventure cost and proved, without archaeology.
