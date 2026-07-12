---
title: "PRD: The-Council-of-Minions"
status: architecture-ready
created: 2026-07-06
updated: 2026-07-07
---

# PRD: The-Council-of-Minions

## 0. Discovery State

This PRD is architecture-ready for the current BMAD planning pass. It synthesizes:

- The active project context at `_bmad-output/project-context.md`.
- The forged Council idea at `_bmad-output/forge/council-of-minions/forged-idea.md`.
- The Open Engine / Open Skills / Open Brain / Knowledge Graph source synthesis in `addendum.md`.
- The architecture spine and Microsoft platform research under `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/`.

The PRD should remain storage-neutral until architecture. Microsoft-native surfaces are product constraints and integration targets, not settled backend decisions.

Clarification: the source projects are conceptual inputs, not implementation patterns to copy. The PRD should capture the useful ideas and translate them into a Microsoft-first Council experience.

## 1. Product Thesis

The Council of Minions is a Microsoft-first, work-item-first orchestration layer for AI-assisted judgment work. It helps Doug turn Microsoft work context into clearer decisions, delegations, follow-ups, risks, and commitments while preserving provenance, human approval, and a lightweight meaning graph.

The core bet is that AI work becomes reliable when four layers reinforce each other:

- **Skills:** repeatable Minion behaviors with triggers, boundaries, and proof standards.
- **Brain:** governed durable context that separates evidence from instruction.
- **Engine:** visible work movement through queue states, blockers, approvals, and receipts.
- **Graph:** a lightweight operational ontology connecting source records, work items, people, projects, decisions, commitments, artifacts, skills, and receipts.

## 2. Source-Informed Direction

### 2.1 Skill Concept Direction

Council should include a Minion Skill Registry as a product concept. Each reusable Minion behavior must define when it is used, which Microsoft work context it can consider, what authority it has, and what verification or receipt it owes before completion.

### 2.2 Memory Concept Direction

Council should include governed durable context. Agent-written memory starts as evidence or a memory candidate, not binding instruction. Promotion to instruction requires human review or a trusted source rule.

### 2.3 Work Movement Concept Direction

Council should include visible work movement and receipts. Work items should move through understandable states. Blockers, human holds, reviews, delegated follow-ups, failures, and completed work should leave durable receipts.

### 2.4 Knowledge Graph Direction

Council should use a lightweight operational ontology from the start. The graph should support routing, provenance, retrieval, explanation, and audit without becoming a full workflow engine in MVP.

## 3. Microsoft-First Interpretation

The Council should speak Microsoft work language first. Source concepts should be translated into the terms Doug already works in:

- Outlook messages and threads.
- Teams conversations and approvals.
- Meetings and calendar commitments.
- Files, documents, and SharePoint / OneDrive artifacts.
- Planner / To Do-style tasks and follow-ups.
- People, roles, owners, projects, commitments, risks, and decisions.
- Briefs that summarize what needs Doug's judgment.

The PRD should not choose backend storage or copy non-Microsoft operating surfaces. Copilot Studio, M365 Agent Templates, Power Automate, Microsoft Graph, Planner / To Do, Loop, SharePoint, OneDrive, and Teams are Microsoft-first product context and architecture candidates; architecture later decides which are actual implementation components.

## 4. Initial Glossary

- **Source Record** - An email, chat, meeting note, document, manual capture, or other input before work-item extraction.
- **Work Item** - The canonical execution object with type, owner, status, confidence, rationale, provenance, and graph links.
- **Work Item Type** - A controlled type such as decision, delegation, follow_up, request, risk, artifact_task, or meeting_action.
- **Meaning Graph** - The lightweight operational graph connecting source records, work items, people, projects, decisions, commitments, artifacts, skills, receipts, and context.
- **Receipt** - An append-only event recording proposal, claim, approval, block, hold, resume, review, completion, failure, memory proposal, or external action.
- **Memory Candidate** - Proposed durable context that needs review before it can guide future behavior as instruction.
- **Skill** - A reusable Minion procedure with trigger, inputs, tools, authority, boundaries, verification, and update policy.
- **Minion** - A role-bound agent capability or agent persona that acts within explicit Council authority boundaries.
- **Minion Brief** - The human-facing summary of priority work, decisions needed, delegation packages, blockers, receipts, and memory candidates.

