---
name: "Council Queue"
status: partial
updated: 2026-07-08
sources:
  - ../../prds/prd-The-Council-of-Minions-2026-07-06/prd.md
  - ../../prds/prd-The-Council-of-Minions-2026-07-06/addendum.md
  - ../../architecture/architecture-The-Council-of-Minions-2026-07-06/ARCHITECTURE-SPINE.md
  - ../../architecture/architecture-The-Council-of-Minions-2026-07-06/semantic-contract.md
  - ../../architecture/architecture-The-Council-of-Minions-2026-07-06/source-record-contract.md
  - ../../architecture/architecture-The-Council-of-Minions-2026-07-06/work-item-receipt-contract.md
  - ../../dataverse-mvp-schema-plan-2026-07-08.md
  - ../../implementation-readiness-report-2026-07-08.md
paired_design: DESIGN.md
assumptions:
  - "First MVP implementation uses a Dataverse model-driven app named Council Queue."
  - "The first UX pass is an operational contract, not a custom visual design."
  - "Live tenant writes are not approved; flows describe behavior after approval."
open_questions:
  - "Does Doug accept model-driven app UX for the first MVP proof?"
  - "Should Power Apps MCP agent feed be evaluated before or after the first manual model-driven review loop?"
  - "Which source body policy is approved for sample Source Records: link-only, hash-only, summary allowed, or full snapshot allowed?"
---

# Council Queue - Experience Spine

## Foundation

Single-surface Microsoft business application, optimized first for desktop/laptop review work. The practical MVP surface is a Dataverse model-driven app unless Doug rejects that path. `DESIGN.md` is the visual identity reference; this file defines behavior, information architecture, states, interactions, accessibility, and key flows.

The product-level surface is Council Queue plus Minion Brief. Outlook is the first intake/source context. Teams approvals, Power Apps MCP agent feed, Outlook actionable messages, Copilot Studio, Power Automate, and Fabric are candidate extensions after tenant validation. They do not replace the Council product-level review concept.

This UX contract does not authorize live tenant writes.

## Information Architecture

| Area | Surface | Reached from | Purpose |
| --- | --- | --- | --- |
| Intake | Source Records | Left nav / Intake group | Review captured Outlook/manual source evidence before extraction. |
| Intake | New Source Records | Intake view | Triage source records with extraction status `new`. |
| Intake | Held Source Records | Intake view | Review source records blocked by data boundary, sensitivity, uncertainty, or drift. |
| Work | Work Items | Left nav / Work group | Inspect canonical Work Items across states. |
| Work | Proposed Work Items | Work view | Review extracted work before approval or auto-creation trust expands. |
| Work | Needs Human Approval | Work view | Focus decisions, delegations, risks, sensitive items, memory promotions, skill authority changes, and tenant-affecting work. |
| Work | Blocked or Held | Work view | Resolve blockers, holds, missing evidence, or authority gaps. |
| Work | In Review | Work view | Inspect work awaiting review, receipt completion, or human decision. |
| Brief | Minion Briefs | Left nav / Brief group | Read snapshot projections of priority work, decisions, delegations, blockers, receipts, and memory candidates. |
| Brief | Recent Receipts | Brief group | Audit recent actions and state transitions. |
| Knowledge | Graph Entities | Left nav / Knowledge group | Review operational graph nodes used for routing, explanation, and audit. |
| Knowledge | Graph Edges | Knowledge group | Inspect relationship claims and grounding evidence. |
| Knowledge | Memory Candidates | Knowledge group | Review proposed durable context before instruction promotion. |
| Knowledge | Approved Instructions | Knowledge group | Inspect approved durable guidance and supersession state. |
| Knowledge | Skills | Knowledge group | Review Minion Skill trigger, context, authority, proof, and update policy. |
| Knowledge | Minions | Knowledge group | Review Minion roles and allowed skill scope. |
| Governance | Tenant Evidence | Left nav / Governance group | Store tenant readiness proof and constraints. |
| Governance | Platform Evaluations | Governance group | Record Microsoft-first platform selection evidence and deferrals. |

