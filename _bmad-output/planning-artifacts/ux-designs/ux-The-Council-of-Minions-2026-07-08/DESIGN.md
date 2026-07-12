---
name: "Council Queue"
description: "Operational Microsoft-first review surface for Source Records, Work Items, Receipts, Minion Briefs, and governance evidence."
status: partial
updated: 2026-07-08
sources:
  - ../../prds/prd-The-Council-of-Minions-2026-07-06/prd.md
  - ../../prds/prd-The-Council-of-Minions-2026-07-06/addendum.md
  - ../../architecture/architecture-The-Council-of-Minions-2026-07-06/ARCHITECTURE-SPINE.md
  - ../../architecture/architecture-The-Council-of-Minions-2026-07-06/semantic-contract.md
  - ../../architecture/architecture-The-Council-of-Minions-2026-07-06/work-item-receipt-contract.md
  - ../../dataverse-mvp-schema-plan-2026-07-08.md
assumptions:
  - "First implementation surface is a Dataverse model-driven app unless Doug rejects it."
  - "Fluent / Power Apps model-driven defaults carry most component visuals."
  - "This pass defines a practical MVP contract, not a polished custom brand system."
open_questions:
  - "Does Doug accept a model-driven app as the first Council Queue / Minion Brief surface?"
  - "Should the MVP use only standard model-driven styling, or allow a thin custom app later for richer review ergonomics?"
colors:
  surface-base: '#F7F8FA'
  surface-raised: '#FFFFFF'
  surface-subtle: '#EEF3F8'
  ink-primary: '#1F2328'
  ink-secondary: '#5E6773'
  ink-muted: '#8A94A3'
  border-default: '#D6DCE3'
  border-strong: '#AEB8C4'
  action-primary: '#0F6CBD'
  action-primary-foreground: '#FFFFFF'
  signal-approval: '#107C10'
  signal-attention: '#C19C00'
  signal-risk: '#D83B01'
  signal-blocked: '#A4262C'
  signal-info: '#0078D4'
typography:
  page-title:
    fontFamily: 'Segoe UI, Aptos, system-ui, sans-serif'
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.25'
    letterSpacing: '0'
  section-title:
    fontFamily: 'Segoe UI, Aptos, system-ui, sans-serif'
    fontSize: 18px
    fontWeight: '600'
    lineHeight: '1.35'
    letterSpacing: '0'
  body:
    fontFamily: 'Segoe UI, Aptos, system-ui, sans-serif'
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.45'
    letterSpacing: '0'
  label:
    fontFamily: 'Segoe UI, Aptos, system-ui, sans-serif'
    fontSize: 12px
    fontWeight: '600'
    lineHeight: '1.35'
    letterSpacing: '0'
  meta:
    fontFamily: 'Segoe UI, Aptos, system-ui, sans-serif'
    fontSize: 12px
    fontWeight: '400'
    lineHeight: '1.35'
    letterSpacing: '0'
rounded:
  sm: 2px
  md: 4px
  lg: 8px
  full: 9999px
spacing:
  '1': 4px
  '2': 8px
  '3': 12px
  '4': 16px
  '5': 20px
  '6': 24px
  page-gutter: 24px
  compact-row: 36px
  comfortable-row: 48px
components:
  command-primary:
    background: '{colors.action-primary}'
    foreground: '{colors.action-primary-foreground}'
    radius: '{rounded.md}'
  state-badge:
    radius: '{rounded.full}'
    typography: '{typography.meta}'
  data-grid:
    row-height: '{spacing.comfortable-row}'
    compact-row-height: '{spacing.compact-row}'
    border: '{colors.border-default}'
  evidence-panel:
    background: '{colors.surface-raised}'
    border: '{colors.border-default}'
    radius: '{rounded.lg}'
  brief-panel:
    background: '{colors.surface-subtle}'
    border: '{colors.border-default}'
    radius: '{rounded.lg}'
---

# Council Queue - Design Spine

## Brand & Style

Council Queue is an operational review tool, not a marketing destination and not a playful agent dashboard. It should read like a Microsoft business app built for repeated judgment work: dense enough to scan, restrained enough to trust, and explicit enough that provenance and authority are never hidden.

The visual posture is sober and legible. The interface should feel closer to a model-driven app command center than a consumer inbox. The product can still have personality through names like Minion Brief, but the visual system must not make serious approval, receipt, and governance work feel casual.

## Colors

The palette inherits Microsoft / Fluent conventions where the implementation surface provides them. Council-specific color is reserved for action and state communication:

- **Action primary** `{colors.action-primary}` is for the single primary command in a region, such as Create Source Record or Generate Brief.
- **Approval** `{colors.signal-approval}` indicates approved, completed, accepted, or available evidence.
- **Attention** `{colors.signal-attention}` indicates proposed, needs review, held, or unverified.
- **Risk** `{colors.signal-risk}` indicates sensitive, legal, finance, governance, or high-risk classification.
- **Blocked** `{colors.signal-blocked}` indicates blocked, failed, denied, or cannot proceed.
- **Info** `{colors.signal-info}` indicates source, provenance, or system evidence.

Do not use color alone to communicate status. Every status color must be paired with a text label and, where supported, an icon or field value.

## Typography

Use system Microsoft typography: Segoe UI, Aptos, or the model-driven app default. The product needs readable data density more than display character.

Page titles use `{typography.page-title}`. Section headers use `{typography.section-title}`. Grid values, form values, and receipt details use `{typography.body}`. Field labels and state labels use `{typography.label}` or the model-driven default equivalent.

No viewport-scaled type. No negative letter spacing. Avoid oversized hero copy inside the app surface.

## Layout & Spacing

Use model-driven app structure when available: left navigation, command bar, view selector, data grid, main form, related tabs, and side panels. Custom layout should preserve that mental model.

Spacing is compact by default. Lists and grids should prioritize scan speed. Review forms may use more vertical spacing when evidence, rationale, and source links need to be read together.

Primary screen pattern:

1. Page title and command bar.
2. View/filter row.
3. Data grid or focused record form.
4. Evidence/provenance panel.
5. Related Receipts or graph explanation panel.

Cards are allowed only for repeated records, summary panels, and modal/detail surfaces. Do not put cards inside cards.

## Elevation & Depth

Prefer borders and tonal layering to shadows. Shadows should come from the host model-driven app only. Custom components should not add decorative elevation.

Important evidence panels use `{components.evidence-panel}`. Brief summary panels use `{components.brief-panel}`. These panels exist to group operational information, not to decorate the page.

## Shapes

Use restrained corners: `{rounded.sm}` for fields and grid controls, `{rounded.md}` for commands, `{rounded.lg}` for panels and dialogs. Avoid large rounded cards, decorative pills, and playful shapes.

Status badges may use `{rounded.full}` only when the host UI system already presents statuses as badges. The badge label must still be text-first.

## Components

### Command Buttons

Primary commands use `{components.command-primary}` only when they move the current workflow forward. Secondary actions use the host system's secondary, outline, or command-bar styles.

Primary command examples:

- New Source Record
- Extract Proposed Work Item
- Append Receipt
- Generate Brief

Commands that could imply external action must visually differ from internal review commands and must remain disabled or approval-gated until a separate external-action approval exists.

### State Badge

State badges show product-level state groups: proposed, approved, blocked, held, in review, completed, failed. They pair text, color, and field value. They must not invent local synonyms that compete with the Semantic Contract.

### Data Grid

Data grids are the default repeated-record surface. Each grid should expose status, type, risk, owner candidate, source system, last receipt, and verification state where relevant. Row height should not change on hover or selection.

### Evidence Panel

Evidence panels group source links, source metadata, receipt references, confidence, rationale, policy flags, and graph explanation. Evidence panels should appear beside or below the record being reviewed. They must never hide the source reference behind decorative accordions by default.

### Brief Panel

Brief panels summarize queue state, decisions needed, delegations ready, risks if ignored, blockers, recent receipts, and memory candidates. A Brief is a projection. The visual treatment must always make it clear that Work Items and Receipts are the source of truth.

### Graph Explanation

Graph explanation is textual and relationship-list based in MVP. It may show source, person, project, topic, decision, commitment, risk, skill, and receipt links. It is not a node-link graph editor.

## Do's and Don'ts

| Do | Don't |
| --- | --- |
| Use Microsoft business-app defaults and override only what carries Council meaning | Build a custom decorative dashboard before the model-driven MVP is proven |
| Keep records, receipts, and evidence visible together during review | Hide provenance behind a generic details drawer |
| Use color for status only with labels and fields | Use color as decoration or personality |
| Keep Source Record, Work Item, Receipt, Memory Candidate, Skill, Graph Entity, and Brief visually distinct | Collapse them into one generic "item" card |
| Treat Brief as a projection with references back to Work Items and Receipts | Let Brief text look like the source of truth |
| Use compact data grids for repeated review | Use oversized cards for every work item |
| Keep graph explanation as readable relationships | Introduce graph editing or spatial visualization in MVP |