## 5. Candidate Capability Groups

### 5.1 Source Intake and Extraction

The Council captures Microsoft source records and proposes work items from them. The extraction step must preserve source references, rationale, confidence, and uncertainty.

### 5.2 Work Item Queue

The Council maintains a visible queue of proposed, approved, blocked, held, in-review, and completed work items. The queue should support human review before sensitive or outward-facing action.

### 5.3 Delegation Decision Support

The Council prepares delegation-ready packages with suggested owner, rationale, confidence, recommended stance, urgency, internal handoff draft, and external reply draft when useful.

### 5.4 Meaning Graph and Context

The Council links work items to people, projects, source records, decisions, commitments, artifacts, and prior receipts. It uses those links to improve routing, briefing, explanation, and audit.

### 5.5 Skill Registry

The Council maintains reusable Minion skills and authority classes so repeated work becomes reliable without silently expanding what agents are allowed to do.

### 5.6 Receipts and Audit

The Council records append-only receipts for work-item state changes, approvals, holds, delegation, memory proposals, and any external action.

### 5.7 Minion Brief

The Council produces a brief that shows the priority queue, decisions needed, delegations ready, risks if ignored, blockers, recent receipts, and memory candidates.

## 6. MVP Scope Direction

### 6.1 In Scope

- Work-item-first model with source records as inputs.
- Outlook-first intake plus manual capture for non-email work.
- Minion Brief plus Council Queue as the first review and approval surface.
- Proposed work items with type, rationale, confidence, urgency, owner suggestion, and recommended next action.
- Human approval gates for decision, delegation, risk, outbound action, sensitive handling, and authority expansion.
- Lightweight Meaning Graph for routing, provenance, retrieval, explanation, and audit.
- Receipt ledger for agent and human actions.
- Brief-level relationship explanations and source/provenance links, without a graph editor.
- Governed memory candidates with recall/use policy before promotion to approved instruction.
- Storage-neutral contract before backend selection.

### 6.2 Out of Scope for MVP

- Live tenant writes or published automations without explicit phase approval.
- Broad company-wide rollout.
- A complete enterprise ontology.
- Generic all-purpose personal memory.
- Treating the graph as a full workflow engine.
- A graph editor or complete ontology workbench.
- Automatic promotion of agent-written memory into binding instruction.
- Backend-specific product commitments before architecture.

## 7. Closed Architecture Decisions

- Decision: The product model is work-item-first; email is one source, not the product boundary.
- Decision: MVP intake is Outlook-first plus manual capture. Outlook remains the first source and entry point, but not the only product surface.
- Decision: The first review surface is the Minion Brief plus Council Queue. Outlook links back to source messages and may host notifications or drafts, but review state belongs to the Council surface.
- Decision: Human holds and approvals are product-level Council actions. Teams approvals, Outlook actionable messages, Power Apps agent feed, or model-driven app commands remain candidate implementations after tenant validation.
- Decision: MVP is Doug-private first, with team-ready object contracts and authority boundaries.
- Decision: Work items require source provenance and rationale.
- Decision: Human-in-the-loop is mandatory for outbound action and sensitive handling.
- Decision: The graph is lightly operational in MVP.
- Decision: MVP graph visibility is brief-level relationship explanation and provenance, not graph editing.
- Decision: Minimum durable memory is `Memory Candidate` plus `approved instruction`, with source, recall/use policy, and receipts before durable influence.
- Decision: The Council owns one Semantic Contract. Dataverse semantic models, Fabric IQ ontology, Fabric Graph, Copilot Studio knowledge, Dataverse business skills, and future agent knowledge planes project from it.
- Decision: Source projects contribute concepts, not implementation requirements.
- Decision: The PRD will use Microsoft-first product language while avoiding premature backend architecture.

## 8. Implementation Follow-Ups

1. Validate tenant availability, admin settings, DLP, sensitivity labels, retention boundaries, Copilot credits, Fabric capacity, and Power Platform environment strategy before live tenant work.
2. Use the architecture fit matrix before selecting Dataverse, Power Apps, Copilot Studio, Power Automate, Work IQ, Fabric IQ / Graph, or custom services.
3. Create epics and stories only after the Source Record, Work Item / Receipt, Semantic Contract, Auto-Creation Policy, and tenant-readiness contracts are reviewed.
