---
title: "MVP Overnight Plan"
project: "The-Council-of-Minions"
status: active
created: 2026-07-08
owner: Doug
current_branch: codex/update-bmad-harness-context
current_gate: local_readiness_gaps_addressed_tenant_gated
primary_blocker: "UX contract and runtime setup now have local artifacts; live implementation remains blocked by tenant validation, source/write approvals, publisher prefix, and model-driven app acceptance."
---

# MVP Overnight Plan

## Purpose

Create the overnight execution plan for getting The Council of Minions MVP as far as possible using the BMAD approach without crossing the current architecture boundaries.

This plan treats BMAD as the delivery harness, not as product architecture. The product remains Microsoft-first, work-item-first, Dataverse-proposed, and tenant-gated until the required evidence exists.

## Current State

- Branch: `codex/update-bmad-harness-context`
- Open PR: `https://github.com/sdholbrook/The-Council-of-Minions/pull/1`
- PRD status: architecture-ready
- Architecture status: final for epic/story planning
- Current dirty artifacts: planning packet plus Dataverse dry-run implementation prep under `_bmad-output/`
- Proposed storage decision: `_bmad-output/planning-artifacts/storage-decision-record-2026-07-08.md`
- Live tenant kickoff checklist: `_bmad-output/planning-artifacts/live-tenant-kickoff-2026-07-08.md`
- Dataverse schema plan: `_bmad-output/planning-artifacts/dataverse-mvp-schema-plan-2026-07-08.md`
- Live validation runbook: `_bmad-output/planning-artifacts/live-tenant-validation-runbook-2026-07-08.md`
- Tenant evidence template: `_bmad-output/planning-artifacts/tenant-validation-evidence-2026-07-08.md`
- MVP sprint plan: `_bmad-output/planning-artifacts/mvp-sprint-plan-2026-07-08.md`
- First vertical-slice work orders: `_bmad-output/planning-artifacts/first-vertical-slice-work-orders-2026-07-08.md`
- Implementation readiness report: `_bmad-output/planning-artifacts/implementation-readiness-report-2026-07-08.md`
- Dataverse schema manifest: `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json`
- Dataverse manifest validator: `_bmad-output/implementation-artifacts/dataverse-manifest-validate.ps1`
- Dataverse read-only preflight script: `_bmad-output/implementation-artifacts/dataverse-preflight-readonly.ps1`
- Dataverse dry-run deployment plan script: `_bmad-output/implementation-artifacts/dataverse-deployment-plan.ps1`
- Tenant decision packet: `_bmad-output/implementation-artifacts/tenant-decision-packet.json`
- Tenant decision validator: `_bmad-output/implementation-artifacts/tenant-decision-packet-validate.ps1`
- Tenant local prerequisite guard: `_bmad-output/implementation-artifacts/tenant-prereq-local-check.ps1`
- Sprint status tracking: `_bmad-output/implementation-artifacts/sprint-status.yaml`
- UX contract: `_bmad-output/planning-artifacts/ux-designs/ux-The-Council-of-Minions-2026-07-08/DESIGN.md` and `EXPERIENCE.md`
- Runtime/setup baseline: `_bmad-output/implementation-artifacts/runtime-setup-baseline-2026-07-08.md`
- Local validation script: `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1`
- Current BMAD workflow state: `bmad-create-epics-and-stories`, `bmad-check-implementation-readiness`, and `bmad-sprint-planning` are complete; next formal story-cycle gate is `bmad-create-story`
- No custom application runtime manifest exists yet in the repo; the practical MVP runtime is documented as Dataverse/model-driven app pending Doug approval
- Dataverse is proposed as the MVP operational store, pending Doug's explicit approval and tenant verification
- No tenant validation evidence exists yet
- Local CLI prerequisite evidence exists; active PAC auth is not currently pointed at the Council target environment
- Required Doug decisions are now captured in a machine-readable packet, but remain pending

## Meaning of "MVP Finished"

There are three possible completion levels. The overnight default is Level 1 plus as much Level 2 preparation as possible.

| Level | Meaning | Can complete overnight without more input? | Notes |
| --- | --- | --- | --- |
| Level 1 | BMAD planning finished | Complete | Includes epics, stories, coverage, readiness report, and sprint-status tracking. |
| Level 2 | Implementation-ready MVP slice | Partially | Story set, solution decision packet, local validation plan, runtime/setup baseline, UX contract, and first vertical-slice work orders exist; tenant validation and approvals remain open. |
| Level 3 | Live Microsoft tenant MVP | No | Requires tenant identity, permissions, licensing, DLP/security evidence, admin settings, and explicit authorization for live Microsoft work. |

## Required From Doug Before Overnight Work Can Fully Run

### Required Now

