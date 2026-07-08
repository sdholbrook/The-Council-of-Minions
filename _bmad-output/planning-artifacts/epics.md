---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
status: complete-ready-for-implementation-readiness
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-The-Council-of-Minions-2026-07-06/prd.md
  - _bmad-output/planning-artifacts/prds/prd-The-Council-of-Minions-2026-07-06/addendum.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/ARCHITECTURE-SPINE.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/architecture-finish-decisions-2026-07-07.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/semantic-contract.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/source-record-contract.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/work-item-receipt-contract.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/auto-creation-policy.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/microsoft-platform-fit-matrix-2026-07-07.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/microsoft-platform-research-2026-07-07.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/semantic-knowledge-placement-2026-07-07.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/tenant-readiness-checklist.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/reviews/review-architecture-finish-readiness.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/reviews/review-adversarial-divergence.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/reviews/review-current-tech.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/reviews/review-microsoft-platform-alignment.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/reviews/review-rubric.md
  - _bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/reviews/review-semantic-contract-alignment.md
---

# The-Council-of-Minions - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for The-Council-of-Minions, decomposing the requirements from the PRD and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: The system must capture Microsoft work context as Source Records before any work-item extraction occurs.

FR2: The system must support Outlook-first intake for messages and threads while preserving Outlook source links and conversation/thread context.

FR3: The system must support manual capture for non-email work context during MVP.

FR4: The system must preserve source provenance for each Source Record, including source system, source kind, native object reference, capture time, capture actor, source version or drift detector, permissions, sensitivity metadata when available, attachments when captured, and source-to-work-item rationale.

FR5: The system must explicitly extract zero, one, or many proposed Work Items from a Source Record instead of mutating Source Records into Work Items.

FR6: The system must classify proposed Work Items using the controlled MVP types: `decision`, `delegation`, `follow_up`, `request`, `risk`, `artifact_task`, and `meeting_action`.

FR7: The system must preserve extraction rationale, confidence, uncertainty, suggested owner, urgency, risk class, and recommended next action for each proposed Work Item.

FR8: The system must maintain a canonical Work Item execution shell with stable Council-level identity, state group, owner candidate, approved owner, source references, rationale, approval requirement, semantic contract version, and creation receipt.

FR9: The system must support product-level Work Item state groups: `proposed`, `approved`, `blocked`, `held`, `in_review`, `completed`, and `failed`.

FR10: The system must expose a Council Queue where proposed, approved, blocked, held, in-review, completed, and failed Work Items can be reviewed.

FR11: The system must expose a Minion Brief that summarizes priority work, decisions needed, delegations ready, risks if ignored, blockers, recent receipts, and memory candidates.

FR12: The system must provide delegation decision support packages with suggested owner, rationale, confidence, recommended stance, urgency, internal handoff draft, and external reply draft when useful.

FR13: The system must require human approval before execution for `decision`, `delegation`, `risk`, outbound action, sensitive handling, memory promotion, skill authority expansion, and tenant-affecting activity.

FR14: The system must allow low-risk `follow_up` and `meeting_action` Work Items to be auto-created only when the Auto-Creation Policy criteria and confidence thresholds are met.

FR15: The system must keep auto-created Work Items separate from approved external action; auto-created does not mean auto-approved.

FR16: The system must append a Receipt for any meaningful proposal, state transition, approval, delegation, block, hold, resume, review, completion, failure, memory proposal, memory promotion, source drift, policy denial, or external action request/result.

FR17: The system must keep Receipts append-only and represent corrections as new Receipts rather than edits to prior Receipts.

FR18: The system must enforce idempotency for connector-triggered, scheduled, or agent-generated mutations.

FR19: The system must maintain a lightweight Meaning Graph linking Work Items, Source Records, people, roles, projects, artifacts, decisions, commitments, risks, topics, skills, Minions, receipts, and memory context.

FR20: The system must use the Meaning Graph for routing, retrieval, provenance, context, explanation, and audit without allowing graph edges to own workflow state or approval movement.

FR21: The system must use the Council Semantic Contract as the canonical source for domain nouns, identifiers, edge vocabulary, provenance meaning, approval meaning, and receipt semantics.

FR22: The system must treat Dataverse semantic models, Fabric IQ ontology, Fabric Graph, Copilot Studio knowledge, Dataverse business skills, and future agent knowledge planes as projections or bindings of the Council Semantic Contract.

