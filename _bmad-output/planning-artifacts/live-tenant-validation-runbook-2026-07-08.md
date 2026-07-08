---
title: "Live Tenant Validation Runbook"
project: "The-Council-of-Minions"
status: ready-for-user-auth
created: 2026-07-08
target_environment_url: https://sdhdev.crm.dynamics.com
target_environment_id: ba9a96b2-f562-40f6-931d-6b55873954ee
target_organization_id: 0c0fa4db-8614-ef11-9f83-000d3a342d36
---

# Live Tenant Validation Runbook - 2026-07-08

## Purpose

Define the exact live-tenant validation sequence for The Council of Minions MVP. This runbook separates read-only verification from write actions so Doug can approve the boundary before anything is created or changed.

## Safety Rules

1. Do not paste passwords, refresh tokens, client secrets, or recovery codes into Codex.
2. Use interactive Microsoft sign-in only.
3. Verify the active tenant and environment before every live action.
4. Treat all live capabilities as `VERIFY IN TENANT` until command output proves them.
5. Do not create or publish agents, flows, app registrations, connectors, Fabric items, or outbound messages during the first validation pass.
6. Do not write sample source content until source body policy is explicit.
7. Do not create Dataverse schema until Doug approves Dataverse sandbox writes.

## Phase 0 - Required User Confirmation

Doug must provide:

```text
C
Dataverse approved as MVP operational store.
Fabric IQ / Fabric Graph deferred to phase 2 graph/analytics.
Tenant/domain: <tenant domain or tenant ID>
Environment type: dev/sandbox/trial/prod
Live reads: Outlook/Graph allowed or not allowed
Live writes: Dataverse sandbox writes allowed after approval / forbidden
Source body policy: link-only / hash-only / summary allowed / full snapshot allowed
Model-driven app is acceptable as first Council Queue / Minion Brief surface: yes/no
Power Apps MCP agent feed evaluation tonight: yes/no
Publisher prefix: <prefix>
```

Without these confirmations, run only local planning and no live tenant work.

## Phase 1 - Power Platform Authentication

Before interactive login, run the local no-auth checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\tenant-prereq-local-check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\dataverse-manifest-validate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\dataverse-deployment-plan.ps1
```

Expected result:

- Local prerequisite check prints `TENANT_PREREQ_LOCAL_CHECK_OK`.
- Manifest validation succeeds.
- Deployment plan prints `DRY RUN ONLY`.
- No tenant authentication or writes occur.

Current local observation from 2026-07-08:

- Power Platform CLI is installed.
- Azure CLI is installed.
- `pac auth list` currently shows an active profile for `https://vetsci-val-synsci.crm.dynamics.com/`, not the Council target `https://sdhdev.crm.dynamics.com`.
- Before tenant validation, create or select a `Council-SDH-Dev` PAC auth profile for the target environment.

Run from `C:\repo\The-Council-of-Minions` while Doug is present.

```powershell
pac auth create --url https://sdhdev.crm.dynamics.com --name Council-SDH-Dev
pac auth list
pac auth who
pac env who
```

Validation:

- `pac auth who` shows the expected signed-in user.
- `pac env who` points to `https://sdhdev.crm.dynamics.com` or the equivalent environment URL.
- Environment ID matches `ba9a96b2-f562-40f6-931d-6b55873954ee`.
- Organization ID matches `0c0fa4db-8614-ef11-9f83-000d3a342d36`.

If mismatch:

1. Stop.
2. Do not run write commands.
3. Use `pac auth list` and `pac auth select` to select the correct profile, or recreate auth with the correct URL.

Optional hard check after auth selection:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\tenant-prereq-local-check.ps1 -RequireTargetAuth
```

This command fails if the active PAC profile does not point to `https://sdhdev.crm.dynamics.com`.

## Phase 2 - Read-Only Environment Inspection

Commands:

```powershell
pac env who
pac env list
pac env list-settings
```

Record evidence for:

- Environment display name.
- Environment type.
- Region.
- Dataverse availability.
- Current auth user.
- Settings related to search, Copilot, AI, intelligence, MCP, auditing, and DLP where visible.

Output artifact:

- `_bmad-output/planning-artifacts/tenant-validation-evidence-2026-07-08.md`

## Phase 3 - Optional Azure / Graph Authentication

Only run if Doug authorizes Graph/Azure validation.

```powershell
az login --tenant <tenant-id-or-domain>
az account show
```

If Outlook/Graph reads are authorized through PowerShell:

```powershell
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -Scopes "User.Read","Mail.Read","Calendars.Read"
Get-MgContext
```

Minimum validation:

- Signed-in account matches Doug or approved account.
- Tenant matches expected tenant.
- Scopes are read-only unless Doug explicitly approves more.

