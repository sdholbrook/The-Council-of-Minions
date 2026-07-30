---
baseline_commit: 7d6ff79
---

# Story 6.1: Pin and Verify the Code-First Toolchain

Status: ready-for-dev
Gates: T1 (VERIFY IN TENANT ledger, PRD §7) must go green INSIDE this story; no
scaffold story starts until it does. Home-machine execution — container sessions stop
above T1.

<!-- Staged via Meridian council-staging 2026-07-28 (gauntlet stage 6). -->
<!-- ringer-check: test -s apps/council-mobile/PINS.md && grep -q "@microsoft/power-apps-native-host" apps/council-mobile/PINS.md && grep -q "power-platform-skills" apps/council-mobile/PINS.md -->
<!-- ringer-owned: apps/council-mobile/PINS.md; _bmad-output/implementation-artifacts/native-app-evidence/T1-toolchain.md -->
<!-- ringer-expect: apps/council-mobile/PINS.md; _bmad-output/implementation-artifacts/native-app-evidence/T1-toolchain.md -->

Lane: native — tenant/toolchain-coupled judgment (plugin install into the working
environment); the pin-file check above is the mechanical residue a ringer can verify.

## Story

As Doug's build system,
I want the plugin marketplace, plugins, and every package version pinned and verified,
so that preview churn becomes deliberate rebases instead of silent drift.

## Acceptance Criteria

1. Given a working environment with Node 22 LTS and npm 10+, when the
   power-platform-skills marketplace and the mobile-apps + code-apps plugins are
   installed, then the install transcript is committed as
   `native-app-evidence/T1-toolchain.md` (tenant gate T1, NA-FR8).
2. Given the toolchain is installed, when `apps/council-mobile/PINS.md` is written,
   then it records: marketplace version/commit, both plugin versions, and exact
   versions for `@microsoft/power-apps-native-host`, `-auth`, `-common`,
   `@microsoft/power-apps`, Expo SDK, React Native, React (NA-NFR2; arch I4 + A7).
3. Given PINS.md exists, when any of these versions later changes, then the change is
   a deliberate commit citing the manifest diff — this rule is stated in PINS.md
   itself.

## Tasks / Subtasks

- [ ] Verify Node 22 LTS + npm 10+ (`node -v`, `npm -v`) — record in T1 evidence.
- [ ] Install power-platform-skills marketplace; install mobile-apps + code-apps
      plugins; capture the transcript.
- [ ] Author `apps/council-mobile/PINS.md` (versions + the rebase rule + "no floating
      ranges" statement).
- [ ] Commit both files; T1 row flips green in the PRD's VERIFY IN TENANT ledger copy
      inside the evidence file.

## Dev Notes

Architecture I3/I4; PRD NA-NFR2 §6 for the exact version universe verified 2026-07-28
(native-host 0.2.25-era pins: Expo 55, RN 0.83.x, React 19.2). `@microsoft/*` scope
only — unscoped npm lookalikes are squats.
