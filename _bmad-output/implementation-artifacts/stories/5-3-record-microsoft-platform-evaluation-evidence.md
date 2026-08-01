# Story 5.3: Record Microsoft Platform Evaluation Evidence

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/platform-evaluation-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/platform-evaluation-slice.json;_bmad-output/implementation-artifacts/platform-evaluation-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/platform-evaluation-slice.json;_bmad-output/implementation-artifacts/platform-evaluation-slice-validate.ps1 -->

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

## Story goal (FR26, FR27, FR28, NFR2)

Microsoft-native planes are evaluated before custom substrate; custom services
must cite the gap they fill.

## Slice must prove

1. Two capability evaluations (e.g. memory/graph grounding; workflow
   automation), each considering AT LEAST four relevant Microsoft candidates
   from: Work IQ, Dataverse intelligence/MCP, Power Apps MCP agent feed,
   Copilot Studio, Power Automate, Fabric IQ/Graph, Fabric data agents — each
   candidate row capturing tenant gates, permission/DLP impact, licensing/
   cost, ALM path, contract gaps, decision, review reference.
2. One custom-service proposal citing the specific Microsoft-native gap or
   tenant constraint it addresses, decision recorded (receipt) BEFORE
   implementation (no implementation artifacts referenced).

## Validator must assert

Candidate coverage (>=4 per evaluation, from the named set); row field
completeness; the custom proposal's gap citation references a recorded gap in
an evaluation row; decision receipts complete and precede any implementation
marker; minted-vs-referenced ids; cross-slice uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/platform-evaluation-slice.json` (storyKey: `5-3-record-microsoft-platform-evaluation-evidence`)
- `_bmad-output/implementation-artifacts/platform-evaluation-slice-validate.ps1` — prints `PLATFORM_EVALUATION_SLICE_VALIDATE_OK`,
  exits 0 on success; lists every issue and exits 1 otherwise. Hardening bar
  (the review swarm's kill list): no self-asserted booleans standing in for
  proof, no hardcoded-id binding rules (general rules over collections), LIVE
  cross-slice id harvests from $PSScriptRoot distinguishing MINTED ids (must
  be unique) from REFERENCED ids (must resolve), no conditional/skippable
  mandatory checks, coverage derived not counted. Verify a corrupted slice
  copy FAILS before finishing.
