---
title: "Live Tenant Kickoff Checklist"
project: "The-Council-of-Minions"
status: awaiting-user-auth-and-approvals
created: 2026-07-08
target_environment_id: ba9a96b2-f562-40f6-931d-6b55873954ee
target_organization_id: 0c0fa4db-8614-ef11-9f83-000d3a342d36
---

# Live Tenant Kickoff Checklist - 2026-07-08

## Current Decision Position

Recommended before kickoff:

1. Approve Dataverse as the MVP operational store.
2. Defer Fabric IQ / Fabric Graph to graph, ontology, and analytics projection after MVP contracts stabilize.
3. Use Microsoft source systems as the source of truth for source artifacts.
4. Use Microsoft Graph / Work IQ for source-context access, not as the Council operational store.
5. Use model-driven Power Apps as the first implementation candidate for Council Queue / Minion Brief.
6. Keep all outbound action, memory promotion, skill expansion, automation publishing, and tenant-affecting writes approval-gated.

## Provided Dataverse Environment

| Field | Value |
| --- | --- |
| Environment unique name | `unq0c0fa4db8614ef119f83000d3a342` |
| Environment ID | `ba9a96b2-f562-40f6-931d-6b55873954ee` |
| Organization ID | `0c0fa4db-8614-ef11-9f83-000d3a342d36` |
| Web API endpoint | `https://sdhdev.api.crm.dynamics.com/api/data/v9.2` |
| Discovery endpoint | `https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances` |
| Inferred environment URL | `https://sdhdev.crm.dynamics.com` |

The inferred environment URL must be verified with `pac auth create` and `pac env who`.

## Local Tools Already Present

| Tool | Status | Version / evidence | Use |
| --- | --- | --- | --- |
| Power Platform CLI `pac` | Installed | `2.8.1+ga4eb71c` | Dataverse auth, environment inspection, solution ALM, model-driven app/solution work. |
| Azure CLI `az` | Installed | `2.85.0` | Azure/Microsoft Graph token validation and tenant/account checks. |
| GitHub CLI `gh` | Installed | `2.90.0` | PR updates and repo workflow. |
| Git | Installed | `2.54.0.windows.1` | Source control. |
| Node.js | Installed | `24.15.0` | npm/npx tools, Work IQ CLI if needed, future web/runtime tooling. |
| npm | Installed | Present with Node | npm/npx installs. |
| .NET SDK/runtime | Installed | `10.0.9` via `pac`; `dotnet.exe` present | Power Platform CLI, optional Dataverse SDK/tooling. |
| PowerShell 7 `pwsh` | Installed | `7.6.3` | Microsoft Graph and Power Platform automation. |
| Microsoft Graph PowerShell | Installed | `2.35.1` modules present | Outlook/Graph validation if connector or CLI path is insufficient. |
| Power Apps PowerShell modules | Installed | `Microsoft.PowerApps.*` modules present | Admin/environment checks when appropriate. |

## Local Tools Not Present

| Tool | Required before kickoff? | Recommendation |
| --- | --- | --- |
| CLI for Microsoft 365 `m365` | No | Optional. Install only if we need broader M365 admin scripting outside Graph PowerShell/Codex connectors. |
| Work IQ CLI `@microsoft/workiq` | Not required for Dataverse kickoff | Optional but useful for M365 source-context validation if tenant has Work IQ/Copilot licensing. Can run with `npx -y @microsoft/workiq mcp` without global install. |
| Agent 365 CLI | No for MVP Dataverse store | Defer until we are building/publishing Microsoft 365 agents. |
| Microsoft 365 Agents Toolkit CLI | No for Dataverse/model-driven MVP | Defer unless we choose a Teams/M365 agent packaging path. |
| Power Platform VS Code extension | No | Useful for humans, not needed for Codex terminal work. |
| XrmToolBox | No | Useful for interactive Dataverse inspection, not needed for automated BMAD workflow. |

## Codex Connectors / MCP Available In This Thread

| Connector / MCP | Status | Use |
| --- | --- | --- |
| Outlook Email | Available after tool discovery | Search/reference mailbox messages through delegated connector. Good for source-context review if Doug authorizes reads. |
| Outlook Calendar | Available after tool discovery | Calendar and meeting context. |
| Teams | Available after tool discovery | Teams messages/channels if authorized. |
| SharePoint / OneDrive | Available after tool discovery | Files, versions, permissions, uploads if authorized. |
| Dataverse MCP | Not exposed in this thread | Use `pac`, Dataverse Web API, and PowerShell/Azure auth instead. |
| Power Apps MCP agent feed | Tenant/platform capability, not a local Codex plugin | Evaluate inside the Power Platform/Copilot Studio tenant after Dataverse and model-driven app setup. |

## Must-Have Before Kickoff

No new local installs are strictly required before the first live-tenant validation.

Required actions:

