---
title: "MVP Sprint Plan"
project: "The-Council-of-Minions"
status: live-dataverse-foundation-and-demo-seed-complete
created: 2026-07-08
depends_on:
  - epics.md
  - dataverse-mvp-schema-plan-2026-07-08.md
  - live-tenant-validation-runbook-2026-07-08.md
  - tenant-validation-evidence-2026-07-08.md
  - ux-designs/ux-The-Council-of-Minions-2026-07-08/DESIGN.md
  - ux-designs/ux-The-Council-of-Minions-2026-07-08/EXPERIENCE.md
  - ../implementation-artifacts/runtime-setup-baseline-2026-07-08.md
---

# MVP Sprint Plan - 2026-07-08

## Purpose

Define the provisional MVP sprint sequence now that the formal `bmad-create-epics-and-stories` workflow has generated stories, passed final validation, and `bmad-check-implementation-readiness` has completed.

This plan started as implementation preparation, not authorization for live tenant work. As of 2026-07-08, Doug approved guarded Dataverse writes after target preflight. The live Dataverse foundation, table-backed model-driven app, deterministic receipt-backed demo seed, receipt-backed state transitions, sitemap groups, pinned model-driven forms/views, and post-curation screen proof now exist in `sdhdev`. Live Outlook/Graph read approval and broader governance carry-forward remain open.

## Planning Boundary

- Dataverse is the approved MVP operational store for this tenant slice.
- Fabric IQ / Fabric Graph are deferred to phase 2 graph/analytics projection.
- Outlook/Graph source access is tenant-gated.
- Dataverse live writes are approved only through the guarded apply script after target preflight.
- Source body policy is `link_only` for sample/demo records.
- Publisher prefix is `com`.
- The runtime path is Dataverse plus model-driven app `Council Queue`.
- Focused UX contract exists for the Council Queue / Minion Brief surface.
- Live tenant changes have been made in `sdhdev` and are recorded in `dataverse-live-validation-2026-07-08.md`.
- Sprint status tracking exists at `_bmad-output/implementation-artifacts/sprint-status.yaml`.
- Local validation command exists at `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1`.

## MVP Outcome

The MVP is done when a user can:

1. Capture or simulate a Microsoft Source Record.
2. Extract a proposed Work Item with rationale, confidence, risk/urgency, and source provenance.
3. Review the Work Item in a Council Queue / Minion Brief surface.
4. Approve, hold, block, review, complete, or fail the Work Item.
5. See Receipts for every meaningful mutation.
6. See brief-level relationship/provenance explanation.
7. Keep Memory Candidates and Skill authority changes review-gated.
8. Prove tenant readiness and no-live-write boundaries before connecting live Microsoft surfaces.

## Sprint Sequence

### Sprint 0 - Tenant Readiness and Decision Closure

Goal: close the minimum readiness decisions, establish the first runnable implementation boundary, and authenticate to the provided Dataverse environment without making schema changes.

Stories:

| ID | Story | Depends on | Done when |
| --- | --- | --- | --- |
| S0.0 | Establish runtime and validation baseline | Readiness report | Done locally: `_bmad-output/implementation-artifacts/runtime-setup-baseline-2026-07-08.md` and `council-mvp-local-validate.ps1`. |
| S0.1 | Confirm BMAD planning gates | Completed BMAD solutioning gates | Epics, readiness report, and `sprint-status.yaml` exist. |
| S0.2 | Approve storage decision | Doug approves Dataverse/Fabric split | Storage decision status can move from proposed to accepted. |
| S0.3 | Authenticate to Power Platform | Doug completes `pac auth create` | `pac env who` proves expected environment/org IDs. |
| S0.4 | Record tenant evidence | S0.3 | `tenant-validation-evidence-2026-07-08.md` has command evidence. |
| S0.5 | Confirm live boundaries | Doug answers live reads/writes/source policy | Runbook allows or forbids next phases clearly. |
| S0.6 | Confirm publisher prefix and solution naming | Doug supplies prefix | Schema write plan is tenant-ready. |
| S0.7 | Define focused UX contract | Readiness report | Done locally: `ux-designs/ux-The-Council-of-Minions-2026-07-08/DESIGN.md` and `EXPERIENCE.md`; Doug still needs to accept model-driven app surface. |

Validation:

- `pac auth who`
- `pac env who`
- `pac env list-settings`
- `git diff --check`
- BMAD config resolver
- `powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-mvp-local-validate.ps1`

### Sprint 1 - Dataverse Operational Foundation

Goal: create the Council operational substrate in Dataverse after write approval.

Stories:

