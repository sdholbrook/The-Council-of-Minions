# PRD Addendum: Source Synthesis for The Council of Minions

Updated: 2026-07-06

## Purpose

This addendum captures source ideas that should inform the PRD, ontology, product language, and Microsoft-first approach. It is intentionally broader than the PRD.

The sources are conceptual inputs, not implementation blueprints. The Council should not copy Open Brain's stack, Open Engine's Linear workflow, Open Skills packaging, or any non-Microsoft operational pattern as product requirements. The PRD should translate useful concepts into a Microsoft 365-native work experience; architecture can later decide concrete storage, services, and implementation mechanics.

## Source Set Reviewed

- Open Brain / OB1 repository: https://github.com/NateBJones-Projects/OB1
- Open Engine guide: https://unlock-ai.natebjones.com/open-engine
- Open Skills overview and directory: https://unlock-ai.natebjones.com/open-skills
- Open Stack field guide: https://unlock-ai.natebjones.com/guides/open-stack/open-stack-field-guide
- Knowledge Graph Guys homepage and blog: https://www.knowledge-graph-guys.com/ and https://www.knowledge-graph-guys.com/blog
- Local pasted extracts supplied by Doug covering Open Brain, Open Engine, AI memory, AlphaEvolve, organisational intelligence, and data mesh / ontology themes.

## Interpretation Boundary

The imported ideas are:

- Durable context across AI sessions.
- Repeatable agent capabilities.
- Visible work movement.
- Explicit receipts and audit.
- Human approval boundaries.
- Semantic organization of unique work data.
- A feedback cycle where human-reviewed outcomes improve future AI assistance.

The imported ideas are not:

- A requirement to use Supabase, Linear, Slack, MCP, OB1 schemas, Open Engine status names, or any source project's runtime stack.
- A requirement to implement a general personal brain or all-purpose agent operating system.
- A reason to weaken the Microsoft-first product direction.

Council product language should start from Microsoft work concepts: Outlook messages, Teams conversations, meetings, calendar events, files, SharePoint/OneDrive artifacts, Planner / To Do tasks, people, approvals, decisions, commitments, risks, and briefs.

## Source Idea Families

### 1. Open Skills: Repeatable Agent Capability

Open Skills contributes the concept of repeatable agent capability. The important ideas for Council are:

- A repeatable Minion behavior should encode trigger conditions, required inputs, boundaries, quality standards, and proof owed before completion.
- Skills should be small enough to compose instead of becoming large monolithic manuals.
- Skills carry personal taste, operating standards, and hard-won corrections from prior runs.
- Skills should have authority classes: manual-only, ask-before-use, and approved automatic use within a specific workflow.
- Skill expansion should require human approval when it adds capability, authority, data access, or external action.

Council implication:

- The Council needs a Minion Skill Registry as a product concept, not just a list of prompts.
- Each reusable capability should define when a Minion may use it, which Microsoft work context it may consider, what approval it needs, and what evidence it must leave.
- The PRD should describe the registry conceptually. Packaging belongs to architecture.

### 2. Open Brain: Durable Memory and Context

Open Brain contributes the concept of durable, governed context shared across AI work. The useful ideas for Council are:

- Durable context prevents repeated explanation across agents and sessions.
- Memory should be shared across Council experiences, not trapped in one chat thread.
- Agent-written memory should not automatically become binding instruction.
- Memory needs provenance, source references, review state, recall traces, and use policy.
- Personal and organisational context must be scoped: evidence, instruction, private, or excluded.
- The strongest conceptual contributions point toward entity extraction, provenance chains, reviewed memory, source references, and durable work operating context.

Council implication:

- The Council needs a governed Context and Memory Layer that distinguishes evidence from instruction.
- The first Microsoft-first version should not become a generic personal data lake. It should remember the context needed for Microsoft work decisions: people, projects, decisions, commitments, preferences, source records, prior receipts, delegation patterns, and standing rules.
- Memory write-back must be explicit and reviewable. A Minion may propose durable memory; Doug or a delegated reviewer decides whether it becomes instruction.