FR23: The system must support Memory Candidates with source, rationale, confidence, scope, review state, recall/use policy, and receipt history before they can become Approved Instructions.

FR24: The system must provide a Minion Skill Registry where each reusable Minion capability declares trigger, allowed context, required inputs, authority class, approval requirements, proof owed, and update policy.

FR25: The system must require approval when a Skill installation or expansion adds data access, external action, tool use, or authority.

FR26: The system must preserve Microsoft-first product language and surfaces: Outlook messages, Teams conversations, meetings, files, tasks, people, approvals, decisions, commitments, risks, and briefs.

FR27: The system must evaluate Microsoft-native intelligence planes before custom substrate for work context, business data grounding, human review, ontology, graph, memory, skills, tools, and analytics.

FR28: The system must support service-selection evidence records that document evaluated Microsoft candidates, tenant gates, permission/DLP impact, licensing/cost, lifecycle/ALM path, contract gaps, decision, and review reference.

FR29: The system must mark live Microsoft tenant behavior, connector use, published agents, app registrations, data writes, automations, and external actions as `VERIFY IN TENANT` until tenant readiness evidence exists.

FR30: The system must support source drift handling by creating new source version references, drift receipts, or superseding Source Records instead of silently rewriting prior rationale or receipts.

### NonFunctional Requirements

NFR1: The architecture must remain storage-neutral until object contracts, identity, provenance, mutation rules, and ownership are reviewed.

NFR2: Microsoft-native options must be evaluated before custom services are selected for semantic search, business skills, memory, MCP tools, human review, ontology, graph, analytics, or workflow automation.

NFR3: The MVP must stay Doug-private first while preserving team-ready identity, authority, provenance, and approval boundaries.

NFR4: The system must preserve least-privilege access, source permissions, sensitivity labels, retention flags, DLP behavior, and tenant boundaries wherever available.

NFR5: The system must not perform live tenant writes, publish automations, create app registrations, request broad permissions, or execute external action during documentation-first phases.

NFR6: The system must maintain an append-only audit trail for human and agent activity with actor identity, authority basis, before/after state, source references, evidence references, policy flags, result, and failure semantics.

NFR7: The system must preserve logical atomicity between status changes, provenance updates, graph projections, memory status changes, and receipt logging wherever possible.

NFR8: The system must keep canonical domain definitions in one Council Semantic Contract and prevent independent dual authoring in Dataverse glossary, Fabric ontology, Copilot Studio knowledge, repo docs, or Minion skills.

NFR9: The system must treat preview, admin-gated, cost-gated, capacity-dependent, or tenant-specific Microsoft capabilities as non-binding until verified.

NFR10: The system must keep the Meaning Graph lightly operational in MVP and avoid building a full workflow engine or graph editor before the graph proves routing, provenance, and explanation value.

NFR11: The system must separate evidence, Memory Candidate, and Approved Instruction states so agent-written observations cannot become binding instructions without approval or trusted-source policy.

NFR12: The system must use stable Council-level identifiers as primary product identities and store Microsoft/platform identifiers only as source references or bindings.

NFR13: The system must record failures with attempted action, actor, authority, source evidence, retry allowance, failure code, and whether human review is required.

NFR14: The system must keep source records, work items, graph entities, receipts, memory candidates, skills, and briefs as distinct concepts and identities.

NFR15: The system must support future ALM/projection paths for Dataverse metadata/glossary, Fabric IQ ontology, Fabric Graph, Copilot Studio knowledge, and repo documentation without making any one preview plane canonical.

NFR16: The system must be reviewable before implementation readiness; epics and stories must cite companion contracts directly and tenant validation must run before Phase 4 implementation.

### Additional Requirements

AR1: There is no starter application runtime manifest in the repo yet; initial implementation stories must establish a target runtime only after architecture selects a solution path.

AR2: There is no selected backend store; Dataverse, Planner / To Do patterns, SharePoint / Loop, Cosmos DB, Fabric, and graph sidecars remain candidates until a later architecture decision.

AR3: If Dataverse is selected for operational records, Council terms must be encoded in table/column display names, descriptions, relationships, public views, forms, and glossary entries so Dataverse semantic model can project approved meaning.

AR4: Dataverse semantic model must be treated as a Dataverse/Copilot runtime projection, not as the canonical ontology, especially while preview and ALM limitations remain.

AR5: If Fabric is used, Fabric IQ ontology and Fabric Graph must be generated or bound from the approved Council Semantic Contract rather than independently inventing names or relationships.