1. Resolve remaining implementation-readiness gates before live Phase 4 work: tenant validation, source/write boundaries, publisher prefix, model-driven app acceptance, and explicit write approval.

### Required Before Any Live Microsoft Work

1. Target tenant and environment name.
2. User identity and admin/owner for validation.
3. Whether live reads are allowed.
4. Whether live writes are forbidden, allowed only in a sandbox, or allowed after approval.
5. Microsoft 365, Power Platform, Dataverse, Copilot, and Fabric licensing/capacity assumptions.
6. DLP, sensitivity label, retention, and data boundary constraints.
7. Human approval owner for decisions, delegations, outbound actions, memory promotion, skill expansion, and tenant writes.

### Useful But Not Blocking For Planning

1. Whether to bias solution architecture toward Dataverse as the first operational-store candidate.
2. Whether a local prototype is desired before tenant validation.
3. Whether the first UX should be model-driven app, Power Apps agent feed, Teams/Approvals, Outlook-first surface, or a local mocked Council Queue for design validation.
4. Whether "finished by morning" means planning-complete, implementation-ready, or a working local mock.

## Overnight BMAD Work Tracks

### Track 0 - Control and Safety

Goal: Keep the work aligned with the architecture packet and avoid accidental live-tenant or backend commitments.

Tasks:

1. Keep `epics.md` as the active BMAD epics artifact.
2. Keep all live Microsoft work marked `VERIFY IN TENANT`.
3. Keep BMAD in the harness layer only.
4. Preserve `Source Record`, `Work Item`, `Receipt`, `Memory Candidate`, `Graph Entity`, `Skill`, `Minion`, and `Minion Brief` as distinct concepts.
5. Do not begin live tenant writes or implementation story execution until readiness gaps are explicitly handled.

Exit evidence:

- `git status` shows only intentional planning artifacts.
- Every new artifact cites the PRD and architecture packet rather than inventing new product definitions.

### Track 1 - Finish BMAD Epics and Stories

Goal: Complete the current BMAD epics/stories workflow after confirmation.

Tasks:

1. `bmad-create-epics-and-stories` completed.
2. `bmad-check-implementation-readiness` completed with `NEEDS WORK`.
3. Correct tenant/write readiness gaps before implementation.

Actual epic shape:

1. Source Intake and Proposed Work Items.
2. Council Queue, Approval, and Receipt Ledger.
3. Minion Brief and Delegation Support.
4. Meaning Graph and Memory Governance.
5. Skill Authority and Microsoft Platform Governance.

Exit evidence:

- `_bmad-output/planning-artifacts/epics.md` has no placeholder sections.
- Frontmatter records the completed epics workflow.
- Requirements coverage maps all FR/NFR/AR items to epics or stories.

### Track 2 - Adversarial Review and Readiness

Goal: Prove the story set is coherent before implementation starts.

Tasks:

1. Run an adversarial project review against the story set.
2. Check for object collapse risk: Source Record, Work Item, Receipt, Memory Candidate, and Graph Entity must not become one generic row/document.
3. Check for Microsoft-platform drift: Dataverse, Fabric, Copilot, Power Automate, Work IQ, and Power Apps must remain candidates until tenant evidence exists.
4. Check for approval-boundary drift: no story may imply external action, sensitive handling, tenant writes, or memory promotion without approval.
5. Run implementation-readiness review after epics/stories exist.

Exit evidence:

- Review artifact under `_bmad-output/planning-artifacts/` or `_bmad-output/test-artifacts/`.
- Readiness status clearly says either implementation-ready, implementation-ready with conditions, or blocked by explicit gates.

### Track 3 - MVP Sprint and Backlog Sequencing

Goal: Turn the story set into an ordered MVP execution plan.

Tasks:

1. Identify the first vertical slice that demonstrates source-to-work-item behavior without live tenant writes.
2. Sequence dependencies so contracts, mock source records, work item shell, receipts, and review surface come before Microsoft integration.
3. Mark tenant-validation stories separately from local/prototype stories.
4. Define a "no-live-write" MVP path and a later "tenant-validated" path.
5. Produce sprint-ready story order with acceptance criteria and verification notes.

Likely first vertical slice:

1. Load or capture a mock Outlook Source Record.
2. Extract a proposed Work Item with rationale, confidence, owner candidate, urgency, and recommended next action.
3. Display it in a Council Queue / Minion Brief surface.
4. Apply human approval/hold/block/review state changes.
5. Append Receipts for every mutation.
6. Show relationship/provenance explanation without graph editing.

Exit evidence:

- Sprint plan maps story order, dependencies, gates, and validation commands.
- First vertical slice has a clear start and done condition.
- Provisional work orders trace back to extracted FR/NFR/AR requirements pending formal BMAD story generation.

### Track 4 - Solution Decision Packet

Goal: Prepare implementation decisions without pretending tenant evidence exists.

