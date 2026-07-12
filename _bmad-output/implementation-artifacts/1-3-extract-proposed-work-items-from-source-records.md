---
baseline_commit: d7cc29a57621c435a61a181ef6724b9fb0b0f1ec
---

# Story 1.3: Extract Proposed Work Items From Source Records

Status: in-progress

<!-- Generated from bmad-create-story context on 2026-07-08, then advanced through the local and scoped live Dataverse implementation path. Broader approvals and outbound actions remain gated. -->

## Story

As Doug,
I want the Council to propose Work Items from a Source Record with rationale and confidence,
so that I can decide whether a source should become executable work.

## Acceptance Criteria

1. Given a Source Record exists, when extraction runs, then the system must produce zero, one, or many proposed Work Items, and each proposed Work Item must include type, summary, extraction rationale, confidence, uncertainty, suggested owner, urgency, risk class, and recommended next action.
2. Given a proposed Work Item is created, when it is persisted, then it must reference the primary Source Record, and it must preserve Council-level identity separate from Microsoft or Dataverse row identifiers.

## Tasks / Subtasks

- [x] Confirm story gates before implementation.
  - [x] Verify Dataverse write approval, tenant preflight, source body policy, publisher prefix, model-driven app acceptance, and approval/receipt boundaries before any live tenant write.
  - [x] If approval is not present, keep work local to story, manifest, validation, and mock extraction artifacts.
- [x] Define the proposed Work Item extraction slice.
  - [x] Use `Council Work Item` / `com_councilworkitem`; do not create source-specific task tables.
  - [x] Use stable `CWI-*` Council Work Item IDs instead of Source Record, Graph, Outlook, or Dataverse row IDs.
  - [x] Include type, summary, state group, owner candidate, owner confidence, urgency, risk class, confidence summary, primary source, rationale, recommended next action, approval required, semantic contract version, auto-creation policy result, and policy flags.
  - [x] Include separate extraction rationale, extraction confidence, type confidence, source identification confidence, and uncertainty fields in the local slice proof.
- [x] Preserve Source Record / Work Item separation.
  - [x] Use existing manual and Outlook Source Record sample IDs as primary source references.
  - [x] Add Work Item Source link examples instead of embedding Source Records inside Work Items.
  - [x] Keep source extraction status updates deferred until receipt-backed mutation stories.
- [x] Enforce proposal-only behavior.
  - [x] Keep all examples in `proposed` state.
  - [x] Require human approval before execution.
  - [x] Do not create receipts, graph edges, external actions, or approved work in this story.
- [ ] Configure tenant persistence after write approval.
  - [x] Persist proposed Work Items in the target Dataverse environment only after read-only preflight, completed decision packet, write approval, and publisher/source-body decisions.
  - [x] Persist Work Item Source links so each proposed Work Item has auditable source provenance.
  - [ ] Confirm proposed items appear in Council Queue views without creating outbound action.
- [x] Strengthen validation around this slice.
  - [x] Add a local proposed Work Item extraction slice validator.
  - [x] Wire the validator into `council-mvp-local-validate.ps1`.
  - [x] Run required local validation before committing.

## Dev Notes

### Product and Architecture Guardrails

