---
stepsCompleted: []
status: requirements-extracted-pending-confirmation
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

{{requirements_coverage_map}}

## Epic List

{{epics_list}}

<!-- Repeat for each epic in epics_list (N = 1, 2, 3...) -->

## Epic {{N}}: {{epic_title_N}}

{{epic_goal_N}}

<!-- Repeat for each story (M = 1, 2, 3...) within epic N -->

### Story {{N}}.{{M}}: {{story_title_N_M}}

As a {{user_type}},
I want {{capability}},
So that {{value_benefit}}.

**Acceptance Criteria:**

<!-- for each AC on this story -->

**Given** {{precondition}}
**When** {{action}}
**Then** {{expected_outcome}}
**And** {{additional_criteria}}

<!-- End story repeat -->
