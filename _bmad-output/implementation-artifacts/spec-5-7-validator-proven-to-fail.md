---
title: 'Story 5-7: the tenant-readiness validator must be proven to fail'
type: 'bugfix'
created: '2026-08-02'
status: 'done'
baseline_revision: '55bc8148b4b1cad537c0fdd003c446edde7a1eb1'
final_revision: '4ac9197e306a1594834be97df8f10a6d57ca92ab'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/implementation-artifacts/stories/5-7-validator-proven-to-fail.md'
  - '{project-root}/_bmad-output/implementation-artifacts/stories/5-4-enforce-tenant-readiness-and-verify-in-tenant-gates.md'
warnings: [oversized]
---

<intent-contract>

## Intent

**Problem:** A 07-14 probe injected fabricated tenant-readiness evidence and `tenant-readiness-gates-slice-validate.ps1` still printed its OK token and exited 0: the eight `tenantValidationEvidence` fields are presence-checked only (`Test-HasNonEmptyField`), and nothing committed ever proves the validator can fail. A gate that cannot fail proves nothing; story 5-4 stays held until this lands.

**Approach:** Refactor the validator's linear check body into a reusable check-set function; add committed mutation fixtures (≥5 named fabrication classes); make every run first prove each fixture FAILS the check set before validating the real slice; replace presence/assertion checks with derivation against independently checkable facts (receipts collection, manifest vocabulary and `target` block, tenant-decision-packet values).

## Boundaries & Constraints

**Always:**
- PowerShell only, no new dependencies; edit only the owned paths: `tenant-readiness-gates-slice-validate.ps1` and new `tenant-readiness-probe-fixtures/`.
- Fixtures are committed files; the proven-to-fail battery re-runs on every invocation, before the OK token can print.
- Self-test failure semantics: a fixture producing **zero** issues is fatal (exit 1, no OK token). A fixture run that throws counts as a produced failure (the gate still refused it).
- Fixture runs reuse the exact same check-set function and the same sibling-universe/manifest/packet inputs as the real run — only the tenant-slice path is substituted.
- Real-slice behavior preserved: unmodified slice ⇒ exit 0, existing summary lines, `TENANT_READINESS_GATES_SLICE_VALIDATE_OK` printed last.

**Block If:** Derivation checks (as specced below) fail against the *unmodified* real slice for a reason that cannot be fixed inside the validator — the slice JSON is frozen, so that would be an unresolvable contradiction between AC3 and AC4.

**Never:** Do not modify the other five slice validators, any `*-slice.json`, the manifest, or `tenant-decision-packet.json`. Do not weaken or delete any existing check to make a fixture fail. Fixture filenames must not match `*-slice.json` (keeps them out of any sibling harvest even if paths shift).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Real slice + ≥5 committed fixtures | Per-fixture self-test line (name + issue count), then real-slice summary + OK token | Exit 0 |
| Fixture passes cleanly | Any fixture yields 0 issues (e.g. unmutated copy) | Names the fixture, states the gate cannot fail | Exit 1, no OK token, real slice not blessed |
| Fixtures dir missing / <5 fixtures | Dir absent or sparse | States the mutation battery is missing/incomplete | Exit 1, no OK token |
| Fixture unparseable/throws | Malformed fixture JSON | Counted as a produced failure; self-test continues | No script abort |
| Real slice dirty | Self-test passes, slice has issues | Full issue list printed | Exit 1, no OK token |
| `-ShowFixtureIssues` | Switch passed | Additionally prints each fixture's full issue list (for proving check-content catches) | n/a |

</intent-contract>

## Code Map

- `_bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1` -- the validator; lines 45-60 `Test-HasNonEmptyField`, 128-141 `Read-JsonInput` (contains `exit 1` — must become `throw`), 252-273 input loading, 374-381 early `exit 1` on missing run block (must become add-issue + return), 610-650 the eight-field presence checks + decision vocab, 885-897 hardcoded verificationReceipt equality, 1119-1142 runId/CAP collision checks, 1144-1159 final report
- `_bmad-output/implementation-artifacts/tenant-readiness-gates-slice.json` -- real slice (read-only); verified capability `CAP-LOCAL-COUNCIL-QUEUE-APP-001`, receipts `CR-LOCAL-TENANT-VERIFY-001`/`CR-LOCAL-TENANT-DENY-001`, runId `TENANT-READINESS-LOCAL-2026-07-14-001`
- `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json` -- independent facts: `target.environmentId`, `target.environmentUrl`, `target.organizationId`; `com_counciltenantevidence.com_decision` vocabulary
- `_bmad-output/implementation-artifacts/tenant-decision-packet.json` -- independent facts: `decisions.tenantDomainOrId.value`, `decisions.humanApprovalOwner.value`
- `_bmad-output/implementation-artifacts/approval-boundaries-slice.json` -- sibling; its runId `APPROVAL-LOCAL-2026-07-13-001` seeds the collision fixture (no sibling carries CAP- ids, so the collision class must use runId)
- `_bmad-output/implementation-artifacts/tenant-readiness-probe-fixtures/` -- NEW committed fixtures dir