| ID | Story | Depends on | Done when |
| --- | --- | --- | --- |
| S1.1 | Create unmanaged Council solution | S0.2, S0.3, S0.6, write approval | Solution exists in target environment and is exportable. |
| S1.2 | Create global choice sets | S1.1 | Work item, receipt, source, risk, authority, and platform choices exist. |
| S1.3 | Create core operational tables | S1.2 | Source Record, Work Item, Receipt exist with stable Council ID columns. |
| S1.4 | Create provenance join tables | S1.3 | Work Item Source and Receipt Source exist. |
| S1.5 | Create knowledge/governance tables | S1.3 | Graph Entity, Graph Edge, Memory Candidate, Approved Instruction, Skill, Minion, Brief, Tenant Evidence, Platform Evaluation exist. |
| S1.6 | Create relationships and views | S1.3-S1.5 | Model supports source-to-work-item provenance, receipt lookups, and queue views. |
| S1.7 | Export solution to repo | S1.6 | Exported solution artifact is version-controlled. |

Validation:

- Tables are distinct.
- Council IDs are separate from Dataverse row IDs.
- Receipts have idempotency key.
- Work Item has primary source lookup.
- No app registrations, flows, agents, outbound messages, or Fabric objects created.

### Sprint 2 - Source-to-Work-Item Vertical Slice

Goal: prove the core product loop with mock or approved source data.

Stories:

| ID | Story | Depends on | Done when |
| --- | --- | --- | --- |
| S2.1 | Create sample Source Record | S1.3, source policy | Source Record captures source metadata and data boundary. |
| S2.2 | Create proposed Work Item from source | S2.1 | Work Item has type, rationale, confidence, owner candidate, urgency, risk, source provenance. |
| S2.3 | Append proposal Receipt | S2.2 | Receipt records actor, authority, idempotency key, source refs, confidence, result, policy flags. |
| S2.4 | Show proposed item in queue view | S2.2 | Proposed Work Items and Needs Human Approval views show the record. |
| S2.5 | Apply approval/hold/block state with Receipt | S2.3 | State changes only after receipt evidence exists. |
| S2.6 | Add basic graph provenance | S2.1-S2.5 | Graph Entity/Edge records explain source, work item, person/project/topic, and receipt grounding. |

Validation:

- Every Work Item cites a Source Record.
- Every mutation has a Receipt.
- Source Record remains separate from Work Item.
- Graph edges do not mutate workflow state.

### Sprint 3 - Council Queue and Minion Brief Surface

Goal: make the MVP usable as a review surface.

Stories:

| ID | Story | Depends on | Done when |
| --- | --- | --- | --- |
| S3.1 | Create model-driven app shell | S1.6 | Council Queue app opens with Intake, Work, Brief, Knowledge, Governance groups. |
| S3.2 | Configure Work Item forms and views | S3.1 | Proposed, Approval, Held, Blocked, In Review, Failed views are usable. |
| S3.3 | Configure Receipt forms and views | S3.1 | Recent, Failed, Policy Denial, External Action Request views are usable. |
| S3.4 | Configure Source Record forms and views | S3.1 | Source metadata and data boundary are visible. |
| S3.5 | Create Brief snapshot workflow manually | S2.6 | Brief record summarizes priority queue, decisions, delegations, blockers, receipts, and memory candidates. |
| S3.6 | Validate no source-of-truth drift | S3.5 | Brief is projection only; Work Item/Receipt remain canonical. |

Validation:

- Model-driven app supports the first review flow.
- No Power Apps MCP agent feed dependency yet.
- No autonomous agent or flow required for MVP proof.

### Sprint 4 - Governance, Memory, Skill, and Policy Guardrails

Goal: prove the safety model before automation expansion.

Stories:

| ID | Story | Depends on | Done when |
| --- | --- | --- | --- |
| S4.1 | Create Memory Candidate flow manually | S2.1-S2.5 | Memory Candidate is proposed with source, rationale, confidence, review state. |
| S4.2 | Promote Approved Instruction with receipt | S4.1 | Approved Instruction references source and approval receipt. |
| S4.3 | Create Skill Registry records | S1.5 | Skill records declare trigger, context, authority, proof owed, update policy. |
| S4.4 | Validate auto-creation policy | S2.1-S2.5 | Low-risk follow-up/meeting-action criteria are represented; sensitive items remain proposed-only. |
| S4.5 | Create platform evaluation records | S1.5 | Work IQ, Dataverse, Power Apps MCP, Copilot Studio, Power Automate, Fabric entries are recorded. |
| S4.6 | Create tenant evidence records | S0.4, S1.5 | Tenant evidence is tracked in Dataverse and repo evidence artifact. |

Validation:

- Memory cannot become instruction without approval receipt.
- Skill authority expansion requires approval.
- Service selection has evidence records.
- Auto-created does not mean externally actionable.

### Sprint 5 - Automation Candidate Evaluation

Goal: decide what to automate next without breaking approval boundaries.

