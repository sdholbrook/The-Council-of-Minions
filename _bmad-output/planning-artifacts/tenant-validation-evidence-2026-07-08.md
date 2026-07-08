---
title: "Tenant Validation Evidence"
project: "The-Council-of-Minions"
status: scoped-dataverse-write-complete
created: 2026-07-08
target_environment_url: https://sdhdev.crm.dynamics.com
target_environment_id: ba9a96b2-f562-40f6-931d-6b55873954ee
target_organization_id: 0c0fa4db-8614-ef11-9f83-000d3a342d36
---

# Tenant Validation Evidence - 2026-07-08

## Purpose

Record the actual evidence gathered before and after treating any Microsoft tenant, Dataverse environment, connector, model-driven app, agent, flow, or source integration as available for The Council of Minions MVP.

This file contains verified current-state evidence from live commands, admin settings, or user-approved connector checks. Do not store raw authentication output or access tokens here.

## Current Status

| Area | Status | Evidence |
| --- | --- | --- |
| Power Platform CLI | Locally available | `pac help` printed version `2.8.1+ga4eb71c (.NET 10.0.9)` on 2026-07-08. |
| Power Platform auth | Target profile selected | `pac env select --environment ba9a96b2-f562-40f6-931d-6b55873954ee` selected `https://sdhdev.crm.dynamics.com/` on 2026-07-08. |
| Azure CLI | Locally available | `az version` printed `azure-cli` `2.85.0` on 2026-07-08. |
| Tenant decision packet | Complete for Dataverse MVP write | `_bmad-output/implementation-artifacts/tenant-decision-packet.json` is approved for guarded Dataverse MVP writes; `tenant-decision-packet-validate.ps1 -RequireComplete` passes. |
| Outlook Source Reference local slice | Mock/manual only | `_bmad-output/implementation-artifacts/outlook-source-reference-slice.json` exists; `outlook-source-reference-slice-validate.ps1` passes locally, but no live Outlook/Graph read has been authorized or performed. |
| Proposed Work Item extraction local slice | Local contract plus live demo seed | `_bmad-output/implementation-artifacts/proposed-work-item-extraction-slice.json` exists; `proposed-work-item-extraction-slice-validate.ps1` passes locally; deterministic proposed Work Item, Work Item Source, proposal Receipt, graph provenance, and Brief rows are seeded in Dataverse. |
| Environment identity | Verified | `pac env who` matched Environment ID `ba9a96b2-f562-40f6-931d-6b55873954ee` and Organization ID `0c0fa4db-8614-ef11-9f83-000d3a342d36`. |
| Dataverse availability | Verified and written | Web API endpoint `https://sdhdev.api.crm.dynamics.com/api/data/v9.2` accepted metadata and data writes into solution `CouncilOfMinionsMVP`. |
| Dataverse search/indexing | Not tested | Full search/indexing behavior remains a later validation item. |
| Dataverse intelligence / semantic model | Not tested | Awaiting environment settings/admin evidence. |
| Dataverse MCP availability | Not tested | No Dataverse MCP exposed in Codex thread; tenant capability must be checked separately. |
| Power Apps MCP agent feed | Not tested | Tenant/app capability; not a local Codex plugin. |
| Model-driven app feasibility | Valid table-backed app created | Published model-driven app `Council Queue` exists with 12 Council table components. `ValidateApp` returns success with only form/view selection warnings. |
| Outlook/Graph reads | Not authorized | Awaiting Doug's live-read boundary. |
| Teams reads | Not authorized | Awaiting Doug's live-read boundary and target team/channel if needed. |
| SharePoint/OneDrive reads | Not authorized | Awaiting Doug's live-read boundary and target source if needed. |
| Fabric IQ / Graph | Deferred | Proposed phase 2 graph/analytics projection; not MVP workflow state owner. |
| Live writes | Authorized and completed | Doug authorized removing the tenant write restriction. Guarded script created Dataverse solution, choices, tables, relationships, a validated table-backed model-driven app, deterministic receipt-backed demo rows, graph provenance, and a Minion Brief in `sdhdev`. |
| Source body policy | Link-only | Sample Source Records use `link_only` policy. |
| Human approval owner | Doug | Doug is the approval owner for MVP tenant writes and approval-gated actions. |
| Rollback path | Solution scoped | Delete unmanaged solution `CouncilOfMinionsMVP` and published app `Council Queue` if rollback is required. |

## Expected Environment

| Field | Expected value | Verification source |
| --- | --- | --- |
| Environment URL | `https://sdhdev.crm.dynamics.com` | `pac auth who`, `pac env who` |
| Environment unique name | `unq0c0fa4db8614ef119f83000d3a342` | Power Platform developer resources / `pac env who` if shown |
| Environment ID | `ba9a96b2-f562-40f6-931d-6b55873954ee` | `pac env who` / admin portal |
| Organization ID | `0c0fa4db-8614-ef11-9f83-000d3a342d36` | `pac env who` / Web API / admin portal |
| Web API endpoint | `https://sdhdev.api.crm.dynamics.com/api/data/v9.2` | Developer resources / API check |

## Evidence Log

Append entries as evidence is gathered.

### Entry 0 - Local Prerequisite Check

