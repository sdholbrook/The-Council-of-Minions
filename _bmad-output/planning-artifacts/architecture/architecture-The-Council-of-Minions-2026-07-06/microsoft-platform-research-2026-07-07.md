# Microsoft Platform Research - 2026-07-07

## Scope

Purpose: capture current Microsoft product direction for Copilot, Dataverse, Fabric, Power Platform, model-driven apps, AI, ontology, graph, and knowledge so the Council architecture follows Microsoft movement without copying non-Microsoft implementation patterns.

Source standard: Microsoft Learn and Microsoft product blogs only. Release-plan and Learn pages are treated as stronger evidence than blog positioning. Preview and tenant-gated capabilities stay non-binding until verified in tenant.

## Executive Synthesis

Microsoft's 2026 direction is not a single backend choice. It is a set of managed intelligence planes:

- **Work IQ** for Microsoft 365 work context, semantic index, context packaging, tools, agent workspaces, and tenant-governed agent operations.
- **Dataverse intelligence** for business data grounding, Dataverse semantic models, Dataverse MCP tools, reusable business skills, and business data in Microsoft 365 Copilot.
- **Power Apps MCP server and agent feed** for human review of agent-created tasks and draft Dataverse changes inside model-driven apps.
- **Copilot Studio and Power Automate** for low-code agent creation, agent flows, knowledge, tool orchestration, human review, and workflow automation.
- **Fabric IQ, Fabric ontology, Fabric Graph, and Fabric data agents** for governed business vocabulary, data bindings, lineage, graph traversal, natural-language data access, and analytical/operational intelligence.

Architecture implication: keep the Council's source-to-work-item contract, receipts, provenance, approval boundary, and storage neutrality. Add a rule that any custom semantic, memory, skill, MCP, ontology, graph, or human-review substrate must be justified against Microsoft-native planes first.

## Platform Signals

| Area | Microsoft signal | Council implication |
| --- | --- | --- |
| Microsoft 365 Copilot and Work IQ | Work IQ APIs reached GA on June 16, 2026, with domains for chat, context, tools, and workspaces. Microsoft describes Work IQ as a semantic and governed work intelligence layer over email, calendar, meetings, chats, files, people, collaboration patterns, and line-of-business systems. | Source intake and Minion Brief should evaluate Work IQ first for Microsoft 365 work context instead of designing a custom Microsoft Graph stitching layer by default. |
| Agent 365 / Work IQ MCP tooling | Microsoft exposes governed MCP servers for Work IQ, Microsoft 365 data, Fabric IQ Ontology, Dataverse / Dynamics, and related tools under admin controls, scoped permissions, and observability. | Council tool access should prefer Microsoft-governed MCP servers where available, with custom tools limited to contract gaps. |
| Dataverse 2026 wave 1 | The release plan spotlights Work IQ and Microsoft 365 Copilot integration, Dataverse APIs, MCP servers, Python SDK, reusable skills, adaptive learning, rich business context, agent identity, and auditability. | Dataverse remains a strong candidate for Work Item, Receipt, Skill, and business-context persistence, but AD-9 still prevents accidental storage binding before the contract is reviewed. |
| Dataverse intelligence | Microsoft positions Dataverse intelligence as business-data understanding for agents and Copilot, extending Work IQ's work-artifact context into business data. Admin settings control Dataverse data availability in Microsoft 365 Copilot, Dataverse intelligence, search indexing, and MCP access. | Council must separate Microsoft 365 work context from business-data grounding. Tenant settings become an explicit architecture gate. |
| Dataverse semantic models and business skills | Microsoft is moving Dataverse from record access toward semantic models, business skills, skill learning, MCP discovery, and coding-agent plugins. | Council's Skill Registry should not assume skills are only repo prompts. It must distinguish Council skills, Dataverse business skills, Copilot Studio agents, and approved memory. |
| Dataverse semantic model | Microsoft describes the Dataverse semantic model as a preview, automatically provisioned business-aware understanding layer for agents and Copilot experiences over Dataverse data, built from semantic indexing, inferred metadata signals, and glossary terms. | Treat it as the Dataverse runtime projection of Council business meaning, not the canonical Council ontology or graph. Keep canonical definitions in a Council Semantic Contract and project them into Dataverse metadata and glossary entries. |
| Model-driven apps and Microsoft 365 Copilot | Microsoft 365 Copilot in model-driven apps answers over Dataverse table data and app context. Current documentation emphasizes read-only Copilot operations unless customized with an agent. | A model-driven app is a candidate Council cockpit, but mutation still belongs behind Council approvals and receipts. |
| Power Apps MCP server and agent feed | Starting May 1, 2026, model-driven app agent feed supports agents that use the Power Apps MCP Server to create tasks. Agent feed gives human review surfaces for agent tasks and draft Dataverse record creation or updates. | This maps closely to Council's human approval boundary and work-item queue, especially for review/step-in workflows. Treat it as a candidate surface, not yet the canonical queue. |
| Copilot Studio | Copilot Studio agents combine instructions, context, knowledge, topics, tools, triggers, and agent flows. Knowledge can include Dataverse, Power Platform, Dynamics 365, SharePoint, websites, and external systems, with DLP controls over knowledge source types. | Copilot Studio is a candidate Minion orchestration and agent packaging surface. It should not own Council receipts, provenance, or durable instruction unless the Council contract says so. |
| Power Automate | 2026 wave 1 includes AI agent authoring, self-healing, Copilot Studio integration, process intelligence, object-centric process mining, Fabric integration, and MCP. | Power Automate is a later automation-runner candidate after AD-4, AD-5, AD-10, and tenant validation are satisfied. |
| Fabric data agents | Fabric data agents can answer over Lakehouse, Warehouse, Power BI semantic model, KQL database, ontology, and Microsoft Graph sources, generating and executing read-only queries under user credentials and governance. | Fabric data agents are better suited for analytical briefs, research, and data Q&A than Council workflow mutation. |
| Fabric IQ ontology | Fabric IQ ontology defines enterprise concepts, relationships, properties, rules, constraints, data bindings, lineage, and natural-language ontology queries. | Fabric IQ is the strongest Microsoft-native candidate for a richer Meaning Graph later, especially if Council data lands in OneLake/Fabric. MVP should still keep the graph lightly operational. |
| Fabric Graph | Fabric Graph models relationship-heavy data using graph storage and query, supports graph traversal and NL-to-GQL, but current documentation lists source and scale limitations. | Fabric Graph is a candidate graph projection/analysis engine, not an MVP workflow engine. Preview and capacity constraints must be checked before binding. |