Stories:

| ID | Story | Depends on | Done when |
| --- | --- | --- | --- |
| S5.1 | Evaluate Outlook/Graph source intake | S0.5, source read approval | Read-only source intake path is documented or deferred. |
| S5.2 | Evaluate Work IQ | S0.5, license/tenant evidence | Work IQ is adopted/deferred/rejected with evidence. |
| S5.3 | Evaluate Power Apps MCP agent feed | S3.1, tenant evidence | Agent feed fit is adopted/deferred/rejected with evidence. |
| S5.4 | Evaluate Copilot Studio packaging | S4.3, tenant evidence | Agent packaging is adopted/deferred/rejected with authority notes. |
| S5.5 | Evaluate Power Automate runner | S4.4, tenant evidence | Automation runner is adopted/deferred/rejected with idempotency and receipt constraints. |
| S5.6 | Evaluate Fabric IQ / Graph phase 2 | S4.5, tenant evidence | Graph/ontology projection path is documented, not workflow-state owner. |

Validation:

- No automation is published without approval.
- No app registration is created without explicit authorization.
- No outbound action is executed.

## First Vertical Slice Recommendation

Build the MVP proof in this order:

1. Dataverse solution with Source Record, Work Item, Receipt.
2. Manual/mock Source Record.
3. Proposed Work Item.
4. Proposal Receipt.
5. Human approval/hold Receipt.
6. State projection update.
7. Basic Graph Entity/Edge provenance.
8. Model-driven queue/brief surface.

This demonstrates the product thesis without waiting for Graph, Work IQ, Copilot Studio, Power Automate, Fabric, or Power Apps MCP agent feed.

## Story Readiness Matrix

| Story range | Ready now? | Blocker |
| --- | --- | --- |
| S0.0 | Yes locally | Runtime/setup baseline exists; tenant execution still needs Doug approval. |
| S0.1 | Yes | Epics/stories, readiness report, and sprint status have been generated. |
| S0.2 | Yes | Dataverse approved; Fabric IQ / Graph deferred to phase 2. |
| S0.3-S0.4 | Yes | `pac env who` proved environment ID and organization ID. |
| S0.5-S0.6 | Yes | Dataverse writes allowed after preflight; source policy `link_only`; publisher prefix `com`. |
| S0.7 | Yes | UX spines exist and model-driven app surface accepted. |
| S1.x | Mostly | Live solution, choices, tables, columns, relationships, and app components exist. Exported/unpacked ALM artifact still remains a follow-up. |
| S2.x | Mostly | Deterministic Source Record, proposed Work Item, Work Item Source, proposal Receipt, Receipt Source, and receipt-backed state transition demo rows exist. |
| S3.x | Mostly | `Council Queue` validates with 12 table components, sitemap, 12 pinned forms, 30 pinned views, 18 manifest-curated views, and post-curation screen proof. |
| S4.x | Partially | Can document policy now; live records need S1. |
| S5.x | Partially | Can document evaluation criteria now; live checks need tenant evidence. |

## Verification Commands

Local:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-mvp-local-validate.ps1
git diff --check
$env:PYTHONIOENCODING='utf-8'; uv run --python 3.11 _bmad/scripts/resolve_config.py --project-root C:\repo\The-Council-of-Minions
```

Tenant read-only:

```powershell
pac auth create --url https://sdhdev.crm.dynamics.com --name Council-SDH-Dev
pac auth who
pac env who
pac env list-settings
```

Tenant write commands are intentionally not listed here because they require Doug's explicit write approval and publisher prefix first.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Runtime/setup gap | Product stories cannot be executed in a runnable app | Locally addressed by runtime/setup baseline; tenant execution still gated. |
| UX contract gap | Compatible data model could still produce a poor review surface | Locally addressed by UX spines; Doug still needs to accept model-driven app as the first surface. |
| Wrong tenant/environment | Live changes in wrong place | Require `pac env who` match before any write. |
| Source body policy unclear | Sensitive data capture risk | Default to link-only until Doug approves otherwise. |
| Receipt append-only not technically enforced | Audit drift | Restrict roles and add plugin/flow validation before broader users. |
| Dataverse semantic model treated as canonical | Semantic drift | Keep Council Semantic Contract canonical and project into Dataverse. |
| Model-driven app too heavy for MVP | Usability delay | Use model-driven app for admin/review MVP; defer richer UX until UX workflow. |

## Handoff Notes

After Doug supplies the missing approvals:

1. Keep `sprint-status.yaml` as the formal BMAD sprint tracker.
2. Create the first story through `bmad-create-story`, using the runtime baseline and UX spines as implementation inputs.
3. Run tenant validation when Doug is present.
4. Update tenant evidence.
5. Begin S1 only after explicit Dataverse write approval.