- Date/time: 2026-07-08T01:07:50-04:00
- Command or source: `pac help`, `pac auth list`, `az version`
- Capability: Local CLI readiness before interactive tenant validation
- Observed result: Power Platform CLI and Azure CLI are installed. Active PAC auth points to `https://vetsci-val-synsci.crm.dynamics.com/`, not the Council target `https://sdhdev.crm.dynamics.com`.
- Decision: local prerequisites partially ready; target PAC auth still required
- Restrictions: no tenant writes performed; no Council environment read-only validation performed yet
- Follow-up owner: Doug / Codex during interactive auth

### Entry 0.1 - Tenant Decision Packet Initialized

- Date/time: 2026-07-08
- Command or source: `tenant-decision-packet.json`, `tenant-decision-packet-validate.ps1`
- Capability: Structured capture for Doug decisions before tenant validation or writes
- Observed result: Decision packet was created as pending evidence capture. It is now superseded by the completed scoped Dataverse write packet; `tenant-decision-packet-validate.ps1 -RequireComplete` passes.
- Decision: historical entry superseded; scoped live Dataverse write approval is closed
- Restrictions: at the time of this entry, no tenant writes were performed; this was later superseded by Entry 1
- Follow-up owner: Doug

### Entry 0.2 - Outlook Source Reference Slice Initialized

- Date/time: 2026-07-08T01:20:40-04:00
- Command or source: `outlook-source-reference-slice.json`, `outlook-source-reference-slice-validate.ps1`
- Capability: Local mock/manual Outlook message and thread Source Record reference shape
- Observed result: Local validator passes and proves message/thread source kinds, conversation reference, source object reference, data boundary policy, mock/manual evidence marking, and no Work Item creation on save.
- Decision: live Outlook/Graph reads are still not authorized
- Restrictions: no Graph calls performed; no tenant writes performed; mock/manual records are not verified tenant evidence
- Follow-up owner: Doug

### Entry 0.3 - Proposed Work Item Extraction Slice Initialized

- Date/time: 2026-07-08T01:30:33-04:00
- Command or source: `proposed-work-item-extraction-slice.json`, `proposed-work-item-extraction-slice-validate.ps1`
- Capability: Local proposed Work Item extraction from Source Record samples
- Observed result: Local validator passes and proves proposed Work Item shape, Council-level `CWI-*` identity, primary Source Record references, Work Item Source links, confidence/uncertainty fields, and proposal-only behavior.
- Decision: historical entry superseded for scoped Dataverse writes; live Outlook/Graph reads and approval execution remain out of scope
- Restrictions: at the time of this entry, no tenant writes or receipts were created; this was later superseded by Entry 1 for deterministic demo seed rows
- Follow-up owner: Doug

### Entry 1 - Guarded Dataverse MVP Write Completed

- Date/time: 2026-07-08T09:52:27-04:00
- Command or source: `dataverse-apply-mvp-schema.ps1 -ExecuteWrites -SeedSampleRows`
- Capability: Live Dataverse MVP schema, solution, app shell, and sample data
- Observed result: Target preflight matched `sdhdev` environment and organization IDs. The script created solution `CouncilOfMinionsMVP`, 15 global choices, 14 custom tables, non-lookup columns, lookup relationships, published customizations, created and validated model-driven app `Council Queue` with 12 Council table components, and seeded deterministic demo rows: Source Record `manual-demo-source-001`, proposed Work Item `CWI-DEMO-001`, proposal Receipt `CR-DEMO-PROPOSED-001`, Work Item Source, Receipt Source, graph provenance rows, and Minion Brief `BRIEF-DEMO-001`. An earlier failed seed retry left an additional sample Source Record row with no paired Work Item.
- Decision: Dataverse write restriction removed for the guarded MVP path after target proof
- Restrictions: no outbound action, no flow publish, no agent publish, no app registration, and no Fabric mutation performed
- Follow-up owner: Doug / Codex

## Minimum MVP Gate

Before the scoped live tenant slice can be considered valid, evidence must show:

1. Correct tenant and Dataverse environment.
2. Doug or approved account can authenticate with least-privilege suitable for setup.
3. Dataverse database exists and is accessible.
4. Write boundary is explicit.
5. Source body policy is explicit.
6. Audit/receipt persistence path is approved.
7. Human approval surface is selected or deferred with a local/mock substitute.
8. No-live-write boundary for unapproved actions is preserved.

## Decisions Pending From Doug

No Dataverse MVP write decisions remain pending. Outlook/Graph live reads remain not allowed, and Fabric IQ / Fabric Graph remain deferred to phase 2.
### Preflight Evidence - 2026-07-08T10:26:09.1351802-04:00

- Manifest: C:\repo\The-Council-of-Minions\_bmad-output\implementation-artifacts\dataverse-mvp-schema-manifest.json
- Expected environment URL: https://sdhdev.crm.dynamics.com
- Expected environment unique name: unq0c0fa4db8614ef119f83000d3a342
- Expected environment ID: ba9a96b2-f562-40f6-931d-6b55873954ee
- Expected organization ID: 0c0fa4db-8614-ef11-9f83-000d3a342d36
- Web API endpoint: https://sdhdev.api.crm.dynamics.com/api/data/v9.2
- Discovery endpoint: https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances
- pac auth who exit code: 0
- pac env who exit code: 0
- Environment ID matched in pac env who: True
- Organization ID matched in pac env who: True
- pac env list-settings exit code: 0
- pac auth who, pac env who, and pac env list-settings output retained only as summaries to avoid storing raw tenant details.
