---
title: 'Story 1.5: Handle Source Drift and Supersession'
type: 'feature'
created: '2026-07-13'
status: 'done'
baseline_revision: '3867d0d2de4a7e7a961da0676d967c4c7d93d6f0'
final_revision: 'f7c4dbbddec73cd88834cbaea4f5f315329dda11'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
warnings: [oversized]
---

<intent-contract>

## Intent

**Problem:** Stories 1.1–1.4 prove capture and extraction, but nothing proves what happens when a source changes after it has produced rationale or Work Items (FR30, FR16, FR17): drift must create a new source version reference, a drift receipt, or a superseding Source Record — never a silent rewrite of prior rationale or receipts — and a drifted source that affects an existing Work Item must flag it for review, with any state change backed by a new Receipt.

**Approach:** Extend the Epic 1 local-contract pattern: a story-keyed JSON slice proves one version-drift scenario (with drift receipt and targeted Work Item review flag) and one supersession scenario (superseding Source Record), validated by a PowerShell script against the Dataverse manifest vocabulary, wired into `council-mvp-local-validate.ps1`, with story 1-5 marked in-progress. Receipts appear as local contract evidence only; live mutations stay receipt-gated to Epic 2 and are recorded as deferred.

## Boundaries & Constraints

**Always:**
- Council identity only: new records use fresh `CSR-*`/`CR-*` IDs; never Dataverse/Graph IDs as product identity. Receipt IDs must not collide with `state-transition-demo-evidence.json` receiptIds.
- Every receipt in the slice uses manifest vocabulary (`com_verb: source_drifted`, valid actor type and result), carries all manifest-required receipt fields including a unique idempotency key, and has strict-boolean `com_append_only_locked: true`.
- Prior rationale and receipts stay untouched: no edits to any 1.1–1.4 slice JSON or validator; prior source/Work Item IDs may appear in the 1.5 slice only as references (drift events, receipts, links, review flags, deferred updates) — never with replacement rationale or status fields applied in-slice.
- The drifted and superseded sources must be sources that already produced Work Items or rationale (use `CSR-MANUAL-MEETING-001` from 1.4 and `CSR-OUTLOOK-THREAD-MOCK-001` held in 1.4).
- Review flagging is targeted: only the Work Item whose rationale the drift affects is flagged; no Work Item state group changes in-slice — state changes appear only as receipt-gated deferred entries.
- The superseding Source Record carries the full required source-record field shape, `com_parent_ref` naming the superseded record, mock/manual evidence marking, and ISO 8601 timestamps.

