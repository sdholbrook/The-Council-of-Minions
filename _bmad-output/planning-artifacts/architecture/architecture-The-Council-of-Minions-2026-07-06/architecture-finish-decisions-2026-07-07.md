# Architecture Finish Decisions - 2026-07-07

## Purpose

Close the product and architecture forks found by adversarial review so downstream BMAD work can build from one consistent packet.

## Closed Decisions

| Decision | Resolution | Why it matters |
| --- | --- | --- |
| MVP operator | Doug-private first, team-ready contracts | Keeps MVP narrow while preserving authority, identity, and provenance boundaries needed for later team use. |
| Product boundary | Microsoft-work-context-first, not email-only | Preserves the work-item model while keeping Outlook as the first useful intake source. |
| First intake | Outlook-first plus manual capture | Honors the forge output and gives the MVP a concrete starting surface. |
| First review surface | Minion Brief plus Council Queue | Prevents competing Outlook-only, Teams-only, dashboard-only, or model-driven app-only MVPs. |
| Approval frame | Council product-level approval first | Teams approvals, Outlook actionable messages, Power Apps agent feed, and model-driven commands are implementation candidates after tenant validation. |
| Graph visibility | Brief-level relationship explanation | Avoids building a graph editor before the graph proves routing, provenance, and explanation value. |
| Memory MVP | Memory Candidate before approved instruction, with recall/use policy | Keeps durable context governed and auditable. |
| Semantic authority | Council Semantic Contract | Dataverse semantic model, Fabric IQ ontology, Fabric Graph, Copilot Studio knowledge, and business skills become projections, not competing sources of truth. |
| Automation | Proposed or auto-created low-risk items only; no external action without approval | Keeps useful triage possible without crossing authority boundaries. |

## Remaining Implementation Gates

- Tenant validation must happen before any live Microsoft 365, Power Platform, Dataverse, Fabric, Copilot Studio, or automation work.
- Platform selection must use `microsoft-platform-fit-matrix-2026-07-07.md`.
- Epics and stories must cite the companion contracts rather than re-inventing object shapes.
