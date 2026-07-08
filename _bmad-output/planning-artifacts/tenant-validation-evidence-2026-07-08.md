---
title: "Tenant Validation Evidence"
project: "The-Council-of-Minions"
status: local-prereq-checked-readonly
created: 2026-07-08
target_environment_url: https://sdhdev.crm.dynamics.com
target_environment_id: ba9a96b2-f562-40f6-931d-6b55873954ee
target_organization_id: 0c0fa4db-8614-ef11-9f83-000d3a342d36
---

# Tenant Validation Evidence - 2026-07-08

## Purpose

Record the actual evidence gathered before treating any Microsoft tenant, Dataverse environment, connector, model-driven app, agent, flow, or source integration as available for The Council of Minions MVP.

This file starts as a template. Fill it only with verified current-state evidence from live commands, screenshots, admin settings, or user-approved connector checks.

## Current Status

| Area | Status | Evidence |
| --- | --- | --- |
| Power Platform CLI | Locally available | `pac help` printed version `2.8.1+ga4eb71c (.NET 10.0.9)` on 2026-07-08. |
| Power Platform auth | Wrong active profile for Council target | `pac auth list` succeeded on 2026-07-08, but the active profile points to `https://vetsci-val-synsci.crm.dynamics.com/`, not `https://sdhdev.crm.dynamics.com`. Create or select `Council-SDH-Dev` before tenant validation. |
| Azure CLI | Locally available | `az version` printed `azure-cli` `2.85.0` on 2026-07-08. |
| Tenant decision packet | Pending decisions | `_bmad-output/implementation-artifacts/tenant-decision-packet.json` exists; `tenant-decision-packet-validate.ps1` passes in warning mode and fails with `-RequireComplete` until Doug supplies required decisions. |
| Environment identity | Not tested | Expected Environment ID: `ba9a96b2-f562-40f6-931d-6b55873954ee`; expected Organization ID: `0c0fa4db-8614-ef11-9f83-000d3a342d36`. |
| Dataverse availability | Inferred, not verified | Web API endpoint provided: `https://sdhdev.api.crm.dynamics.com/api/data/v9.2`; must verify with `pac env who`. |
| Dataverse search/indexing | Not tested | Awaiting `pac env list-settings` or admin portal evidence. |
| Dataverse intelligence / semantic model | Not tested | Awaiting environment settings/admin evidence. |
| Dataverse MCP availability | Not tested | No Dataverse MCP exposed in Codex thread; tenant capability must be checked separately. |
| Power Apps MCP agent feed | Not tested | Tenant/app capability; not a local Codex plugin. |
| Model-driven app feasibility | Not tested | Awaiting Dataverse auth and write approval. |
| Outlook/Graph reads | Not authorized | Awaiting Doug's live-read boundary. |
| Teams reads | Not authorized | Awaiting Doug's live-read boundary and target team/channel if needed. |
| SharePoint/OneDrive reads | Not authorized | Awaiting Doug's live-read boundary and target source if needed. |
| Fabric IQ / Graph | Deferred | Proposed phase 2 graph/analytics projection; not MVP workflow state owner. |
| Live writes | Not authorized | Awaiting Doug's explicit Dataverse sandbox write boundary. |
| Source body policy | Missing | Awaiting link-only/hash-only/summary/full snapshot decision. |
| Human approval owner | Missing | Awaiting Doug confirmation. |
| Rollback path | Draft only | Delete unmanaged solution / disable app, flows, agents after any future write. Needs actual solution name after creation. |

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
- Observed result: Decision packet exists and is intentionally pending. Normal validation passes with pending-decision warnings; `-RequireComplete` fails until required decisions are supplied.
- Decision: live write approval is not closed
- Restrictions: no tenant writes performed; no Council environment read-only validation performed yet
- Follow-up owner: Doug

### Entry 1

- Date/time:
- Command or source:
- Capability:
- Observed result:
- Decision: not tested
- Restrictions:
- Follow-up owner:

## Minimum MVP Gate

Before implementation starts against the live tenant, evidence must show:

1. Correct tenant and Dataverse environment.
2. Doug or approved account can authenticate with least-privilege suitable for setup.
3. Dataverse database exists and is accessible.
4. Write boundary is explicit.
5. Source body policy is explicit.
6. Audit/receipt persistence path is approved.
7. Human approval surface is selected or deferred with a local/mock substitute.
8. No-live-write boundary for unapproved actions is preserved.

## Decisions Pending From Doug

1. Dataverse approved as MVP operational store: yes/no.
2. Fabric IQ / Fabric Graph deferred to phase 2 graph/analytics: yes/no.
3. Tenant domain or tenant ID.
4. Outlook/Graph live reads allowed: yes/no.
5. Dataverse sandbox writes allowed after approval: yes/no.
6. Source body policy: link-only, hash-only, summary allowed, or full snapshot allowed.
7. Publisher prefix.
8. Model-driven app as first Council Queue / Minion Brief surface: yes/no.
9. Power Apps MCP agent feed evaluation tonight: yes/no.
