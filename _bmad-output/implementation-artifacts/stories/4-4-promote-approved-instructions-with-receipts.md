# Story 4.4: Promote Approved Instructions With Receipts

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/approved-instructions-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/approved-instructions-slice.json;_bmad-output/implementation-artifacts/approved-instructions-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/approved-instructions-slice.json;_bmad-output/implementation-artifacts/approved-instructions-slice-validate.ps1 -->

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

## Story goal (FR23, FR16, FR17, NFR11)

Promotion to Approved Instruction requires explicit evidence; supersession
never overwrites.

## Slice must prove

1. One promotion: an Approved Instruction (CAI-LOCAL-*) with instruction text,
   scope, source candidate ref (a 4-3 CMC id — coordinate by referencing the
   4-3 slice's declared ids; if absent use a self-contained candidate embedded
   in THIS slice and note it), approval receipt (actor=human/Doug, authority
   basis, rationale, source evidence), effective date, status=active.
2. One supersession: a replacement instruction approved via a NEW receipt; the
   old instruction marked superseded with a link to the supersession receipt —
   its original text/receipt untouched (`priorInstructionUnchanged: true`).

## Validator must assert

Instruction field completeness incl. ISO-8601 effective date; approval receipt
full field set; supersession chain (old.status=superseded, link resolves, new
receipt distinct); prior-unchanged guard; status vocabulary; cross-slice id
uniqueness. NOTE: do not hard-depend on the 4-3 slice existing — cross-check
its ids only when the file is present (parallel development).

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/approved-instructions-slice.json` (storyKey: `4-4-promote-approved-instructions-with-receipts`)
- `_bmad-output/implementation-artifacts/approved-instructions-slice-validate.ps1` — prints
  `APPROVED_INSTRUCTIONS_SLICE_VALIDATE_OK` and exits 0 on success; lists every issue and exits 1 otherwise.
  Validator-laziness is the review swarm's #1 kill: no conditional/skippable
  checks, no hardcoded ids as binding rules, live cross-slice harvests (mirror
  the epic-2/3 HARDENED validators), content deltas proven not self-asserted.
