# Story 5.6: Manage Phase 2 Knowledge and Analytics Projections

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/phase2-projections-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/phase2-projections-slice.json;_bmad-output/implementation-artifacts/phase2-projections-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/phase2-projections-slice.json;_bmad-output/implementation-artifacts/phase2-projections-slice-validate.ps1 -->

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

## Story goal (FR22, FR27, FR28, AR5, AR6, AR11)

Fabric/Copilot-Studio/analytics projections stay DEFERRED until MVP contracts
stabilize; graph/ontology expansion never owns workflow state.

## Slice must prove

1. Three Phase-2 projection plans (Fabric knowledge, Copilot Studio surface,
   analytics), each marked `phase: 2`, `deferredUntil:
   "mvp-contracts-stable"`, with the triggering stability criteria named
   (which MVP contracts must hold) and `ownsWorkflowState: false`.
2. A guard scenario: a premature-activation attempt yields a policy-denial
   receipt; the projection remains deferred.
3. Cross-reference to the 4-5 semantic-contract projection slice (planes are
   projections only) — referenced, not duplicated.

## Validator must assert

All plans deferred with non-empty stability criteria; ownsWorkflowState
strictly false; the denial receipt binds to a plan id; the 4-5 cross-reference
resolves when that slice is present; minted-vs-referenced ids; cross-slice
uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/phase2-projections-slice.json` (storyKey: `5-6-manage-phase-2-knowledge-and-analytics-projections`)
- `_bmad-output/implementation-artifacts/phase2-projections-slice-validate.ps1` — prints `PHASE2_PROJECTIONS_SLICE_VALIDATE_OK`,
  exits 0 on success; lists every issue and exits 1 otherwise. Hardening bar
  (the review swarm's kill list): no self-asserted booleans standing in for
  proof, no hardcoded-id binding rules (general rules over collections), LIVE
  cross-slice id harvests from $PSScriptRoot distinguishing MINTED ids (must
  be unique) from REFERENCED ids (must resolve), no conditional/skippable
  mandatory checks, coverage derived not counted. Verify a corrupted slice
  copy FAILS before finishing.
