---
title: "Dataverse MVP Schema Plan"
project: "The-Council-of-Minions"
status: draft-ready-for-tenant-validation
created: 2026-07-08
target_environment_id: ba9a96b2-f562-40f6-931d-6b55873954ee
depends_on:
  - storage-decision-record-2026-07-08.md
  - live-tenant-kickoff-2026-07-08.md
  - architecture/architecture-The-Council-of-Minions-2026-07-06/semantic-contract.md
  - architecture/architecture-The-Council-of-Minions-2026-07-06/source-record-contract.md
  - architecture/architecture-The-Council-of-Minions-2026-07-06/work-item-receipt-contract.md
  - architecture/architecture-The-Council-of-Minions-2026-07-06/auto-creation-policy.md
---

# Dataverse MVP Schema Plan - 2026-07-08

## Purpose

Map the Council's storage-neutral contracts into a Dataverse MVP schema without executing tenant changes yet.

This is an implementation-prep artifact. It does not authorize live tenant writes. It becomes executable only after Doug approves Dataverse as the MVP operational store, confirms live-write boundaries, and completes interactive authentication.

## Design Rules

1. Dataverse is the operational store, not the semantic authority.
2. The Council Semantic Contract remains canonical.
3. Every Council object has a stable Council ID separate from Dataverse row ID.
4. Source Records, Work Items, Receipts, Graph Entities, Memory Candidates, Approved Instructions, Skills, Minions, Briefs, Tenant Evidence, and Platform Evaluations are separate tables.
5. Source Records never mutate into Work Items.
6. Receipts are append-only.
7. The Meaning Graph is a projection for routing, provenance, context, explanation, and audit. It is not the workflow engine.
8. No outbound action, memory promotion, skill authority expansion, agent publishing, app registration, flow publishing, or external mutation is allowed by schema alone.

## Naming Proposal

Final publisher prefix must be confirmed before tenant writes.

| Item | Proposed value |
| --- | --- |
| Solution display name | Council of Minions MVP |
| Solution unique name | `CouncilOfMinionsMVP` |
| Publisher display name | Council of Minions |
| Publisher prefix | `com` |
| Entity/table prefix | `com_` |
| Primary app display name | Council Queue |
| First model-driven app unique name | `com_CouncilQueue` |

If `com` conflicts or Doug prefers another prefix, use the tenant-safe publisher prefix selected before solution creation.

## MVP Tables

### 1. Council Source Record

Display name: `Council Source Record`
Schema name: `com_councilsourcerecord`
Primary name: `com_name`

Purpose: store captured source metadata and allowed snapshots before extraction.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Human-readable source label. |
| `com_council_source_record_id` | Text alternate key candidate | Yes | Stable Council source ID, not Dataverse row ID. |
| `com_source_system` | Choice | Yes | Outlook, Teams, SharePoint, OneDrive, Calendar, Manual, Other. |
| `com_source_kind` | Choice | Yes | Message, Thread, Chat, Meeting, File, Comment, Task, Manual Note, Other. |
| `com_source_object_ref` | Text | Yes | Native source ID or pointer. |
| `com_source_object_url` | URL/Text | No | Resolvable link when allowed. |
| `com_conversation_ref` | Text | No | Thread/chat/meeting binding. |
| `com_parent_ref` | Text | No | Parent source pointer. |
| `com_captured_at` | DateTime | Yes | ISO 8601 equivalent. |
| `com_captured_by` | Text or lookup later | Yes | User, Minion, connector, or trusted rule. |
| `com_observed_modified_at` | DateTime | No | Native modified timestamp. |
| `com_source_version_ref` | Text | No | ETag, change key, version ID, hash, or equivalent. |
| `com_content_snapshot_ref` | Multiline Text or File reference | No | Only if data boundary allows. |
| `com_content_hash` | Text | No | Hash of captured content or extracted text when allowed. |
| `com_attachment_refs` | Multiline Text | No | JSON/text list of attachment IDs, names, hashes, permission notes. |
| `com_permission_snapshot` | Multiline Text | No | Best-known access scope at capture. |
| `com_sensitivity_label` | Text/Choice | No | Sensitivity/confidentiality label when visible. |
| `com_retention_or_hold_flags` | Multiline Text | No | Retention/legal hold/policy flags. |
| `com_extraction_status` | Choice | Yes | New, Extracted, Ignored, Held, Failed, Superseded. |
| `com_extraction_confidence` | Decimal | No | Confidence 0-1. |
| `com_source_to_work_item_rationale` | Multiline Text | No | Why work was or was not proposed. |
| `com_data_boundary_policy` | Choice | Yes | Link Only, Hash Only, Summary Allowed, Full Snapshot Allowed, Unknown. |

