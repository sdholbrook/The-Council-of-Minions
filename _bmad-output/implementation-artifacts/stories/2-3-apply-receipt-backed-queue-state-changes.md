# Story 2.3: Apply Receipt-Backed Queue State Changes

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/receipt-backed-state-changes-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/receipt-backed-state-changes-slice.json;_bmad-output/implementation-artifacts/receipt-backed-state-changes-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/receipt-backed-state-changes-slice.json;_bmad-output/implementation-artifacts/receipt-backed-state-changes-slice-validate.ps1 -->

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

## Story goal (FR9, FR16, FR17, NFR6)

Every meaningful state change is backed by an append-only Receipt; corrections
are new Receipts.

## Slice must prove

1. One Work Item walked through proposed → approved → in-review → completed,
   and one through proposed → blocked → resumed → failed (or held variant) —
   EVERY transition backed by a receipt carrying: verb, actor type, actor id,
   authority basis, occurred-at, before state, after state, evidence
   references, rationale, result, policy flags.
2. A correction scenario: an erroneous receipt followed by a NEW correction
   receipt referencing it — the original visibly unedited (guard:
   `priorReceiptsUnchanged: true`).
3. Verbs drawn ONLY from the manifest receipt-verb vocabulary; occurred-at
   strictly ordered along each transition chain.

## Validator must assert

Chain completeness (no transition without a receipt; before/after states form
an unbroken chain); full field set per receipt; verb vocabulary membership;
timestamp ordering; correction pattern (new receipt + untouched original);
append-only guards; cross-slice id uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/receipt-backed-state-changes-slice.json` — the slice
  (storyKey: `2-3-apply-receipt-backed-queue-state-changes`).
- `_bmad-output/implementation-artifacts/receipt-backed-state-changes-slice-validate.ps1` — the
  validator; prints `RECEIPT_BACKED_STATE_CHANGES_SLICE_VALIDATE_OK` and exits 0 on success, lists every issue and
  exits 1 otherwise. A validator that cannot fail is a defect.
