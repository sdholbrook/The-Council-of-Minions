# Microsoft Platform Fit Matrix - 2026-07-07

Status: architecture-ready  
Purpose: make AD-11 actionable before solution architecture or implementation selects Microsoft services.

## Rule

Evaluate Microsoft-native intelligence planes before custom substrate. A custom service is acceptable only when a documented Council requirement is not met by Microsoft-native options or when tenant, lifecycle, licensing, cost, capacity, governance, or availability blocks adoption.

## Fit Matrix

| Council need | First Microsoft plane | Fit | Required evidence before adoption | Current decision |
| --- | --- | --- | --- | --- |
| Microsoft 365 work context | Work IQ context, tools, and MCP | Strong candidate for M365 emails, files, meetings, chats, people, and agent-ready work context. | Tenant availability, permission model, admin controls, Copilot credit impact, data boundary behavior, action safety. | Evaluate first; not bound. |
| Outlook-first source intake | Microsoft Graph / Outlook, Work IQ, Outlook source links | Strong candidate for source references and thread context. | Message/thread identity, delta/change tracking, sensitivity labels, attachments, shared mailbox behavior, Graph permission scope. | First intake source; implementation not selected. |
| Business-data grounding | Dataverse intelligence, Dataverse semantic model, Dataverse MCP | Strong candidate if operational records live in Dataverse. | Environment settings, Dataverse Search/indexing, semantic model availability, glossary/metadata strategy, MCP availability, ALM gaps. | Candidate projection; not canonical semantics. |
| Work Item operational store | Dataverse | Strong candidate because of model-driven apps, security, business data, MCP, and Power Platform integration. | Contract fit, row-level security, ALM, audit, receipt append-only behavior, cost, environment strategy, backup/retention. | Candidate only under AD-9. |
| Human review queue | Minion Brief / Council Queue product surface, Power Apps MCP agent feed, model-driven app, Teams approvals | Power Apps agent feed is promising for human review; product surface still Council-owned. | Agent feed availability, MCP onboarding, task-review UX, approval semantics, audit receipts, licensing. | Council surface fixed; implementation open. |
| Agent packaging | Copilot Studio, Work IQ tools, Agent 365 managed MCP | Strong candidate for Microsoft-native agents and managed tools. | Tool authorization, DLP, lifecycle, environment promotion, prompt/instruction governance, human review support. | Evaluate after contracts. |
| Workflow automation | Power Automate, Copilot Studio agent flows | Strong candidate for low-code automation after approval and receipt rules are enforceable. | Idempotency, error handling, receipts, approval boundaries, DLP, connector policy, environment strategy. | Deferred; no live automation implied. |
| Semantic contract projection | Dataverse metadata/glossary, Fabric IQ ontology, Copilot Studio knowledge | Strong candidates for platform-specific projection from the Council Semantic Contract. | ALM path, drift detection, glossary ownership, ontology bindings, review process, projection regeneration. | Council Semantic Contract is canonical. |
| Relationship analysis / graph | Fabric IQ ontology, Fabric Graph | Strong candidate for cross-domain relationship analysis and future graph projection. | Fabric capacity, preview status, source support, refresh, lineage, query limits, DLP/Purview behavior. | Candidate only; graph is not workflow engine. |
| Analytics and data Q&A | Fabric data agents, Power BI semantic models, Fabric data sources | Strong candidate for read-only analysis and briefing. | Read-only enforcement, data source limits, user identity, DLP/Purview behavior, source freshness, capacity cost. | Candidate for future briefs, not MVP mutation. |
| Durable memory | Council Memory Candidate / Approved Instruction contract, Dataverse or repo-backed store, Copilot Studio knowledge as projection | Microsoft planes can expose memory, but Council approval and recall/use policy are product-specific. | Store selection, approval workflow, recall tracing, deletion/supersession, sensitivity, retention, projection behavior. | Council contract first. |

## Evidence Template

Every service-selection decision must record:

- Council capability and contract requirement.
- Microsoft candidate evaluated.
- Official source/date checked.
- Tenant setting or admin gate.
- Permission and DLP impact.
- Licensing, capacity, or cost gate.
- Lifecycle / ALM path.
- Contract gaps.
- Decision: adopt, defer, reject, or custom-gap build.
- Receipt or review reference.

## Current Recommendation

For solution architecture, evaluate in this order:

1. Work IQ for Microsoft 365 source context.
2. Dataverse for operational Work Items, Receipts, Semantic Contract projection, and model-driven review candidates.
3. Power Apps MCP agent feed and model-driven apps for human review if Dataverse is selected.
4. Copilot Studio / Power Automate for agent packaging and automation only after receipt and approval contracts are enforceable.
5. Fabric IQ / Graph / data agents for richer ontology, graph analysis, and analytics after MVP contracts stabilize.

This recommendation is not a backend decision. AD-9 still controls.

## Sources

- [Microsoft Power Platform 2026 release wave 1 plan](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/)
- [Overview of Microsoft Dataverse 2026 release wave 1](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/data-platform/)
- [Work IQ overview](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/work-iq/)
- [Work IQ MCP overview](https://learn.microsoft.com/en-us/microsoft-agent-365/tooling-servers-overview)
- [Dataverse intelligence](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-intelligence)
- [Overview of Dataverse semantic model](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/semantic-model-overview)
- [Work with Power Apps MCP server](https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/power-apps-mcp-server)
- [What is Microsoft Copilot Studio?](https://learn.microsoft.com/en-us/microsoft-copilot-studio/fundamentals-what-is-copilot-studio)
- [What is Fabric IQ?](https://learn.microsoft.com/en-us/fabric/iq/overview)
- [What is ontology in Fabric IQ?](https://learn.microsoft.com/en-us/fabric/iq/ontology/overview)
- [Graph in Microsoft Fabric overview](https://learn.microsoft.com/en-us/fabric/graph/overview)
- [Fabric data agent concepts](https://learn.microsoft.com/en-us/fabric/data-science/concept-data-agent)
