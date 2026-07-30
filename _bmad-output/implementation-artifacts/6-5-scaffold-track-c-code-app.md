---
baseline_commit: 7d6ff79
---

# Story 6.5: Scaffold Track C (Code App, Desktop Curation)

Status: ready-for-dev
Gates: depends on 6.3 + 6.4 (proven data + read-only patterns). Home-machine + tenant
execution for scaffold and push.

<!-- Staged via Meridian council-staging 2026-07-28 (gauntlet stage 6). -->
<!-- ringer-check: node -e "const p=require('./apps/council-desktop/package.json'); if(!p.dependencies||!p.dependencies['@microsoft/power-apps']) throw new Error('missing @microsoft/power-apps'); console.log('track-c-scaffold-present')" -->
<!-- ringer-owned: apps/council-desktop/**; _bmad-output/implementation-artifacts/native-app-evidence/track-c-push-receipt.md -->
<!-- ringer-expect: apps/council-desktop/package.json; _bmad-output/implementation-artifacts/native-app-evidence/track-c-push-receipt.md -->

Lane: native — scaffold + curation surface judgment; the dependency-presence check is
the mechanical residue.

## Story

As Doug,
I want a pro-code desktop surface for the worst model-driven fit,
so that curation flows live in reviewable code.

## Acceptance Criteria

1. Given Track M's proven client configuration, when the code-apps plugin scaffolds
   `apps/council-desktop/`, then it reuses the same environment binding and pin
   discipline (PINS entry added; NA-FR6, arch §4).
2. Given the curation surface, when the memory-candidate → approved-instruction
   promotion flow renders, then any write it performs follows I1 receipts — promotion
   without a receipt fails the story (epic-4 4-4 alignment).
3. Given a working surface, when `npx power-apps push` deploys it, then the push
   output is committed as `track-c-push-receipt.md` (NA-FR9).

## Tasks / Subtasks

- [ ] Scaffold via the code-apps plugin; record gate answers (same file pattern as
      6.2).
- [ ] Implement the promotion curation surface on view-driven columns; wire I1
      receipt discipline for the promotion write.
- [ ] Push; commit the receipt; add Track C versions to PINS.md.

## Dev Notes

Arch §4: sequenced after Track M so the client configuration is proven once. One
surface only in MVP — further Track C surfaces are new stories, not scope creep here
(arch §8).
