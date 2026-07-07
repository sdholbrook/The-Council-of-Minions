---
project_name: 'The-Council-of-Minions'
user_name: 'Doug'
date: '2026-07-06'
sections_completed:
  - technology_stack
  - product_model_rules
  - source_provenance_rules
  - graph_rules
  - governance_rules
  - workflow_rules
  - anti_patterns
status: 'complete'
rule_count: 42
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- BMAD is the project harness, not part of the product solution; treat it as an operational layer for skills, workflows, templates, and structure
- BMAD should be maintained at `@next` and updated frequently so the harness stays current; do not treat any local BMAD version as a fixed product dependency
- Git repository with Markdown-first planning and implementation artifacts under `_bmad-output/`
- Configuration stack based on TOML and YAML under `_bmad/`
- Local workflow helpers currently use Python under `_bmad/scripts/` and JavaScript under `_bmad/wds/scripts/`
- No target application runtime manifest exists yet in the workspace (`package.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, and `go.mod` are not present)
- Microsoft-native target environment includes Microsoft 365 Copilot, M365 Agent Templates, Copilot Studio, Power Automate, Outlook, Teams, Planner / Microsoft To Do, SharePoint, OneDrive, Loop, Microsoft Graph, Azure DevOps, and related Microsoft services
- Product direction has expanded from an email-first delegation engine to a work-item-first orchestration model with email as one source among several
- MVP intake is Outlook-first plus manual capture; Outlook is the first source and entry point, not the full product boundary
- The first review and approval surface is the Minion Brief plus Council Queue; Outlook links back to source messages and may host notifications or drafts
- Canonical datastore remains intentionally unresolved pending architecture work; likely options include Dataverse, Planner / To Do hybrid patterns, and external data layers such as Cosmos DB or Fabric
- Current architecture packet lives at `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/`
- Architecture companion contracts define the Semantic Contract, Source Record Contract, Work Item / Receipt Contract, Auto-Creation Policy, Microsoft Platform Fit Matrix, and Tenant Readiness Checklist

## Critical Implementation Rules

### Product Model Rules

- Treat the system as work-item-first, not email-first; email is an important source, not the top-level product boundary.
- Treat MVP as Outlook-first intake with Minion Brief plus Council Queue as the first review surface.
- Use `work item` as the canonical execution object.
- Model work items as a universal shell with a `type` field plus linked context, not as separate execution systems per intake channel.
- Phase 1 starter work-item types are `decision`, `delegation`, `follow_up`, `request`, `risk`, `artifact_task`, and `meeting_action`.
- MVP is Doug-private first while preserving team-ready object contracts and authority boundaries.

### Source and Provenance Rules

- Treat emails, chats, notes, meeting outputs, and manual captures as source records first, not as work items by default.
- Normalize source records into proposed work items through an explicit extraction step.
- Not every source record should become a work item.
- Every work item must preserve source-to-work-item provenance plus rationale.
- Source records must preserve source system, source kind, source object reference, conversation/thread reference, capture time, source version or hash, permissions/sensitivity metadata when available, attachments, and source-to-work-item rationale.
- Source changes after capture must be handled as drift, supersession, or a new source version; do not silently rewrite prior receipts or rationale.
- Preserve confidence and explanation whenever extraction, classification, or owner selection is uncertain.

### Graph and Ontology Rules

- Keep the graph lightly operational in Phase 1: enough to drive routing, context, and traceability without turning every edge into workflow logic.
- Link work items to people, projects, decisions, commitments, artifacts, and source records.
- Prefer a small explicit edge vocabulary over free-form semantic links.
- Design the schema so the graph can grow into a more strongly operational model later without redefining the core objects.
- Keep the Council Semantic Contract as the canonical source for domain nouns, identifiers, edge vocabulary, provenance meaning, approval meaning, and receipt semantics.
- Treat Dataverse semantic models, Fabric IQ ontology, Fabric Graph, Copilot Studio knowledge, Dataverse business skills, and future agent knowledge planes as projections or bindings of the Council Semantic Contract.
- Platform-inferred terms or relationships may propose contract updates, but they do not silently become canonical.

### Governance and Automation Rules

- Use a mixed creation model: low-risk items like `follow_up` and `meeting_action` may be auto-created at high confidence, while `decision`, `delegation`, and `risk` items require human approval before creation.
- Auto-creation is exception-only: source identification >= 0.95, work-item type >= 0.90, low-risk classification >= 0.95, owner >= 0.85 when needed, and next-action confidence >= 0.90.
- Decision, delegation, risk, artifact task, sensitive, legal, finance, contract, relationship, governance, tenant-affecting, or outbound work stays proposed-only until human approval.
- Human-in-the-loop is mandatory for outbound action, sensitive handling, and approval-boundary decisions.
- Maintain one canonical typed work-item record plus an append-only audit trail of both human and agent actions.
- Receipts must carry actor identity, authority basis, idempotency key, before/after state, source references, evidence references, policy flags, result, and failure semantics where applicable.
- Preserve logical atomicity whenever possible between status changes, provenance updates, and receipt logging.
- Keep delegation-first handling as the default for judgment-heavy items, but allow explicit non-delegable exceptions.
- Non-delegable exceptions include role-expected personal handling, negotiation or concession setting, delegation-created risk, and tradeoff decisions that Doug should own directly.

### Workflow and Architecture Rules

- Define the canonical storage-neutral contract before choosing the backend.
- Do not let Dataverse, Planner / To Do, Cosmos DB, Fabric, or any other storage choice become an accidental product dependency before requirements are explicit.
- Evaluate Microsoft-native intelligence planes before custom substrate: Work IQ, Dataverse intelligence / MCP, Power Apps MCP agent feed, Copilot Studio, Power Automate, Fabric IQ / Graph, and Fabric data agents.
- Use `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/microsoft-platform-fit-matrix-2026-07-07.md` before selecting a Microsoft service or custom gap build.
- Use BMAD skills, workflows, processes, documentation templates, and folder structure as the default harness for planning and implementation work.
- Build the repo as the source of truth for prompts, definitions, governance, ontology, evaluation, and implementation notes.
- Keep BMAD concerns in the harness layer; do not model BMAD itself as part of the shipped product architecture.
- Mark all tenant-specific unknowns as `VERIFY IN TENANT` instead of guessing.
- Use `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/tenant-readiness-checklist.md` before any live Microsoft 365, Power Platform, Dataverse, Fabric, Copilot Studio, or automation behavior.
- Do not request credentials, connect live systems, create app registrations, publish agents, or create live automations during documentation-first phases unless the project explicitly moves beyond Phase 1 constraints.

### Critical Don't-Miss Rules

- Do not treat all source records equally; surfaced queues should stay narrower than intake scope.
- Do not collapse source records, work items, graph entities, and audit receipts into one undifferentiated object.
- Do not create work items or graph links that cannot point back to a concrete source or explicit human input.
- Do not let the ontology become a decorative taxonomy; every retained type or edge should justify routing, context, provenance, or audit value.
- Do not let the graph become a full workflow engine too early; Phase 1 should stay lightly operational by design.
- Do not encode BMAD as a fixed-version product dependency or solution component.
- Do not author competing definitions in Dataverse glossary, Fabric IQ ontology, Copilot Studio knowledge, and repo docs; project from the Council Semantic Contract.
- Do not treat a Microsoft platform audit log as sufficient unless it can express Council receipt semantics.

---

## Usage Guidelines

**For AI Agents:**

- Read this file before implementing any code, model, schema, or workflow for the project.
- Prefer the more restrictive option when governance, provenance, or approval boundaries are unclear.
- Preserve the distinction between source records, work items, graph entities, and audit events in all implementations.
- If new project patterns emerge, update this file rather than encoding those assumptions only in code or prompts.

**For Humans:**

- Keep this file lean and focused on agent-relevant rules rather than broad product prose.
- Update it when the product model, storage contract, or governance boundaries change.
- Revisit it before architecture selection so backend choices are checked against the storage-neutral contract.
- Remove rules that become obvious implementation defaults and add rules only when they prevent meaningful mistakes.

Last Updated: 2026-07-07