- BMAD is the delivery harness, not the product runtime. Keep all product semantics in Council contracts and implementation artifacts. [Source: `_bmad-output/project-context.md#Technology-Stack-&-Versions`]
- The product is work-item-first, but Source Records precede Work Items. Extraction is explicit; Source Records never become Work Items by mutation. [Source: `_bmad-output/project-context.md#Source-and-Provenance-Rules`; `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/source-record-contract.md#Invariant`]
- A Work Item is the canonical execution shell. Variation belongs in `type`, linked context, approval requirements, and receipts. [Source: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/ARCHITECTURE-SPINE.md#AD-3---Work-Item-is-the-canonical-execution-shell-ADOPTED`]
- Proposed is not approved for execution. Decision, delegation, risk, sensitive, governance, tenant-affecting, or outbound work remains proposed until human approval. [Source: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/work-item-receipt-contract.md#State-Rules`; `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/auto-creation-policy.md#Default-Rule`]
- Receipts are required for meaningful mutations, but Story 1.3 stops before receipt creation. Receipt-backed proposal/state movement belongs to later Epic 2 stories. [Source: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/work-item-receipt-contract.md#Mutation-Rules`]

### Dataverse Slice

The existing manifest already contains the tables needed for Story 1.3:

| Table | Story use |
| --- | --- |
| `com_councilsourcerecord` | Input Source Records from Story 1.1 and Story 1.2 local samples. |
| `com_councilworkitem` | Proposed Work Item shell with stable Council ID, type, state, rationale, confidence, primary source, and approval requirement. |
| `com_councilworkitemsource` | Provenance links from Work Items to Source Records. |

Key Work Item fields for this story:

| Column | Requirement |
| --- | --- |
| `com_council_work_item_id` | Stable `CWI-*` Council-level identity. Do not use Dataverse row IDs or Microsoft source IDs. |
| `com_type` | One of the controlled MVP Work Item types. |
| `com_state_group` | Must start as `proposed`. |
| `com_owner_candidate` / `com_owner_candidate_confidence` | Suggested owner and confidence; may remain uncertain. |
| `com_risk_class` | Use controlled risk class. Sensitive/governance/unknown keeps approval required. |
| `com_confidence_summary` | Human-readable extraction/type/owner/source confidence explanation. |
| `com_primary_source_record` | Required lookup to the Source Record that justified the proposal. |
| `com_rationale` | Why the Work Item exists. |
| `com_recommended_next_action` | What Doug should do next. |
| `com_approval_required` | Must be true for local Story 1.3 examples. |
| `com_auto_creation_policy_result` | Use `proposal_only` or `not_evaluated`; do not mark executable auto-created work in this story. |

Relevant artifacts:

- `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json`
- `_bmad-output/implementation-artifacts/manual-source-record-slice.json`
- `_bmad-output/implementation-artifacts/outlook-source-reference-slice.json`
- `_bmad-output/implementation-artifacts/proposed-work-item-extraction-slice.json`
- `_bmad-output/implementation-artifacts/proposed-work-item-extraction-slice-validate.ps1`

### Previous Story Intelligence

Stories 1.1 and 1.2 established the local implementation pattern:

- Create a story-specific JSON slice that proves the contract without tenant writes.
- Add a PowerShell validator with a clear success marker.
- Wire the validator into `council-mvp-local-validate.ps1`.
- Mark tenant-dependent model-driven app configuration complete only after Doug approves live writes and target preflight proves the environment; table components and curated views/forms are now proven.
- Mark mock/manual Outlook evidence as not tenant verified.

Carry-forward constraints:

- Do not create a Work Item merely by saving a Source Record.
- Do not create receipts in Story 1.3; that is an Epic 2 responsibility.
- Do not silently update Source Record extraction status without receipt-backed mutation semantics.
- Do not infer approval from proposal.

### Anti-Patterns to Avoid

- Do not collapse Source Records, Work Items, Work Item Source links, Receipts, and graph edges into one object.
- Do not mark a Work Item approved, completed, delegated, or externally actionable in this story.
- Do not store source body text beyond the existing local samples.
- Do not create Power Automate flows, app registrations, Copilot agents, Graph calls, Fabric items, or tenant writes outside the approved Dataverse schema/app/sample-row boundary.
- Do not use a Source Record ID as the Work Item ID.
- Do not claim live MVP behavior from local JSON validation.

## Testing Requirements

Minimum local validation before review:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\proposed-work-item-extraction-slice-validate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\dataverse-manifest-validate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-mvp-local-validate.ps1
git diff --check
```

Expected local success markers:

```text
PROPOSED_WORK_ITEM_EXTRACTION_SLICE_VALIDATE_OK
COUNCIL_MVP_LOCAL_VALIDATE_OK
```

Persist proposed Work Items in Dataverse only after `tenant-decision-packet-validate.ps1 -RequireComplete` passes, read-only preflight proves the target environment, and Doug approves writes.

## Definition of Done

- Local extraction slice shows proposed Work Items from existing Source Record samples.
- Each proposed Work Item includes type, summary, rationale, confidence, uncertainty, owner candidate, urgency, risk class, and recommended next action.
- Each proposed Work Item references a primary Source Record.
- Work Item IDs are stable Council IDs and not Microsoft/Dataverse row identifiers.
- Local validator and full MVP validator pass.
- If tenant implementation occurs later, tenant evidence and source-controlled solution/export artifacts are committed.
- No approvals, outbound actions, flows, agents, app registrations, Fabric mutations, or tenant writes outside the approved Dataverse demo seed boundary occur in this story.

## Open Questions / Required User Decisions

These remain required before live Story 1.3 completion:

1. Does Doug approve Dataverse as the MVP operational store?
2. Does Doug approve Dataverse writes after read-only preflight proves the target environment?
3. What publisher prefix should replace or confirm placeholder `com`?
4. What source body policy is allowed for sample records?
5. Does Doug accept model-driven app views/forms as the first Council Queue surface?
6. Who is the human approval owner for proposed Work Item execution decisions?

## Project Context Reference

Read `_bmad-output/project-context.md` before implementation. The highest-risk rules for this story are:

- Normalize source records into proposed work items through an explicit extraction step.
- Not every source record should become a work item.
- Preserve source-to-work-item provenance plus rationale.
- Preserve confidence and explanation whenever extraction, classification, or owner selection is uncertain.
- Decision, delegation, risk, sensitive, governance, tenant-affecting, and outbound work stays proposed-only until human approval.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-08 | Created Story 1.3 from BMAD epic context and implemented the local proposed Work Item extraction slice. This was initially local-only until Dataverse persistence and Council Queue configuration were approved. |
| 2026-07-08 | Added live deterministic Dataverse demo seed after write approval: Source Record `manual-demo-source-001`, proposed Work Item `CWI-DEMO-001`, Work Item Source, proposal Receipt `CR-DEMO-PROPOSED-001`, Receipt Source, graph provenance, and Minion Brief `BRIEF-DEMO-001`. |
| 2026-07-09 | Applied `Council Queue` form/view curation: Work Item views are pinned, including `Proposed Work Items`, `Needs Human Approval`, state-specific review views, and `ValidateApp` reports zero form/view issues. |

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- Red check: `proposed-work-item-extraction-slice-validate.ps1` failed before `proposed-work-item-extraction-slice.json` existed.
- Green check: `proposed-work-item-extraction-slice-validate.ps1` passes and prints `PROPOSED_WORK_ITEM_EXTRACTION_SLICE_VALIDATE_OK`.
- Regression gate: `council-mvp-local-validate.ps1` passes and prints `COUNCIL_MVP_LOCAL_VALIDATE_OK`.

### Completion Notes List

- Story context created from BMAD epics, project context, Source Record contract, Work Item/Receipt contract, Auto-Creation Policy, current manifest, and Story 1.1/1.2 local slice patterns.
- Local non-tenant implementation proves proposed Work Item extraction shape, Council-level Work Item IDs, primary source references, Work Item Source links, proposal-only behavior, confidence/uncertainty capture, and Source Record / Work Item separation.
- Live tenant persistence is now proven for the deterministic demo seed after completed target preflight and Doug-approved writes.
- Remaining work: keep final tenant-surface screen proof current after app curation, then move the story to review when the BMAD story gate is ready.

### File List

- `_bmad-output/implementation-artifacts/1-3-extract-proposed-work-items-from-source-records.md`
- `_bmad-output/implementation-artifacts/proposed-work-item-extraction-slice.json`
- `_bmad-output/implementation-artifacts/proposed-work-item-extraction-slice-validate.ps1`
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