Views:

- New Source Records
- Held Source Records
- Extracted Source Records
- Source Records With Drift Risk

### 2. Council Work Item

Display name: `Council Work Item`
Schema name: `com_councilworkitem`
Primary name: `com_title`

Purpose: canonical execution shell for proposed and approved work.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_title` | Text | Yes | Human-readable short label. |
| `com_council_work_item_id` | Text alternate key candidate | Yes | Stable Council Work Item ID. |
| `com_type` | Choice | Yes | Decision, Delegation, Follow Up, Request, Risk, Artifact Task, Meeting Action. |
| `com_summary` | Multiline Text | Yes | Current explanation. |
| `com_state_group` | Choice | Yes | Proposed, Approved, Blocked, Held, In Review, Completed, Failed. |
| `com_owner_candidate` | Text | No | Suggested owner. |
| `com_owner_candidate_confidence` | Decimal | No | Confidence 0-1. |
| `com_approved_owner` | Text or user/team lookup later | No | Owner after approval. |
| `com_urgency` | Choice | No | Low, Normal, High, Critical, Unknown. |
| `com_risk_class` | Choice | Yes | None, Relationship, Legal, Finance, Delivery, Sensitive, Governance, Unknown. |
| `com_confidence_summary` | Multiline Text | No | Extraction/type/owner confidence explanation. |
| `com_primary_source_record` | Lookup to Source Record | Yes | Primary source. |
| `com_rationale` | Multiline Text | Yes | Why the Work Item exists. |
| `com_recommended_next_action` | Multiline Text | No | Proposed action or decision path. |
| `com_approval_required` | Yes/No | Yes | True for decision/delegation/risk/outbound/sensitive/etc. |
| `com_semantic_contract_version` | Text | Yes | Contract version/date used. |
| `com_created_receipt` | Lookup to Receipt | No | Backfilled after creation receipt exists if circular dependency is awkward. |
| `com_auto_creation_policy_result` | Choice | No | Not Evaluated, Auto-Created, Proposal Only, Policy Denied. |
| `com_policy_flags` | Multiline Text | No | Sensitive/legal/finance/relationship/tenant/DLP/authority flags. |

Views:

- Proposed Work Items
- Needs Human Approval
- Approved Work Items
- Blocked or Held Work Items
- In Review
- Completed Recently
- Failed / Needs Review

### 3. Council Work Item Source

Display name: `Council Work Item Source`
Schema name: `com_councilworkitemsource`
Primary name: `com_name`

Purpose: join table so one Work Item can cite multiple Source Records while preserving one primary source on the Work Item.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Generated label. |
| `com_work_item` | Lookup to Work Item | Yes | Linked Work Item. |
| `com_source_record` | Lookup to Source Record | Yes | Supporting source. |
| `com_source_role` | Choice | Yes | Primary, Supporting, Contradicting, Superseding. |
| `com_rationale` | Multiline Text | No | Why this source matters. |
| `com_confidence` | Decimal | No | Source support confidence. |

### 4. Council Receipt

Display name: `Council Receipt`
Schema name: `com_councilreceipt`
Primary name: `com_receipt_id`

Purpose: append-only audit event for meaningful actions, transitions, decisions, failures, and external-action requests/results.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_receipt_id` | Text alternate key candidate | Yes | Stable Council receipt ID. |
| `com_work_item` | Lookup to Work Item | No | Optional for source/memory-only receipts. |
| `com_verb` | Choice | Yes | Proposed, Approved, Delegated, Blocked, Held, Resumed, Reviewed, Completed, Failed, Memory Proposed, Memory Promoted, Source Drifted, Policy Denied, External Action Requested, External Action Completed. |
| `com_actor_type` | Choice | Yes | Human, Minion, System, Connector, Trusted Rule. |
| `com_actor_id` | Text | Yes | User, Minion, service principal, or rule reference. |
| `com_authority_basis` | Choice/Text | Yes | Human approval, trusted rule, policy, explicit command, system constraint. |
| `com_occurred_at` | DateTime | Yes | Event time. |
| `com_idempotency_key` | Text alternate key candidate | Yes | Prevent duplicate mutation. |
| `com_before_state` | Text/Choice | No | Prior state or value. |
| `com_after_state` | Text/Choice | No | New state or value. |
| `com_evidence_refs` | Multiline Text | No | Artifact/source/approval references. |
| `com_decision_rationale` | Multiline Text | No | Human/agent-readable rationale. |
| `com_confidence` | Decimal | No | Confidence when inferred or suggested. |
| `com_result` | Choice | Yes | Accepted, Rejected, Succeeded, Failed, Superseded, No Op. |
| `com_failure_code` | Text | No | Required when result is Failed. |
| `com_policy_flags` | Multiline Text | No | Sensitive/legal/finance/relationship/tenant/DLP/authority flags. |
| `com_append_only_locked` | Yes/No | Yes | Always true after create; used by plugin/flow/rule later to prevent edits. |

