---
title: "First Vertical Slice Work Orders"
project: "The-Council-of-Minions"
status: readiness-reviewed-needs-ux-runtime-tenant-approval
created: 2026-07-08
source_plan: mvp-sprint-plan-2026-07-08.md
---

# First Vertical Slice Work Orders - 2026-07-08

## Purpose

Define the first implementable MVP slice as work orders that a BMAD developer agent can execute after the formal epics/stories workflow is completed, readiness gaps are handled, and tenant write approval is granted.

These work orders are aligned to the validated BMAD stories and the completed implementation-readiness report. They remain blocked by runtime/setup, focused UX, tenant validation, and Dataverse write approval.

## Slice Goal

Prove the Council's core loop:

Source Record -> proposed Work Item -> proposal Receipt -> human review state change -> review Receipt -> provenance graph explanation -> Minion Brief projection.

## Non-Negotiable Guardrails

1. Source Records and Work Items remain separate records.
2. Every Work Item has source provenance and rationale.
3. Every meaningful mutation has a Receipt.
4. Receipts are append-only by process and later technical enforcement.
5. Work Item state is a projection from canonical record plus receipts.
6. Meaning Graph does not own workflow state.
7. No outbound action is executed.
8. No memory becomes Approved Instruction without approval Receipt.
9. No automation, app registration, flow, agent, or Fabric item is created during this slice unless separately approved.

## Work Order 0 - Confirm Runtime and Tenant Gate

As Doug and the implementation agent,
I want the live tenant and implementation boundary confirmed,
So that the MVP is built in the right environment with no accidental live action.

### Acceptance Criteria

**Given** no runtime manifest exists in the repo
**When** implementation work begins
**Then** the selected runtime, local run command, validation command, packaging path, and minimal CI/check baseline must be documented
**And** product stories must not proceed against an accidental or implicit runtime.

**Given** the first review surface is user-facing
**When** the Council Queue / Minion Brief surface is implemented
**Then** forms, views, commands, filters, approval actions, source/provenance panels, graph explanation panel, empty/error states, and accessibility expectations must be defined before claiming UX readiness.

**Given** the target Dataverse environment details in `storage-decision-record-2026-07-08.md`
**When** `pac auth create`, `pac auth who`, and `pac env who` are run
**Then** the active environment must match Environment ID `ba9a96b2-f562-40f6-931d-6b55873954ee`
**And** the active organization must match `0c0fa4db-8614-ef11-9f83-000d3a342d36`.

**Given** the implementation is moving from planning to tenant work
**When** any live write is proposed
**Then** Doug must have explicitly approved the write boundary and publisher prefix.

### Evidence

- `tenant-validation-evidence-2026-07-08.md` updated with auth/environment proof.
- No Dataverse write commands run before approval.

## Work Order 1 - Create Council Dataverse Solution

As a Council operator,
I want a dedicated unmanaged Dataverse solution,
So that all MVP components are isolated, exportable, and reviewable.

### Acceptance Criteria

**Given** Dataverse sandbox writes are approved
**When** the Council solution is created
**Then** the solution must use the approved publisher prefix
**And** it must be unmanaged in the development environment
**And** it must be exportable for source control.

**Given** no runtime manifest exists in the repo
**When** solution creation completes
**Then** exported solution artifacts must become the implementation source artifact unless a separate runtime is explicitly selected.

### Evidence

- Solution visible in target environment.
- Exported solution package or unpacked solution path added to repo when approved.
- `tenant-validation-evidence-2026-07-08.md` records solution name and publisher.

## Work Order 2 - Create Core Contract Tables

As a Council implementer,
I want Dataverse tables for Source Records, Work Items, and Receipts,
So that the core source-to-work-item loop can be stored without collapsing product concepts.

### Acceptance Criteria

**Given** the schema plan is approved
**When** core tables are created
**Then** `Council Source Record`, `Council Work Item`, and `Council Receipt` must be separate Dataverse tables
**And** each must include a stable Council ID column separate from the Dataverse row ID.

**Given** the Work Item contract
**When** the Work Item table is created
**Then** it must include type, state group, risk class, confidence explanation, primary source, rationale, recommended next action, approval required, semantic contract version, and created receipt fields.

