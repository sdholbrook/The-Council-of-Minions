# Story 3.1: Create a Minion Brief Snapshot

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/minion-brief-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/minion-brief-slice.json;_bmad-output/implementation-artifacts/minion-brief-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/minion-brief-slice.json;_bmad-output/implementation-artifacts/minion-brief-slice-validate.ps1 -->

You are implementing one story in The-Council-of-Minions — a Dataverse-backed
work-item governance system built contract-first: each story ships a story-keyed
JSON evidence slice + a hardened PowerShell validator over it, proving the
semantics locally with NO live tenant writes. Your working directory IS a git
worktree of the repo — edit in place, leave everything uncommitted, never run
git commit/push/add. You own ONLY the two files named in ringer-owned.

## The repo pattern (READ these first — they are the law)

- `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json` —
  the authoritative vocabulary: table/field names, receipt verbs, state groups,
  actor types. Every field/verb/state you emit MUST exist in this manifest.
- `_bmad-output/implementation-artifacts/source-drift-supersession-slice.json`
  and `...-slice-validate.ps1` (story 1-5) — the gold-standard slice + validator
  pair. Mirror its structure and hardening exactly: story-keyed slice with
  declared guards (`receiptsAreLocalContractEvidenceOnly: true`, no-live-write
  guards), wrapped JSON loads, TryParse numeric checks, strict booleans,
  cross-slice ID-collision tripwires against the sibling slices (1-1..1-5),
  ISO 8601 timestamps, `$PSScriptRoot`-relative paths, a final
  `<NAME>_SLICE_VALIDATE_OK` success token, issue list + exit 1 on any failure.
- Sibling slices for cross-checks: `manual-source-record-slice.json`,
  `outlook-source-reference-slice.json`, `proposed-work-item-extraction-slice.json`,
  `zero-multi-item-extraction-slice.json` (existing CWI-*/CSR-*/CR-* ids — your
  new ids must not collide).

## Hard rules (all stories)

- Local contract evidence ONLY: no live Dataverse mutation anywhere in the
  slice; every would-be live write appears as a deferred entry naming its
  receipt gate.
- Do NOT edit `council-mvp-local-validate.ps1` — suite wiring is the
  integrator's job after review.
- IDs: new `CWI-LOCAL-*` / `CR-LOCAL-*` / `CSR-*` ids, unique across ALL slices.
- Every receipt carries the full manifest-required field set; receipts are
  append-only (corrections = new receipts, never edits).
- An `acceptanceMapping` section maps every AC of this story to the slice
  evidence that proves it.
- HOW TO RUN your validator:
  `export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/<your-validator>.ps1`
  Exit 0 with the OK token = pass. The executed acceptance check runs exactly this.

## Story goal (FR11)

A Minion Brief snapshot summarizes the queue as a PROJECTION — never the source
of truth, never silently rewritten.

## Slice must prove

1. One Brief snapshot generated from the epic-2 queue state (reference real
   CWI-*/CR-* ids from the epic-2 slices) with ALL eight sections: priority
   work, decisions needed, delegations ready, risks if ignored, blockers,
   recent receipts, memory candidates, and a projection disclaimer
   (`isProjection: true`, `sourceOfTruth: "work-items+receipts"`).
2. A queue-change scenario: an underlying Work Item changes AFTER the snapshot
   → the original Brief is untouched (guard `briefsAreImmutableSnapshots:
   true`) and a NEW snapshot (or refresh-evidence receipt) exists referencing
   the change.
3. Snapshot creation receipt-backed (manifest verbs).

## Validator must assert

All eight sections present and non-empty-or-declared; every referenced
CWI-/CR- id resolves in the epic-2 sibling slices; the two snapshots differ
where the change dictates and the original is byte-stable (hash recorded in
slice + rechecked); projection guards strict-bool true; receipts complete;
cross-slice id uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/minion-brief-slice.json` (storyKey: `3-1-create-a-minion-brief-snapshot`)
- `_bmad-output/implementation-artifacts/minion-brief-slice-validate.ps1` — prints
  `MINION_BRIEF_SLICE_VALIDATE_OK` and exits 0 on success; lists every issue and exits 1 otherwise. A
  validator that cannot fail is a defect: your reviewers hardened epic 2 for
  exactly dead tripwires, self-asserting booleans, and hardcoded coverage —
  do not ship those. Epic-2 hardened validators are the pattern to mirror.