AR6: Fabric Graph may support relationship analytics, traversal, impact chains, dependency paths, and explanations, but it must not own Council workflow state or approval movement.

AR7: Work IQ must be evaluated first for Microsoft 365 source context, semantic work context, governed tools, agent workspaces, and agent-ready work packaging.

AR8: Dataverse intelligence, Dataverse semantic model, and Dataverse MCP must be evaluated for business-data grounding if operational Council records live in Dataverse.

AR9: Power Apps MCP agent feed, model-driven apps, Teams approvals, and Outlook actionable surfaces must be evaluated as implementation candidates for human review while the Council Queue remains the product-level review concept.

AR10: Copilot Studio and Power Automate may be considered for agent packaging and automation only after approval and receipt contracts are enforceable.

AR11: Fabric data agents, Power BI semantic models, and Fabric sources are candidates for future read-only analysis and briefing, not MVP workflow mutation.

AR12: Tenant readiness must verify tenant identity, licensing, Copilot credit impact, Power Platform environment, Dataverse settings, Work IQ / Agent 365 availability, Outlook / Graph permissions, Teams approvals, SharePoint / OneDrive behavior, Copilot Studio controls, Power Automate policies, Fabric capacity, sensitivity/retention behavior, security review, data boundary, human approval owners, and rollback path.

AR13: Before MVP implementation starts, tenant validation must at minimum verify Outlook/Graph read path, chosen storage candidate availability if selected, human review surface availability, DLP/sensitivity behavior for captured source records, audit/receipt persistence path, and no-live-write boundary for unapproved actions.

AR14: Epics and stories must cite the companion contracts instead of redefining Source Record, Work Item, Receipt, Memory Candidate, Graph Entity, Skill, or approval semantics.

AR15: The first implementation story set must prevent downstream teams from collapsing Source Record, Work Item, Receipt, Memory Candidate, and Graph Entity into one generic row, document, or Microsoft platform object.

AR16: Solution architecture must define synchronization mechanics for approved Council terms into Dataverse metadata/glossary, Fabric IQ ontology, Fabric Graph, Copilot Studio knowledge, and repo documentation.

AR17: The MVP surface boundary is Outlook-first intake plus manual capture, with Minion Brief plus Council Queue as the first review and approval surface.

AR18: The architecture is ready for epic/story planning but not Phase 4 implementation until epics/stories exist and tenant validation has been performed.

### UX Design Requirements

No UX design contract was found under `_bmad-output/planning-artifacts/ux-designs`, and no legacy UX document was included. UX-DR extraction is therefore intentionally empty for Step 1.

### FR Coverage Map

FR1: Epic 1 - Source Intake and Proposed Work Items
FR2: Epic 1 - Source Intake and Proposed Work Items
FR3: Epic 1 - Source Intake and Proposed Work Items
FR4: Epic 1 - Source Intake and Proposed Work Items
FR5: Epic 1 - Source Intake and Proposed Work Items
FR6: Epic 1 - Source Intake and Proposed Work Items
FR7: Epic 1 - Source Intake and Proposed Work Items
FR8: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR9: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR10: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR11: Epic 3 - Minion Brief and Delegation Support
FR12: Epic 3 - Minion Brief and Delegation Support
FR13: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR14: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR15: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR16: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR17: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR18: Epic 2 - Council Queue, Approval, and Receipt Ledger
FR19: Epic 4 - Meaning Graph and Memory Governance
FR20: Epic 4 - Meaning Graph and Memory Governance
FR21: Epic 4 - Meaning Graph and Memory Governance
FR22: Epic 4 - Meaning Graph and Memory Governance
FR23: Epic 4 - Meaning Graph and Memory Governance
FR24: Epic 5 - Skill Authority and Microsoft Platform Governance
FR25: Epic 5 - Skill Authority and Microsoft Platform Governance
FR26: Epic 5 - Skill Authority and Microsoft Platform Governance
FR27: Epic 5 - Skill Authority and Microsoft Platform Governance
FR28: Epic 5 - Skill Authority and Microsoft Platform Governance
FR29: Epic 5 - Skill Authority and Microsoft Platform Governance
FR30: Epic 1 - Source Intake and Proposed Work Items

## Epic List

### Epic 1: Source Intake and Proposed Work Items

Users can capture Outlook-first and manual Microsoft work context as Source Records, then extract explainable proposed Work Items without losing provenance or silently rewriting source rationale.