## Tasks & Acceptance

**Execution:**
- `tenant-readiness-gates-slice-validate.ps1` -- wrap the entire check body (manifest vocab through final cross-check) in `Invoke-TenantReadinessCheckSet` taking all six input paths plus the pre-harvested sibling file list, returning the issues list; no `exit`/final `Write-Host` inside; `Read-JsonInput` throws instead of exiting; missing-run-block early-exit becomes add-issue + return -- self-test needs to run the check set repeatedly without killing the process
- `tenant-readiness-gates-slice-validate.ps1` -- add derivation checks inside the function: (a) `verifiedCapability.verificationReceipt` must resolve by membership in the slice's receipts collection, and the resolved receipt must have verb `reviewed`, result `succeeded`, and `com_evidence_refs` naming the verified capability id; (b) derive eight-field coverage from the `tenantValidationEvidence` block itself and require asserted `evidenceFieldsPresent` and `tenantEvidenceStatus` to match the derived value (complete ⇔ all eight non-empty AND receipt resolves), never trusting the asserted boolean; (c) bind evidence content to independent facts read from already-loaded inputs (never literals): `environment` must contain manifest `target.environmentId` and `target.environmentUrl`; `tenantIdentity` must contain manifest `target.organizationId` and packet `decisions.tenantDomainOrId.value`; `followUpOwner` must equal packet `decisions.humanApprovalOwner.value`; `authUser` must contain packet `decisions.humanApprovalOwner.value`; keep the existing decision-vocabulary check -- AC3: fabricated well-formed strings must be caught by content (licensingOrCapacityAssumptions/relevantSettings/restrictions have no independent machine-checkable fact and stay presence+coverage-derived)
- `tenant-readiness-gates-slice-validate.ps1` -- add main flow: (1) require the fixtures dir with ≥5 `*.json` fixtures AND all canonical fixture filenames present — the five below plus `fixture-06-resolvable-receipt-unproving.json` (sixth canonical, added by the post-loopback review patch) — else exit 1; (2) every `*.json` in the dir must declare a non-empty top-level `expectedIssuePatterns` array (regex strings), else exit 1 naming the file — a stray, clean, or malformed file thereby fails loudly; (3) run the check set against each fixture (same siblings/manifest/packet, tenant-slice path substituted): a fixture passes the battery only if it produced ≥1 issue AND every one of its `expectedIssuePatterns` matches at least one produced issue string; a thrown fixture run yields only the synthetic throw message and so cannot satisfy class patterns; print `Self-test: <name> produced N issue(s); M/M expected pattern(s) matched` per fixture (full lists under `-ShowFixtureIssues` switch); exit 1 naming every fixture that failed the battery; (4) only then run the real slice, print the summary + OK token on clean, else issue list + exit 1; summary counts must come from data parsed inside the validated run (e.g. returned by the check-set function), never a post-validation re-read -- AC2 + battery integrity: each fabrication class is machine-pinned to the check that catches it, so deleting or neutering any derivation check turns the battery red
- `tenant-readiness-probe-fixtures/fixture-01-evidence-field-dropped.json` -- copy of real slice with one of the eight evidence fields (e.g. `followUpOwner`) removed, asserted `evidenceFieldsPresent`/`tenantEvidenceStatus` left untouched; `expectedIssuePatterns` pin the missing-field message AND the asserted-vs-derived coverage mismatch -- fabrication class: dropped field
- `tenant-readiness-probe-fixtures/fixture-02-flip-without-receipt.json` -- planned capability (e.g. `CAP-LOCAL-MINION-AGENT-FEED-001`) with `verified` flipped to `true`, still `verifyInTenant: true`, no `verificationReceipt`; `expectedIssuePatterns` pin the strict-boolean-false violation -- fabrication class: unreceipted flip
- `tenant-readiness-probe-fixtures/fixture-03-fabricated-evidence.json` -- `tenantValidationEvidence` replaced with well-formed plausible strings (wrong tenant/org/environment ids, wrong auth user, wrong follow-up owner) and `verificationReceipt` set to an id absent from the receipts collection; `expectedIssuePatterns` pin receipt-non-resolution AND ≥2 independent-fact content bindings (must include the followUpOwner/humanApprovalOwner binding) -- fabrication class: the 07-14 probe; the patterns force the catch to be by-content
- `tenant-readiness-probe-fixtures/fixture-04-denial-rebound.json` -- `capabilityBindings` entry for `CR-LOCAL-TENANT-DENY-001` and `boundaryRuleAttempt.attemptedOnCapability` re-pointed at the verified capability; `expectedIssuePatterns` pin the deny-must-bind-unverified violation -- fabrication class: denial bound to a verified capability
- `tenant-readiness-probe-fixtures/fixture-05-minted-id-collision.json` -- `tenantReadinessRun.runId` replaced with sibling runId `APPROVAL-LOCAL-2026-07-13-001`; `expectedIssuePatterns` pin the runId-collision message -- fabrication class: minted-id collision
- `tenant-readiness-probe-fixtures/fixture-06-resolvable-receipt-unproving.json` -- receipt resolves but proves nothing: verb `approved` (not `reviewed`), result `no_op` (not `succeeded`), `com_evidence_refs` dropped, `tenantEvidenceStatus` under-claimed as `recorded`, decision out-of-vocabulary; `expectedIssuePatterns` pin all five messages (three resolved-receipt content sub-checks, derived-status under-claim branch, `com_decision` vocabulary derivation) -- fabrication class: resolvable-but-unproving receipt (sixth canonical, added by the post-loopback review patch)
- `council-mvp-local-validate.ps1` -- Sprint status YAML check (lines 534-541): update the stale exact-count tripwires from 5 epics / 25 stories / 5 retrospectives to 6 / 32 / 6 -- epic-6 (six stories + retrospective) was merged into `sprint-status.yaml` before this story's baseline (commits 0b3efe1, 9cde1df), so the deterministic gate can never pass with the old counts; keep the checks exact-count (no weakening to `-ge`)
- `sprint-status.yaml` -- move the trailing `# HELD: ...` comment on the `5-4-enforce-tenant-readiness-and-verify-in-tenant-gates` line onto its own comment line directly above the key, preserving the comment text verbatim -- the suite's strict status-line regex rejects trailing comments, which both drops the story from the status-line count and trips the illegal-line check; YAML semantics and downstream key harvesting (`dataverse-readiness-slice-validate.ps1:331`) are unaffected

