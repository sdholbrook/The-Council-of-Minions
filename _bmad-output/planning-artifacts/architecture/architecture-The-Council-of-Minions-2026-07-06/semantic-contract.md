# Council Semantic Contract

Status: architecture-ready  
Updated: 2026-07-07

## Authority

This file is the canonical semantic source for Council domain meaning until a later phase selects an authoritative managed store and ALM path. Dataverse semantic models, Fabric IQ ontology, Fabric Graph, Copilot Studio knowledge, Dataverse business skills, repo prompts, and Minion skills are projections or bindings of this contract.

Platform-inferred terms or relationship suggestions are candidate updates. They become canonical only after review, approval, and receipt.

## Canonical Nouns

| Term | Definition | Required distinction |
| --- | --- | --- |
| Source Record | A captured Microsoft work artifact or manual input before extraction. | Not every Source Record becomes a Work Item. |
| Work Item | The canonical execution shell for proposed or approved work. | Separate from source artifacts, tasks, graph nodes, and receipts. |
| Work Item Type | Controlled type describing execution intent. | Types do not create separate execution systems. |
| Receipt | Append-only audit event for a meaningful action, decision, transition, or failure. | Receipts are not comments or mutable status fields. |
| Meaning Graph | Lightweight operational graph for routing, context, provenance, explanation, and audit. | Not the workflow engine. |
| Graph Entity | A node representing a person, role, project, artifact, decision, commitment, risk, source, skill, Minion, or topic. | Not automatically a Work Item. |
| Memory Candidate | Proposed durable context awaiting review. | Not binding instruction until approved. |
| Approved Instruction | Durable guidance approved for future Minion behavior. | Must reference source and approval receipt. |
| Skill | Reusable Minion capability with trigger, context, authority, proof, and update policy. | Not a prompt blob without governance. |
| Minion | Role-bound agent capability acting within Council authority. | Not an unrestricted autonomous actor. |
| Minion Brief | Human-facing synthesis of priority work, decisions, delegations, risks, blockers, receipts, and memory candidates. | Not the source of truth for state. |

## Work Item Types

| Type | Meaning | Auto-create allowed |
| --- | --- | --- |
| decision | Doug or an approved owner must choose a stance or tradeoff. | No |
| delegation | Work should be assigned or handed off to someone else. | No |
| follow_up | A low-risk reminder or response tracking item. | Conditional |
| request | Someone asks for action, input, review, or information. | Proposed only unless low-risk policy allows follow-up form. |
| risk | Legal, finance, relationship, delivery, or governance exposure. | No |
| artifact_task | Work needed on a file, document, deck, plan, or other artifact. | Proposed only |
| meeting_action | Action item or commitment from meeting context. | Conditional |

## Edge Vocabulary

| Edge | From | To | Meaning |
| --- | --- | --- | --- |
| proposed_from | Work Item | Source Record | Work item was extracted from source. |
| evidenced_by | Receipt / Memory Candidate / Work Item | Source Record | Source supports the claim. |
| assigned_to | Work Item | Person / Role | Suggested or approved owner. |
| involves | Work Item / Source Record | Person / Role | Person is materially involved. |
| about | Work Item / Source Record | Project / Topic / Artifact / Risk | Subject relationship. |
| depends_on | Work Item | Work Item / Artifact / Decision | Work requires prior resolution. |
| blocks | Work Item / Risk | Work Item | Relationship prevents progress. |
| resolves | Receipt / Work Item | Risk / Decision / Work Item | Action resolves an item. |
| supersedes | Memory Candidate / Approved Instruction | Memory Candidate / Approved Instruction | New context replaces old context. |
| uses_skill | Receipt / Work Item | Skill | Skill was invoked or proposed. |
| assisted_by | Work Item | Minion | Minion contributed. |

## Identity Rules

- Council identifiers are stable product identifiers and must not expose backend-specific IDs as primary user-facing IDs.
- Platform identifiers from Outlook, Teams, SharePoint, Dataverse, Fabric, Planner / To Do, or Graph are stored as source references or bindings.
- A semantic term, graph entity, source record, work item, receipt, skill, memory candidate, and approved instruction each need distinct identity.

## Projection Rules

- Dataverse table display names, descriptions, relationships, views, forms, semantic-model glossary entries, and business skills should use approved terms from this contract.
- Fabric IQ entity types, properties, relationships, constraints, and bindings should use approved terms from this contract.
- Fabric Graph labels and edge names should use approved terms from this contract where graph analysis is adopted.
- Copilot Studio topics, knowledge, tool names, and agent instructions should reference approved terms from this contract.
- Platform-specific terminology can be added as aliases, but canonical names stay here.

## Change Process

Every semantic change must record:

- Proposed term, edge, alias, or definition.
- Source and rationale.
- Affected projections.
- Reviewer or trusted-source rule.
- Approval or rejection receipt.
- Version/date of the updated contract.

## MVP Boundary

MVP retains only terms and edges that drive routing, context, provenance, audit, approval, memory review, delegation support, or the Minion Brief. Decorative taxonomy is out of scope.