1. Doug confirms: `C` for the BMAD epics workflow.
2. Doug confirms: Dataverse is the MVP operational store.
3. Doug confirms: Fabric IQ / Graph are deferred to graph/analytics projection.
4. Doug confirms live-write boundary:
   - Recommended tonight: Dataverse sandbox writes allowed after approval; Outlook/Graph reads allowed; no outbound emails/messages/flows/agents.
5. Doug completes interactive sign-in when prompted:
   - `pac auth create --url https://sdhdev.crm.dynamics.com --name Council-SDH-Dev`
   - `az login --tenant <tenant-id-or-domain>` if Graph/Azure checks are needed.

## Optional Installs Before Kickoff

Install only if we choose the matching path:

```powershell
# Optional: Work IQ CLI for Microsoft 365 work-context validation.
npm install -g @microsoft/workiq

# Optional: CLI for Microsoft 365 for broader M365 admin scripting.
npm install -g @pnp/cli-microsoft365

# Optional: Agent 365 CLI for later Microsoft 365 agent packaging.
dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli
```

Prefer not installing optional tools until a story or tenant gate actually needs them.

## First Authentication Commands

Run these from `C:\repo\The-Council-of-Minions` when Doug is present to complete browser/device sign-in:

```powershell
pac auth create --url https://sdhdev.crm.dynamics.com --name Council-SDH-Dev
pac auth list
pac auth who
pac env who
pac env list
```

If Graph/Azure validation is authorized:

```powershell
az login --tenant <tenant-id-or-domain>
az account show
```

If Outlook/Graph reads are authorized through PowerShell rather than Codex connector:

```powershell
Import-Module Microsoft.Graph.Authentication
Connect-MgGraph -Scopes "User.Read","Mail.Read","Calendars.Read"
Get-MgContext
```

Use the minimum scopes needed. Do not request write scopes until a story explicitly requires them and Doug approves.

## First Tenant Validation After Login

### Local Dry-Run Checks

Before any tenant auth or write, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\dataverse-manifest-validate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\dataverse-deployment-plan.ps1
```

These commands validate the manifest and print the intended Dataverse deployment plan. They do not authenticate or write to the tenant.

### Power Platform / Dataverse

1. Confirm active auth profile with `pac auth who`.
2. Confirm environment identity with `pac env who`.
3. Confirm the environment ID and organization ID match Doug's provided values.
4. List environment settings with `pac env list-settings`.
5. Check whether Dataverse search and relevant AI/intelligence settings are visible.
6. Confirm solution strategy and publisher prefix before any Dataverse writes.

### Outlook / Graph

1. Confirm the mailbox/user context.
2. Confirm delegated read scope.
3. Test a small read-only query if Doug authorizes it.
4. Record whether message body capture is allowed, summary-only, hash-only, or link-only.

### Human Review Surface

1. Confirm whether model-driven app is acceptable as MVP review surface.
2. Confirm whether Power Apps MCP agent feed should be evaluated tonight.
3. Confirm whether Teams approvals or Outlook actionable messages are phase 2.

## Recommended Live-Write Boundary For Tonight

Allowed after explicit approval:

- Create unmanaged Dataverse solution.
- Create custom Dataverse tables/columns for Council MVP.
- Create model-driven app shell.
- Create sample/mock Source Records, Work Items, and Receipts.

Not allowed tonight unless explicitly reauthorized:

- Sending emails or Teams messages.
- Publishing Power Automate flows.
- Publishing Copilot Studio agents.
- Creating app registrations.
- Granting broad Graph application permissions.
- Writing to Planner / To Do.
- Creating Fabric capacities, workspaces, ontologies, or graphs.
- Capturing sensitive/full message bodies without a data boundary decision.

## Before-Bed Answer Template For Doug

Doug can unblock the overnight run by replying with:

```text
C
Dataverse approved as MVP operational store.
Fabric IQ / Fabric Graph deferred to phase 2 graph/analytics.
Environment: https://sdhdev.crm.dynamics.com
Tenant/domain: <tenant domain or tenant ID>
Environment type: dev/sandbox/trial/prod
Live reads: Outlook/Graph allowed or not allowed
Live writes: Dataverse sandbox writes allowed after approval / forbidden / other
Source body policy: link-only / hash-only / summary allowed / full snapshot allowed
Model-driven app is acceptable as first Council Queue / Minion Brief surface: yes/no
Power Apps MCP agent feed evaluation tonight: yes/no
```

## References

- Storage decision: `_bmad-output/planning-artifacts/storage-decision-record-2026-07-08.md`
- Tenant readiness checklist: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/tenant-readiness-checklist.md`
- Microsoft platform fit matrix: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/microsoft-platform-fit-matrix-2026-07-07.md`
- Semantic contract: `_bmad-output/planning-artifacts/architecture/architecture-The-Council-of-Minions-2026-07-06/semantic-contract.md`