**Given** the Receipt contract
**When** the Receipt table is created
**Then** it must include verb, actor type, actor ID, authority basis, occurred at, idempotency key, before/after state, evidence refs, rationale, result, failure code, and policy flags.

### Evidence

- Dataverse table list/screenshots or exported solution metadata.
- Core table forms/views show required fields.

## Work Order 3 - Create Provenance Link Tables

As a Council reviewer,
I want Work Items and Receipts to cite their supporting Source Records,
So that decisions and queue state can be audited back to evidence.

### Acceptance Criteria

**Given** one Source Record can produce multiple Work Items
**When** a Work Item is proposed
**Then** the Work Item must have a primary source lookup
**And** additional source links must be represented in `Council Work Item Source`.

**Given** Receipts need evidence
**When** a Receipt is appended
**Then** source evidence must be represented through `Council Receipt Source` or evidence references.

### Evidence

- Join tables exist.
- Sample Work Item links to one primary Source Record and at least one Work Item Source link when appropriate.
- Sample Receipt links to source evidence.

## Work Order 4 - Create Choice Sets and Views

As a Council reviewer,
I want controlled values and focused views,
So that work state and approval boundaries are legible.

### Acceptance Criteria

**Given** the Semantic Contract defines controlled terms
**When** choices are created
**Then** Work Item Type, State Group, Risk Class, Receipt Verb, Actor Type, Receipt Result, Source System, Source Kind, Extraction Status, Data Boundary Policy, Authority Class, and Platform Decision must use approved values.

**Given** the review surface is model-driven
**When** views are created
**Then** the app must show Proposed Work Items, Needs Human Approval, Blocked or Held, In Review, Failed / Needs Review, Recent Receipts, and New Source Records.

### Evidence

- Choice sets exist in solution.
- Views appear in model-driven app or table designer.

## Work Order 5 - Create First Source Record

As Doug,
I want a safe source record captured or simulated,
So that the MVP loop can be tested without violating data boundaries.

### Acceptance Criteria

**Given** source body policy is not approved
**When** the first Source Record is created
**Then** it must use link-only or mock content
**And** no sensitive or full message body content is stored.

**Given** source metadata is required
**When** the Source Record is saved
**Then** it must include source system, source kind, source object reference, source URL if allowed, captured at, captured by, source version/hash if available, extraction status, and rationale.

### Evidence

- One sample Source Record exists.
- Data boundary policy is set.
- Source content policy is recorded in tenant evidence.

## Work Order 6 - Create First Proposed Work Item

As Doug,
I want a proposed Work Item extracted from the Source Record,
So that I can review the Council's proposed next action before anything executes.

### Acceptance Criteria

**Given** a Source Record exists
**When** a Work Item is created
**Then** it must be in `proposed` state
**And** it must reference the primary Source Record
**And** it must include type, summary, owner candidate, urgency, risk class, confidence explanation, rationale, recommended next action, approval required, and semantic contract version.

**Given** the first slice must not execute external action
**When** the Work Item is proposed
**Then** it must not send messages, create Planner tasks, update source systems, or publish automation.

### Evidence

- Proposed Work Item exists and appears in views.
- Work Item has source link and rationale.

## Work Order 7 - Append Proposal Receipt

As a Council auditor,
I want a Receipt recording the Work Item proposal,
So that the creation is explainable and traceable.

### Acceptance Criteria

**Given** a proposed Work Item exists
**When** the proposal Receipt is created
**Then** the Receipt verb must be `proposed`
**And** actor type, actor ID, authority basis, occurred at, idempotency key, source references, confidence, result, and policy flags must be populated.

**Given** idempotency is required
**When** the same proposal is attempted again with the same idempotency key
**Then** the implementation must prevent or flag duplicate mutation before production use.

### Evidence

- Proposal Receipt exists.
- Idempotency key is populated.
- Work Item references creation receipt where feasible.

## Work Order 8 - Apply Human Review State

As Doug,
I want to approve, hold, block, review, complete, or fail a Work Item with a receipt,
So that the queue moves only under explicit authority.

### Acceptance Criteria

**Given** a proposed Work Item exists
**When** Doug applies a review outcome
**Then** a Receipt must be appended before or with the state projection update
**And** the Receipt must record before state, after state, authority basis, decision rationale, result, and policy flags.

