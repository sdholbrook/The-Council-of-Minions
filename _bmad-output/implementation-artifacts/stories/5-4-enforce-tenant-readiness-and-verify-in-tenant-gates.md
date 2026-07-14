# Story 5.4: Enforce Tenant Readiness and VERIFY IN TENANT Gates

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/tenant-readiness-gates-slice.json;_bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1 -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/tenant-readiness-gates-slice.json;_bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1 -->

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

## Story goal (FR29, NFR5, NFR9, AR12)

Anything depending on the live tenant is `VERIFY IN TENANT` until evidence
exists; no live write before the approved boundary is documented.

## Slice must prove

1. Four planned capabilities of different kinds (connector, published agent,
   app registration, automation) each marked `verifyInTenant: true` with no
   tenant evidence and guards proving no live write occurred.
2. One capability with a completed tenant-validation evidence record: tenant
   identity, environment, auth user, licensing/capacity assumptions, relevant
   settings, restrictions, decision, follow-up owner — flipping it to
   verified, receipt-backed.
3. The boundary rule demonstrated: an attempted action on an unverified
   capability yields a policy-denial receipt (2-6 vocabulary).

## Validator must assert

Unverified capabilities all flagged with zero evidence fields and no-write
guards; the verified one's evidence record is complete (all eight fields);
the denial receipt binds to an unverified capability; verification flips are
receipt-backed; minted-vs-referenced ids; cross-slice uniqueness.

## Deliverables (exactly two files)

- `_bmad-output/implementation-artifacts/tenant-readiness-gates-slice.json` (storyKey: `5-4-enforce-tenant-readiness-and-verify-in-tenant-gates`)
- `_bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1` — prints `TENANT_READINESS_GATES_SLICE_VALIDATE_OK`,
  exits 0 on success; lists every issue and exits 1 otherwise. Hardening bar
  (the review swarm's kill list): no self-asserted booleans standing in for
  proof, no hardcoded-id binding rules (general rules over collections), LIVE
  cross-slice id harvests from $PSScriptRoot distinguishing MINTED ids (must
  be unique) from REFERENCED ids (must resolve), no conditional/skippable
  mandatory checks, coverage derived not counted. Verify a corrupted slice
  copy FAILS before finishing.