**Acceptance Criteria:**
- Given the committed repo state, when the validator runs, then stdout shows one self-test line per fixture (≥5) each reporting ≥1 issue and all expected patterns matched, then the real-slice summary, `TENANT_READINESS_GATES_SLICE_VALIDATE_OK` last, exit 0.
- Given an unmutated copy of the real slice temporarily added to the fixtures dir (it has no `expectedIssuePatterns` and yields zero issues), when the validator runs, then it exits 1, names that fixture, and prints no OK token.
- Given the fixtures directory renamed away, emptied below 5 fixtures, or missing any of the six canonical fixture filenames, when the validator runs, then it exits 1 with no OK token.
- Given a same-directory copy of the validator with any single new derivation check removed (e.g. the followUpOwner binding), when that copy runs, then its battery exits 1 because fixture-03's pattern for that check goes unmatched — check regressions are detected by the committed battery, not by human inspection.
- Given `-ShowFixtureIssues`, when the validator runs, then fixture-03's printed issues include the unresolved `verificationReceipt` and at least one independent-fact content mismatch (environment/tenantIdentity/authUser/followUpOwner) — content catches, not fixture-diffing.
- Given the five other slice validators and all `*-slice.json` files, when `git status` is inspected after implementation, then none of them changed.
- Given the committed repo state, when `council-mvp-local-validate.ps1` runs under the documented environment, then every suite step passes and the suite exits 0 — the deterministic verification gate requires the full suite green, with no out-of-scope carve-outs.

## Spec Change Log

### 2026-08-02 — Loopback 1 (bad_spec)

**Triggering findings (review pass 1, surfaced independently by three reviewers, one empirically demonstrated):**
1. (high) The battery asserted only issue-count > 0 per fixture, and every fixture also trips at least one pre-existing baseline check — so deleting/neutering any (or all) of the new derivation checks left the battery green. Demonstrated live: neutralizing the followUpOwner binding dropped fixture-03 from 8→7 issues and the validator still printed the OK token with exit 0. The committed battery would have passed against the baseline check set too.
2. (medium) "A throw counts as a produced failure" + count-only assertion made the battery vacuously satisfiable: five malformed JSON files satisfy it while proving only that `ConvertFrom-Json` throws.
3. (medium) The battery required a count (≥5), not the five named fabrication classes — deleting fixture-03 and dropping in junk `.json` still blessed the real slice.
4. (medium) Content bindings covered only 3 of 8 evidence fields; `authUser` accepted any fabricated string although the packet's `humanApprovalOwner` is an available independent fact.
5. (low) The success summary re-read the slice after validation (unvalidated re-read + drift-prone duplicated count logic).