**Given** the outcome could imply external action
**When** the Work Item is approved
**Then** approval authorizes only the declared internal state transition unless a separate external-action approval exists.

### Evidence

- Review Receipt exists.
- Work Item state reflects receipt-backed transition.
- No outbound action occurs.

## Work Order 9 - Add Basic Provenance Graph

As Doug,
I want the brief to explain why a Work Item exists and what it relates to,
So that I can trust the Council's recommendation.

### Acceptance Criteria

**Given** Source Record, Work Item, and Receipts exist
**When** graph records are created
**Then** Graph Entities must represent relevant source/person/project/topic/skill/minion concepts
**And** Graph Edges must use approved edge vocabulary
**And** graph records must not own state transitions.

### Evidence

- Graph Entity/Edge records exist.
- Edge rationale and confidence are populated.
- Workflow state still lives in Work Item/Receipt.

## Work Order 10 - Create First Minion Brief

As Doug,
I want a Minion Brief snapshot,
So that I can see priority work, decisions, blockers, receipts, and memory candidates in one review surface.

### Acceptance Criteria

**Given** at least one Work Item and Receipt exist
**When** a Brief is created
**Then** it must summarize priority work, decisions needed, delegations ready if any, risks if ignored, blockers, recent receipts, and memory candidates
**And** it must be clearly treated as a projection, not as the source of truth.

### Evidence

- Council Brief record exists.
- Brief references Work Item and Receipts.
- Work Item state is not edited only through Brief text.

## Work Order 11 - Export and Commit MVP Slice

As a project maintainer,
I want the tenant solution and planning artifacts committed,
So that the MVP work is reproducible and reviewable.

### Acceptance Criteria

**Given** the slice is built or validated
**When** solution export is approved
**Then** exported solution artifacts must be added to the repo
**And** planning artifacts must reflect actual tenant evidence
**And** the PR must be updated.

**Given** no solution export is approved
**When** planning-only progress is complete
**Then** planning artifacts must still be committed and PR #1 updated.

### Evidence

- `git diff --check` passes.
- BMAD config resolver passes.
- Git commit created.
- Branch pushed.
- PR #1 updated.

## Traceability

| Work Order | Requirements covered |
| --- | --- |
| WO0 | FR27, FR28, FR29, NFR2, NFR4, NFR5, NFR9, AR12, AR13 |
| WO1 | FR8, FR10, FR16, NFR1, NFR6, NFR12, AR1, AR3 |
| WO2 | FR1, FR4, FR5, FR6, FR8, FR9, FR16, FR17, NFR14 |
| WO3 | FR4, FR5, FR16, FR30, NFR6, NFR14 |
| WO4 | FR6, FR9, FR10, FR13, FR21, NFR8 |
| WO5 | FR1, FR2, FR3, FR4, FR30, NFR4 |
| WO6 | FR5, FR6, FR7, FR8, FR13, FR15 |
| WO7 | FR16, FR17, FR18, NFR6, NFR7, NFR13 |
| WO8 | FR9, FR13, FR16, FR17, NFR6, NFR7 |
| WO9 | FR19, FR20, FR21, FR22, NFR10, NFR15 |
| WO10 | FR10, FR11, FR12, FR16, FR19, FR23 |
| WO11 | NFR16, AR14, AR15, AR18 |

## Immediate Next Action

Wait for Doug to supply:

```text
Dataverse approved as MVP operational store.
Fabric IQ / Fabric Graph deferred to phase 2 graph/analytics.
Tenant/domain: <tenant domain or tenant ID>
Environment type: dev/sandbox/trial/prod
Live reads: Outlook/Graph allowed or not allowed
Live writes: Dataverse sandbox writes allowed after approval / forbidden
Source body policy: link-only / hash-only / summary allowed / full snapshot allowed
Model-driven app is acceptable as first Council Queue / Minion Brief surface: yes/no
Power Apps MCP agent feed evaluation tonight: yes/no
Publisher prefix: <prefix>
```

Also resolve before development:

- Runtime path: Dataverse/model-driven app only, local prototype first, or another explicit runtime.
- UX path: focused model-driven app UX spec now, or accepted limited admin-style MVP surface.
