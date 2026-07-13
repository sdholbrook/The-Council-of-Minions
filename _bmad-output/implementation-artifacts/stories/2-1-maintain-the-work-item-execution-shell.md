# Story 2.1: Maintain the Work Item Execution Shell

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/work-item-execution-shell-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/work-item-execution-shell-slice.json;_bmad-output/implementation-artifacts/work-item-execution-shell-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/work-item-execution-shell-slice.json;_bmad-output/implementation-artifacts/work-item-execution-shell-slice-validate.ps1 -->

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

## Story goal (FR8, FR9, FR10, NFR12)

Each Work Item is a canonical execution shell independent of any Microsoft
source system, and the Council Queue exposes all seven state groups.

## Slice must prove

1. Work Items (at least 3, covering different types) each carrying: stable
   Council identity (`CWI-LOCAL-*` primary id), type, summary, state group,
   owner candidate, approved owner (where known), source references (to
   existing CSR-* ids from sibling slices), rationale, approval requirement,
   semantic contract version, and a creation receipt reference (CR-LOCAL-*).
2. Explicit proof that NO Microsoft platform identifier (GUID, activity id,
   message id) is used as primary product identity — platform ids may appear
   only inside source references.
3. A `queueView` section exposing ALL seven state groups — proposed, approved,
   blocked, held, in-review, completed, failed — each populated or explicitly
   empty-but-declared.

## Validator must assert

Required-field completeness per Work Item; id format + cross-slice uniqueness;
source refs resolve to sibling-slice CSR ids; primary-id-is-not-platform-id
(pattern check: reject GUID-shaped primary ids); all seven state groups present
in queueView; creation receipts exist with manifest verbs + full fields.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/work-item-execution-shell-slice.json` — the slice
  (storyKey: `2-1-maintain-the-work-item-execution-shell`).
- `_bmad-output/implementation-artifacts/work-item-execution-shell-slice-validate.ps1` — the
  validator; prints `WORK_ITEM_EXECUTION_SHELL_SLICE_VALIDATE_OK` and exits 0 on success, lists every issue and
  exits 1 otherwise. A validator that cannot fail is a defect.