**Amended (all outside `<intent-contract>`):** battery task rewritten to require the five canonical fixture filenames, a non-empty `expectedIssuePatterns` array on every fixture file, and per-fixture pattern matching against produced issues (throw text cannot satisfy class patterns); fixture tasks now specify their pinned patterns; derivation task adds the `authUser`⊇`humanApprovalOwner` binding and documents why licensing/settings/restrictions stay presence-only; summary counts must come from validated-run data; ACs and Verification extended with the regression-tripwire proof (neutered validator copy ⇒ battery red) and canonical-fixture-missing proof.

**Known-bad state avoided:** a "proven-to-fail" battery that cannot detect the loss of the very checks it exists to prove — the 07-14 probe vector reopening silently one level up.

**KEEP (must survive re-derivation — attempt-1 diff saved at `/tmp/claude-1000/-srv-bmad-projects-The-Council-of-Minions--bmad-loop-runs-20260802-185001-3d60-worktrees-5-7-validator-proven-to-fail/8baea1ed-fc0a-4304-8062-38c31577a27e/scratchpad/attempt-1.patch`, a valid base to re-apply and extend):**
- The `Invoke-TenantReadinessCheckSet` refactor shape: six path params + `-SiblingSliceFiles` (harvested once from `$PSScriptRoot`, excluding the real slice), returns the issues list; `Read-JsonInput` throws instead of exiting; missing-run-block early-exit became add-issue + return; no wholesale re-indentation of the moved body.
- The five fixtures' mutation content exactly as attempt 1 (verified catches: 01→3, 02→1, 03→8, 04→2, 05→1 issues); extend each with `expectedIssuePatterns`, keep `probeFixture`. *(Post-review update: the authUser binding raises 03 to 9 issues, and canonical `fixture-06-resolvable-receipt-unproving.json` — 7 issues, 5 patterns — joined the set, making six canonical fixtures total; see Review Triage Log 2026-08-02 post-loopback and the fixture-06 task line.)*
- The derivation checks and their exact issue-message texts from attempt 1 (they are the pattern targets), e.g. "does not resolve to any receipt in this slice's receipts collection", "does not match the coverage derived", "must contain the manifest target.environmentId", "decisions.humanApprovalOwner.value".
- Main-flow ordering (required inputs → battery → real slice; OK token printed last and only on a clean real slice) and the `-ShowFixtureIssues` switch with the `Self-test: <name> …` line format.

### 2026-08-02 — Deterministic-verification repair (post-review)

**Trigger:** The loop's deterministic gate runs the full `council-mvp-local-validate.ps1` suite and requires exit 0. It threw at the Sprint status YAML check ("Expected 5 epics in sprint status, found 6", line 535) — a failure this spec's Verification had carved out as pre-existing/out-of-scope. The gate honors no carve-outs, so the story cannot land until the suite is green end to end.

**Root cause (pre-existing at baseline 55bc814, not introduced by this story):** epic-6 (six stories + retrospective) was merged into `sprint-status.yaml` at loop launch (commits 0b3efe1, 9cde1df), making the suite's exact-count tripwires (5 epics / 25 stories / 5 retrospectives) stale. Additionally, the `5-4-enforce…` line's trailing `# HELD:` comment fails the check's strict status-line regex, which would trip the illegal-line check once the counts are fixed, and the previous session's spec edit left a blank line at EOF, failing the suite's first step (`git diff --check`).

**Amended (all outside `<intent-contract>`):** two Execution tasks added — update the suite's sprint-status counts to 6 / 32 / 6 (kept exact-count; no weakening), and relocate the 5-4 trailing comment to its own line (text verbatim; YAML semantics and `dataverse-readiness-slice-validate.ps1` key harvesting unaffected); suite AC added; Verification suite line now expects full-suite exit 0; the spec's EOF whitespace fixed. Probe evidence: a sibling-named suite copy with exactly these repairs ran green through every step (tenant-readiness step: 6 fixture self-tests, all patterns matched, OK token, summary from validated-run data).

**Owned-paths note:** the intent-contract's "edit only the owned paths" clause scopes the validator feature build; it exists to prevent weakening sibling validators or mutating frozen data inputs. `council-mvp-local-validate.ps1` and `sprint-status.yaml` are workflow-harness artifacts, absent from the contract's Never list; updating a count tripwire to match operator-merged project state and relocating a comment weaken nothing. The Never list (five slice validators, `*-slice.json`, manifest, packet) remains untouched.