Views:

- Recent Receipts
- Failed Receipts
- Policy Denials
- External Action Requests
- Memory Receipts

Implementation note: Dataverse cannot enforce append-only semantics with a table definition alone. MVP must enforce it through security roles, command design, and later plugin/flow validation before broader access.

### 5. Council Receipt Source

Display name: `Council Receipt Source`
Schema name: `com_councilreceiptsource`

Purpose: join table for receipt-to-source references.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Generated label. |
| `com_receipt` | Lookup to Receipt | Yes | Receipt reference. |
| `com_source_record` | Lookup to Source Record | Yes | Source evidence. |
| `com_evidence_role` | Choice | No | Supporting, Approval, Failure Evidence, Drift Evidence. |

### 6. Council Graph Entity

Display name: `Council Graph Entity`
Schema name: `com_councilgraphentity`

Purpose: lightweight operational graph node for context, routing, provenance, explanation, and audit.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Entity label. |
| `com_council_graph_entity_id` | Text alternate key candidate | Yes | Stable Council graph entity ID. |
| `com_entity_type` | Choice | Yes | Person, Role, Project, Artifact, Decision, Commitment, Risk, Source, Skill, Minion, Topic. |
| `com_external_binding_ref` | Text | No | Platform/source binding if any. |
| `com_description` | Multiline Text | No | Human-readable meaning. |
| `com_semantic_contract_version` | Text | Yes | Contract version/date. |
| `com_status` | Choice | Yes | Active, Candidate, Deprecated, Superseded. |

### 7. Council Graph Edge

Display name: `Council Graph Edge`
Schema name: `com_councilgraphedge`

Purpose: approved edge vocabulary projection. Not workflow state.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Generated edge label. |
| `com_edge_type` | Choice | Yes | Proposed From, Evidenced By, Assigned To, Involves, About, Depends On, Blocks, Resolves, Supersedes, Uses Skill, Assisted By. |
| `com_from_entity` | Lookup to Graph Entity | No | For entity-to-entity edges. |
| `com_to_entity` | Lookup to Graph Entity | No | For entity-to-entity edges. |
| `com_from_work_item` | Lookup to Work Item | No | For Work Item source. |
| `com_to_work_item` | Lookup to Work Item | No | For Work Item target. |
| `com_source_record` | Lookup to Source Record | No | For source grounding. |
| `com_receipt` | Lookup to Receipt | No | For receipt grounding. |
| `com_rationale` | Multiline Text | No | Why the edge exists. |
| `com_confidence` | Decimal | No | Confidence 0-1. |
| `com_created_receipt` | Lookup to Receipt | No | Receipt that created or approved the edge. |

Constraint: a story or plugin must validate that each edge has an allowed from/to shape according to `semantic-contract.md`.

