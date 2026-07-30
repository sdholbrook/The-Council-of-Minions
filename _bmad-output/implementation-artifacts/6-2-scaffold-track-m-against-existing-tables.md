---
baseline_commit: 7d6ff79
---

# Story 6.2: Scaffold Track M Against Existing Tables

Status: ready-for-dev
Gates: depends on 6.1 (T1 green); flips T2 (Wrap/Entra registration), T3 (Developer
app sign-in), T4 (first live read) inside this story. Home-machine + tenant execution.

<!-- Staged via Meridian council-staging 2026-07-28 (gauntlet stage 6). -->
<!-- ringer-check: node -e "const p=require('./apps/council-mobile/package.json'); const fs=require('fs'); const pins=fs.readFileSync('apps/council-mobile/PINS.md','utf8'); for (const d of ['@microsoft/power-apps-native-host']) { if(!p.dependencies||!p.dependencies[d]) throw new Error('missing dep '+d); if(!pins.includes(p.dependencies[d].replace(/^[^0-9]*/,''))) throw new Error('dep '+d+' version not in PINS.md'); } console.log('scaffold-pins-consistent')" -->
<!-- ringer-owned: apps/council-mobile/** (EXCEPT src/mutations/**, src/screens/queue/**, src/screens/item/**, src/screens/brief/** — owned by 6.3/6.4); _bmad-output/implementation-artifacts/native-app-evidence/T2-registration.md; native-app-evidence/T3-device.md; native-app-evidence/T4-first-read.md; native-app-evidence/gate-answers-create-mobile-app.md -->
<!-- ringer-expect: apps/council-mobile/package.json; _bmad-output/implementation-artifacts/native-app-evidence/gate-answers-create-mobile-app.md; _bmad-output/implementation-artifacts/native-app-evidence/T4-first-read.md -->

Lane: native — interactive tenant-bound scaffold flow with judgment at every approval
gate; the package/PINS consistency check is the mechanical residue.

## Story

As Doug,
I want the mobile app scaffolded by `/create-mobile-app` bound to the EXISTING tables,
so that the phone surface exists without a single schema change.

## Acceptance Criteria

1. Given T1–T3 are green, when `/create-mobile-app` runs, then EVERY approval-gate
   answer (data model, native capabilities, connectors, screens) is recorded verbatim
   in `native-app-evidence/gate-answers-create-mobile-app.md` (NA-FR7).
2. **Given the flow's data-model gate, when it proposes table creation, then the story
   binds to existing `com_council*` tables only — and if the flow cannot bind to
   existing tables, the story STOPS, records the constraint in the gate-answers file,
   and escalates to Doug (readiness known-unknown K1; NA-FR5, arch I2). Creating a
   duplicate/parallel table set is a hard fail, not a workaround.**
3. Given the scaffold exists, when the Wrap-generated Entra registration is created,
   then its app id + registration record land in `T2-registration.md` and the 5-3
   evidence record's DLP inventory (NA-NFR4).
4. Given Metro + QR preview, when the Developer app opens the scaffold on Doug's
   iPhone, then "Needs Human Approval" renders live rows (T4 evidence: screenshot +
   row count; NA-FR1).
5. Given screens render view data, when column sets are defined, then they come from
   SDK view metadata or generated `view-columns.json` — hand-typed column lists fail
   review (arch A4).

## Tasks / Subtasks

- [ ] Re-verify T1; sign into the Developer app (T3 evidence: environment shown).
- [ ] Run `/create-mobile-app`; capture gate answers; enforce AC2 at the data-model
      gate.
- [ ] Inventory the Wrap registration (T2).
- [ ] Generate `view-columns.json` from the ALM unpack (same parser as
      `tools/docs-render/render_screens.py`) or wire SDK view metadata; commit the
      choice + reason.
- [ ] Prove T4 (live read on device); commit evidence.

## Dev Notes

Arch §3 (layer table), I2/I3; PRD §7 T2–T4. Scaffold customization stays ABOVE the
scaffold line (I3): screens/mappers/mutations only — 6.3/6.4 own those paths, so this
story leaves `src/mutations/**` and the three screen dirs untouched (ownership is
enforced by the ringer boundary).