### 3. Open Engine: Work Movement, Queue, Ledger, Receipts

Open Engine contributes the concept of visible work movement, queue discipline, and receipts. Core ideas:

- Work should move through visible states rather than disappearing into chat.
- Standing context should be separate from finite work.
- Each agent or Minion should leave clear status evidence that humans can inspect.
- Blocked work is different from authority-bound work that requires human approval.
- Receipts should make agent activity legible: proposed, approved, delegated, blocked, held, resumed, completed, failed, reviewed.
- The work loop should be smoke-tested before trusting higher-stakes automation.

Council implication:

- Council should adapt work movement concepts to Microsoft work systems rather than copy Linear.
- The product should feel native to Microsoft work: messages, chats, meetings, files, tasks, approvals, owners, due dates, and briefs.
- The PRD should require visible receipts before autonomous workflow expansion.
- The first working Council should process proposed work items through Microsoft-first review and approval concepts before doing any outward action.

### 4. Knowledge Graphs and Ontology: Unique Data as AI Foundation

The Knowledge Graph Guys source set emphasizes that AI advantage comes from connected, semantically meaningful organisational data. Key ideas:

- AI needs the organisation's unique data, not generic internet averages.
- Data must be connected, consolidated, protected, and centered on what makes the organisation unique.
- Knowledge graphs map relationships and capture semantics, giving AI a foundation for reliable insight.
- Ontologies define the conceptual core: the terms, classes, and relationships that explain how the organisation thinks.
- LLMs can help build, connect, clean, structure, and enrich data, while ontologies and graphs constrain and improve LLM reasoning.
- Stable identifiers, URLs / URIs, semantic layers, data products, and graph-backed routing help avoid fragile one-off retrieval.
- The loop is co-creative: AI helps improve the graph, and the graph improves AI behavior.

Council implication:

- The Council needs a lightweight operational ontology from the beginning. It should not wait until after automation exists.
- The ontology should define work item, source record, person, project, decision, commitment, artifact, risk, skill, Minion, receipt, and audit event.
- The graph should be operationally useful but not become the workflow engine too early. It should drive routing, context, provenance, retrieval, and explanation.
- Every proposed work item should link back to source records and relevant graph entities.

### 5. AI / Ontology / Data Cycle

The practical cycle to bring into the Council is:

1. Capture source records from Microsoft surfaces.
2. Extract candidate work items, entities, relationships, risks, decisions, and commitments.
3. Link extracted facts to a small ontology and existing graph entities.
4. Present proposed work items with rationale, confidence, provenance, and recommended handling.
5. Route approved work through a visible queue and receipt ledger.
6. Write back audited receipts, decisions, owner corrections, and useful memory candidates.
7. Use reviewed write-backs to improve future extraction, routing, delegation, and briefing.

This cycle should be explicit in the PRD because it prevents two common failures: treating AI output as ungrounded prose, and treating the graph as decorative taxonomy.

## Microsoft-Native Council Mapping

| Source Pattern | Council Concept | Microsoft-First Translation | Requirement Direction |
| --- | --- | --- | --- |
| Open Skills | Minion Skill Registry | Reusable Council capabilities expressed in Microsoft work language | Each skill declares trigger, authority, allowed context, proof, and update policy. |
| Open Brain | Governed Context and Memory Layer | Durable Council memory about Microsoft work, people, projects, decisions, commitments, preferences, and receipts | Evidence vs instruction policy; reviewable memory proposals; source references and recall traces. |
| Open Engine | Work Item Queue and Receipt Ledger | Visible Microsoft work movement through proposed work, approvals, delegations, blockers, reviews, and completion | Explicit states, blocker/hold semantics, human approvals, reviews, and receipts. |
| Knowledge Graph | Council Meaning Graph | A Microsoft work meaning layer over source records, work items, people, meetings, files, decisions, risks, and commitments | Lightweight ontology for routing, context, provenance, and audit. |
| Data Mesh / Semantic Layer | Source and Entity Contracts | Stable identity and meaning for Microsoft work artifacts and relationships | Source metadata, entity links, provenance, and business-meaning definitions where needed. |