### 8. Council Memory Candidate

Display name: `Council Memory Candidate`
Schema name: `com_councilmemorycandidate`

Purpose: proposed durable context awaiting review.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Candidate label. |
| `com_council_memory_candidate_id` | Text alternate key candidate | Yes | Stable Council ID. |
| `com_summary` | Multiline Text | Yes | Proposed durable context. |
| `com_scope` | Choice | Yes | Personal, Project, Tenant, Excluded, Unknown. |
| `com_review_state` | Choice | Yes | Proposed, Approved, Rejected, Superseded, Needs Clarification. |
| `com_confidence` | Decimal | No | Confidence 0-1. |
| `com_source_record` | Lookup to Source Record | Yes | Grounding source. |
| `com_rationale` | Multiline Text | Yes | Why it should or should not become durable. |
| `com_recall_use_policy` | Multiline Text | No | How future Minions may use it. |
| `com_created_receipt` | Lookup to Receipt | No | Proposal receipt. |
| `com_review_receipt` | Lookup to Receipt | No | Approval/rejection receipt. |

### 9. Council Approved Instruction

Display name: `Council Approved Instruction`
Schema name: `com_councilapprovedinstruction`

Purpose: approved durable guidance for future Minion behavior.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Instruction label. |
| `com_council_approved_instruction_id` | Text alternate key candidate | Yes | Stable Council ID. |
| `com_instruction_text` | Multiline Text | Yes | Approved guidance. |
| `com_scope` | Choice | Yes | Personal, Project, Tenant, Workflow, Skill. |
| `com_source_memory_candidate` | Lookup to Memory Candidate | No | Candidate that became instruction. |
| `com_approval_receipt` | Lookup to Receipt | Yes | Approval evidence. |
| `com_status` | Choice | Yes | Active, Superseded, Retired. |
| `com_effective_from` | DateTime | Yes | Active date. |
| `com_superseded_by` | Lookup to Approved Instruction | No | Replacement. |

### 10. Council Skill

Display name: `Council Skill`
Schema name: `com_councilskill`

Purpose: reusable Minion capability with trigger, context, authority, proof, and update policy.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Skill name. |
| `com_council_skill_id` | Text alternate key candidate | Yes | Stable Council skill ID. |
| `com_trigger` | Multiline Text | Yes | When used. |
| `com_allowed_context` | Multiline Text | Yes | What context may be considered. |
| `com_required_inputs` | Multiline Text | No | Required input conditions. |
| `com_authority_class` | Choice | Yes | Manual Only, Ask Before Use, Approved Automatic. |
| `com_approval_requirements` | Multiline Text | Yes | Approval gates. |
| `com_proof_owed` | Multiline Text | Yes | Verification and receipt expectations. |
| `com_update_policy` | Multiline Text | Yes | How skill changes are reviewed. |
| `com_status` | Choice | Yes | Candidate, Active, Deprecated, Suspended. |

### 11. Council Minion

Display name: `Council Minion`
Schema name: `com_councilminion`

Purpose: role-bound agent/capability identity.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Minion name/role. |
| `com_council_minion_id` | Text alternate key candidate | Yes | Stable Council ID. |
| `com_role` | Text | Yes | Role/capability label. |
| `com_allowed_skill_scope` | Multiline Text | No | Skill usage bounds. |
| `com_authority_summary` | Multiline Text | Yes | What it may and may not do. |
| `com_status` | Choice | Yes | Candidate, Active, Suspended, Retired. |

### 12. Council Brief

Display name: `Council Brief`
Schema name: `com_councilbrief`

Purpose: human-facing snapshot/projection of current priority queue, risks, blockers, receipts, and memory candidates.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Brief title/date. |
| `com_council_brief_id` | Text alternate key candidate | Yes | Stable Council brief ID. |
| `com_brief_date` | DateTime | Yes | Generated time. |
| `com_priority_summary` | Multiline Text | Yes | Queue summary. |
| `com_decisions_needed` | Multiline Text | No | Decision summary. |
| `com_delegations_ready` | Multiline Text | No | Delegation summary. |
| `com_risks_if_ignored` | Multiline Text | No | Risk summary. |
| `com_blockers` | Multiline Text | No | Blockers/holds. |
| `com_recent_receipts` | Multiline Text | No | Receipt references. |
| `com_memory_candidates` | Multiline Text | No | Candidate references. |

