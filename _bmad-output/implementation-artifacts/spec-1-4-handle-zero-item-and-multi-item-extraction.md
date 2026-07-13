---
title: 'Story 1.4: Handle Zero-Item and Multi-Item Extraction'
type: 'feature'
created: '2026-07-13'
status: 'done'
baseline_revision: 'e3690ae04d6805210321f29e649b61b3c2c432e2'
final_revision: 'b9368218b4a7c2ff4a8442c761db64d9ea20edf1'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
warnings: [oversized]
---

<intent-contract>

## Intent

**Problem:** Story 1.3 proved one-source-one-item extraction, but nothing yet proves the other cardinalities the contract demands (FR5): a Source Record with no actionable work must be markable `ignored`/`held` with rationale instead of spawning a filler Work Item, and a Source Record with multiple distinct commitments must yield multiple proposed Work Items each with its own rationale, confidence, type, and source link (FR7, NFR14).

**Approach:** Follow the established Epic 1 local-contract pattern: add a story-keyed JSON extraction slice proving zero-item and multi-item outcomes against the Dataverse manifest vocabulary, add a PowerShell validator with a success marker, wire it into `council-mvp-local-validate.ps1`, and mark story 1-4 in-progress in sprint status. Live tenant mutation of Source Record extraction status stays receipt-gated (Epic 2) and is recorded as deferred, exactly as story 1.3 did.

## Boundaries & Constraints

**Always:**
- All proposed Work Items stay `com_state_group: proposed`, `com_approval_required: true`, `com_auto_creation_policy_result: proposal_only` (or `not_evaluated`).
- Council identity only: `CWI-*` Work Item IDs, `CSR-*` Source Record IDs; never Dataverse/Graph/source IDs as product identity.
- Zero-item outcomes use only `ignored` or `held` (both already in the manifest `com_extractionstatus` choice) and each carries a non-empty rationale.
- A source with a zero-item outcome must have zero proposed Work Items in the slice.
- Each multi-item Work Item carries its own `extraction_rationale`, `extraction_confidence`, `type_confidence`, `source_identification_confidence`, `uncertainty`, and its own primary Work Item Source link.
- Source Records and Work Items remain separate objects; status mutations are recorded as deferred (receipt-gated to Epic 2), not performed.