**Block If:** Any step would require a live Dataverse write, live Outlook/Graph read, or a change to `dataverse-mvp-schema-manifest.json` (needed vocabulary — `source_drifted`, `superseded`, `drift_evidence`, `superseding` — already exists; if it turns out it doesn't, that is a human decision).

**Never:** No live receipts or tenant mutations; no outbound action, flows, agents, or app registrations; no edits to 1.1–1.4 slices/validators or app-curation evidence; no marking of live tenant records; no claiming tenant-verified behavior from local JSON validation.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Version drift on Work-Item-producing source | `CSR-MANUAL-MEETING-001` (3 Work Items in 1.4); newer note version observed | Drift event with new `com_source_version_ref` + `com_content_hash` + `com_observed_modified_at` later than capture; drift receipt `CR-LOCAL-DRIFT-001` (verb `source_drifted`) with `drift_evidence` receipt-source link; `CWI-LOCAL-MEETING-ACTION-001` flagged review-needed with rationale (deadline changed); other two 1.4 items explicitly unaffected | No error expected |
| Supersession of rationale-producing source | `CSR-OUTLOOK-THREAD-MOCK-001` (held in 1.4); newer thread snapshot captured | Superseding record `CSR-OUTLOOK-THREAD-MOCK-002` (`com_parent_ref` to prior, hash_only, mock evidence); receipt `CR-LOCAL-SUPERSEDE-001` (verb `source_drifted`, before `held` / after `superseded`); prior record's `superseded` status only in `sourceUpdatesDeferred`; 1.4 held rationale not restated | No error expected |
| Slice violates contract | Drift event naming an unknown source, receipt missing idempotency key or `com_append_only_locked` ≠ strict true, superseding record reusing an existing CSR ID, review flag naming an unknown Work Item, in-slice Work Item state change | Validator lists the issue and exits 1 | Issue list printed, no success marker |
| Valid slice | Complete 1.5 slice + manifest + sibling slices | Validator prints `SOURCE_DRIFT_SUPERSESSION_SLICE_VALIDATE_OK`, exit 0 | n/a |

</intent-contract>

## Code Map

Read-only references (do not edit):
- `_bmad-output/implementation-artifacts/zero-multi-item-extraction-slice.json` -- 1.4 slice: guard/deferred/acceptance shape to mirror; drifted meeting source + affected Work Item IDs live here
- `_bmad-output/implementation-artifacts/zero-multi-item-extraction-slice-validate.ps1` -- hardened validator to mirror (TryParse helpers, null guards, strict bools, cross-slice loads, vocab tripwires, wrapped JSON loads, `$PSScriptRoot`-relative params)
- `_bmad-output/implementation-artifacts/proposed-work-item-extraction-slice.json` -- 1.3 Work Item/source IDs for cross-checks
- `_bmad-output/implementation-artifacts/manual-source-record-slice.json`, `outlook-source-reference-slice.json` -- prior `CSR-*` IDs, source-record required-field shape, 1.2 mock field style
- `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json` -- vocabularies: `com_receiptverb` (`source_drifted`), `com_extractionstatus` (`superseded`), `com_councilreceipt` required columns, `com_councilreceiptsource.com_evidence_role` (`drift_evidence`), work-item-source role `superseding`
- `_bmad-output/implementation-artifacts/state-transition-demo-evidence.json` -- reserved `CR-*` receipt IDs (BOM-prefixed JSON; load with UTF-8 BOM handling)

Files to change:
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1` -- new step directly after "Zero/multi-item extraction slice validation" (lines 92–101)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` -- `1-5-…: backlog` at line 56

## Tasks & Acceptance

**Execution:**
- `_bmad-output/implementation-artifacts/source-drift-supersession-slice.json` -- create the story 1.5 slice: `storyKey: 1-5-handle-source-drift-and-supersession`; guards matching 1.4 minus `noReceiptCreationInThisSlice`, plus `receiptsAreLocalContractEvidenceOnly: true`, `priorRationaleAndReceiptsUnchanged: true`, `noWorkItemStateChangeInThisSlice: true`; a `driftRun` (new local runId, semanticContractVersion `2026-07-07`) containing (a) one `driftEvents` entry for `CSR-MANUAL-MEETING-001` recording prior vs newly observed version evidence and non-empty drift rationale; (b) one `supersessions` entry capturing embedded superseding record `CSR-OUTLOOK-THREAD-MOCK-002`; (c) two `receipts` (`CR-LOCAL-DRIFT-001`, `CR-LOCAL-SUPERSEDE-001`) with full manifest-required fields; (d) `receiptSourceLinks` with `drift_evidence` roles binding each receipt to its source(s); (e) `workItemsFlaggedForReview` naming `CWI-LOCAL-MEETING-ACTION-001` with reason, flag mechanism, and unaffected-item notes for the other two 1.4 items; (f) `sourceUpdatesDeferred` + `workItemStateChangesDeferred` entries stating every live mutation (version-ref apply, `superseded` status, any state-group move) is receipt-gated to Epic 2; (g) `acceptanceMapping` for both epic ACs -- proves drift and supersession without tenant writes
- `_bmad-output/implementation-artifacts/source-drift-supersession-slice-validate.ps1` -- create validator mirroring the 1.4 validator's structure and hardening: verifies storyKey, all declared guards true (+ mandatory guard names), drift event (known prior source; new version ref non-empty and, when the prior slice records a version ref, different from it — the 1.4 meeting source records none, so the drift event's prior-evidence block must state that explicitly; hash format; `com_observed_modified_at` ISO 8601 and later than the source's `com_captured_at`; non-empty rationale), receipts (unique new `CR-*` IDs with no collision against demo-evidence receiptIds, verb/actor/result in manifest vocabulary, required fields non-empty, unique idempotency keys, ISO 8601 `com_occurred_at`, strict-bool `com_append_only_locked: true`, confidence TryParse in [0,1]), receipt-source links (valid `drift_evidence` role, refs resolve), superseding record (required source-record fields, fresh `CSR-*` ID unique across 1.1/1.2/1.4/this slice, `com_parent_ref` = superseded ID, valid policy/kind/system, ISO 8601 capture time), review flags (Work Item exists in 1.3/1.4, non-empty reason, no in-slice state change), prior-reference hygiene (prior IDs never carry replacement rationale/status in-slice), derived deferred coverage (drifted + superseded sources and flagged Work Items all have deferred entries), acceptance mapping non-empty per criterion, receipt-field sniffing not applicable (receipts are sanctioned here) but no live-write markers; wrapped JSON loads and non-empty cross-slice tripwires; prints `SOURCE_DRIFT_SUPERSESSION_SLICE_VALIDATE_OK` on success, lists issues and exits 1 on failure -- makes the drift contract enforceable
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1` -- insert step "Source drift and supersession slice validation" immediately after the "Zero/multi-item extraction slice validation" step, echoing child output before the exit-code check (1.4 pattern), spelled `powershell` -- wires the story into the canonical suite
- `_bmad-output/implementation-artifacts/sprint-status.yaml` -- set `1-5-handle-source-drift-and-supersession: in-progress`; update both `last_updated` occurrences to the current datetime -- counts must stay 5 epics / 25 stories / 5 retrospectives

**Acceptance Criteria:**
- Given the committed 1.5 slice and manifest, when the story validator runs, then it exits 0 and prints `SOURCE_DRIFT_SUPERSESSION_SLICE_VALIDATE_OK`.
- Given the drifted source `CSR-MANUAL-MEETING-001`, when the slice is inspected, then it contains a new source version reference differing from prior evidence, a `source_drifted` receipt bound by a `drift_evidence` link, and a review flag on `CWI-LOCAL-MEETING-ACTION-001` only — with every 1.1–1.4 artifact byte-identical (`git diff` shows no change to them).
- Given the superseded source `CSR-OUTLOOK-THREAD-MOCK-001`, when the slice is inspected, then `CSR-OUTLOOK-THREAD-MOCK-002` supersedes it via `com_parent_ref`, its 1.4 held rationale is nowhere restated or modified, and its `superseded` extraction status appears only inside `sourceUpdatesDeferred`.
- Given a copy of the slice mutated to break the contract (receipt `com_append_only_locked` set to string `"true"`, drift event pointing at an unknown source, or an in-slice Work Item state change), when the validator runs against the mutated copy, then it exits 1 and names the violation.
- Given the aggregate suite runs, when it reaches the new step, then the new step passes and the previously-passing 1.3 and 1.4 validators still pass unchanged.

## Spec Change Log

## Review Triage Log

### 2026-07-13 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 17: (high 0, medium 3, low 14)
- defer: 1: (high 0, medium 0, low 1)
- reject: 8: (high 0, medium 0, low 8)
- addressed_findings:
  - `[medium]` `[patch]` Content-hash equality was never checked, so a "drift" or "supersession" with byte-identical content validated green — the observed drift hash must now differ from the prior record's hash, and a superseding record's hash must differ from the superseded record's.
  - `[medium]` `[patch]` The prior-rationale restatement tripwire ran only for superseded sources, leaving the drift path unguarded — drifted sources' prior rationale (source record, zero-item outcomes, and 1.3/1.4 per-item extraction/work-item rationales) is now protected on both paths.
  - `[medium]` `[patch]` Flag eligibility, the flagged-or-cleared coverage sweep, and unaffected-note relevance were scoped to drifted sources only, so items from a superseded Work-Item-producing source escaped review coverage and legitimately flagging them would have been rejected — all three now use drifted plus superseded sources.
  - `[low]` `[patch]` Restatement matching was raw-text Contains only, silently no-oping on any rationale containing JSON-escaped characters — an escaped-variant check was added.
  - `[low]` `[patch]` No temporal ordering for supersession: a superseding record captured before the superseded record validated green — capture-time ordering now enforced.
  - `[low]` `[patch]` The drift event's priorEvidence block was unaudited assertion — echoed com_captured_at/com_content_snapshot_ref must now match the actual 1.4 record values.
  - `[low]` `[patch]` decisionPolicy booleans were decorative — the five policy names are now mandatory and every entry must be strict boolean true.
  - `[low]` `[patch]` The superseding record needed no receipt-source link (deleting its link passed) — every superseding record must now be bound by a drift_evidence link.
  - `[low]` `[patch]` Test-HasNonEmptyField used .Contains on PSObject property names, degrading to substring matching for single-property records — replaced with the -contains operator.
  - `[low]` `[patch]` A slice without a driftRun block crashed with a parameter-binding exception instead of a named violation — null guard with issue-list exit added.
  - `[low]` `[patch]` Offset-less timestamps validated, making drift ordering host-timezone dependent — explicit UTC offset now required, handling ConvertFrom-Json's datetime round-trip via DateTimeKind (the first cut of this patch flagged the valid committed slice; fixed and re-verified).
  - `[low]` `[patch]` A sibling slice whose collection path renames would load empty and silently no-op its cross-checks while aggregate tripwires stayed quiet — per-collection load tripwires added for all six cross-slice collections.
  - `[low]` `[patch]` com_content_hash format was checked only for the pinned supersession source — the format check now covers any superseding record, and hash_only superseding records must carry a hash.
  - `[low]` `[patch]` Receipts could omit com_before_state/com_after_state/com_evidence_refs/com_decision_rationale (only the supersede receipt's values were pinned) — all four added to required receipt fields.
  - `[low]` `[patch]` sourceUpdatesDeferred entries naming unknown or misspelled sources passed — entries must now name a known prior or superseding source.
  - `[low]` `[patch]` workItemStateChangesDeferred entries with a missing workItem field passed anonymously — the field is now required.
  - `[low]` `[patch]` The slice's flagMechanism claimed the flag "is surfaced as the Council Queue drift indicator," a surface this slice does not touch — reworded to intended-once-that-surface-lands with an explicit no-app-curation note.

### 2026-07-13 — Review pass (follow-up)

- intent_gap: 0
- bad_spec: 0
- patch: 14: (high 0, medium 4, low 10)
- defer: 1: (high 0, medium 0, low 1)
- reject: 10: (high 0, medium 0, low 10)
- addressed_findings:
  - `[medium]` `[patch]` Receipts were unmoored from drift evidence — a fabricated third `source_drifted` receipt with its own `drift_evidence` link validated green; receipts must now correspond one-to-one with drift events plus supersessions.
  - `[medium]` `[patch]` Receipt-source links and deferred source updates could bind any known prior source — both are now restricted to sources that drifted, were superseded, or supersede in this slice.
  - `[medium]` `[patch]` The prior-rationale restatement tripwire was ordinal case-sensitive raw-text matching, so a case or whitespace tweak evaded it — matching is now whitespace-normalized and case-insensitive.
  - `[medium]` `[patch]` Cross-slice timestamp ordering and priorEvidence echo equality round-tripped prior-side values through culture-sensitive string casts, giving engine-dependent verdicts (pwsh 7 auto-parses JSON datetimes, Windows PowerShell 5.1 keeps strings) — a `Get-ComparableInstant` helper now normalizes both engines to instant comparisons.
  - `[low]` `[patch]` priorEvidence was audited only when the prior slice recorded no version ref — mutation-field and echo checks (now including `com_source_version_ref`) run whenever priorEvidence is present.
  - `[low]` `[patch]` The drift receipt's before/after states were unpinned, so a bare held→superseded status transition passed — drift receipt states must record version evidence, not bare extraction-status values, and after_state must carry the newly observed version ref.
  - `[low]` `[patch]` Flag eligibility, unaffected-note relevance, and the flagged-or-cleared coverage sweep read only `com_primary_source_record` — all three now also traverse 1.3/1.4 `workItemSourceLinks` so non-primary-role items cannot escape review coverage (with load tripwires for both link collections).
  - `[low]` `[patch]` Duplicate workItemsUnaffected entries passed — duplicates are now a named violation.
  - `[low]` `[patch]` A superseding record could claim extraction status `extracted`/`held` for extraction that never ran — it must now start as `new`.
  - `[low]` `[patch]` The superseding record's `com_observed_modified_at` was format-checked only — it must now be later than the superseded record's capture time.
  - `[low]` `[patch]` Divergent duplicate prior Source Records across sibling slices resolved first-wins silently — divergence is now a named violation.
  - `[low]` `[patch]` Required receipt fields were a hardcoded list that would not track the manifest — they are now derived from manifest `com_councilreceipt` required columns (with a derivation tripwire) plus the story's pinned extras.
  - `[low]` `[patch]` `com_policy_flags`, `driftKind`, and `supersededRecordDisposition` were decorative — policy flags are required and must declare `local_contract_evidence_only` and `no_tenant_write`; the other two must be non-empty.
  - `[low]` `[patch]` The spec's verification command globbed for scratchpad pwsh in a way that breaks when multiple installs match — pinned to the first match with proper quoting.

## Design Notes

- Receipts are sanctioned in this slice (unlike 1.3/1.4) because drift receipts are the story's deliverable; they are local contract evidence, not a live ledger — Epic 2 (Story 2.3) owns live receipt-backed mutation, so every live apply stays deferred.
- Host is Linux without system PowerShell; canonical suite runs on Windows. Portable pwsh 7.4.6 works (proven in 1.4). Keep the suite step spelled `powershell`. Two pre-existing suite steps ("Epics placeholder check", stale-gate `rg` check) fail on Linux only — out of scope; do not "fix" them.
- `state-transition-demo-evidence.json` has a UTF-8 BOM: PowerShell `Get-Content -Raw | ConvertFrom-Json` handles it natively; do not strip the file.
- Mutation negative tests run against temp copies in the scratchpad, never against committed artifacts.

## Verification

**Commands:**
- `PW=$(command -v pwsh || ls -1 /tmp/claude-1000/*/*/scratchpad/pwsh/pwsh 2>/dev/null | head -1); "$PW" -NoProfile -File _bmad-output/implementation-artifacts/source-drift-supersession-slice-validate.ps1` -- expected: exit 0, `SOURCE_DRIFT_SUPERSESSION_SLICE_VALIDATE_OK` (the `head -1` guards against multiple scratchpad pwsh installs; if no pwsh anywhere: download portable `powershell-7.4.6-linux-x64.tar.gz` from PowerShell GitHub releases into the scratchpad, `chmod +x pwsh`)
- `$PW -NoProfile -File _bmad-output/implementation-artifacts/zero-multi-item-extraction-slice-validate.ps1` and `…/proposed-work-item-extraction-slice-validate.ps1` -- expected: both markers print (no 1.3/1.4 regression)
- Negative test: copy slice + validator to scratchpad, mutate per the I/O matrix, run validator with `-DriftSlicePath` (or equivalent param) at the mutated copy -- expected: exit 1, violation named
- `git diff --check` -- expected: clean; and `git status` shows no modification to any 1.1–1.4 slice or validator
- Full-suite spot check (Linux): run `council-mvp-local-validate.ps1` under pwsh with a `powershell`→pwsh shim on PATH -- expected: the new "Source drift and supersession slice validation" step prints its marker before the known Linux-only `rg` failure in "Epics placeholder check"

**Manual checks (if no CLI):**
- Confirm `sprint-status.yaml` keeps exactly 5 epics, 25 stories, 5 retrospectives, and story 1-5 reads `in-progress` (lifecycle value beyond that is orchestrator-owned).

## Auto Run Result

**Summary:** Story 1.5 implemented via the established Epic 1 local-contract pattern: a story-keyed drift/supersession slice proves (a) version drift on the Work-Item-producing meeting source `CSR-MANUAL-MEETING-001` — new source version reference, sha256 content hash, and observed-modified time, backed by drift receipt `CR-LOCAL-DRIFT-001` (verb `source_drifted`) bound by a `drift_evidence` link, with a targeted review flag on `CWI-LOCAL-MEETING-ACTION-001` only and explicit unaffected notes for the other two 1.4 items — and (b) supersession of the held Outlook thread mock `CSR-OUTLOOK-THREAD-MOCK-001` by embedded record `CSR-OUTLOOK-THREAD-MOCK-002` via `com_parent_ref`, backed by receipt `CR-LOCAL-SUPERSEDE-001`, with the prior record's `superseded` status recorded only as a receipt-gated deferred update. Prior rationale and receipts stay byte-identical in their own slices; receipts here are local contract evidence only, and every live mutation stays gated to Epic 2 Story 2.3. A validator enforces the contract against the Dataverse manifest and is wired into the canonical suite. The review pass hardened the validator with 17 patches (content-hash drift equality, drift-path rationale restatement protection, superseded-source review coverage, supersession temporal ordering, priorEvidence cross-checks, decisionPolicy enforcement, offset-required timestamps, per-collection load tripwires, and more) without changing the slice's evidentiary content beyond one flagMechanism honesty reword. An independent follow-up review pass (four fresh layers against the full diff) then applied 14 further validator-hardening patches — most notably receipt↔drift-evidence one-to-one mooring, drift-scoped receipt-source links and deferred updates, a case/whitespace-insensitive restatement tripwire, engine-independent timestamp comparisons, workItemSourceLinks-aware review coverage, and manifest-derived required receipt fields — again with zero changes to the slice's evidentiary content.

**Files changed:**
- `_bmad-output/implementation-artifacts/source-drift-supersession-slice.json` — new story 1.5 slice: guards, drift event, supersession with embedded superseding record, two receipts, three drift_evidence links, targeted review flag plus unaffected notes, deferred source/work-item mutations, acceptance mapping for both epic ACs.
- `_bmad-output/implementation-artifacts/source-drift-supersession-slice-validate.ps1` — new validator mirroring the 1.4 hardening; further hardened by the 17 first-pass and 13 follow-up-pass review patches in the Review Triage Log; prints `SOURCE_DRIFT_SUPERSESSION_SLICE_VALIDATE_OK`.
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1` — new suite step "Source drift and supersession slice validation" after the 1.4 step, echoing child output before the exit-code check.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story 1-5 `backlog` → `in-progress`; both `last_updated` occurrences refreshed; counts stay 5 epics / 25 stories / 5 retrospectives (further lifecycle movement is orchestrator-owned).
- `_bmad-output/implementation-artifacts/deferred-work.md` — two new entries: the committed-negative-test-harness gap extended to the 1.5 validator (first pass), and the latent `.Contains` property-name substring defect in the four 1.1–1.4 validators (follow-up pass).
- `_bmad-output/implementation-artifacts/spec-1-5-handle-source-drift-and-supersession.md` — this spec (follow-up pass also fixed the fragile scratchpad-pwsh glob in the Verification commands).

**Review findings breakdown:** Two passes, four layers each (adversarial, edge-case, verification-gap, intent-alignment). First pass: 0 intent gaps, 0 bad_spec; 17 patches applied (3 medium, 14 low — see Review Triage Log); 1 deferred (negative-harness scope extension to the 1.5 validator); 8 rejected. Follow-up pass: 0 intent gaps, 0 bad_spec; 14 patches (4 medium, 10 low — see the follow-up Review Triage Log entry); 1 deferred (the latent `.Contains` substring property check in the 1.1–1.4 validators, unfixable here because the spec freezes those files); 10 rejected. Follow-up rejects were: the `superseding` work-item-source role tripwired but unexercised (the tripwire is the intent's Block-If vocabulary gate, not fabricated evidence); spec/sprint-status lifecycle wording versus the working tree's `done` flip and the stale `last_updated` on that flip (orchestrator-owned write-backs, disclosed in Residual risks); mock scenario timestamps postdating authoring time and `com_captured_by: Doug` (fictional scenario times consistent with the 1.1–1.4 mock convention; all intent-required orderings are enforced); single-use pinned validator and synthetic hashes (intent-sanctioned pattern, rejected in the first pass on the same authority); the committed-negative-harness gap re-raised by two layers (real, but already tracked as ledger entries — per the orchestrator's instruction existing entries were not re-opened or duplicated); suite-step copy-paste accretion (established convention; a shared helper would touch prior stories' wiring); the never-executed Windows PowerShell 5.1 branch (disclosed residual risk, further mitigated by the engine-independent instant comparisons); and the live-system reading of the intent (sanctioned local-evidence surface, disclosed via acceptanceMapping.tenantEvidenceRequired). Rejects were: the supersede receipt's before/after modeling (explicitly disclosed local-evidence shape mandated by the intent contract), synthetic hashes not individually marked (the artifact is globally marked local-contract evidence), hard-coded scenario pinning and validator duplication (the intent-sanctioned Epic 1 story-slice pattern), drift/supersession verb indistinguishability (manifest vocabulary change is Block-If gated), runId collision with 1.1/1.2/demo artifacts (no such runIds exist), spec style/oversized complaints (workflow-declared), empty-path-parameter crash (impossible-state cosmetic), and the intent audit's live-system/executable-logic readings (the local-contract reading is mandated by the epic's tenant gates and the 1.1–1.4 convention, and the divergence is disclosed in-artifact via acceptanceMapping.tenantEvidenceRequired).

**Verification (portable pwsh 7.4.6 on Linux; canonical suite is Windows):** story validator exit 0 + marker on the committed slice (re-verified after every patch); 20 mutation probes each exit 1 naming the violation — 6 from the implementation pass, 3 from the spec's acceptance criteria (strict-bool string `"true"`, unknown drift source, in-slice state change), and 11 targeting the new hardening checks (identical-hash supersession, restated drift rationale, superseding record predating the superseded one, string decision-policy value, offset-less timestamp, missing before-state, missing superseding link, unknown deferred source, missing driftRun, unrelated unaffected item, priorEvidence mismatch); 1.3 and 1.4 validators unchanged and passing; full suite under a `powershell`→pwsh shim passes the new step and every subsequent validator step until the pre-existing Linux-only `rg` backslash-path failure in "Epics placeholder check" (passes on Windows); `git diff --check` clean; sprint status keeps 5/25/5. Follow-up pass: validator exit 0 + marker re-confirmed on the committed slice after all 13 validator patches; 18 fresh mutation probes each exit 1 naming the violation — phantom third receipt, link bound to an unrelated known source, case-tweaked rationale restatement, duplicate unaffected note, priorEvidence false echo on a version-ref-carrying source, drift receipt claiming a held→superseded transition, superseding record claiming `extracted` status, superseding observed-modified-at predating the superseded capture, dropped/missing policy flags (2), missing driftKind, missing supersededRecordDisposition, deferred update naming an unrelated source, divergent duplicate prior record across sibling-slice copies, a non-primary `supporting` link escaping review coverage, and re-runs of the 3 acceptance-criteria probes; 1.3/1.4 validators re-verified passing and the full suite re-run to the same known Linux-only stop; `git diff --check` clean.

**Residual risks:** The authoritative full-suite proof remains a Windows run of `council-mvp-local-validate.ps1`; the Windows PowerShell 5.1 string-branch of the timestamp handling has never executed on this Linux host, though the follow-up pass's `Get-ComparableInstant` normalization makes both engine branches converge on instant semantics by construction. The slice is hand-authored contract evidence, not runtime drift detection — consistent with stories 1.1–1.4; live drift detection, version-ref application, `superseded` status moves, Work Item review surfacing in the Council Queue, and receipt-backed state changes all remain gated (Epic 2 Story 2.3 receipts, Epic 5 tenant readiness). The validator's failure paths are probe-verified in-session only (38 probes across both passes); the committed negative-test harness remains deferred (ledger entries 3 and 4). The spec's post-commit frontmatter finalization (final_revision, status) is a workflow write-back that lands in the working tree after the story commit, mirroring how story 1.4's lifecycle flip was handled; it is orchestrator-owned from there — the working tree's sprint-status `1-5: done` flip and its `last_updated` value are likewise orchestrator-owned and were left untouched by this pass.