## Review Triage Log

### 2026-08-02 — Review pass
- intent_gap: 0
- bad_spec: 5: (high 1, medium 3, low 1)
- patch: 0
- defer: 2: (medium 1, low 1) — carried to the post-loopback pass per cascade (bad_spec moots lower categories this pass): (a) the battery's own veto branches (dir-missing / sparse / pattern-fail exits) are exercised by no committed automation, so a future edit could disable the battery itself while the suite stays green — same disease one level up, fleet-wide pattern; (b) `council-mvp-local-validate.ps1:306` invokes `powershell` via a backslash path that resolves on this Linux host only through a `~/.local/bin/powershell` shim (pre-existing).
- reject: 14 (case-insensitive containment semantics; same-dir fact files not hash-pinned; hardcoded summary "1" [structurally enforced]; flush-left function body [cosmetic]; catch-masks-code-defects [fails closed]; committed fixture duplication [intent mandates committed copies]; six-fold re-parsing [trivial scale]; stale spec line refs [planning artifact]; fixtures-dir-is-a-file misdiagnosis [fails closed]; -TenantSlicePath override collisions [fails closed]; empty-string param binding error [fails closed]; IO-vs-JSON error message conflation; `Out-Null` cargo cult + committed epic-context [by-design cache]; decision-vocab check pre-existed [descriptive note])
- addressed_findings:
  - `[high]` `[bad_spec]` Battery asserts only count>0; every fixture also trips a pre-existing check, so new derivation checks can regress invisibly (empirically proven) — spec amended: per-fixture `expectedIssuePatterns` machine-pin each fabrication class to its catching check; loopback to re-derive.
  - `[medium]` `[bad_spec]` Throw-counts-as-failure makes the battery vacuously satisfiable by malformed files — amended: every dir entry needs patterns; throw text cannot match them.
  - `[medium]` `[bad_spec]` Battery requires a count, not the five named classes — amended: five canonical fixture filenames required.
  - `[medium]` `[bad_spec]` `authUser` accepted any fabricated string — amended: bind to packet `humanApprovalOwner`.
  - `[low]` `[bad_spec]` Success summary re-read the slice post-validation — amended: counts from validated-run data.

### 2026-08-02 — Review pass (post-loopback)
- intent_gap: 0
- bad_spec: 0
- patch: 2: (medium 1, low 1)
- defer: 3: (medium 1, low 2) — appended to the deferred-work ledger this pass: (a) the battery's own veto branches (dir-missing / canonical-missing / pattern-unmatched / zero-issue exits) are exercised by no committed automation; (b) the suite's `powershell` backslash invocation resolves only via a local shim; (c) the input-decay tripwires over manifest/packet facts are structurally unpinnable by slice-substitution fixtures.
- reject: 10 (duplicate-receipt-id smuggling [baseline duplicate check already fires]; non-boolean `evidenceFieldsPresent` dodge [baseline strict-bool check at :594 covers it — verified by reviewer]; output-stream pollution [fails closed under pattern rules]; `-FixturesDirPath` bypass knob + basename-only logs [gate assumes committed invocation]; shared-input pre-parse suggestion [fails closed; root-cause line now printed]; fixture-04 stale prose/count drift [patterns pin what matters]; fixture clone maintenance trap [intent mandates committed copies]; scratchpad KEEP path in change log [historical record]; fixtures 02/04/05 pinning baseline checks [correct — those classes ARE baseline-caught; the ratchet protects them too]; narrative-fields fabrication residue [documented spec decision — no independent fact exists])
- addressed_findings:
  - `[medium]` `[patch]` The three resolved-receipt content sub-checks (verb `reviewed` / result `succeeded` / `com_evidence_refs` naming the capability), the derived-status under-claim branch, and the `com_decision` vocabulary derivation were pinned by no fixture — empirically shown deletable with the battery staying green — and the in-code comment overstated the guarantee. Fixed: new canonical `fixture-06-resolvable-receipt-unproving.json` (receipt resolves but proves nothing: verb `approved`, result `no_op`, refs dropped; status under-claimed `recorded`; decision out-of-vocab) pinning all five messages; comment now states precisely that every slice-reachable check is fixture-pinned while manifest/packet input-decay tripwires are runtime fail-closed guards. Tripwire-verified: deleting the verb sub-check or the under-claim branch now turns the battery red naming the unmatched pattern.
  - `[low]` `[patch]` A pattern broad enough to match the synthetic throw text could vacuously satisfy the battery, and a fixture-run throw's root cause was hidden without `-ShowFixtureIssues`. Fixed: patterns matching the synthetic throw text are rejected as too broad (verified with a `.` pattern), and a throw's message line always prints.