IA closure rule: every user-facing command must land on one of these surfaces or explicitly defer to a future non-MVP surface. No hidden inbox, agent chat, dashboard-only queue, or graph editor is part of MVP.

## Voice and Tone

Microcopy is direct, evidence-first, and boring on purpose. It should help Doug decide, not entertain him.

| Do | Don't |
| --- | --- |
| "Needs human approval." | "Your Minion needs you!" |
| "No external action approved." | "Ready to send." |
| "Source body policy is unknown." | "Something went wrong." |
| "Receipt required before state changes." | "Update status?" |
| "This Brief is a projection." | "This is the source of truth." |
| "VERIFY IN TENANT." | "Available." |

Use Council nouns exactly: Source Record, Work Item, Receipt, Meaning Graph, Memory Candidate, Approved Instruction, Skill, Minion, Minion Brief.

## Component Patterns

Behavioral rules. Visual specs live in `DESIGN.md`.

| Component | Use | Behavioral rules |
| --- | --- | --- |
| Source Record grid | Intake | Sort by captured time descending by default. Show source system, source kind, extraction status, data boundary policy, source object reference, captured by, and drift indicator. |
| Source Record form | Intake detail | Put source link/object reference, data boundary policy, sensitivity, retention/hold flags, extraction status, rationale, and related Work Items above less-used metadata. |
| Work Item grid | Work | Show title, type, state group, approval required, risk class, owner candidate, confidence, primary source, last receipt, and policy flags. |
| Work Item form | Work detail | Use a two-column review layout on desktop: decision fields and rationale on the left; source/provenance/receipts on the right. Stack on narrow screens. |
| Command bar | Any detail | Commands are context-aware and approval-aware. Commands that imply external action are disabled until an external-action approval receipt exists. |
| Approval command | Work detail | Append Receipt first or atomically with state projection. Capture before state, after state, authority basis, rationale, result, and policy flags. |
| Hold / block command | Work detail | Require reason text. Preserve current owner/rationale and append a Receipt. |
| Complete / fail command | Work detail | Require result rationale. Failure requires failure code and human-review flag. |
| Receipt timeline | Work, Brief | Append-only display ordered newest first by default, with a filter for verb and actor type. No inline editing in MVP. |
| Evidence panel | Source, Work, Receipt | Always shows source references, permission/sensitivity notes when available, confidence, rationale, and related receipt links. |
| Graph explanation panel | Work, Brief | Shows relationship rows, not a visual graph editor. Each row includes relationship type, target, rationale, confidence, and grounding source/receipt. |
| Brief snapshot | Brief | Display projection content and references back to Work Items and Receipts. Never allow Work Item state to be edited by changing Brief text. |
| Memory Candidate review | Knowledge | Approve/reject/supersede only through receipt-backed commands. Promotion creates or links Approved Instruction. |
| Skill authority review | Knowledge | Changes that add data access, tool use, external action, or authority require explicit approval before active status. |
| Tenant evidence record | Governance | Evidence records include environment, verifier, date, restriction, decision, evidence link/ref, and follow-up owner. |

## State Patterns

