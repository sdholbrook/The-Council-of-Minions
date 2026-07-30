# PRD: Council Native Operator Surface (council-native-app)

- **Status: final** (gauntlet stage 4; delta-PRD to `prd-The-Council-of-Minions-2026-07-06`)
- **Author trail:** Doug's directives 2026-07-28 (Meridian D-2026-07-28-15/-17) → research
  `pp-native-stack-research.md` → forge SURVIVE → product brief → this PRD.
- **Governs:** epic-6 only. Epics 1–5, the Dataverse schema, and the model-driven app's
  admin role are UNCHANGED by this document.

## 0. Discovery State

The Council MVP runs on Dataverse with the **Council Queue** model-driven app as its only
surface. Doug's daily loop (triage source records → approve/decline proposed work items →
read the Minion Brief) is phone-hostile in model-driven UX. Microsoft's code-first Power
Platform track went public-preview: `power-platform-skills` plugin marketplace (mobile-apps
+ code-apps plugins with MCP servers), `@microsoft/power-apps-native-host` (Expo/RN,
Tamagui, TanStack), Power Apps Developer iOS preview app, Code Apps SDK 1.x. Doug: *"it is
worth exploring using code app and a mobile version… I would very much like the council of
minions working when I get home."* Platform evaluation evidence (story 5-3 form) exists:
`5-3-evidence-operator-surface-code-first-2026-07-28.md`.

## 1. Product Thesis

**The Dataverse spine stays; surfaces become code.** Two additive, pro-code surfaces on
the same tables, same receipts, same approval boundaries: a phone-first native app for the
daily loop (Track M), and a Code App for desktop curation (Track C). The repo — not
designer state — becomes the source of truth for surface behavior, making surfaces
reviewable, diffable, and AI-iterable through the same plugin toolchain that scaffolds
them. The model-driven app remains the admin/fallback surface.

## 2. Users and Core Journeys