Do not request `Mail.Send`, `Calendars.ReadWrite`, `Files.ReadWrite.All`, `Sites.ReadWrite.All`, or Graph application permissions in the first pass.

## Phase 4 - Optional Codex Connector Read Tests

Only run after Doug authorizes delegated reads.

Allowed read tests:

- Outlook Email: recent or targeted search with small result size.
- Outlook Calendar: list upcoming events or mailbox profile.
- SharePoint/OneDrive: list visible drives or fetch a user-approved file.
- Teams: list user-approved channel messages if team/channel IDs are provided.

Do not write messages, upload files, edit files, cancel calendar events, or change Teams content during the first pass.

## Phase 5 - Dataverse Write Approval Gate

Before any Dataverse schema write, confirm:

```text
Dataverse sandbox writes approved for Council MVP schema.
Publisher prefix: <prefix>
Solution name: CouncilOfMinionsMVP or replacement.
Model-driven app surface approved: yes/no.
Sample source records policy: link-only/hash-only/summary/full.
```

If not approved, stop at read-only evidence and update planning artifacts.

## Phase 6 - Dataverse Solution Creation Plan

Do not run until Phase 5 is approved.

Planned operations:

1. Create publisher if needed.
2. Create unmanaged solution.
3. Create global choices.
4. Create tables and columns from `dataverse-mvp-schema-plan-2026-07-08.md`.
5. Create relationships.
6. Create views.
7. Create model-driven app shell if approved.
8. Create minimal sample records if source policy allows.
9. Export unmanaged solution to repo for source control.

Because direct `pac` table/column creation support varies by component type and ALM path, choose one implementation mechanism after environment verification:

| Mechanism | When to use |
| --- | --- |
| Power Apps maker portal + export | Fastest safe first build with human supervision. |
| Power Platform CLI solution project | Best after initial table/app components exist or if using existing solution packaging. |
| Dataverse Web API script | Best for repeatable schema automation after auth/token path is proven. |
| PowerShell module | Useful for admin/config checks; less ideal for full schema creation. |

Recommendation: first schema creation should be supervised in Power Apps maker portal or through a generated Web API script reviewed before execution. Export solution immediately after.

## Phase 7 - Evidence Artifact

Create `_bmad-output/planning-artifacts/tenant-validation-evidence-2026-07-08.md` with:

| Area | Evidence |
| --- | --- |
| Tenant identity | Account, tenant, environment, org IDs. |
| Licensing | What is visible/known. |
| Dataverse availability | `pac env who` and environment settings. |
| Search/intelligence | Relevant setting output. |
| Outlook/Graph reads | Authorized yes/no and test output if any. |
| Write boundary | Approved/forbidden and scope. |
| Source body policy | Link/hash/summary/full. |
| Human review surface | Model-driven app / agent feed / other. |
| Rollback | How to delete solution or disable app/flow/agent if created. |

## Phase 8 - Stop Conditions

Stop and ask Doug before proceeding if:

- Auth lands in the wrong tenant or environment.
- Environment URL does not match expected environment ID.
- Dataverse is missing or inaccessible.
- User lacks maker/admin privileges.
- DLP/security settings are unclear.
- Any operation requires app registration or admin consent.
- Any operation requests write scopes outside approved Dataverse sandbox writes.
- Any source content appears sensitive and source policy is not explicit.
- Power Apps MCP/agent feed requires Copilot Studio publishing or MCP onboarding.

## Phase 9 - Post-Validation BMAD Updates

After validation:

1. Update tenant readiness evidence.
2. Update storage decision status from proposed to accepted or revise.
3. Update implementation-readiness status.
4. Continue `bmad-create-epics-and-stories` when `C` is confirmed.
5. Create stories for any validated tenant setup path.
6. Commit planning and evidence artifacts.
7. Update PR #1.

## Command Reference

```powershell
# Power Platform auth and environment
pac auth create --url https://sdhdev.crm.dynamics.com --name Council-SDH-Dev
pac auth list
pac auth select --index <index>
pac auth who
pac env who
pac env list
pac env list-settings

# Azure/Graph only if authorized
az login --tenant <tenant-id-or-domain>
az account show

# Graph PowerShell only if authorized
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -Scopes "User.Read","Mail.Read","Calendars.Read"
Get-MgContext
Disconnect-MgGraph
```

## Current Blockers

- Dataverse storage decision awaits explicit approval.
- Tenant/domain ID is not yet supplied.
- Live read/write boundaries are not yet supplied.
- Source body policy is not yet supplied.
- Publisher prefix is not yet supplied.
- Active PAC auth is currently not the Council target environment.
