# Story 4.5: Project the Semantic Contract Without Dual Authoring

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/semantic-contract-projection-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/semantic-contract-projection-slice.json;_bmad-output/implementation-artifacts/semantic-contract-projection-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/semantic-contract-projection-slice.json;_bmad-output/implementation-artifacts/semantic-contract-projection-slice-validate.ps1 -->

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

## Story goal (FR21, FR22, NFR8, NFR15, AR16)

Council terms project into Microsoft knowledge planes (Dataverse, Fabric,
Copilot Studio, agent knowledge) — the Council Semantic Contract stays the
single canonical source; the planes never become authoring surfaces.

## Slice must prove

1. A projection manifest: at least four Council terms/edge-types (from the
   Dataverse manifest vocabulary) projected to two named planes, each
   projection entry carrying: canonical term id, target plane, projected
   representation, projection date, and `canonicalSource:
   "council-semantic-contract"`.
2. No-dual-authoring guards: `planesAreProjectionsOnly: true` and a
   drift-detection entry — one projected term deliberately shown drifted in a
   plane with a detection record + receipt flagging it for reconciliation
   (never edited in place in the plane).
3. Projection/reconciliation events receipt-backed.

## Validator must assert

Every projected term resolves to the manifest vocabulary; projection entries
complete; both guards strict-bool; the drift record references a real
projected term and carries a receipt with policy flags; no projection entry
claims authority (no state/approval fields); cross-slice id uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/semantic-contract-projection-slice.json` (storyKey: `4-5-project-the-semantic-contract-without-dual-authoring`)
- `_bmad-output/implementation-artifacts/semantic-contract-projection-slice-validate.ps1` — prints
  `SEMANTIC_CONTRACT_PROJECTION_SLICE_VALIDATE_OK` and exits 0 on success; lists every issue and exits 1 otherwise.
  Validator-laziness is the review swarm's #1 kill: no conditional/skippable
  checks, no hardcoded ids as binding rules, live cross-slice harvests (mirror
  the epic-2/3 HARDENED validators), content deltas proven not self-asserted.