**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR30

**Implementation notes:** Preserve Source Record and Work Item as separate concepts; default source body policy to link-only until approved; support zero, one, or many proposed Work Items from each Source Record.

### Epic 2: Council Queue, Approval, and Receipt Ledger

Users can review proposed, approved, blocked, held, in-review, completed, and failed Work Items in a Council Queue, with receipt-backed state transitions, human approval boundaries, safe auto-creation rules, and idempotent mutation handling.

**FRs covered:** FR8, FR9, FR10, FR13, FR14, FR15, FR16, FR17, FR18

**Implementation notes:** Keep external action separate from Work Item creation or approval; append Receipts for meaningful mutations; enforce idempotency for connector-triggered, scheduled, and agent-generated mutations.

### Epic 3: Minion Brief and Delegation Support

Users can review a Minion Brief that summarizes priority work, decisions needed, delegations ready, risks if ignored, blockers, recent receipts, memory candidates, and delegation support packages.

**FRs covered:** FR11, FR12

**Implementation notes:** Treat Brief records as projections, not as the source of truth; include draft handoff/reply support without sending outbound messages unless separately approved.

### Epic 4: Meaning Graph and Memory Governance

Users can see relationship and provenance explanations through a lightweight Meaning Graph and manage Memory Candidates without allowing graph edges, observations, or unreviewed context to become workflow authority.

**FRs covered:** FR19, FR20, FR21, FR22, FR23

**Implementation notes:** Keep the Council Semantic Contract canonical; project approved meaning into Dataverse, Fabric, Copilot Studio, and future agent planes; keep graph edges out of workflow-state ownership.

### Epic 5: Skill Authority and Microsoft Platform Governance

Users can manage reusable Minion skills, authority expansion, Microsoft-first platform evaluation, service-selection evidence, tenant readiness, and `VERIFY IN TENANT` boundaries before adopting live Microsoft capabilities.

**FRs covered:** FR24, FR25, FR26, FR27, FR28, FR29

**Implementation notes:** Evaluate Microsoft-native planes before custom substrate; require approval for skill authority expansion; preserve tenant evidence and live-write boundaries before platform adoption.

## Epic 1: Source Intake and Proposed Work Items

Users can capture Outlook-first and manual Microsoft work context as Source Records, then extract explainable proposed Work Items without losing provenance or silently rewriting source rationale.

### Story 1.1: Capture Manual Source Records

As Doug,
I want to manually capture a work-context source record,
So that non-email commitments and decisions can enter the Council without pretending they came from Outlook.

**Requirements:** FR1, FR3, FR4, NFR4, AR17

**Acceptance Criteria:**

**Given** the Council MVP is running without live Microsoft source access
**When** Doug creates a manual Source Record
**Then** the record must capture source system, source kind, native object reference or manual reference, capture time, capture actor, data boundary policy, and source-to-work-item rationale
**And** no Work Item is created until an explicit extraction step runs.

**Given** source content is sensitive or source body policy is unknown
**When** a manual Source Record is saved
**Then** the system must support link-only, hash-only, or summary-only capture
**And** the source body policy must be visible on the Source Record.

### Story 1.2: Capture Outlook Source References

As Doug,
I want Outlook messages and threads captured as Source Records with links and conversation context,
So that email-driven work can be reviewed without losing its original source.

**Requirements:** FR2, FR4, NFR4, AR13

**Acceptance Criteria:**

**Given** Outlook/Graph reads are authorized for the target tenant
**When** an Outlook message or thread is captured
**Then** the Source Record must preserve the Outlook source link, source object reference, conversation or thread reference, capture actor, capture time, and available source version metadata
**And** the Source Record must not become a Work Item directly.

**Given** live Outlook/Graph reads are not authorized
**When** the MVP is demonstrated
**Then** the system must support a mock or manually-entered Outlook Source Record
**And** the record must be marked as mock/manual evidence rather than verified tenant evidence.

### Story 1.3: Extract Proposed Work Items From Source Records

As Doug,
I want the Council to propose Work Items from a Source Record with rationale and confidence,
So that I can decide whether a source should become executable work.

**Requirements:** FR5, FR6, FR7, FR8

**Acceptance Criteria:**

**Given** a Source Record exists
**When** extraction runs
**Then** the system must produce zero, one, or many proposed Work Items
**And** each proposed Work Item must include type, summary, extraction rationale, confidence, uncertainty, suggested owner, urgency, risk class, and recommended next action.

