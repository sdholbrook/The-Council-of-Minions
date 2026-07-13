# Story 2.6: Record Failures and Policy Denials

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/failure-policy-denial-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/failure-policy-denial-slice.json;_bmad-output/implementation-artifacts/failure-policy-denial-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/failure-policy-denial-slice.json;_bmad-output/implementation-artifacts/failure-policy-denial-slice-validate.ps1 -->

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

## Story goal (FR16, NFR13)

Failures and policy denials are recorded with evidence, distinguishing system
errors, policy denials, and human-review items.

## Slice must prove

1. Three failure receipts covering distinct kinds — a system error (retryable),
   a policy denial (non-retryable), and a failure requiring human review —
   each carrying: attempted action, actor, authority basis, source evidence
   refs, retry allowance, failure code, result, and human-review-required flag.
2. For the policy denial: the affected Work Item remains in a reviewable state
   (per manifest state groups) and the denial rationale traces to specific
   policy flags AND evidence references present in the slice.
3. Failure codes drawn from (or declared as extending) the manifest vocabulary.

## Validator must assert

Full field set per failure receipt; the three kinds distinguishable by their
fields (retry allowance / failure code / review flag combinations); denial
traceability (policy flags + evidence refs resolve within the slice); affected
item's state group is reviewable; receipts append-only; cross-slice id
uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/failure-policy-denial-slice.json` — the slice
  (storyKey: `2-6-record-failures-and-policy-denials`).
- `_bmad-output/implementation-artifacts/failure-policy-denial-slice-validate.ps1` — the
  validator; prints `FAILURE_POLICY_DENIAL_SLICE_VALIDATE_OK` and exits 0 on success, lists every issue and
  exits 1 otherwise. A validator that cannot fail is a defect.
