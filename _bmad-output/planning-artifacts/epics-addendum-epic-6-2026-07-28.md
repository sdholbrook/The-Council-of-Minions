# Epics Addendum — Epic 6: Council Native Operator Surface (Code-First)

*Formalized at gauntlet stage 6 (2026-07-28). `epics.md` is deliberately untouched —
this addendum is the authoritative epic-6 text until Doug folds it in. Sources:
`prds/prd-council-native-app-2026-07-28/prd.md` (NA-FR/NA-NFR),
`architecture/architecture-council-native-app-2026-07-28/` (I1–I8 + adversarial
receipt). Supersedes the sketch in `epic-6-proposal-council-native-app-2026-07-28.md`.*

**Epic goal:** Doug's daily loop native on his phone and a pro-code desktop curation
surface — both on the existing Dataverse schema, receipts identical across surfaces,
model-driven app retained as admin/fallback, everything Private-Preview-labeled.

**Requirements:** NA-FR1–9, NA-NFR1–6 (delta-PRD) under the main PRD's FR26–FR29/NFR2
governance. **Dependency order:** 6.1 → 6.2 → {6.3 ∥ 6.4} → 6.5 → 6.6.

### Story 6.1: Pin and Verify the Code-First Toolchain

As Doug's build system,
I want the plugin marketplace, plugins, and every package version pinned and verified,
so that preview churn becomes deliberate rebases instead of silent drift.

**Given** a working environment with Node 22 LTS and npm 10+
**When** the power-platform-skills marketplace and the mobile-apps + code-apps plugins are installed
**Then** `apps/council-mobile/PINS.md` records marketplace, plugin, and `@microsoft/*` package versions (NA-NFR2, arch I4/A7)
**And** tenant gate T1 evidence is committed before any scaffold runs (NA-FR8).

### Story 6.2: Scaffold Track M Against Existing Tables

As Doug,
I want the mobile app scaffolded by `/create-mobile-app` bound to the EXISTING tables,
so that the phone surface exists without a single schema change.

**Given** T1 is green and the Developer app is signed in (T2, T3)
**When** the scaffold flow runs with every approval-gate answer recorded
**Then** the app binds to existing `com_council*` tables only — **if the flow insists on
creating tables, the story STOPS and records the constraint** (readiness K1; NA-FR5/I2)
**And** the Wrap-generated registration is inventoried (NA-NFR4)
**And** QR preview renders live reads from "Needs Human Approval" (T4; NA-FR1)
**And** view columns come from generated metadata, never hand-typed lists (arch A4).

### Story 6.3: Approve/Decline Slice (Mobile)

As Doug,
I want to approve or decline a proposed work item from my phone with a receipt,
so that the daily decision loop is truly mobile.

**Given** a work item in "Needs Human Approval" on the T4-proven scaffold
**When** Approve or Decline is tapped
**Then** the mutation module writes receipt-FIRST with deterministic IDs
(`CR-<wi-id>-<STATE>`, arch I1/§5) and the state change follows idempotently (NA-FR2)
**And** Decline maps to `held` + decline rationale on the receipt — no new state value (arch A5)
**And** an orphan-receipt reconciliation query exists and runs clean (arch A3)
**And** the same transition made in the model-driven app produces an identical receipt
shape (success criterion 1; T5 evidence).

### Story 6.4: Minion Brief Read Surface (Mobile)

As Doug,
I want the active Minion Brief readable on my phone,
so that the standing picture travels with me.

**Given** the T4-proven scaffold
**When** BriefScreen renders "Active Council Briefs" (NA-FR3)
**Then** the surface is verifiably read-only — no mutation-module imports (mechanical
check) — and renders live data.

### Story 6.5: Scaffold Track C (Code App, Desktop Curation)

As Doug,
I want a pro-code desktop surface for the worst model-driven fit,
so that curation flows live in reviewable code.

**Given** Track M's data path is proven (post-6.3/6.4)
**When** the code-apps plugin scaffolds `apps/council-desktop/` with the memory-candidate
→ approved-instruction promotion surface (NA-FR6)
**Then** the surface reuses the proven client configuration, respects I1 receipts for
any write, and its first `npx power-apps push` receipt is committed (NA-FR9).

### Story 6.6: ALM and Preview-Posture Evidence

As the Council's governance layer,
I want the deployment story recorded honestly,
so that epic-5 discipline survives the new toolchain.

**Given** stories 6.1–6.5 receipts exist
**When** the evidence pass runs
**Then** `native-app-evidence/` carries: registration inventory, licensing state,
deploy receipts, the solution-packaging watch item — and the 5-3 evidence record gains
an OUTCOMES section (NA-FR8/9, NA-NFR6; arch §7).