**Given** a proposed Work Item is created
**When** it is persisted
**Then** it must reference the primary Source Record
**And** it must preserve Council-level identity separate from Microsoft or Dataverse row identifiers.

### Story 1.4: Handle Zero-Item and Multi-Item Extraction

As Doug,
I want the Council to handle Source Records that produce no work or multiple work items,
So that intake scope stays broader than surfaced queue scope.

**Requirements:** FR5, FR7, NFR14

**Acceptance Criteria:**

**Given** a Source Record contains no actionable work
**When** extraction runs
**Then** the Source Record may be marked ignored or held with rationale
**And** no Work Item should be created only to satisfy a one-source-one-task assumption.

**Given** a Source Record contains multiple distinct commitments, decisions, or risks
**When** extraction runs
**Then** the system must allow multiple proposed Work Items
**And** each Work Item must retain its own rationale, confidence, type, and source link.

### Story 1.5: Handle Source Drift and Supersession

As Doug,
I want source changes to create drift evidence instead of silently rewriting history,
So that prior decisions and receipts remain auditable.

**Requirements:** FR30, FR16, FR17

**Acceptance Criteria:**

**Given** a Source Record has already produced rationale or Work Items
**When** the source changes or a newer source version is captured
**Then** the system must create a new source version reference, drift receipt, or superseding Source Record
**And** prior rationale and receipts must remain unchanged.

**Given** a drifted Source Record affects an existing Work Item
**When** the drift is reviewed
**Then** the Work Item must show that review is needed
**And** any state change must be backed by a new Receipt.

## Epic 2: Council Queue, Approval, and Receipt Ledger

Users can review proposed, approved, blocked, held, in-review, completed, and failed Work Items in a Council Queue, with receipt-backed state transitions, human approval boundaries, safe auto-creation rules, and idempotent mutation handling.

### Story 2.1: Maintain the Work Item Execution Shell

As Doug,
I want each Work Item represented as a canonical execution shell,
So that work can move through the Council without being tied to one Microsoft source system.

**Requirements:** FR8, FR9, FR10, NFR12

**Acceptance Criteria:**

**Given** a proposed Work Item is created
**When** it is stored
**Then** it must include stable Council identity, type, summary, state group, owner candidate, approved owner if known, source references, rationale, approval requirement, semantic contract version, and creation receipt reference
**And** it must not use a Microsoft platform identifier as its primary product identity.

**Given** the Work Item is shown in the Council Queue
**When** Doug reviews it
**Then** the queue must expose proposed, approved, blocked, held, in-review, completed, and failed state groups.

### Story 2.2: Enforce Human Approval Boundaries

As Doug,
I want high-risk work to stay proposed until I approve it,
So that decisions, delegations, risks, sensitive handling, memory promotion, skill authority expansion, and tenant-affecting actions do not execute automatically.

**Requirements:** FR13, FR15

**Acceptance Criteria:**

**Given** a proposed Work Item is classified as decision, delegation, risk, sensitive, outbound, memory promotion, skill authority expansion, or tenant-affecting
**When** the system evaluates approval requirements
**Then** the Work Item must be marked approval required
**And** no external action may occur before explicit approval.

**Given** a Work Item is approved
**When** approval is recorded
**Then** approval must authorize only the declared state transition or action scope
**And** broader external action requires a separate approval if not included.

### Story 2.3: Apply Receipt-Backed Queue State Changes

As Doug,
I want every meaningful Work Item state change backed by a Receipt,
So that the queue is explainable and auditable.

**Requirements:** FR9, FR16, FR17, NFR6

**Acceptance Criteria:**

**Given** a Work Item is proposed, approved, blocked, held, resumed, reviewed, completed, or failed
**When** the state changes
**Then** a Receipt must be appended with verb, actor type, actor ID, authority basis, occurred at, before state, after state, evidence references, rationale, result, and policy flags
**And** previous Receipts must not be edited to represent corrections.

**Given** a correction is needed
**When** Doug or an agent identifies the correction
**Then** the correction must be represented as a new Receipt
**And** the original Receipt remains available for audit.

### Story 2.4: Enforce Idempotent Mutations

As a Council operator,
I want connector-triggered, scheduled, and agent-generated mutations to be idempotent,
So that retries do not create duplicate Work Items, Receipts, or approvals.

**Requirements:** FR18, FR16

**Acceptance Criteria:**