Tasks:

1. Draft a storage decision record using Dataverse as the proposed MVP operational store.
2. Draft Microsoft plane evaluation records for Work IQ, Dataverse intelligence/MCP, Power Apps MCP agent feed, Copilot Studio, Power Automate, Fabric IQ/Graph, and Fabric data agents.
3. Create a tenant evidence backlog from `tenant-readiness-checklist.md`.
4. Define local mock interfaces for source intake, extraction, receipts, queue, and graph projection so implementation can begin without live Microsoft dependencies if Doug approves.
5. Draft the Dataverse MVP schema plan and live validation runbook.
6. Prepare a machine-readable Dataverse schema manifest, manifest validator, and dry-run deployment plan.

Exit evidence:

- Decision records distinguish selected, candidate, deferred, and `VERIFY IN TENANT`.
- No story requires a live tenant before the tenant gate is complete.
- Dataverse table, column, relationship, view, app, security, and validation plan is explicit before any write.
- Deployment prep remains dry-run only until Doug approves writes and `pac env who` proves the target environment.

### Track 5 - Implementation Preparation

Goal: Prepare the first implementation run without guessing the runtime.

Tasks:

1. Inventory repo runtime options and confirm no app manifest exists.
2. Recommend an implementation path only after the story set is complete.
3. If a local prototype is desired, propose a minimal runtime with mock data and no tenant writes.
4. Define test strategy for object contracts, receipt append behavior, approval boundaries, and source drift.
5. Prepare the first `bmad-create-story` / `bmad-dev-story` candidates.

Exit evidence:

- Implementation readiness artifact identifies the first story to build.
- Validation plan lists local tests and review gates.
- Runtime decision is explicit, not accidental.

### Track 6 - Git and PR Hygiene

Goal: Keep the open PR useful and mergeable.

Tasks:

1. Commit planning artifacts in coherent chunks.
2. Update PR #1 with the epics/story and readiness summary.
3. Keep branch tracking clean.
4. Do not merge to `main` unless Doug explicitly requests it.

Exit evidence:

- Working tree clean or intentionally staged.
- PR body reflects the latest artifacts.

## Overnight Execution Order

1. Invoke BMAD completion handoff. Complete.
2. Run implementation-readiness review. Complete, status `NEEDS WORK`.
3. Produce sprint/backlog sequencing. Complete, including `sprint-status.yaml`.
4. Produce solution decision packet and tenant evidence backlog. Prepared, tenant evidence still empty.
5. Prepare first implementation story. Pending tenant/write boundary decision.
6. Validate files with `git diff --check` and BMAD config resolver.
7. Validate the tenant decision packet and local PAC prerequisite guard.
8. Commit and push artifacts if the packet is coherent.
9. Update PR #1.

## Explicit Non-Goals Overnight

- No live Microsoft tenant writes.
- No app registrations.
- No published Copilot Studio agents.
- No Power Automate flows.
- No broad Graph permissions.
- No Dataverse environment changes without explicit live-write approval and preflight evidence.
- No Fabric capacity/workspace changes.
- No backend commitment without a decision record and tenant evidence.
- No graph editor.
- No automatic memory promotion.
- No outbound messages or external actions.

## Open Decisions

| Decision | Default until Doug answers | Why |
| --- | --- | --- |
| Implementation readiness | Complete with local follow-up artifacts | UX contract and runtime setup exist; tenant validation and write approvals remain open. |
| MVP finish level | Level 1 planning complete plus Level 2 prep | Level 3 requires tenant evidence. |
| Storage candidate | Dataverse proposed as MVP operational system of record; awaiting Doug approval | Microsoft-first and aligned with model-driven app, Dataverse intelligence, Power Apps MCP, and receipt/governance needs. |
| Runtime | Dataverse/model-driven app proposed as practical MVP runtime | Runtime/setup baseline exists; Doug approval and tenant validation still required. |
| UX surface | Minion Brief plus Council Queue in model-driven app pattern | UX spines exist; Doug acceptance of model-driven app surface still required. |
| Tenant work | Read-only preflight only after interactive login; no writes | Architecture requires `VERIFY IN TENANT` and Doug approval before mutation. |
| Tenant decision packet | Pending | Must pass `tenant-decision-packet-validate.ps1 -RequireComplete` before write approval. |

## Completion Criteria For This Goal

The active MVP goal can be marked complete only when current evidence proves:

1. BMAD epics/stories are complete and reviewed.
2. Requirements coverage is complete.
3. Implementation-readiness status is documented.
4. Sprint/backlog sequencing and `sprint-status.yaml` exist.
5. First implementable MVP slice is defined.
6. Required Doug inputs and tenant gates are listed.
7. Git/PR state is clean and updated.
8. Any implementation work performed has been verified.

Until then, the goal remains active.