### 2026-08-02 — Review pass (deterministic-verification repair)
- intent_gap: 0
- bad_spec: 0
- patch: 3: (medium 1, low 2)
- defer: 0 — three findings re-surfaced items already recorded in the deferred-work ledger by the post-loopback pass inside this same diff (battery veto branches unautomated — this pass's verification-gap reviewer additionally demonstrated the whole battery is deletable while the suite's OK-token-only assertions stay green; manifest/packet input-decay tripwires structurally unpinnable by slice substitution; `powershell` shim dependency at council-mvp-local-validate.ps1:306); not re-appended, to avoid duplicate ledger entries.
- reject: 13 (uncommitted-repair/stale-final_revision/done-vs-in-review cluster [workflow lifecycle — resolved by this pass's finalize commit]; pattern distinctiveness not machine-checked [inherent design limit, owned by Design Notes]; fixture content drift unpinned [prior disposition: intent mandates committed copies]; selective owned-paths rhetoric [necessity-based: the count tripwires blocked the deterministic gate, the shim does not]; stale 5-4 hold lifecycle [orchestrator-owned; route plan already sequences 5-4-enforce next]; epic-5-context provenance [by-design cache, prior disposition]; KEEP /tmp path [historical record, prior disposition]; fixture metadata keys not explicitly stripped [any future unknown-key tightening fails loud — battery red]; SummaryCollector key-mismatch blank counts [cosmetic, single writer/reader pair]; suite asserts only exit-code + OK token [same claim as the ledgered battery-veto entry]; out-of-contract suite/sprint-status edits argued in spec rather than intent [authorized by the resumption invocation: "repair the working tree so verification passes without changing the spec's frozen intent contract"]; throw-semantics stricter than the matrix letter [adjudicated at Loopback 1; Design Notes record the reconciliation]; edge-hunter guard-snippet description [described a skip that did not yet exist — the patch below makes it real])
- addressed_findings:
  - `[medium]` `[patch]` Spec text lagged the reviewed implementation: the battery task, AC, and KEEP block said five canonical fixtures while the code enforces six, so a future re-derivation honoring the spec would drop `fixture-06` and un-pin the resolved-receipt sub-checks — the exact regression Loopback 1 exists to prevent. Fixed: battery task names all six canonicals, a fixture-06 task line added, AC updated to six, KEEP annotated (03→9 after the authUser binding; fixture-06: 7 issues / 5 patterns).
  - `[low]` `[patch]` Synthetic throw issues were eligible pattern-match targets (the too-broad guard bars only the fixed probe prefix, not variable exception text), so a crafted parsable-but-throwing fixture could in principle satisfy its patterns, and the battery comment overstated the guarantee. Fixed: the matching loop now skips synthetic throw issues outright — a throwing fixture can never satisfy any declared pattern; comments updated to state the guarantee precisely. Committed-state behavior unchanged (verified: identical self-test output, suite exit 0).
  - `[low]` `[patch]` The in-code comment above the six-element canonical array still said "The five canonical fabrication-class fixtures". Fixed: comment states six (five intent-named classes plus post-loopback fixture-06); the `-lt 5` floor kept as the intent-contract's literal `<5 fixtures` matrix row (canonical-name enforcement subsumes it in practice).

### 2026-08-02 — Review pass (follow-up on done spec, fresh dispatch)
- intent_gap: 0
- bad_spec: 0
- patch: 1: (low 1)
- defer: 1: (medium 1) — appended to the deferred-work ledger this pass as a NEW entry: the suite's sprint-status tripwires prove cardinality only, not membership (shape-regex line count against exact totals, no expected-key roster), so a fabricated same-shape key can displace a real story with every suite check green — pre-existing at baseline, surfaced while the counts were under repair. Three further findings re-surfaced items already ledgered in this diff (battery veto branches unautomated / whole-battery deletion invisible to the suite's OK-token-only assertions — re-demonstrated again this pass; manifest/packet input-decay tripwires battery-unpinnable; `powershell` shim dependency); not re-appended, to avoid duplicate ledger entries — the orchestrator owns their status and resolution.
- reject: 12 (`-FixturesDirPath`/`-TenantSlicePath` bypass knobs [prior disposition: gate assumes committed invocation]; pattern distinctiveness not machine-checked [inherent design limit, owned by Design Notes]; self-certification / stale-final_revision / uncommitted-spec-mods cluster [workflow lifecycle — resolved by this pass's finalize commit]; fixture rot with no drift detector [intent mandates committed copies]; HELD-comment relocation deemed a workaround + future-orphaning risk [strict status-line regex is the tripwire's design; regeneration speculative]; exact-count tripwires will fire on the next story addition [tripwire working as designed, documented in Auto Run Result]; `$metadataProblem` single-slot under-reporting [fails closed, cosmetic diagnostics]; fixture-06 metadata keys at top vs 01-05 at bottom [cosmetic, JSON key order immaterial to the battery]; epic-5-context.md "spec lives in stories/" pointer [by-design regenerable cache; the story definition does live there]; existing input-decay ledger entry overstates exposure — bindings skip on empty facts so fixture-03 patterns unmatch and the battery goes red, only diagnostic precision is unprotected [ledger entries are orchestrator-owned; noted here, no modification permitted this pass]; owned-paths breach re-argued [prior disposition: authorized by the resumption invocation]; throw-semantics stricter than the matrix letter [adjudicated at Loopback 1, reconciled in Design Notes])
- addressed_findings:
  - `[low]` `[patch]` The synthetic-throw sentinel `Fixture run threw (counted as a produced failure):` existed as four independent hardcoded literals (over-broad-pattern probe, catch producer, pattern-matching skip, root-cause print guard); rewording the producer alone would silently disarm the skip and re-open the vacuous-satisfaction hole the post-loopback patch closed, while every committed consumer stayed green. Fixed: hoisted to a single `$fixtureThrowPrefix` defined at battery start and reused at all four sites (the print guard's shortened `Fixture run threw` prefix became the full, stricter one — the catch producer is the only minter). Verified: committed-state output byte-identical (6 self-tests, all patterns matched, OK token last, exit 0); malformed-fixture probe still exits 1 naming the fixture with the throw's root cause always printed; full suite green, exit 0.

## Design Notes

- Sibling harvest stays anchored to `$PSScriptRoot` excluding the *real* tenant slice; fixtures live in a subdirectory, so the non-recursive `*-slice.json` harvest never sees them. Pass the harvested sibling list into every check-set call so fixture runs see the identical referenced-id universe.
- No sibling slice mints CAP- ids, so the story's "CAP-LOCAL-*/runId" collision class is only realizable via runId — fixture-05 uses a real sibling runId so the existing collision check (validator :1129-1133) fires.
- Keep the existing hardcoded `CR-LOCAL-TENANT-VERIFY-001` expectations (they encode the 5-4 contract); the new resolution checks derive through the collection *in addition*, so a fabricated receipts collection cannot satisfy them by renaming.
- `expectedIssuePatterns` regexes must be stable substrings of the exact issue messages emitted by the class-distinctive check (e.g. `does not resolve to any receipt`, `does not match the coverage derived`, `decisions\.humanApprovalOwner\.value`, `must use a new local runId`, `verified must be strict boolean false`, `must bind`), chosen so each pattern is emitted only by the check the fixture exists to prove. Pattern choice is the tripwire: a pattern satisfiable by a pre-existing presence check defeats the battery's purpose.
- The intent-contract's "a fixture run that throws counts as a produced failure" still holds (a throw never triggers the zero-issue fatality); the pattern obligation is an additional, stricter requirement every dir entry must meet, so decayed/malformed fixtures now fail the battery loudly instead of vacuously passing it.
- The check-set function must ignore unknown top-level fixture keys (`probeFixture`, `expectedIssuePatterns`) — they are battery metadata, not slice content; the battery reads them from the parsed fixture before invoking the check set.

## Verification

**Commands:**
- `export DOTNET_ROOT=$HOME/.dotnet; export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.local/bin:$PATH; pwsh -File _bmad-output/implementation-artifacts/tenant-readiness-gates-slice-validate.ps1` -- expected: ≥5 self-test lines each with all expected patterns matched, summary, OK token last, exit 0
- `pwsh -File ..._validate.ps1 -ShowFixtureIssues` (same env) -- expected: fixture-03 issues show receipt-resolution + independent-fact catches (incl. authUser and followUpOwner); fixture-01 shows missing field + asserted-vs-derived mismatch
- `cp _bmad-output/implementation-artifacts/tenant-readiness-gates-slice.json _bmad-output/implementation-artifacts/tenant-readiness-probe-fixtures/fixture-99-clean.json && pwsh -File ..._validate.ps1; rm .../fixture-99-clean.json` -- expected: exit 1, fixture-99 named (no expectedIssuePatterns / zero issues), no OK token; then re-run clean, exit 0
- Temporarily move `fixture-03-fabricated-evidence.json` out of the dir, run, move back -- expected: exit 1 naming the missing canonical fixture, no OK token
- Regression tripwire proof: copy the validator to a sibling temp name in the same directory, delete/neuter one derivation check line (e.g. the followUpOwner binding), run the copy, then delete it -- expected: battery exits 1 with fixture-03's pattern unmatched; restore/delete copy afterwards
- `pwsh -File _bmad-output/implementation-artifacts/council-mvp-local-validate.ps1` (same env) -- expected: every suite step passes (tenant-readiness step prints its OK token; Sprint status YAML check prints `Sprint status YAML OK.`), suite exits 0 — the deterministic gate accepts nothing less
- `git status --porcelain` -- expected: changes only under the two owned paths, `council-mvp-local-validate.ps1`, `sprint-status.yaml` (plus this spec and workflow artifacts); no `*-slice.json`, no other slice validator, no manifest/packet changes

**Manual checks (if no CLI):**
- Confirm the OK token cannot be reached on any code path that skips the fixture battery.

## Auto Run Result

**Summary:** Fresh follow-up review dispatch on the completed story (spec arrived `status: done` → routed to a new four-layer review pass per workflow). Adversarial, edge-case, verification-gap, and intent-alignment reviewers examined the full diff since baseline 55bc814 in parallel. Outcome: no intent gaps, no spec defects; one low-severity patch applied (the synthetic-throw sentinel, previously four independent hardcoded literals, hoisted to a single `$fixtureThrowPrefix` reused by the over-broad-pattern probe, the catch producer, the pattern-matching skip, and the root-cause print guard — a future rewording of one copy can no longer silently disarm the skip); one new pre-existing finding appended to the deferred-work ledger (sprint-status tripwires prove cardinality, not membership); three re-surfaced findings already ledgered in this diff were not re-appended; 12 findings rejected on prior dispositions or design adjudications. This pass's finalize commit also lands the previous session's dangling lifecycle metadata (the spec's `final_revision`/status update left uncommitted at cc8e939).

**Files changed (full diff since baseline 55bc814):**
- `tenant-readiness-gates-slice-validate.ps1` — check-set refactor, derivation/content-binding checks, proven-to-fail mutation battery gating the OK token; this pass: synthetic-throw sentinel deduplicated into `$fixtureThrowPrefix`
- `tenant-readiness-probe-fixtures/fixture-01…06.json` — six committed canonical fabrication-class fixtures with `expectedIssuePatterns`
- `council-mvp-local-validate.ps1` — sprint-status count tripwires 5/25/5 → 6/32/6 (exact-count preserved)
- `sprint-status.yaml` — 5-4 HELD comment relocated to its own line; 5-7 flipped to done
- `spec-5-7-validator-proven-to-fail.md` — change-log entries, triage logs (incl. this pass), this result
- `deferred-work.md` — four ledger entries: three from the post-loopback pass, one new this pass (sprint-status membership gap)
- `epic-5-context.md` — compiled epic context cache (committed at d35329a)

**Review findings breakdown (this pass):** 1 patch applied (low); 1 new deferral (medium, ledgered); 3 re-surfaced findings already ledgered in this diff, not re-appended; 12 rejected.

**Follow-up review recommendation:** false — the sole review-driven change is a localized deduplication of string literals with verified byte-identical committed-state behavior; the substantive implementation was independently reviewed three times across this story's passes.

**Verification performed (this pass, after the patch):** standalone validator: 6 self-test lines, all patterns matched (3/2, 1/1, 9/8, 2/2, 1/1, 7/5 issues/patterns), summary from validated-run data, OK token last, exit 0 — output identical to pre-patch. Malformed-fixture probe (fixture-98): battery names it, the throw's root cause prints without `-ShowFixtureIssues`, exit 1, no OK token, no script abort; probe removed afterwards. Full suite `council-mvp-local-validate.ps1`: every step green (Sprint status YAML OK; tenant-readiness step prints its OK token), `COUNCIL_MVP_LOCAL_VALIDATE_OK`, exit 0. Scope: this pass touched only the validator, this spec, and the append-only ledger; no `*-slice.json`, no sibling validator, no manifest/packet changes.

**Residual risks:** the four deferred-work ledger entries (battery veto branches have no committed automated executor — re-demonstrated this pass: deleting the battery leaves the suite's OK-token-only assertions green; manifest/packet input-decay tripwires are battery-unpinnable via slice substitution — though this pass's verification-gap reviewer showed the fail-closed property itself is redundantly covered by fixture-03's pattern pinning, leaving only diagnostic precision unprotected; the suite's `powershell` backslash invocation depends on a local shim; sprint-status tripwires count but do not enumerate story keys). The suite's exact-count sprint-status tripwires will intentionally fire on the next epic/story addition — that is the tripwire working as designed, not drift.