**Given** a mutation is triggered by a connector, schedule, or agent
**When** the mutation is attempted
**Then** it must include an idempotency key
**And** duplicate attempts with the same key must be rejected, flagged, or treated as no-op.

**Given** an idempotency check fails or cannot be verified
**When** the mutation is attempted
**Then** the system must record a failure or policy-denial Receipt
**And** the item must require human review before retry.

### Story 2.5: Apply Safe Auto-Creation Policy

As Doug,
I want only low-risk follow-up and meeting-action items auto-created under strict confidence thresholds,
So that useful work can appear quickly without bypassing approval boundaries.

**Requirements:** FR14, FR15, FR13

**Acceptance Criteria:**

**Given** a candidate Work Item is a low-risk `follow_up` or `meeting_action`
**When** source identification, type classification, low-risk classification, owner confidence when needed, and next-action confidence meet policy thresholds
**Then** the Work Item may be auto-created
**And** it must still remain separate from approved external action.

**Given** a candidate fails any threshold or risk check
**When** extraction evaluates auto-creation
**Then** the Work Item must remain proposed-only
**And** policy rationale must be visible in the Work Item or Receipt.

### Story 2.6: Record Failures and Policy Denials

As Doug,
I want failed or denied actions recorded with evidence,
So that I can distinguish system errors, policy denials, and items needing human review.

**Requirements:** FR16, NFR13

**Acceptance Criteria:**

**Given** an attempted mutation, extraction, approval, or external action request fails
**When** the failure is recorded
**Then** the Receipt must include attempted action, actor, authority basis, source evidence, retry allowance, failure code, result, and whether human review is required.

**Given** a policy denies an action
**When** the denial is displayed
**Then** the Work Item must remain in a reviewable state
**And** the denial rationale must be traceable to policy flags and evidence references.

## Epic 3: Minion Brief and Delegation Support

Users can review a Minion Brief that summarizes priority work, decisions needed, delegations ready, risks if ignored, blockers, recent receipts, memory candidates, and delegation support packages.

### Story 3.1: Create a Minion Brief Snapshot

As Doug,
I want a Minion Brief snapshot of the current Council queue,
So that I can review priority work and risks without opening every Work Item individually.

**Requirements:** FR11

**Acceptance Criteria:**

**Given** Work Items and Receipts exist
**When** a Minion Brief is generated
**Then** it must summarize priority work, decisions needed, delegations ready, risks if ignored, blockers, recent receipts, and memory candidates
**And** the Brief must be clearly treated as a projection rather than the source of truth.

**Given** a Brief references queue state
**When** underlying Work Items or Receipts change
**Then** the Brief must not silently rewrite history
**And** a new Brief snapshot or refresh evidence must be created.

### Story 3.2: Build Delegation Decision Support Packages

As Doug,
I want delegation candidates packaged with rationale and confidence,
So that I can decide whether to delegate, hold, or handle work personally.

**Requirements:** FR12, FR13

**Acceptance Criteria:**

**Given** a proposed Work Item is a delegation candidate
**When** the support package is created
**Then** it must include suggested owner, rationale, confidence, recommended stance, urgency, source references, and risks
**And** the package must preserve non-delegable exception reasons when applicable.

**Given** Doug approves or rejects a delegation
**When** the decision is recorded
**Then** a Receipt must capture the decision rationale, authority basis, before state, after state, and result.

### Story 3.3: Prepare Internal Handoff and External Reply Drafts

As Doug,
I want internal handoff and external reply drafts prepared but not sent,
So that I can move faster while retaining control over outbound communication.

**Requirements:** FR12, FR13, FR15

**Acceptance Criteria:**

**Given** a delegation or reply draft is useful
**When** the system prepares draft text
**Then** the draft must be linked to the Work Item and source evidence
**And** it must be marked as draft-only until Doug approves outbound action.

**Given** outbound action is not approved
**When** a draft exists
**Then** the system must not send email, Teams messages, Planner tasks, or other external updates
**And** any request for outbound action must be represented as a separate approval-gated event.

## Epic 4: Meaning Graph and Memory Governance

Users can see relationship and provenance explanations through a lightweight Meaning Graph and manage Memory Candidates without allowing graph edges, observations, or unreviewed context to become workflow authority.

### Story 4.1: Create Lightweight Meaning Graph Records

