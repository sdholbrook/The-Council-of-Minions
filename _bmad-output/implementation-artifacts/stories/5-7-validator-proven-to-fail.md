# Story 5-7: the tenant-readiness validator must be proven to fail

<!-- ringer-check: export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1 -->
<!-- ringer-owned: _bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1;_bmad-output/implementation-artifacts/tenant-readiness-probe-fixtures/ -->
<!-- ringer-expect: _bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1 -->

**Why this story exists.** Story 5-4 was held out of the epic-5 wave: an
orchestrator probe on 07-14 injected fabricated-but-well-formed tenant-readiness
evidence and the validator still printed `TENANT_READINESS_GATES_SLICE_VALIDATE_OK`
and exited 0 (commit `068ce1b`; route-plan exclusion note). **A gate that cannot
fail proves nothing.** This story re-fixes the validator; 5-4 itself stays held
until this lands.

## The two defects (verified in the validator source)

1. **Presence stands in for proof.** Every substantive evidence check routes
   through `Test-HasNonEmptyField` (`tenant-readiness-gates-slice-validate.ps1:45-57`)
   — true for any non-empty string. The eight mandatory
   `tenantValidationEvidence` fields are checked for presence only (`:610-630`),
   so plausible fabricated strings pass.
2. **No negative self-test.** The 5-4 story mandates *"verify a corrupted slice
   copy FAILS before finishing"* (`5-4-…md:82`); the validator contains zero
   self-invocation and nothing that mutates and re-checks. The 07-14 probe ran
   only in scratchpad and left nothing committed — the proven-to-fail evidence
   evaporated (same disease recorded in `deferred-work.md:11,14`).

## Acceptance criteria

1. **Committed mutation battery.** A fixtures directory
   (`tenant-readiness-probe-fixtures/`) holds ≥5 mutated copies of the slice,
   each one a named fabrication class:
   - one of the eight evidence fields dropped;
   - a `verifyInTenant: true` capability flipped to verified with **no**
     `verificationReceipt`;
   - a fabricated `tenantValidationEvidence` block (well-formed strings, no
     resolvable receipt);
   - the boundary-denial receipt re-bound to a **verified** capability;
   - a minted id (`CAP-LOCAL-*`/`runId`) colliding with a sibling slice's.
2. **The validator proves it can fail, on every run, before the OK token.**
   It re-runs its own full check set against each committed fixture and exits
   **1 unless every fixture produces a failure** — a gate that cannot fail
   fails itself. Only then does it check the real slice and, if clean, print
   the OK token and exit 0.
3. **Derivation replaces presence.** Each evidence claim binds to an
   independently checkable fact: `verificationReceipt` must resolve in the
   receipts collection; `decision` must be a value from the manifest's
   `com_decision` vocabulary; coverage is derived from the collection, never a
   counted/asserted boolean. After this, the 07-14 probe's fabricated block
   must be caught by check-content, not merely by fixture-diffing.
4. The real (uncorrupted) slice still validates: exit 0 + OK token — the
   ratchet tightens without breaking the true positive.
5. Only the owned paths change. Do **not** touch the other five slice
   validators (already review-hardened, `068ce1b`) or any slice JSON.

## Constraints

- PowerShell only (the validator's existing language); no new dependencies.
- The fixtures are **committed** — the proven-to-fail behaviour re-runs on
  every invocation, not once in scratchpad.
- Read `_bmad-output/implementation-artifacts/stories/5-4-enforce-tenant-readiness-and-verify-in-tenant-gates.md`
  first: its §"hardening bar" (`:78-82`) is the contract this story makes real.
