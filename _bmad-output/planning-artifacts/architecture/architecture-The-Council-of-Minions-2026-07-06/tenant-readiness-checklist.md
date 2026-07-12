# Tenant Readiness Checklist

Status: architecture-ready  
Updated: 2026-07-07

## Purpose

Define the evidence required before any live Microsoft tenant behavior, connector, app registration, published agent, Power Platform environment, automation, Dataverse store, Fabric capacity, or external action is treated as available.

## Rule

Until this checklist is satisfied for a capability, mark that capability `VERIFY IN TENANT`.

## Checklist

| Area | Evidence required |
| --- | --- |
| Tenant identity | Target tenant, environment, user identity, admin owner, and intended test scope. |
| Licensing | Microsoft 365, Copilot, Power Platform, Dataverse, Fabric, and connector licensing needed for the target capability. |
| Copilot credits / consumption | Expected credit or metered cost impact for Work IQ APIs, agents, Copilot Studio, and related AI features. |
| Power Platform environment | Environment name, type, region, Dataverse availability, solution/ALM strategy, DLP policy. |
| Dataverse settings | Search/indexing, Dataverse intelligence, MCP server, Copilot data availability, audit, security roles. |
| Work IQ / Agent 365 | API availability, MCP server availability, admin controls, allowed tools, observability, action permissions. |
| Outlook / Graph | Permission scope, mailbox type, shared mailbox behavior, message/thread identity, attachments, change tracking. |
| Teams / approvals | Whether Teams approval surfaces are allowed, auditable, and aligned with Council receipt semantics. |
| SharePoint / OneDrive | File access, sensitivity labels, versioning, sharing boundaries, retention, source-link durability. |
| Copilot Studio | Environment, DLP, knowledge sources, agent publishing controls, tool permissions, human review support. |
| Power Automate | Connector policy, run identity, idempotency, retry/failure handling, approval gates, environment promotion. |
| Fabric | Capacity, workspace, OneLake access, Fabric IQ / Graph / data agent availability, Purview/DLP behavior. |
| Sensitivity and retention | Labels, data loss prevention, retention, legal hold, audit, and export restrictions for source records and receipts. |
| Security review | Least-privilege permissions, service principals, managed identities, conditional access, and audit log visibility. |
| Data boundary | Which source content may be captured, summarized, embedded, indexed, or excluded. |
| Human approval | Who can approve decisions, delegations, outbound actions, skill authority expansion, memory promotion, and tenant writes. |
| Rollback | How to disable agents, flows, connectors, MCP servers, app registrations, and environment changes. |

## Evidence Format

For each capability:

- Capability name.
- Tenant/environment.
- Admin or owner.
- Evidence link or screenshot reference.
- Date verified.
- Restrictions found.
- Decision: available, unavailable, available with constraints, or not tested.
- Follow-up owner.

## MVP Minimum

Before MVP implementation starts, verify at least:

- Outlook/Graph read path for source references.
- Chosen storage candidate availability, if one is selected.
- Human review surface availability.
- DLP/sensitivity behavior for captured source records.
- Audit/receipt persistence path.
- No-live-write boundary for unapproved actions.