## Architecture Implications

1. **Do not replace AD-9.** Microsoft direction makes Dataverse and Fabric stronger candidates, but not automatic requirements. Council still needs object contracts, provenance, mutation, and ownership before storage selection.
2. **Add a Microsoft-plane evaluation rule.** Council should evaluate Work IQ, Dataverse intelligence / Dataverse MCP, Power Apps MCP agent feed, Copilot Studio, Power Automate, Fabric IQ / Fabric Graph, and Fabric data agents before building custom equivalents.
3. **Keep source records and work items separate.** Work IQ and Dataverse can provide context and business understanding, but Council still needs its own source-to-work-item decision boundary.
4. **Receipts remain Council-owned.** Microsoft platforms provide auditability and governance, but the Council's product-level receipt verbs and provenance chain remain canonical unless a later design proves a Microsoft-native ledger can express them exactly.
5. **Skill Registry must become multi-plane.** The Council must track whether a capability is a Council Skill, Dataverse business skill, Copilot Studio agent, Power Automate flow, MCP tool, or approved memory.
6. **Meaning Graph should be a projection contract first.** Fabric IQ / Graph may later host or project the graph, but AD-6 still prevents graph edges from becoming workflow state.
7. **Semantic knowledge should be authored once.** Dataverse semantic model and Fabric IQ ontology / graph should both project from a Council Semantic Contract. Platform-inferred terms and relationships can propose updates back to the contract, but they should not silently become canonical.
8. **Human review should be designed with agent feed in mind.** Power Apps MCP agent feed is close to the Council approval model, so UX and solution architecture should evaluate it before creating a custom queue.
9. **Tenant verification is not optional.** Availability, admin toggles, DLP policies, licensing, Copilot Credits, Fabric capacity, preview status, regional settings, and Microsoft 365 / Power Platform governance must be verified before implementation.

## Microsoft-First Fit Matrix