Constraint: Briefs are projections and must not be treated as source of truth for Work Item state.

### 13. Council Tenant Evidence

Display name: `Council Tenant Evidence`
Schema name: `com_counciltenantevidence`

Purpose: store tenant readiness findings and decisions.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Capability/evidence label. |
| `com_capability_name` | Text | Yes | Capability checked. |
| `com_tenant_environment` | Text | Yes | Tenant/environment. |
| `com_admin_or_owner` | Text | No | Owner. |
| `com_evidence_link_or_ref` | Multiline Text | No | Link/screenshot/reference. |
| `com_date_verified` | DateTime | No | Verification date. |
| `com_restrictions_found` | Multiline Text | No | Constraints. |
| `com_decision` | Choice | Yes | Available, Unavailable, Available With Constraints, Not Tested. |
| `com_follow_up_owner` | Text | No | Owner. |

### 14. Council Platform Evaluation

Display name: `Council Platform Evaluation`
Schema name: `com_councilplatformevaluation`

Purpose: service-selection evidence for Microsoft-first decisions.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `com_name` | Text | Yes | Evaluation label. |
| `com_council_capability` | Text | Yes | Capability under evaluation. |
| `com_microsoft_candidate` | Text | Yes | Work IQ, Dataverse, Power Apps MCP, Copilot Studio, Power Automate, Fabric, etc. |
| `com_official_source_date_checked` | Text | Yes | Source/date. |
| `com_tenant_gate` | Multiline Text | No | Tenant/admin gate. |
| `com_permission_dlp_impact` | Multiline Text | No | Permission and DLP impact. |
| `com_licensing_cost_gate` | Multiline Text | No | Licensing/capacity/cost. |
| `com_lifecycle_alm_path` | Multiline Text | No | ALM path. |
| `com_contract_gaps` | Multiline Text | No | Council contract gaps. |
| `com_decision` | Choice | Yes | Adopt, Defer, Reject, Custom Gap Build, Not Tested. |
| `com_review_reference` | Text | No | Review/receipt reference. |

## Choice Sets

Use global choices where reuse is likely:

| Choice | Values |
| --- | --- |
| Work Item Type | Decision, Delegation, Follow Up, Request, Risk, Artifact Task, Meeting Action |
| Work Item State Group | Proposed, Approved, Blocked, Held, In Review, Completed, Failed |
| Risk Class | None, Relationship, Legal, Finance, Delivery, Sensitive, Governance, Unknown |
| Receipt Verb | Proposed, Approved, Delegated, Blocked, Held, Resumed, Reviewed, Completed, Failed, Memory Proposed, Memory Promoted, Source Drifted, Policy Denied, External Action Requested, External Action Completed |
| Actor Type | Human, Minion, System, Connector, Trusted Rule |
| Receipt Result | Accepted, Rejected, Succeeded, Failed, Superseded, No Op |
| Source System | Outlook, Teams, SharePoint, OneDrive, Calendar, Manual, Other |
| Source Kind | Message, Thread, Chat, Meeting, File, Comment, Task, Manual Note, Other |
| Extraction Status | New, Extracted, Ignored, Held, Failed, Superseded |
| Data Boundary Policy | Link Only, Hash Only, Summary Allowed, Full Snapshot Allowed, Unknown |
| Authority Class | Manual Only, Ask Before Use, Approved Automatic |
| Platform Decision | Adopt, Defer, Reject, Custom Gap Build, Not Tested |

## Model-Driven App MVP

App display name: `Council Queue`

Navigation groups:

1. Intake
   - Source Records
   - New Source Records
   - Held Source Records
2. Work
   - Work Items
   - Proposed Work Items
   - Needs Human Approval
   - Blocked or Held
   - In Review
3. Brief
   - Council Briefs
   - Recent Receipts
