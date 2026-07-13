# Story 2.5: Apply Safe Auto-Creation Policy

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/auto-creation-policy-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/auto-creation-policy-slice.json;_bmad-output/implementation-artifacts/auto-creation-policy-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/auto-creation-policy-slice.json;_bmad-output/implementation-artifacts/auto-creation-policy-slice-validate.ps1 -->

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

## Story goal (FR14, FR15, FR13)

Only low-risk `follow_up` / `meeting_action` items auto-create, under explicit
confidence thresholds; everything else stays proposed-only with visible
rationale.

## Slice must prove

1. Two auto-created Work Items (one follow_up, one meeting_action), each
   recording the evaluated thresholds — source identification, type
   classification, low-risk classification, owner confidence (where needed),
   next-action confidence — with numeric values in [0,1] meeting declared
   policy minimums, plus a guard that auto-creation remains separate from
   approved external action.
2. Two denied candidates: one failing a confidence threshold, one failing the
   risk-class check — both remaining proposed-only with policy rationale
   visible in the Work Item or its Receipt.
3. Creation/denial events receipt-backed with policy flags.

## Validator must assert

Threshold values TryParse in [0,1] and >= declared minimums for auto-created
items; denied candidates carry non-empty policy rationale and stay
proposed-only; only the two allowed types auto-create; no-external-action
guards strict-bool true; receipts complete; cross-slice id uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/auto-creation-policy-slice.json` — the slice
  (storyKey: `2-5-apply-safe-auto-creation-policy`).
- `_bmad-output/implementation-artifacts/auto-creation-policy-slice-validate.ps1` — the
  validator; prints `AUTO_CREATION_POLICY_SLICE_VALIDATE_OK` and exits 0 on success, lists every issue and
  exits 1 otherwise. A validator that cannot fail is a defect.
