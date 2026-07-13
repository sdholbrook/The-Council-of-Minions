# Story 4.1: Create Lightweight Meaning Graph Records

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/meaning-graph-records-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/meaning-graph-records-slice.json;_bmad-output/implementation-artifacts/meaning-graph-records-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/meaning-graph-records-slice.json;_bmad-output/implementation-artifacts/meaning-graph-records-slice-validate.ps1 -->

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

## Story goal (FR19, FR20, FR21)

A lightweight Meaning Graph links Council objects for explanation — never for
workflow authority.

## Slice must prove

1. Graph Entities covering at least: two Work Items, two Source Records, a
   person, a role, a project, a topic, and a receipt (ids resolving to sibling
   slices where those objects exist; new GE-LOCAL-* ids for net-new entities),
   each typed from the manifest/Council Semantic Contract vocabulary.
2. Graph Edges (GEDGE-LOCAL-*) linking them, each carrying: vocabulary-valid
   edge type, rationale, confidence [0,1], source/receipt grounding refs, and a
   declared retained-value tag (routing|retrieval|provenance|context|
   explanation|audit).
3. Authority guard: explicit `edgesOwnNoWorkflowState: true` plus a
   demonstration entry showing a Work Item state group is IDENTICAL before and
   after edge creation (no state field on any edge).

## Validator must assert

Entity/edge vocabulary membership; edge field completeness (rationale
non-empty, confidence TryParse [0,1], grounding resolves); every edge carries
a retained-value tag from the closed set; authority guard strict-bool + the
no-state-fields scan over edges; id formats + cross-slice uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/meaning-graph-records-slice.json` (storyKey: `4-1-create-lightweight-meaning-graph-records`)
- `_bmad-output/implementation-artifacts/meaning-graph-records-slice-validate.ps1` — prints
  `MEANING_GRAPH_RECORDS_SLICE_VALIDATE_OK` and exits 0 on success; lists every issue and exits 1 otherwise.
  Validator-laziness is the review swarm's #1 kill: no conditional/skippable
  checks, no hardcoded ids as binding rules, live cross-slice harvests (mirror
  the epic-2/3 HARDENED validators), content deltas proven not self-asserted.