**Block If:** Any step would require a live Dataverse write, live Outlook/Graph read, or a change to `dataverse-mvp-schema-manifest.json` (the needed vocabulary already exists — if it turns out it doesn't, that is a human decision).

**Never:** No receipts created; no outbound action, flows, agents, or app registrations; no edits to the 1.1/1.2/1.3 slice JSONs or their validators; no marking of live tenant records; no claiming tenant-verified behavior from local JSON validation.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Zero-item, ignorable | Existing sample `CSR-MANUAL-LINK-001` (no actionable work) | Zero-item outcome entry: `ignored` + rationale; no Work Item for this source | No error expected |
| Zero-item, undecidable | Existing sample `CSR-OUTLOOK-THREAD-MOCK-001` (mock, unverified) | Zero-item outcome entry: `held` + rationale; no Work Item for this source | No error expected |
| Multi-item | New embedded sample source `CSR-MANUAL-MEETING-001` (meeting note with ≥3 distinct commitments/decisions/risks, `summary_allowed`) | ≥3 proposed Work Items of ≥2 distinct types (e.g. `meeting_action`, `decision`, `risk`), each with own rationale/confidences/link | No error expected |
| Slice violates contract | A proposed item references a zero-item source, lacks a required field, duplicates an ID, or uses a status outside `ignored`/`held` | Validator lists the issue and exits 1 | Validator prints issue list, no success marker |
| Valid slice | Complete 1.4 slice + manifest | Validator prints `ZERO_MULTI_ITEM_EXTRACTION_SLICE_VALIDATE_OK`, exit 0 | n/a |

</intent-contract>

## Code Map

Read-only references (do not edit):
- `_bmad-output/implementation-artifacts/proposed-work-item-extraction-slice.json` -- story 1.3 slice; copy its item/link/guard/deferred-update field shape exactly
- `_bmad-output/implementation-artifacts/proposed-work-item-extraction-slice-validate.ps1` -- validator to mirror in structure, param style (`$PSScriptRoot`-relative paths), and check style
- `_bmad-output/implementation-artifacts/manual-source-record-slice.json` -- known manual `CSR-*` IDs + required source-record field list
- `_bmad-output/implementation-artifacts/outlook-source-reference-slice.json` -- known Outlook mock `CSR-*` IDs
- `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json` -- choice vocabularies: `com_extractionstatus` (`ignored`, `held`), `com_workitemtype`, `com_riskclass`

Files to change:
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1` -- aggregate suite; new step goes right after the "Proposed Work Item extraction slice validation" step (lines 81–90)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` -- story status tracker; `1-4-…: backlog` at line 55

## Tasks & Acceptance

**Execution:**
- `_bmad-output/implementation-artifacts/zero-multi-item-extraction-slice.json` -- create story-1.4 slice: `storyKey: 1-4-handle-zero-item-and-multi-item-extraction`; guards matching 1.3 plus `noWorkItemCreatedForZeroItemSources: true`; an `extractionRun` (new local runId, semanticContractVersion `2026-07-07`) containing (a) `zeroItemOutcomes` for `CSR-MANUAL-LINK-001` → `ignored` and `CSR-OUTLOOK-THREAD-MOCK-001` → `held`, each with rationale, extraction confidence, and a note that no Work Item was created; (b) one embedded sample Source Record `CSR-MANUAL-MEETING-001` (same field shape as 1.1 samples, `com_data_boundary_policy: summary_allowed`, `com_extraction_status: new`) whose summary states three distinct commitments; (c) ≥3 proposed Work Items from that source with ≥2 distinct `com_type` values, full 1.3 field set per item; (d) one primary `workItemSourceLinks` entry per item with own rationale + confidence; (e) `sourceUpdatesDeferred` entries stating extraction-status mutation is receipt-gated; (f) `acceptanceMapping` for both epic ACs -- proves both cardinalities without tenant writes
- `_bmad-output/implementation-artifacts/zero-multi-item-extraction-slice-validate.ps1` -- create validator mirroring the 1.3 validator: verifies storyKey, guards, zero-item outcomes (known source IDs, status ∈ {`ignored`,`held`} and present in manifest `com_extractionstatus`, non-empty rationale, zero proposed items referencing those sources), embedded meeting source (required source-record fields, `CSR-*` ID), multi-item items (≥3, unique `CWI-*` IDs, ≥2 distinct valid types, valid risk classes, `proposed` state, approval required, `proposal_only`/`not_evaluated`, confidences in [0,1], all per-item rationale/uncertainty fields non-empty), one primary link per item with rationale, no receipt fields, acceptance mapping for ACs 1–2; prints `ZERO_MULTI_ITEM_EXTRACTION_SLICE_VALIDATE_OK` on success, lists issues and exits 1 on failure -- makes the contract enforceable
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1` -- insert step "Zero/multi-item extraction slice validation" immediately after the "Proposed Work Item extraction slice validation" step, using the identical `& powershell … -File` + marker-match pattern -- wires the story into the canonical suite
- `_bmad-output/implementation-artifacts/sprint-status.yaml` -- set `1-4-handle-zero-item-and-multi-item-extraction: in-progress`; update both `last_updated` occurrences to the current datetime -- keeps the tracker honest (counts must stay 5 epics / 25 stories / 5 retrospectives)

**Acceptance Criteria:**
- Given the 1.4 slice and manifest, when the story validator runs, then it exits 0 and prints `ZERO_MULTI_ITEM_EXTRACTION_SLICE_VALIDATE_OK`.
- Given a Source Record listed in `zeroItemOutcomes`, when the slice is inspected, then that record is marked `ignored` or `held` with rationale and no proposed Work Item in the slice references it as primary source.
- Given the multi-item source `CSR-MANUAL-MEETING-001`, when the slice is inspected, then ≥3 proposed Work Items of ≥2 distinct types reference it, each carrying its own rationale, confidence fields, type, and its own primary source link.
- Given a copy of the slice mutated to break the contract (a proposed item pointing at a zero-item source, or a zero-item outcome status of `extracted`), when the validator runs against the mutated copy, then it exits 1 and names the violation.
- Given the aggregate suite runs, when it reaches the new step, then the new step passes; the previously-passing 1.3 extraction validator still passes unchanged.

## Spec Change Log

## Review Triage Log

### 2026-07-13 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 10: (high 0, medium 3, low 7)
- defer: 3: (high 0, medium 0, low 3)
- reject: 5: (high 0, medium 0, low 5)
- addressed_findings:
  - `[medium]` `[patch]` Validator checked only 7 of the slice's 9 declared guards, so flipping `dataverseRowsNotUsedAsCouncilIdentity`/`meaningGraphDoesNotOwnWorkflowState` to false still passed — now iterates every declared guard and requires the 7 mandatory names to exist.
  - `[medium]` `[patch]` Owner fields unenforced (`com_owner_candidate`, `com_owner_candidate_confidence`, `com_policy_flags` absent from required list; owner confidence never range-checked) — added to required fields with [0,1] TryParse range check.
  - `[medium]` `[patch]` No cross-slice Council-ID uniqueness: a `CWI-*` ID colliding with story 1.3's slice, or an embedded `CSR-*` colliding with 1.1/1.2 samples, validated green — validator now loads the 1.3 slice and flags CWI collisions, embedded-CSR collisions, and intra-slice embedded duplicates.
  - `[low]` `[patch]` Non-numeric confidence values and null IDs crashed the validator with raw exceptions instead of named violations — all `[decimal]` casts replaced with TryParse helper; null-key guards around `ContainsKey`; null-array guards on all extraction-run collections.
  - `[low]` `[patch]` `com_urgency` was unvalidated free text although the manifest's `com_councilworkitem.com_urgency` column defines choice values — now validated against the column's inline vocabulary.
  - `[low]` `[patch]` New suite step threw on failure before echoing the child validator's output, swallowing the issue list — output now prints before the exit-code check (new step only; siblings deferred).
  - `[low]` `[patch]` Acceptance-mapping check was presence-only — now requires non-empty `localEvidence` and `tenantEvidenceRequired` per criterion.
  - `[low]` `[patch]` Duplicate/contradictory `zeroItemOutcomes` for one source validated green — duplicate sourceRecord entries now flagged.
  - `[low]` `[patch]` Receipt-field sniffing covered only proposed items — extended to the extraction run, zero-item outcomes, and source links (exact-name checks, so `receiptCreationDeferredToStory2` in decisionPolicy stays legal).
  - `[low]` `[patch]` Embedded meeting source inlined the full summary into `com_content_snapshot_ref` (a ref field) and its `com_captured_at` predated the meeting it summarizes — ref is now a token, the three commitments moved into `com_source_to_work_item_rationale` (validator requires all three stated), and capture time follows the sync.

### 2026-07-13 — Review pass

- intent_gap: 0
- bad_spec: 0
- patch: 12: (high 0, medium 2, low 10)
- defer: 0
- reject: 11: (high 0, medium 0, low 11)
- addressed_findings:
  - `[medium]` `[patch]` sprint-status showed 1-4 `done` while the spec's Verification prose still claimed the story "stays `in-progress`" — the flip is the loop orchestrator's post-completion lifecycle action (an uncommitted working-tree change made after commit fbf9037), not an implementation deviation; spec prose updated to state the tracker value is orchestrator-owned, tracker value left untouched.
  - `[medium]` `[patch]` A zero-item outcome naming a source Story 1.3 already extracted from validated green, letting the suite assert contradictory outcomes (`extracted` vs `ignored`/`held`) for one source — validator now loads 1.3's extracted-from sources and flags the contradiction.
  - `[low]` `[patch]` Type-coerced booleans accepted: string `"true"` passed the guard, `com_approval_required`, and `workItemCreated` checks via PowerShell comparison coercion — all three now require strict `[bool]` values.
  - `[low]` `[patch]` Missing manifest vocabularies decayed misleadingly (a missing `com_urgency` column yielded `@($null)`, flagging every urgency invalid; other missing choice sets no-oped silently) — helpers now null-filter and all seven loaded vocabularies assert non-empty with a named issue.
  - `[low]` `[patch]` Cross-slice reference lists (1.1/1.2 source IDs, 1.3 Work Item IDs) silently became empty if sibling slices restructure, no-oping collision checks while exiting 0 — non-empty tripwires added.
  - `[low]` `[patch]` Deferred-update enforcement was hardcoded to the zero-item sources plus the meeting source, so a new extracted-from source needed no `sourceUpdatesDeferred` entry — the required set is now derived from zero-item plus extracted-from sources.
  - `[low]` `[patch]` Three multi-item Work Items sharing one `extraction_rationale` text satisfied the "own rationale" contract — distinct rationale texts now required across the multi-item set.
  - `[low]` `[patch]` Item-level `com_semantic_contract_version` was only presence-checked while the run-level field was pinned — items now pinned to `2026-07-07` as well.
  - `[low]` `[patch]` Unparseable JSON inputs crashed with a raw exception instead of the issue-list contract — all five loads wrapped; named violation plus exit 1.
  - `[low]` `[patch]` Extraction from a source whose data boundary policy is `unknown` validated green despite the epic contract blocking it — each proposed item's primary-source policy is now checked.
  - `[low]` `[patch]` Embedded source `com_captured_at` accepted any non-empty text despite the ISO 8601 contract — `[datetimeoffset]` TryParse check added.
  - `[low]` `[patch]` Receipt sniffing missed the manifest's real receipt columns — `com_receipt` and `com_receipt_id` added to the exact-name list.

## Design Notes

- This host is Linux without system PowerShell; the canonical suite runs on Doug's Windows machine. Portable pwsh 7.4.6 works: existing story validators (`$PSScriptRoot`-relative backslash paths) pass under it, verified this session. Keep the wired suite step spelled `powershell` (Windows convention, matching every sibling step).
- Two pre-existing suite steps ("Epics placeholder check", stale-gate `rg` check) fail on Linux only because `rg` receives backslash path literals — out of scope; do not "fix" them.
- The mutated-copy negative test runs against temp copies in the scratchpad, never against the committed slice.

## Verification

**Commands:**
- `PW=$(command -v pwsh || echo /tmp/claude-1000/*/*/scratchpad/pwsh/pwsh); $PW -NoProfile -File _bmad-output/implementation-artifacts/zero-multi-item-extraction-slice-validate.ps1` -- expected: exit 0, `ZERO_MULTI_ITEM_EXTRACTION_SLICE_VALIDATE_OK` (if no pwsh anywhere: download portable `powershell-7.4.6-linux-x64.tar.gz` from the PowerShell GitHub releases into the scratchpad, `chmod +x pwsh`)
- `$PW -NoProfile -File _bmad-output/implementation-artifacts/proposed-work-item-extraction-slice-validate.ps1` -- expected: `PROPOSED_WORK_ITEM_EXTRACTION_SLICE_VALIDATE_OK` (no 1.3 regression)
- Negative test: copy slice + validator to scratchpad, mutate the copy per the I/O matrix, run validator with `-ExtractionPath` (or equivalent param) pointing at the mutated copy -- expected: exit 1, violation named
- `git diff --check` -- expected: clean
- Full-suite spot check (Linux): run `council-mvp-local-validate.ps1` under pwsh with a `powershell`→pwsh shim on PATH -- expected: the new "Zero/multi-item extraction slice validation" step prints its marker before the suite hits the known Linux-only `rg` failure in "Epics placeholder check"

**Manual checks (if no CLI):**
- Confirm `sprint-status.yaml` still has exactly 5 epics, 25 stories, 5 retrospectives. Story 1-4's lifecycle value is orchestrator-owned: the implementation set it `in-progress`; the loop orchestrator advanced it to `done` after the first review pass completed.

## Auto Run Result

**Summary:** Story 1.4 implemented via the established Epic 1 local-contract pattern: a story-keyed extraction slice proves zero-item outcomes (`CSR-MANUAL-LINK-001` → `ignored`, `CSR-OUTLOOK-THREAD-MOCK-001` → `held`, each with rationale and no Work Item) and multi-item extraction (embedded meeting source `CSR-MANUAL-MEETING-001` → 3 proposed Work Items of 3 distinct types, each with its own rationale, confidences, type, and primary source link). A validator enforces the contract against the Dataverse manifest vocabulary and is wired into the canonical suite. Live extraction-status mutation stays receipt-gated to Epic 2 and is recorded as deferred; nothing claims tenant-verified behavior. A follow-up review pass (second pass, same date) hardened the validator further — strict boolean enforcement, cross-slice zero-vs-extracted contradiction detection, manifest/reference decay tripwires, named-violation JSON parse handling, unknown-boundary-policy extraction blocking, ISO 8601 timestamp checking, derived deferred-update coverage, distinct per-item rationales, item-level contract-version pinning, and manifest-real receipt-column sniffing — without changing the slice data, the suite wiring, or any 1.1–1.3 artifact.

**Files changed:**
- `_bmad-output/implementation-artifacts/zero-multi-item-extraction-slice.json` — new story 1.4 slice: guards, zero-item outcomes, embedded multi-commitment meeting source, 3 proposed Work Items + primary links, deferred status updates, acceptance mapping. Unchanged by the follow-up pass.
- `_bmad-output/implementation-artifacts/zero-multi-item-extraction-slice-validate.ps1` — new validator; hardened across two review passes (pass 1: all-guards iteration, TryParse confidence checks, null guards, owner/urgency/policy-flag enforcement, cross-slice CWI/CSR uniqueness, duplicate-outcome detection, receipt sniffing on all collections, non-empty acceptance evidence; pass 2: the twelve patches in the second Review Triage Log entry); prints `ZERO_MULTI_ITEM_EXTRACTION_SLICE_VALIDATE_OK`.
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1` — new suite step after the 1.3 extraction step; echoes child output before the exit-code check so failure diagnostics survive.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story 1-4 `backlog` → `in-progress` by the implementation; subsequently advanced `in-progress` → `done` by the loop orchestrator after the first pass completed (that working-tree flip is committed with this pass; the lifecycle value is orchestrator-owned).
- `_bmad-output/implementation-artifacts/epic-1-context.md` — compiled epic 1 planning context (workflow artifact).
- `_bmad-output/implementation-artifacts/deferred-work.md` — ledger with 3 deferred findings from the first pass; the follow-up pass added none.
- `_bmad-output/implementation-artifacts/spec-1-4-handle-zero-item-and-multi-item-extraction.md` — this spec.

**Review findings breakdown:** Two passes, each with 4 review layers (adversarial, edge-case, verification-gap, intent-alignment). Pass 1: 10 patches (3 medium, 7 low), 3 deferred to `deferred-work.md`, 5 rejected. Pass 2 (this run): 12 patches (2 medium, 10 low — see second Review Triage Log entry), 0 new deferrals, 11 rejected. Two pass-2 re-flags (no committed negative-test harness; sibling suite steps swallow failure output) duplicated existing ledger entries 3 and 1 and were not re-appended, per the orchestrator's instruction that existing ledger entries stay untouched. Remaining rejects were noise: complaints against the intent-sanctioned local-contract pattern itself, semantic-prose validation asks, cosmetic diagnostic wording on impossible states, ledger-format and workflow-frontmatter critiques, and the acknowledged Windows-run residual. No intent gaps; no spec re-derivation needed in either pass.

**Verification (follow-up pass, portable pwsh 7.4.6 on Linux; canonical suite is Windows):** story validator exit 0 + marker on the committed slice; 1.3 validator unchanged and passing; 13 new mutation probes (guard as string `"true"`, zero-item outcome contradicting a 1.3-extracted source, `workItemCreated` as string, `com_approval_required` as string, item-level contract version drift, duplicated `extraction_rationale`, extracted-from source without a deferred-update entry, `com_receipt` field present, non-ISO `com_captured_at`, `unknown` data boundary policy, manifest missing the urgency vocabulary, 1.3 slice with no Work Items, syntactically invalid JSON input) each exit 1 naming the violation; full suite under a `powershell`→pwsh shim passes the new step and every subsequent validator step until the pre-existing Linux-only `rg` backslash-path failure in "Epics placeholder check" (passes on Windows); `git diff --check` clean; sprint status keeps 5 epics / 25 stories / 5 retrospectives.

**Residual risks:** The authoritative full-suite proof remains a Windows run of `council-mvp-local-validate.ps1`. The slice is hand-authored contract evidence, not a runtime extraction — consistent with stories 1.1–1.3; runtime behavior and tenant persistence stay gated (Epic 2 receipts, Epic 5 tenant readiness). The validator's failure paths are probe-verified in-session only; the committed negative-test harness remains deferred (ledger entry 3). Story 1-4's sprint-status lifecycle value is orchestrator-owned and reads `done`.
