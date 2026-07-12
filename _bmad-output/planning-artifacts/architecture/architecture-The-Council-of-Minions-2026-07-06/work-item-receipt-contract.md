# Work Item And Receipt Contract

Status: architecture-ready  
Updated: 2026-07-07

## Purpose

Define the storage-neutral execution shell and receipt ledger used by the Council before selecting Dataverse, Planner / To Do, SharePoint, Fabric, Cosmos DB, or any other backing store.

## Work Item Required Fields

| Field | Meaning |
| --- | --- |
| council_work_item_id | Stable Council Work Item identifier. |
| type | `decision`, `delegation`, `follow_up`, `request`, `risk`, `artifact_task`, or `meeting_action`. |
| title | Human-readable short label. |
| summary | Current explanation of what needs to happen. |
| state_group | proposed, approved, blocked, held, in_review, completed, failed. |
| owner_candidate | Suggested owner and confidence. |
| approved_owner | Owner after approval, if any. |
| urgency | Product-level urgency, not backend priority. |
| risk_class | none, relationship, legal, finance, delivery, sensitive, governance, unknown. |
| confidence | Extraction/type/owner confidence with explanation. |
| primary_source_record_id | Primary source that justified creation. |
| source_record_ids | All supporting source records. |
| rationale | Why the Work Item exists. |
| recommended_next_action | Proposed action or decision path. |
| approval_required | Whether human approval is required before execution. |
| semantic_contract_version | Contract version used to classify it. |
| created_receipt_id | Receipt that created or proposed it. |

## State Rules

- `proposed` is not approved for execution.
- `approved` allows work to proceed only within declared authority.
- `blocked` means progress needs external dependency resolution.
- `held` means progress waits on human judgment, policy, or timing.
- `in_review` means output exists but needs review.
- `completed` means the work outcome is accepted or closed.
- `failed` means attempted work could not complete and requires review or retry.

## Receipt Required Fields

| Field | Meaning |
| --- | --- |
| receipt_id | Stable receipt identifier. |
| work_item_id | Work Item reference when applicable. |
| verb | proposed, approved, delegated, blocked, held, resumed, reviewed, completed, failed, memory_proposed, memory_promoted, source_drifted, policy_denied, external_action_requested, external_action_completed. |
| actor_type | human, Minion, system, connector, trusted_rule. |
| actor_id | User, Minion, service principal, or rule reference. |
| authority_basis | Human approval, trusted-source rule, policy, explicit command, or system constraint. |
| occurred_at | ISO 8601 timestamp. |
| idempotency_key | Key preventing duplicate mutation. |
| before_state | Prior state group or relevant prior value. |
| after_state | New state group or relevant new value. |
| source_record_ids | Supporting source records. |
| evidence_refs | Links to artifacts, drafts, approvals, or source snapshots. |
| decision_rationale | Human or agent-readable rationale. |
| confidence | Confidence when the receipt records an inferred or agent-suggested action. |
| result | accepted, rejected, succeeded, failed, superseded, no_op. |
| failure_code | Required when result is failed. |
| policy_flags | Sensitive, legal, finance, relationship, tenant, DLP, or authority flags. |

## Mutation Rules

- Any meaningful state transition appends a Receipt before projections update.
- Work Item state, graph links, memory status, and brief content are projections from canonical records plus receipts.
- Receipts are append-only. Corrections are new receipts, not edits to old receipts.
- External action requires an approval receipt before execution and a result receipt after execution.
- Idempotency is mandatory for connector-triggered, scheduled, or agent-generated mutations.

## Failure Semantics

Failures must record what was attempted, by whom or what, under which authority, the source evidence, whether retry is allowed, and whether human review is required.