| State | Surface | Treatment |
| --- | --- | --- |
| Cold load | All model-driven views | Host app loading state. No custom splash, no hero screen. |
| Empty Intake | Source Records | Message: "No Source Records yet." Primary action: New Source Record if allowed. |
| Empty Proposed Work | Proposed Work Items | Message: "No proposed Work Items." Link to New Source Records. |
| Needs approval | Work Items | State badge, approval-required field, and command bar actions: Approve, Hold, Block, Review. |
| Approval blocked | Work detail | Show missing authority, missing source policy, missing tenant evidence, or missing receipt requirement. Disable action and show required evidence. |
| Data boundary unknown | Source detail | Mark as `unknown`; extraction commands require explicit source body policy or link-only/hash-only safe path. |
| Source drift detected | Source and Work detail | Show drift warning and require review before state movement if drift affects rationale. |
| Receipt missing | Work detail | State-change command must block or force receipt creation path. |
| External action requested | Work detail | Show as separate request/receipt. Do not send or publish from the same approval unless separately authorized. |
| Graph evidence uncertain | Graph explanation | Show confidence and uncertainty; do not auto-approve based on graph evidence. |
| Brief stale | Brief | Show generated time and source references. If records change, create a new Brief snapshot or mark refresh evidence; do not silently rewrite history. |
| Permission denied | Any area | Hide inaccessible records when platform security requires it; otherwise show "Access not available for this record." No sensitive details. |
| Tenant unverified | Governance / any dependent command | Show `VERIFY IN TENANT`; disable live-write dependent commands. |
| Offline / service unavailable | Any area | Model-driven app default error plus Council-specific note if mutation cannot be receipt-backed. |

## Interaction Primitives

- Primary interaction is review in grids and record forms.
- Every mutation command must either append a Receipt first or run in an implementation path that proves logical atomicity between receipt and state projection.
- No command may send email, create Planner tasks, post Teams messages, publish flows, publish agents, create app registrations, or mutate Fabric unless separate external-action approval exists.
- Keyboard navigation follows model-driven app defaults. Tab order must match visual reading order in custom components.
- Search and filtering should prioritize state group, work item type, risk class, approval required, owner candidate, source system, and latest receipt.
- Graph explanation is read-only in MVP.
- Brief generation is manual or explicitly commanded in MVP; no silent background rewriting.
- Power Apps MCP agent feed, Teams approvals, and Outlook actionable messages are future or evaluated surfaces, not hidden requirements for the first proof.

## Accessibility Floor

Behavioral accessibility; visual contrast belongs to `DESIGN.md`.

- WCAG 2.2 AA target for any custom UI, with model-driven app defaults used where available.
- Every command has a text label, tooltip/help text where needed, disabled reason, and screen-reader-accessible name.
- Status is never color-only. State group, risk, approval, and verification state must be text fields or accessible labels.
- Focus order: command bar, record summary, primary decision fields, evidence panel, related receipts, graph explanation, related records.
- Receipt timeline and graph explanation rows must be navigable by keyboard.
- Error messages identify the missing evidence or authority, not just "failed."
- Do not use hover-only actions for review-critical commands.
- Touch target and command density should follow model-driven app defaults; any custom command must remain usable at 200 percent zoom.

## Key Flows

### Flow 1 - Manual source to proposed Work Item

Doug is capturing a non-email commitment after a meeting.

1. Doug opens Intake / Source Records.
2. He selects New Source Record.
3. He sets source system `manual`, source kind `manual_note`, data boundary policy, captured time, source object reference, and rationale.
4. He saves the Source Record.
5. He runs Extract Proposed Work Item or manually creates a proposed Work Item from the Source Record.
6. The Work Item opens in `proposed` state with type, summary, rationale, confidence, owner candidate, urgency, risk class, recommended next action, and approval requirement.
7. **Climax:** The Work Item shows its primary Source Record and the Source Record remains separate from the Work Item.

Failure path: source body policy is unknown. The extraction command requires link-only/hash-only fallback or explicit policy before extraction.

### Flow 2 - Review and hold a risky Work Item

Doug is reviewing a proposed delegation that may affect a relationship.

1. Doug opens Work / Needs Human Approval.
2. He filters by type `delegation` and risk class `relationship`.
3. He opens the Work Item.
4. The form shows rationale, owner candidate, confidence, source link, graph explanation, and recent receipts.
5. Doug chooses Hold.
6. The command requires a hold reason and authority basis.
7. A Receipt is appended with before state `proposed`, after state `held`, actor, authority, rationale, and policy flags.
8. **Climax:** The Work Item moves to `held`, the Receipt appears in the timeline, and no external action occurs.