| Council need | First Microsoft plane to evaluate | Why |
| --- | --- | --- |
| Microsoft 365 source context | Work IQ Context / Tools / MCP | Microsoft is optimizing this for agent-ready work context and secure action across Microsoft 365. |
| Business-data grounding | Dataverse intelligence, Dataverse semantic models, Dataverse MCP | This is Microsoft's business-data understanding layer for Copilot and agents. |
| Dataverse agent meaning | Dataverse semantic model, Dataverse glossary, Dataverse metadata | Best fit for Copilot and agent interpretation over Dataverse-backed Council records. It should receive approved Council terms, not author them independently. |
| Human approval queue | Power Apps MCP server, model-driven app agent feed, Approvals / Teams as secondary candidates | The agent feed is explicitly built for human supervision of agent tasks in business apps. |
| Work item and receipts store | Dataverse first candidate, storage-neutral contract still controlling | Dataverse aligns with Power Apps, model-driven app surfaces, security, and MCP, but the Council contract decides. |
| Skill / process knowledge | Dataverse business skills, Copilot Studio agents, Council Skill Registry | Microsoft is productizing business skills; Council still needs authority and proof semantics. |
| Agent packaging | Copilot Studio, Work IQ tools, Agent 365 managed MCP | These are Microsoft's managed agent and tool surfaces. |
| Analytics and data Q&A | Fabric data agents, Power BI semantic models, Microsoft Graph in Fabric | Better fit for read-only analysis and briefs than workflow mutation. |
| Ontology / graph | Fabric IQ ontology, Fabric Graph | Best Microsoft-native direction for governed business vocabulary, data bindings, lineage, and graph analysis. |
| Automation runner | Power Automate, Copilot Studio agent flows | Strong candidate only after approvals, receipts, and tenant gates are clear. |

## Watch Items

- Preview status and dates change quickly. Treat feature plans and preview documentation as direction, not production architecture.
- Dataverse intelligence and Microsoft 365 Copilot data availability require admin settings and Dataverse search/indexing configuration.
- Work IQ APIs and related Microsoft 365 agent capabilities introduce Copilot Credit and cost-management considerations.
- Fabric IQ / Graph may require Fabric capacity and have source, scale, refresh, and tenant-setting constraints.
- Power Apps MCP agent feed support depends on MCP onboarding and agent compatibility.
- DLP and governance can block knowledge sources or connector/tool use even when the feature exists.

## Sources

- [Microsoft Power Platform 2026 release wave 1 plan](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/)
- [Overview of Microsoft Dataverse 2026 release wave 1](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/data-platform/)
- [What's new and planned for Microsoft Dataverse](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/data-platform/planned-features)
- [Announcing the new Work IQ APIs](https://www.microsoft.com/en-us/microsoft-365/blog/2026/06/02/announcing-the-new-work-iq-apis/)
- [Work IQ overview](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/work-iq/)
- [Work IQ MCP overview](https://learn.microsoft.com/en-us/microsoft-agent-365/tooling-servers-overview)
- [Dataverse intelligence](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-intelligence)
- [Overview of Dataverse semantic model](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/semantic-model-overview)
- [Fine-tune semantic model signals](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/fine-tune-semantic-model-signals)
- [Manage semantic model glossary entries](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/manage-semantic-model-glossary)
- [Dataverse semantic model FAQ](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/semantic-model-faq)
- [Power Platform feature settings](https://learn.microsoft.com/en-us/power-platform/admin/settings-features)
- [Dataverse Is Your Agent Data Platform: Here's What's New in July 2026](https://www.microsoft.com/en-us/power-platform/blog/2026/06/29/dataverse-july-2026/)
- [Add Microsoft 365 Copilot to your model-driven app](https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/add-microsoft-365-copilot)
- [Add agents to your model-driven app](https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/add-agents-to-app)
- [Work with Power Apps MCP server](https://learn.microsoft.com/en-us/power-apps/maker/model-driven-apps/power-apps-mcp-server)
- [Supervise agents in model-driven apps with agent feed](https://learn.microsoft.com/en-us/power-apps/user/supervise-agents-with-agent-feed)
- [What is Microsoft Copilot Studio?](https://learn.microsoft.com/en-us/microsoft-copilot-studio/fundamentals-what-is-copilot-studio)
- [Add knowledge to Microsoft Copilot Studio agents](https://learn.microsoft.com/en-us/microsoft-copilot-studio/knowledge-copilot-studio)
- [Configure data loss prevention for Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-data-loss-prevention)
- [Overview of Power Automate 2026 release wave 1](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/power-automate/)
- [What's new in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/fundamentals/whats-new)
- [Fabric data agent concepts](https://learn.microsoft.com/en-us/fabric/data-science/concept-data-agent)
- [Create a Fabric data agent](https://learn.microsoft.com/en-us/fabric/data-science/how-to-create-data-agent)
- [What is Fabric IQ?](https://learn.microsoft.com/en-us/fabric/iq/overview)
- [What is Ontology in Fabric IQ?](https://learn.microsoft.com/en-us/fabric/iq/ontology/overview)
- [Graph in Microsoft Fabric overview](https://learn.microsoft.com/en-us/fabric/graph/overview)
- [Limitations in Graph in Microsoft Fabric](https://learn.microsoft.com/en-us/fabric/graph/limitations)
