---
title: "Storage Decision Record"
project: "The-Council-of-Minions"
status: proposed-for-doug-approval
created: 2026-07-08
decision_scope: MVP tenant implementation
decision_owner: Doug
target_dataverse_environment:
  environment_unique_name: unq0c0fa4db8614ef119f83000d3a342
  environment_id: ba9a96b2-f562-40f6-931d-6b55873954ee
  organization_id: 0c0fa4db-8614-ef11-9f83-000d3a342d36
  web_api_endpoint: https://sdhdev.api.crm.dynamics.com/api/data/v9.2
  inferred_environment_url: https://sdhdev.crm.dynamics.com
  discovery_endpoint: https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances
---

# Storage Decision Record - 2026-07-08

## Decision

Use **Dataverse as the MVP operational system of record** for Council operational records, with the Council Semantic Contract remaining the canonical semantic authority.

Dataverse stores the MVP operational records:

- Source Record metadata and permitted source snapshots.
- Work Items.
- Receipts.
- Memory Candidates and Approved Instructions.
- Minion Skill Registry records.
- Tenant readiness evidence records.
- Service-selection evidence records.
- Human approval and review state.

Use **native Microsoft source systems** as the source of truth for source artifacts:

- Outlook / Exchange for messages and threads.
- Teams for conversations and approval surfaces when adopted.
- Calendar for meetings.
- SharePoint / OneDrive for files and artifacts.
- Planner / To Do only as an optional downstream projection after approval, not as the canonical Work Item store.

Use **Microsoft Graph and Work IQ** for source-context access and Microsoft 365 work intelligence where available, not as the Council operational store.

Use **Dataverse semantic model** as the Dataverse/Copilot runtime projection of approved Council meaning. It is not the canonical ontology.

Use **Fabric IQ / Fabric Graph** later for cross-domain ontology, relationship analysis, lineage, impact paths, graph traversal, and analytics once MVP contracts stabilize and tenant/capacity gates are verified. Fabric is not the MVP workflow-state owner.

Use **Power Apps model-driven app and Power Apps MCP agent feed** as the first Microsoft-native candidates for the Council Queue / Minion Brief human review surface if tenant validation confirms availability.

Use **Copilot Studio and Power Automate** only after approval, receipt, idempotency, DLP, and rollback requirements are enforceable.

## Rationale

Dataverse is the best MVP operational-store candidate because it aligns with:

- Power Platform environment and solution ALM.
- Model-driven app review surfaces.
- Security roles and business data permissions.
- Dataverse search and Dataverse intelligence.
- Dataverse semantic model projection into Copilot/agent experiences.
- Power Apps MCP server and agent feed human-in-the-loop patterns.
- Future Dataverse MCP and business-skill patterns.

This decision does not make Dataverse the canonical semantic source. The Council Semantic Contract remains canonical and projects into Dataverse metadata, table/column descriptions, relationships, views, forms, glossary entries, and later Copilot/agent surfaces.

## Boundaries

- Do not collapse Source Records, Work Items, Receipts, Memory Candidates, Graph Entities, Skills, and Briefs into one generic table.
- Do not treat Dataverse row IDs as primary user-facing Council identifiers.
- Do not store full source content when source permission, sensitivity, retention, or data boundary rules forbid it.
- Do not use Planner / To Do as the canonical Work Item store.
- Do not use Fabric Graph as the workflow engine.
- Do not treat Dataverse semantic model or Fabric IQ ontology as the source of truth for Council terms.
- Do not publish agents, flows, app registrations, connectors, or tenant writes until tenant readiness evidence exists.

## MVP Dataverse Table Candidates

These are logical tables; final schema names can be solution-prefixed later.

| Table | Purpose | Key contract |
| --- | --- | --- |
| Council Source Record | Captured source metadata and allowed snapshots before extraction | `source-record-contract.md` |
| Council Work Item | Canonical execution shell | `work-item-receipt-contract.md` |
| Council Receipt | Append-only action and state ledger | `work-item-receipt-contract.md` |
| Council Graph Entity | Lightweight operational graph node | `semantic-contract.md` |
| Council Graph Edge | Approved edge vocabulary projection | `semantic-contract.md` |
| Council Memory Candidate | Proposed durable context | `semantic-contract.md` |
| Council Approved Instruction | Approved durable guidance | `semantic-contract.md` |
| Council Skill | Reusable Minion capability and authority record | `semantic-contract.md` |
| Council Minion | Role-bound agent/capability identity | `semantic-contract.md` |
| Council Brief | Brief snapshot/projection, not source of truth | `ARCHITECTURE-SPINE.md` |
| Council Tenant Evidence | Tenant readiness evidence and decisions | `tenant-readiness-checklist.md` |
| Council Platform Evaluation | Microsoft platform fit and service-selection evidence | `microsoft-platform-fit-matrix-2026-07-07.md` |

## Tenant Validation Required Before Live Build

### Provided Environment

Doug provided these Dataverse developer resources on 2026-07-08:

| Field | Value |
| --- | --- |
| Environment unique name | `unq0c0fa4db8614ef119f83000d3a342` |
| Environment ID | `ba9a96b2-f562-40f6-931d-6b55873954ee` |
| Organization ID | `0c0fa4db-8614-ef11-9f83-000d3a342d36` |
| Web API endpoint | `https://sdhdev.api.crm.dynamics.com/api/data/v9.2` |
| Discovery endpoint | `https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances` |
| Inferred environment URL for `pac auth create` | `https://sdhdev.crm.dynamics.com` |

The inferred environment URL must be verified during `pac auth create` / `pac env who`.

### Access

- Power Platform environment URL.
- Confirmation that the environment has a Dataverse database.
- Doug or delegated account has System Administrator or equivalent maker/admin role for setup.
- License coverage for Power Apps, Dataverse, Copilot/agents if used, and connectors.
- Whether a dev/sandbox environment exists or one needs to be created by an admin.

### Settings

- Dataverse search/indexing status.
- Dataverse intelligence availability.
- Dataverse semantic model availability.
- Dataverse auditing status.
- Security role strategy.
- DLP policies and connector policy.
- Solution/ALM strategy.

### Source Access

- Whether Outlook/Graph read access is allowed.
- Mailbox type: user mailbox, shared mailbox, or both.
- Allowed permission model: delegated user only, application permissions, or no Graph permissions yet.
- Whether attachments, message bodies, and thread context may be captured, summarized, hashed, or only referenced.
- Sensitivity labels, retention, legal hold, and data boundary rules.

### Human Review

- Whether model-driven app is acceptable as the first Council Queue / Minion Brief surface.
- Whether Power Apps MCP agent feed is available and allowed.
- Whether Teams approvals or Outlook actionable messages are allowed later.
- Who approves decisions, delegations, outbound actions, memory promotion, skill expansion, and tenant writes.

### Fabric and Analytics

- Whether Fabric capacity exists.
- Whether Fabric IQ / ontology / Graph are enabled for the tenant.
- Whether Fabric may be used for read-only analytics or graph projection later.

## Login Plan

No passwords or secrets should be pasted into Codex.

Use local browser/device authentication:

1. Power Platform CLI: `pac auth create --url <environment-url>`
2. Azure CLI if Graph/Azure validation is needed: `az login --tenant <tenant-id-or-domain>`

For the provided environment, first attempt:

```powershell
pac auth create --url https://sdhdev.crm.dynamics.com --name Council-SDH-Dev
pac auth list
pac auth who
pac env who
```

If `pac auth create` rejects the inferred URL, use the environment URL shown in Power Platform admin center or Power Apps maker portal for the same Environment ID.

Installed locally:

- `pac.exe` found at `C:\Users\DougHolbrook\.dotnet\tools\pac.exe`
- `az.cmd` found at `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd`

Microsoft 365 CLI `m365` was not found in the current shell, so the first validation path should use `pac` and `az` unless another approved tool is installed later.

## What Doug Needs To Provide

Required before tenant work:

1. Tenant name/domain and tenant ID if known.
2. Power Platform environment URL, if different from inferred `https://sdhdev.crm.dynamics.com`.
3. Whether this is dev, sandbox, trial, or production.
4. Confirmation that Dataverse exists in that environment. The Web API endpoint strongly suggests yes, but `pac env who` must verify it.
5. Whether Doug can sign in interactively through `pac auth create`.
6. Whether Doug can sign in interactively through `az login`.
7. Whether live reads from Outlook/Graph are allowed tonight.
8. Whether live writes are forbidden, sandbox-only, or allowed after approval.
9. Whether Dataverse is approved as the MVP operational store.
10. Whether Fabric is deferred to phase 2 for graph/analytics.

Useful before tenant work:

1. Preferred solution publisher prefix.
2. Preferred environment/solution name.
3. Whether source message bodies may be stored, summarized, hashed, or only linked.
4. Whether the first user surface should be model-driven app, local mock, or both.
5. Whether Power Apps MCP agent feed should be evaluated tonight or left as a later gate.

## Decision Status

This record is proposed. It becomes accepted when Doug confirms:

1. Dataverse is the MVP operational store.
2. Fabric IQ / Fabric Graph are deferred to graph/analytics projection.
3. Planner / To Do is not the canonical Work Item store.
4. Source systems remain source-of-truth for source artifacts.
5. Live tenant work may proceed only through interactive login and explicit live-write boundaries.

## Current Source Check

Checked against Microsoft Learn on 2026-07-08:

- Work IQ is Microsoft's governed Microsoft 365 work-context and agent intelligence layer.
- Dataverse semantic model is still a projection/runtime interpretation layer with preview/ALM caveats.
- Fabric IQ ontology and Fabric Graph remain preview/tenant-gated and suited to semantic/relationship projection and analysis.
- Power Apps MCP agent feed is explicitly tied to Power Apps MCP server onboarding for model-driven app agent review.

Relevant official docs:

- https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/work-iq/
- https://learn.microsoft.com/en-us/power-apps/maker/data-platform/semantic-model-faq
- https://learn.microsoft.com/en-us/fabric/iq/overview
- https://learn.microsoft.com/en-us/fabric/iq/ontology/overview
- https://learn.microsoft.com/en-us/power-apps/user/supervise-agents-with-agent-feed
- https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/power-apps-mcp-server
