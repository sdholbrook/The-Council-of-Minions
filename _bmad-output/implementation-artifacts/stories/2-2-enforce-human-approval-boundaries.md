# Story 2.2: Enforce Human Approval Boundaries

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/approval-boundaries-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/approval-boundaries-slice.json;_bmad-output/implementation-artifacts/approval-boundaries-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/approval-boundaries-slice.json;_bmad-output/implementation-artifacts/approval-boundaries-slice-validate.ps1 -->

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

## Story goal (FR13, FR15)

High-risk work stays proposed until explicitly approved; approvals authorize
only their declared scope.

## Slice must prove

1. One candidate Work Item per high-risk class — decision, delegation, risk,
   sensitive, outbound, memory promotion, skill authority expansion,
   tenant-affecting — each classified and marked `approvalRequired: true`,
   each with a guard proving no external action occurred pre-approval.
2. One approved Work Item whose approval record declares an explicit scope
   (the authorized state transition/action), plus a second desired action on
   the same item shown as requiring a SEPARATE approval (deferred entry).
3. Approval events receipt-backed (CR-LOCAL-*, manifest verbs, actor =
   human/Doug, authority basis).

## Validator must assert

All eight risk classes present and approvalRequired; strict-bool guards on
no-pre-approval-external-action; approval scope fields non-empty and the
out-of-scope action deferred with rationale; receipts complete + append-only.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/approval-boundaries-slice.json` — the slice
  (storyKey: `2-2-enforce-human-approval-boundaries`).
- `_bmad-output/implementation-artifacts/approval-boundaries-slice-validate.ps1` — the
  validator; prints `APPROVAL_BOUNDARIES_SLICE_VALIDATE_OK` and exits 0 on success, lists every issue and
  exits 1 otherwise. A validator that cannot fail is a defect.
