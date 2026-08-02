# Epic 5 Context: Skill Authority and Microsoft Platform Governance

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Give the Council governed control over what Minions are allowed to do and which Microsoft platform capabilities the product may rely on. Users can manage reusable Minion skills, approval-gate any expansion of agent authority, evaluate Microsoft-native planes before building custom substrate, record service-selection evidence, and enforce tenant readiness and `VERIFY IN TENANT` boundaries so the MVP never assumes live tenant features, permissions, licensing, or data boundaries that have not been proven with evidence.

## Stories

- Story 5.1: Maintain the Minion Skill Registry
- Story 5.2: Approve Skill Authority Expansion
- Story 5.3: Record Microsoft Platform Evaluation Evidence
- Story 5.4: Enforce Tenant Readiness and VERIFY IN TENANT Gates (HELD in sprint until 5.7 lands)
- Story 5.5: Validate Dataverse MVP Operational Store Readiness
- Story 5.6: Manage Phase 2 Knowledge and Analytics Projections
- Story 5.7: The tenant-readiness validator must be proven to fail (mid-sprint addition, renamed from 5-4b; spec lives in implementation-artifacts/stories/)

## Requirements & Constraints

- Every reusable Minion capability lives in a Skill Registry record declaring trigger, allowed context, required inputs, authority class, approval requirements, proof owed, update policy, and status. Inactive/deprecated/suspended skills must be blocked or flagged when recommended.
- Any skill installation or update that adds data access, external action, tool use, or authority requires human approval before activation, producing a Receipt with authority basis, rationale, before/after authority, and evidence references. Denials keep the skill inactive/constrained with visible rationale.
- Microsoft-native intelligence planes (Work IQ, Dataverse intelligence/MCP, Power Apps MCP agent feed, Copilot Studio, Power Automate, Fabric IQ/Graph, Fabric data agents) must be evaluated before any custom service is selected; a custom service must cite the specific Microsoft-native gap or tenant constraint it addresses, recorded before implementation.
- Service-selection evidence records must capture evaluated candidates, tenant gates, permission/DLP impact, licensing/cost, ALM path, contract gaps, decision, and review reference.
- Anything touching the live tenant (connectors, published agents, app registrations, data writes, automations, external actions) stays marked `VERIFY IN TENANT` until tenant evidence exists; no live write before the approved boundary is documented. Preview, admin-gated, cost-gated, capacity-dependent, or tenant-specific capabilities are non-binding until verified.
- Tenant validation evidence must record tenant identity, environment, auth user, licensing/capacity assumptions, relevant settings, restrictions found, decision (available / unavailable / available with constraints / not tested), and follow-up owner. MVP minimum verification: Outlook/Graph read path, chosen storage availability, human review surface, DLP/sensitivity behavior, audit/receipt persistence path, and the no-live-write boundary.
- No live tenant writes, published automations, app registrations, or broad permission requests during documentation-first phases.

## Technical Decisions

- Dataverse is the approved MVP operational system of record (target environment `sdhdev`, environment ID `ba9a96b2-f562-40f6-931d-6b55873954ee`), storing Work Items, Receipts, Skill Registry records, tenant readiness evidence, and service-selection evidence. Native Microsoft systems (Outlook, Teams, SharePoint) remain source of truth for source artifacts.
- Dataverse readiness sequence: read-only preflight (`pac auth who`, `pac env who`, environment settings) must prove expected environment ID, organization ID, and user context before any write; write scripts stay disabled until Doug approves sandbox writes and publisher prefix; schema writes are tied to the current story's needed objects (the dry-run manifest may describe the full target shape without forcing early creation).
- Evaluation order for platform selection: Work IQ for M365 source context; Dataverse for operational records and review candidates; Power Apps MCP agent feed / model-driven apps for human review; Copilot Studio / Power Automate only after receipt and approval contracts are enforceable; Fabric IQ/Graph/data agents only after MVP contracts stabilize.
- The Council Semantic Contract is the canonical semantic authority. Fabric IQ, Fabric Graph, Copilot Studio knowledge, Dataverse business skills, and future agent knowledge planes are projections/bindings only — they must never own workflow state, approval movement, or domain vocabulary. Deferred phase-2 projections must record why deferred, evidence still needed, and the contract gap they may later address.
- Receipt-first mutation applies to all governance actions: approvals, denials, and authority changes append Receipts; state is a projection from canonical records plus receipts.
- Council terms must be encoded in Dataverse display names, descriptions, relationships, views, forms, and glossary entries so the Dataverse semantic model projects approved meaning.
- Use exact domain nouns (Skill, Minion, Receipt, Memory Candidate, etc.); no backend IDs as product identifiers; ISO 8601 timestamps; skills prove use via Receipts.

## UX & Interaction Patterns

- Skills surface lives in the Knowledge group: review trigger, context, authority, proof, and update policy; skill authority changes require explicit approval before active status.
- Tenant-unverified capabilities display `VERIFY IN TENANT` and disable live-write-dependent commands; blocked approvals must show the specific missing authority, evidence, or receipt requirement, never a generic failure.
- Tenant Evidence and Platform Evaluation records are visually distinct record types, not generic items.

## Cross-Story Dependencies

- Story 5.2 builds on the epic-2 human approval boundary and receipt ledger semantics (approval-gated actions, receipt-backed state change).
- Story 5.4 is HELD pending Story 5.7: a 07-14 orchestrator probe showed the tenant-readiness slice validator accepted fabricated evidence (it cannot fail), so 5.7 must land a validator with committed negative fixtures and derivation-based checks before 5.4 proceeds.
- Story 5.5 depends on tenant evidence patterns from 5.4 and gates all Dataverse schema writes for every other epic's operational records.
- Story 5.6 depends on the Council Semantic Contract projection rules established in epic 4 (semantic contract without dual authoring).