Single user: Doug (the Council's one human; FR22-family boundaries assume exactly one).

- **J1 — phone triage (target < 60 s):** open app → "Needs Human Approval" queue →
  open item → read proposal + rationale → approve or decline → receipt written →
  next item. Works one-handed, between meetings.
- **J2 — phone brief:** open app → Minion Brief snapshot (owners, urgency, standing
  delegation state) before a day of meetings.
- **J3 — desktop curation (Track C):** open Code App → curation views that outgrow
  model-driven forms (graph/memory/skill governance) → receipt-backed edits.
- **J4 — admin fallback:** anything not yet in the code surfaces stays one click away
  in the model-driven app; no capability is removed.

## 3. Functional Requirements

- **NA-FR1** The mobile app SHALL render the work-item queue from the existing
  `com_councilworkitem` views — at minimum "Needs Human Approval" and "Proposed Work
  Items" — with view-column parity for decision context.
- **NA-FR2** The mobile app SHALL let Doug approve or decline a proposed work item; the
  resulting state change MUST reuse the epic-2 receipt patterns (idempotent mutation +
  `com_councilreceipt` write) — no parallel mutation path.
- **NA-FR3** The mobile app SHALL render the active Minion Brief
  (`com_councilbrief`, "Active Council Briefs") read-only.
- **NA-FR4** The mobile app SHALL render source-record intake state ("New" / "Held")
  read-only; capture/extraction remain out of scope for the phone surface.
- **NA-FR5** Both tracks SHALL bind exclusively to EXISTING Dataverse tables/columns/
  views; a needed schema change exits this epic into the normal planning flow first.
- **NA-FR6** Track C SHALL provide desktop curation surfaces for the Knowledge and
  Governance rails, replacing no admin capability, deployed as a Code App
  (`@microsoft/power-apps` SDK, `npx power-apps push`).
- **NA-FR7** All scaffolds SHALL be generated through the `power-platform-skills`
  plugins (`/create-mobile-app`, code-apps flow) with every approval gate's answer
  recorded as a receipt in the repo — no hand-rolled equivalents of what the toolchain
  generates (FR27/NFR2 discipline applied to tooling).
- **NA-FR8** Every tenant-touching step (plugin install, Wrap/Entra app registration,
  Developer-app sign-in, environment binding, first data read, first data write) SHALL
  have a `VERIFY IN TENANT` evidence row (story 5-4 pattern) before the next step runs.
- **NA-FR9** App source, pin manifest, and deployment receipts SHALL live in this repo
  under version control; `npx power-apps push` output is committed as evidence per
  deploy.

## 4. Non-Functional Requirements

- **NA-NFR1 (preview posture):** the stack is Private Preview — no production posture,
  single-operator dev tenant only; the epic HALTS at the preview line if any second
  user appears before GA (forge die-condition).
- **NA-NFR2 (pin discipline):** exact versions pinned per app (native-host 0.2.25-era:
  Expo SDK 55, RN 0.83.x, React 19.2); upgrades are deliberate rebases with receipts,
  never floating ranges.
- **NA-NFR3 (offline honesty):** no offline promises; `-native-offline` exists but
  plugin flows don't drive it — watch item, not scope.
- **NA-NFR4 (auth):** Entra identity via the Wrap-generated per-app registration; every
  created registration inventoried in the 5-3 evidence record's DLP section.
- **NA-NFR5 (performance target):** J1 cold-start-to-queue under ~5 s on device via
  QR/dev flow; not a hard gate during preview, measured and recorded per milestone.
- **NA-NFR6 (licensing):** runs within Doug's existing Premium/dev entitlement; any
  second-user cost is a named decision, not an accident (per-app SKU retired 01/2026).

## 5. Scope

**In (MVP):** J1 + J2 on iOS via Developer-app preview; Track C scaffold with one
curation surface; pin manifest + toolchain doc; receipts for every gate.
**Out:** Android (preview runtime gap) · offline · push notifications · any new
Dataverse objects or connectors · production distribution (Solutions packaging of
Mobile App assets is watched, not adopted) · replacing the model-driven app.

## 6. Technical Constraints (verified 2026-07-28, primary sources)

Node 22 LTS + npm 10+ · `power-platform-skills` marketplace (mobile-apps, code-apps
plugins + their MCP servers) · `@microsoft/power-apps-native-host` 0.2.25 /
`-auth` 0.3.5 / `-common` 0.1.8 (Tamagui 2.4.5 + TanStack Query 5.62 baked in) ·
`@microsoft/power-apps` 1.2.7 → CLI 0.13.0 · Power Apps Developer iOS app
(id 6753083462) on Doug's iPhone · deployment `npx power-apps push` (no solution
packaging in plugin flows yet — ALM gap carried consciously) · unscoped npm
lookalikes (`power-apps`, `@pa-client/*`) are squats: `@microsoft/*` only.

## 7. VERIFY IN TENANT Ledger (gates before build — FR29/story 5-4)

| # | Gate | Evidence required |
|---|---|---|
| T1 | Plugin marketplace + both plugins install in the working environment | install transcript committed |
| T2 | Wrap/Entra auto-registration permitted by tenant policy | registration record + app id |
| T3 | Developer app signed in on Doug's iPhone, correct environment | screenshot/receipt |
| T4 | Scaffold reads existing tables with Doug's context | first-read receipt |
| T5 | Approve/decline write path produces a valid `com_councilreceipt` | receipt row id |

T1–T5 are **home-machine + tenant** steps. Container sessions stop at the line above T1.

## 8. Success Criteria

1. J1 round-trip on Doug's iPhone writes the same receipt shape the model-driven app
   writes, visible in both surfaces (single-source-of-truth proof).
2. J2 brief renders live data.
3. Repo carries: app source, pin manifest, gate receipts T1–T5, deploy receipt.
4. Epic-5 governance artifacts stay current (5-3 record updated with outcomes).

## 9. Risks (carried from forge, quantified where possible)

Preview churn (packages moved 4 days before this PRD; expect scaffold rebases) ·
iOS-only runtime · ALM push-only · toolchain novelty (plugin MCP servers are new moving
parts) · tenant-policy surprises at T2 (Wrap registration) — mitigation for each is a
named gate or pin, none is unbounded.

## 10. Epic Pointer

Epic-6 "Council Native Operator Surface (Code-First)" — stories 6.1–6.6 per
`epic-6-proposal-council-native-app-2026-07-28.md`, formalized at gauntlet stage 6.
