# Story 4.2: Explain Work Through Graph Provenance

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/graph-provenance-explanation-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/graph-provenance-explanation-slice.json;_bmad-output/implementation-artifacts/graph-provenance-explanation-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/graph-provenance-explanation-slice.json;_bmad-output/implementation-artifacts/graph-provenance-explanation-slice-validate.ps1 -->

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

## Story goal (FR20, FR19)

Queue/Brief explanations show provenance and distinguish evidence from
inference; uncertainty is visible and never auto-approves.

## Slice must prove

1. One explanation for a real Work Item (sibling CWI id): source records,
   people/roles/projects/topics, supporting receipts, confidence per element,
   and an `evidenceKind: evidence|inference` marker on EVERY element.
2. One conflicting/uncertain-evidence explanation: conflict described,
   `uncertaintyVisible: true`, and a guard + receipt trail proving the Work
   Item was NOT auto-approved from graph evidence (state group unchanged;
   `noAutoApprovalFromGraph: true`).

## Validator must assert

Explanation completeness; every element carries evidenceKind from the closed
set; confidence values TryParse [0,1]; conflict scenario has the uncertainty
flag AND unchanged state (cross-checked against the referenced Work Item's
state group in its home slice); guards strict-bool; cross-slice id
resolution + uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/graph-provenance-explanation-slice.json` (storyKey: `4-2-explain-work-through-graph-provenance`)
- `_bmad-output/implementation-artifacts/graph-provenance-explanation-slice-validate.ps1` — prints
  `GRAPH_PROVENANCE_EXPLANATION_SLICE_VALIDATE_OK` and exits 0 on success; lists every issue and exits 1 otherwise.
  Validator-laziness is the review swarm's #1 kill: no conditional/skippable
  checks, no hardcoded ids as binding rules, live cross-slice harvests (mirror
  the epic-2/3 HARDENED validators), content deltas proven not self-asserted.