As Doug,
I want Work Items, Source Records, people, roles, projects, artifacts, decisions, commitments, risks, topics, skills, Minions, receipts, and memory context linked in a Meaning Graph,
So that the Council can explain why work exists and what it relates to.

**Requirements:** FR19, FR20, FR21

**Acceptance Criteria:**

**Given** Source Records, Work Items, and Receipts exist
**When** graph records are created
**Then** Graph Entities and Graph Edges must use the approved Council Semantic Contract vocabulary
**And** each retained edge must support routing, retrieval, provenance, context, explanation, or audit value.

**Given** a graph edge links operational objects
**When** the edge is created
**Then** the edge must include rationale, confidence, and source or receipt grounding where available
**And** it must not own Work Item state or approval movement.

### Story 4.2: Explain Work Through Graph Provenance

As Doug,
I want queue and brief views to explain relationships and source provenance,
So that I can trust Council recommendations.

**Requirements:** FR20, FR19

**Acceptance Criteria:**

**Given** a Work Item appears in the Council Queue or Minion Brief
**When** Doug opens its explanation
**Then** the system must show source records, relevant people/roles/projects/topics, supporting receipts, and confidence where available
**And** the explanation must distinguish evidence from inference.

**Given** graph evidence conflicts or is uncertain
**When** the explanation is displayed
**Then** uncertainty must be visible
**And** the Work Item must not be auto-approved based on graph evidence alone.

### Story 4.3: Propose Memory Candidates

As Doug,
I want durable context proposed as Memory Candidates before it becomes instruction,
So that useful learning can be reviewed without letting observations silently govern future behavior.

**Requirements:** FR23

**Acceptance Criteria:**

**Given** a source, receipt, or repeated pattern suggests durable context
**When** the system proposes a Memory Candidate
**Then** the candidate must include source, rationale, confidence, scope, review state, recall/use policy, and receipt history
**And** it must not act as an Approved Instruction until reviewed and promoted.

**Given** a Memory Candidate is rejected or needs clarification
**When** the review state changes
**Then** the change must be backed by a Receipt
**And** the candidate must remain distinct from source evidence and Approved Instructions.

### Story 4.4: Promote Approved Instructions With Receipts

As Doug,
I want reviewed Memory Candidates promoted into Approved Instructions only with explicit evidence,
So that binding guidance has provenance and authority.

**Requirements:** FR23, FR16, FR17, NFR11

**Acceptance Criteria:**

**Given** a Memory Candidate is ready for promotion
**When** Doug approves promotion
**Then** an Approved Instruction must be created with instruction text, scope, source candidate, approval receipt, effective date, and status
**And** the approval Receipt must preserve actor, authority basis, rationale, and source evidence.

**Given** an Approved Instruction is superseded
**When** replacement guidance is approved
**Then** the old instruction must be marked superseded
**And** the supersession must be linked to a new Receipt rather than overwriting prior guidance.

### Story 4.5: Project the Semantic Contract Without Dual Authoring

As a Council maintainer,
I want approved Council terms projected into Microsoft knowledge planes without making those planes canonical,
So that Dataverse, Fabric, Copilot Studio, and future agents stay aligned with the Council Semantic Contract.

**Requirements:** FR21, FR22, NFR8, NFR15, AR16

**Acceptance Criteria:**

**Given** a Council term, edge, or approval meaning is used in Dataverse, Fabric, Copilot Studio, or agent knowledge
**When** it is represented in that platform
**Then** it must be projected or bound from the Council Semantic Contract
**And** platform-inferred terms may only propose contract updates.

**Given** Dataverse semantic model or Fabric IQ ontology suggests new terms
**When** the suggestion is reviewed
**Then** it must become a Source Record, Work Item, or Memory Candidate as appropriate
**And** it must not silently update canonical Council meaning.

## Epic 5: Skill Authority and Microsoft Platform Governance

Users can manage reusable Minion skills, authority expansion, Microsoft-first platform evaluation, service-selection evidence, tenant readiness, and `VERIFY IN TENANT` boundaries before adopting live Microsoft capabilities.

### Story 5.1: Maintain the Minion Skill Registry

As Doug,
I want each reusable Minion capability recorded in a Skill Registry,
So that skills have explicit triggers, authority, inputs, and proof obligations.

**Requirements:** FR24

**Acceptance Criteria:**

**Given** a skill is added or updated
**When** it is registered
**Then** the Skill record must declare trigger, allowed context, required inputs, authority class, approval requirements, proof owed, update policy, and status
**And** it must be linked to relevant source evidence or approval receipts where applicable.