## Candidate Canonical Objects

- Source Record: email, chat, meeting note, document, manual capture, or other input before work-item extraction.
- Work Item: canonical execution object with type, status, owner, confidence, provenance, rationale, and graph links.
- Work Item Type: decision, delegation, follow_up, request, risk, artifact_task, meeting_action.
- Graph Entity: person, project, artifact, decision, commitment, organisation, topic, risk, role, skill, Minion.
- Receipt: append-only event recording claim, proposal, approval, block, hold, resume, done, review, memory proposal, or external action.
- Memory Candidate: proposed durable context with source, confidence, scope, and review state.
- Skill: reusable agent capability with trigger, authority, dependencies, verification, and update policy.
- Minion: agent role or capability bundle that acts within explicit authority boundaries.
- Brief: human-facing synthesis of the queue, risks, decisions, follow-ups, and new context.

## Product Direction Imported Into Council

The Council should be a Microsoft-first work orchestration layer for AI-assisted judgment work. It should combine:

- Skills: repeatable Minion behaviors and proof standards.
- Brain: governed durable context and memory.
- Engine: visible work movement with statuses, ledgers, receipts, blockers, and approvals.
- Graph: the semantic model that ties source records, work items, people, projects, commitments, and decisions together.

The product is not a generic AI council, a broad company-wide agent network, a copy of Open Brain or Open Engine, or a dashboard-first inbox assistant. It is a work-item-first Council that uses Microsoft work context to help Doug identify, route, decide, delegate, and follow through on judgment-heavy work.

## MVP Implications

MVP should include:

- Source capture from Outlook-first inputs, plus manual capture for non-email work.
- Explicit source-to-work-item extraction.
- Proposed work items with type, owner suggestion, rationale, confidence, urgency, risk if ignored, and recommended next action.
- Human approval gates for decision, delegation, risk, outbound action, sensitive handling, and authority expansion.
- A visible queue with statuses and receipts.
- A lightweight Meaning Graph / Council Graph that links work items to source records, people, projects, decisions, commitments, and artifacts.
- A Minion Brief that summarizes priority queue, decisions needed, delegations ready, blockers, receipts, and memory candidates.
- A skill registry for repeatable Minion behaviors.

MVP should not include:

- Live tenant writes without explicit phase approval.
- Broad auto-actions across Microsoft 365.
- A complete enterprise ontology.
- Generic all-purpose personal memory.
- Copying source-project implementation stacks or non-Microsoft operating surfaces.
- Full workflow-engine behavior embedded in the graph.
- Automatic conversion of agent-written memory into binding instruction.

## Original PRD Questions Superseded By Architecture Decisions

These questions were retained from source synthesis for traceability. The current PRD closes the architecture-blocking versions in `prd.md` Section 7 and `architecture-finish-decisions-2026-07-07.md`.

1. Is the first PRD scoped to Doug's private Council only, or to a future team-ready pattern with Doug as first operator?
2. Which Microsoft work concept should anchor the first user-visible queue: tasks, brief items, Outlook follow-ups, Teams approvals, or a combined Council queue?
3. Should human holds and approvals be framed around Teams, Outlook, the Minion Brief, or a combination?
4. What is the minimum acceptable durable Council memory concept for MVP before architecture selects storage?
5. What level of graph visibility does Doug need in the first UX: hidden retrieval layer, editable graph workbench, or brief-level relationship explanations only?
6. What current Microsoft tenant constraints need to be marked VERIFY IN TENANT before architecture?