4. Knowledge
   - Graph Entities
   - Graph Edges
   - Memory Candidates
   - Approved Instructions
   - Skills
   - Minions
5. Governance
   - Tenant Evidence
   - Platform Evaluations

First forms:

- Source Record: contract fields, extraction status, source link, data boundary, rationale.
- Work Item: title, type, state group, owner candidate, risk, confidence, source, rationale, next action, approval required.
- Receipt: receipt ID, verb, actor, authority, before/after, evidence, result, failure code, policy flags.
- Brief: summary fields and related Work Items/Receipts.

## Security Roles

Initial role design:

| Role | Access intent |
| --- | --- |
| Council Admin | Configure solution, manage schema, manage all records. |
| Council Operator | Create/review Source Records, Work Items, Receipts, Briefs, Memory Candidates. |
| Council Reviewer | Approve/hold/reject Work Items and Memory Candidates. |
| Council Reader | Read queue, briefs, and receipts. |
| Council Integration | Least-privilege integration account for connectors/automation later. |

Append-only receipt behavior must be reinforced by role permissions and later plugin/flow validation.

## First Live Write Sequence After Approval

Do not execute until Doug approves live Dataverse sandbox writes.

1. Authenticate with `pac auth create --url https://sdhdev.crm.dynamics.com --name Council-SDH-Dev`.
2. Verify environment with `pac env who`.
3. Confirm publisher prefix.
4. Create unmanaged solution.
5. Create publisher if needed.
6. Create global choices.
7. Create core tables: Source Record, Work Item, Receipt.
8. Create join tables: Work Item Source, Receipt Source.
9. Create knowledge/governance tables: Graph Entity, Graph Edge, Memory Candidate, Approved Instruction, Skill, Minion, Brief, Tenant Evidence, Platform Evaluation.
10. Create relationships and lookup columns.
11. Create core views.
12. Create model-driven app shell.
13. Add sample mock records only after data boundary policy is approved.
14. Export unmanaged solution to repo for source control.

## First Vertical Slice Data Flow

1. Create a mock Outlook Source Record with source metadata and link-only or summary-only policy.
2. Create a proposed Work Item extracted from that Source Record.
3. Create a `proposed` Receipt with actor, authority basis, idempotency key, source reference, confidence, and policy flags.
4. Display the Work Item in Proposed Work Items and Needs Human Approval views.
5. Create a human approval or hold Receipt.
6. Update Work Item projection state only after receipt.
7. Add Graph Entity/Edge records for source, person/project/topic, and provenance.
8. Generate a Council Brief snapshot summarizing queue, decisions, blockers, receipts, and memory candidates.

## Validation Checks

Before claiming the tenant MVP schema is ready:

1. `pac env who` matches Environment ID `ba9a96b2-f562-40f6-931d-6b55873954ee`.
2. Solution exists and is unmanaged in the dev environment.
3. Tables exist with distinct identities.
4. Source Record and Work Item are separate tables.
5. Receipt table exists and has idempotency key.
6. Work Item state changes have a corresponding Receipt in sample data.
7. Source-to-work-item provenance exists through primary source and join table.
8. No sample external action, outbound message, flow publish, agent publish, or app registration is created.
9. Model-driven app shows Source Records, Proposed Work Items, Needs Human Approval, Receipts, Briefs, and governance tables.
10. Exported solution is committed to repo if solution export is part of the approved run.

## Open Tenant Decisions

| Decision | Default | Needed before write? |
| --- | --- | --- |
| Publisher prefix | `com` placeholder | Yes |
| Environment URL | `https://sdhdev.crm.dynamics.com` inferred | Verify with `pac env who` |
| Dataverse writes tonight | Not allowed yet | Yes |
| Source body policy | Unknown | Before sample source records |
| Model-driven app as first surface | Recommended | Before app creation |
| Power Apps MCP agent feed | Evaluate later | No |
| Fabric IQ / Graph | Defer to phase 2 | No |

## BMAD Alignment

This schema plan supports the active BMAD track but does not replace the paused `bmad-create-epics-and-stories` workflow. After Doug sends `C`, stories should cite this schema plan as implementation preparation while still treating the PRD and architecture companion contracts as authoritative.