**Given** a skill is inactive, deprecated, or suspended
**When** it appears in a recommendation
**Then** the system must prevent or flag use according to status and authority class.

### Story 5.2: Approve Skill Authority Expansion

As Doug,
I want skill installations and authority expansions approval-gated,
So that new data access, external action, tool use, or authority cannot appear unnoticed.

**Requirements:** FR25, FR13

**Acceptance Criteria:**

**Given** a Skill installation or update adds data access, external action, tool use, or authority
**When** the change is proposed
**Then** it must require approval before activation
**And** the approval must create a Receipt with authority basis, rationale, before/after authority, and evidence references.

**Given** approval is denied
**When** the Skill record is updated
**Then** the skill must remain inactive or constrained
**And** the denial rationale must be visible for future review.

### Story 5.3: Record Microsoft Platform Evaluation Evidence

As a Council architect,
I want Microsoft-native planes evaluated before custom substrate,
So that product implementation follows Microsoft movement without hiding contract gaps.

**Requirements:** FR26, FR27, FR28, NFR2

**Acceptance Criteria:**

**Given** a Council capability needs work context, business-data grounding, human review, ontology, graph, memory, skills, tools, analytics, or automation
**When** implementation options are evaluated
**Then** the evaluation must consider relevant Microsoft candidates including Work IQ, Dataverse intelligence/MCP, Power Apps MCP agent feed, Copilot Studio, Power Automate, Fabric IQ/Graph, and Fabric data agents
**And** the record must capture tenant gates, permission/DLP impact, licensing/cost, ALM path, contract gaps, decision, and review reference.

**Given** a custom service is proposed
**When** service selection is reviewed
**Then** the custom service must cite the Microsoft-native gap or tenant constraint it addresses
**And** the decision must be recorded before implementation.

### Story 5.4: Enforce Tenant Readiness and VERIFY IN TENANT Gates

As Doug,
I want live Microsoft capabilities marked `VERIFY IN TENANT` until proven,
So that the MVP does not assume tenant features, permissions, licensing, or data boundaries that may not exist.

**Requirements:** FR29, NFR5, NFR9, AR12

**Acceptance Criteria:**

**Given** a story, capability, connector, published agent, app registration, data write, automation, or external action depends on the live Microsoft tenant
**When** the capability is planned
**Then** it must be marked `VERIFY IN TENANT` until tenant evidence exists
**And** no live write may occur before the approved boundary is documented.

**Given** tenant validation is performed
**When** evidence is captured
**Then** it must record tenant identity, environment, auth user, licensing/capacity assumptions, relevant settings, restrictions, decision, and follow-up owner.

### Story 5.5: Validate Dataverse MVP Operational Store Readiness

As a Council implementer,
I want Dataverse readiness proven before schema writes,
So that the MVP operational store is created in the intended environment with clear rollback and audit boundaries.

**Requirements:** FR27, FR28, FR29, AR3, AR8, AR13

**Acceptance Criteria:**

**Given** Dataverse is approved as the MVP operational store
**When** read-only preflight runs
**Then** `pac auth who`, `pac env who`, and environment settings evidence must prove the expected environment ID, organization ID, and user context
**And** write scripts must remain disabled until Doug approves Dataverse sandbox writes and publisher prefix.

**Given** Dataverse schema creation is approved
**When** an implementation story requires Dataverse objects
**Then** schema writes must be tied to the current story's needed tables, columns, relationships, or views
**And** the dry-run manifest may describe the full MVP target shape without forcing all tables to be created before story value needs them.

### Story 5.6: Manage Phase 2 Knowledge and Analytics Projections

As a Council architect,
I want Fabric, Copilot Studio, and analytics projections deferred until MVP contracts are stable,
So that graph and ontology expansion does not take over workflow state.

**Requirements:** FR22, FR27, FR28, AR5, AR6, AR11

**Acceptance Criteria:**

**Given** Fabric IQ, Fabric Graph, Copilot Studio knowledge, Dataverse business skills, or future agent knowledge planes are evaluated
**When** a projection is proposed
**Then** the projection must bind to the Council Semantic Contract
**And** it must not become the canonical source for workflow state, approval movement, or domain vocabulary.

**Given** a phase 2 projection is deferred
**When** the decision is recorded
**Then** the platform evaluation record must capture why it is deferred, what evidence is still needed, and what contract gap it may address later.
