---
project_name: 'The-Council-of-Minions'
user_name: 'Doug'
date: '2026-06-30'
sections_completed:
  - technology_stack
  - implementation_rules
  - governance
  - workflow
existing_patterns_found: 10
---

# Project Context for AI Agents

_This file is the active BMAD context artifact. A supplemental June 30 steering note informs these rules, but that note is not the controlling project document._

---

## Technology Stack & Versions

- BMAD module scaffolding `6.9.1-next.19` configured via `_bmad/bmm/config.yaml`
- Git repository with Markdown-first planning artifacts and generated outputs under `_bmad-output/`
- Configuration stack based on TOML and YAML under `_bmad/`
- Python helper scripts under `_bmad/scripts/` and skill `scripts/` folders
- JavaScript helper scripts under `_bmad/wds/scripts/`
- Microsoft-native target stack: Microsoft 365 Copilot, M365 Agent Templates, Copilot Studio, Power Automate, Outlook, Teams, Planner / Microsoft To Do, SharePoint, OneDrive, Loop, Microsoft Graph, Azure DevOps, Dataverse, and Dynamics 365 where available
- No target-product runtime manifest exists yet in the workspace (`package.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, and `go.mod` were not found)

## Critical Implementation Rules

### Template-First Rules

- Start from Microsoft's M365 Agent Templates, not from a blank design.
- Treat Microsoft templates as seed agents to adapt, not as final implementations.
- Prefer documenting template names, URLs, setup guides, and customization notes over committing vendor binaries.
- If vendor assets are intentionally added, store them under `/vendor/m365-agent-templates/` with source and date.

### Scope Rules

- Phase 1 is documentation, template mapping, prompts, governance, and implementation planning only.
- The first working scope is limited to five Minions: Chief, Inbox, Calendar, Briefing, and Follow-Up.
- Build the repo as the source of truth for templates, Minion definitions, prompts, governance, evaluation, and deployment notes.
- Use the steering note as directional input for BMAD decisions, not as the controlling spec.

### Governance Rules

- Human-in-the-loop is mandatory.
- External communications remain draft-only until Doug approves.
- Keep the first implementation at authority Levels 0-2 only.
- Do not send email, make commitments, modify contracts, publish externally, change tenant settings, or grant broad Microsoft Graph permissions.

### Data and Privacy Rules

- The first version is Doug's private council, not a company-wide rollout.
- Do not assume CEO-private outputs can be shared with the company.
- Design for Microsoft-native sources, but do not connect live data in Phase 1.
- Classify future sources by sensitivity and visibility before proposing automation.

### Workflow Rules

- Mark all tenant-specific unknowns as `VERIFY IN TENANT` instead of guessing.
- Do not request credentials, connect to Microsoft 365, create app registrations, publish agents, or create live automations in Phase 1.
- The primary daily artifact is **The Minion Brief** and urgent escalations use **Minion Alert**.
- Map templates to Minions using the source brief: Plan My Day for Chief/Calendar, Executive Briefing for Briefing, Request Tracker plus Status Update Agent for Follow-Up, and Plan My Day plus Request Tracker patterns for Inbox.