Failure path: receipt creation fails or cannot be verified. The Work Item state does not move; a failure or policy-denial receipt is required before retry.

### Flow 3 - Generate a Minion Brief snapshot

Doug wants one review surface for the current queue.

1. Doug opens Brief / Minion Briefs.
2. He chooses Generate Brief.
3. The Brief pulls priority Work Items, decisions needed, delegations ready, risks if ignored, blockers, recent receipts, and Memory Candidates.
4. The Brief displays generated time and source references back to Work Items and Receipts.
5. Doug opens a Work Item from the Brief.
6. He reviews or changes state on the Work Item, not inside the Brief text.
7. **Climax:** The Brief helps him decide, while Work Items and Receipts remain the source of truth.

Failure path: underlying records change after Brief generation. The Brief is marked stale or a new Brief snapshot is created; the old Brief is not silently rewritten.

### Flow 4 - Explain provenance through the Meaning Graph

Doug does not trust why a Work Item was recommended.

1. Doug opens a proposed Work Item.
2. He opens the Graph Explanation panel.
3. The panel lists source, person, project, topic, decision, commitment, risk, skill, Minion, and receipt relationships relevant to the recommendation.
4. Each relationship row shows edge type, target, rationale, confidence, and grounding source or receipt.
5. Doug identifies an uncertain relationship and marks the item for review or correction.
6. **Climax:** The explanation makes the recommendation inspectable without turning the graph into workflow state.

Failure path: graph evidence conflicts. The panel shows uncertainty and the Work Item remains unapproved until human review.

### Flow 5 - Approve a Memory Candidate

Doug sees a repeated pattern that should become durable guidance.

1. Doug opens Knowledge / Memory Candidates.
2. He opens a candidate linked to a Source Record and supporting Receipts.
3. He reviews scope, confidence, rationale, recall/use policy, and source evidence.
4. He chooses Approve Promotion.
5. The command creates an approval Receipt and creates or links an Approved Instruction.
6. **Climax:** The Approved Instruction becomes active with provenance; the Memory Candidate remains distinct from source evidence and instruction.

Failure path: Doug rejects the candidate. A rejection Receipt is appended and the candidate remains reviewable but does not influence future behavior.

## Responsive and Platform

| Surface width | Behavior |
| --- | --- |
| Desktop / wide laptop | Primary target. Left navigation visible; grids and forms use two-column review with evidence panel. |
| Narrow laptop / tablet | Left navigation may collapse. Evidence panel stacks below decision fields. Command bar remains visible. |
| Phone | Read and simple review only if model-driven app supports it. Do not claim phone-first MVP readiness. |

## MVP Acceptance Checks

1. Source Records, Work Items, Receipts, Graph Entities/Edges, Memory Candidates, Skills, Minions, Tenant Evidence, Platform Evaluations, and Briefs are visually distinct surfaces or record types.
2. Proposed Work Items can be reviewed from a focused view.
3. Approval/hold/block/complete/fail commands require receipt-backed rationale.
4. External action is visibly separate from internal review.
5. Minion Brief is clearly a projection.
6. Graph explanation is readable and read-only.
7. Tenant-unverified capabilities show `VERIFY IN TENANT`.
8. Data boundary policy is visible before source body content is captured.
9. Accessibility checks cover keyboard, labels, color independence, disabled reasons, and zoom.

## Inspiration and Anti-patterns

- Lifted from model-driven apps: records, views, forms, command bar, security-aware navigation, related records.
- Lifted from Microsoft approval surfaces: explicit review outcomes, actor identity, and evidence.
- Rejected: inbox-only assistant. Outlook is source context, not the whole product.
- Rejected: dashboard-first AI cockpit. The queue and receipts carry work; a dashboard can summarize later.
- Rejected: graph editor. MVP needs graph explanations, not graph manipulation.
- Rejected: autonomous agent console. Minions may assist only inside authority and receipt boundaries.
