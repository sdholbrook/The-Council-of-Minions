# Model-Driven Screen Red/Green Test Plan

Date: 2026-07-11
Owner: BMAD TEA
Scope: Council Queue model-driven app screen acceptance in `sdhdev`

## Risk Statement

Dataverse metadata checks can pass while the model-driven app still fails for Doug on first use. The screen gate must therefore test the rendered Microsoft app surface, not just solution metadata, table existence, or `ValidateApp` output.

## Red Conditions

- Browser is not authenticated and the run is not interactive.
- The current URL, page title, or visible body matches a Dynamics/Power Apps error surface.
- The app home stays on `Loading...` or does not expose the expected Council navigation groups.
- A named curated view ID cannot render the expected view name and seeded MVP row markers.
- A seeded record form cannot render its expected record markers.
- The runner uses fixed sleeps for screen readiness instead of observable page conditions.

## Green Conditions

- The actual `Council Queue` app opens in `https://sdhdev.crm.dynamics.com`.
- App home shows `Intake`, `Work`, `Brief`, `Knowledge`, and `Governance` navigation groups.
- Curated views render by ID for Source Records, Work Items by state, and Receipts.
- Seeded forms render for the demo Source Record, Work Item, Receipt, and Minion Brief.
- Each run writes screenshots, trace, console log, page errors, network errors, and a report.

## Current Implementation

- `_bmad-output/implementation-artifacts/council-model-driven-screen-test.ps1` resolves the live app ID, curated view IDs from app curation evidence, and seeded record IDs from Dataverse before launching the browser run.
- `_bmad-output/test-artifacts/model-driven-screen/council-model-driven-screen-test.js` drives the screen checks and fails fast on app errors in URL, title, or body text.
- `_bmad-output/implementation-artifacts/council-mvp-local-validate.ps1` verifies the screen gate harness exists and rejects fixed readiness sleeps in the browser runner.

## Latest Live Gate Result

Status: RED
Run ID: `2026-07-11T19-21-54-362Z`

Passing screen evidence:

- App home shell renders Council navigation groups.
- `New Source Records` renders by curated view ID.
- `Proposed Work Items` renders by curated view ID.
- `Approved Work Items` renders by curated view ID.
- `Blocked or Held Work Items` renders by curated view ID.
- `In Review` renders by curated view ID.
- `Completed Recently` renders by curated view ID.
- `Failed Needs Review` renders by curated view ID.
- `Failed Receipts` renders by curated view ID and shows the seeded failed receipt.
- `Recent Receipts` renders by curated view ID and shows the seeded receipt rows without falling back to `Active Council Receipts`.
- The baseline Council Briefs view renders.

Current failing screen:

- `source-record-form` opens the intended seeded Source Record and renders `Manual sample source record`.
- The live main form exposes `Name` and `Owner` but not the required `manual-demo-source-001` identifier marker.
- The suite stops at this first user-visible form defect with screenshot, trace, requested/final URL, title, browser diagnostics, and machine-readable results.

Next product fix:

- Curate the Source Record main form so the canonical Source Record identifier is visible, then rerun the strict suite through the Work Item, Receipt, and Brief forms.

## Acceptance Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-mvp-local-validate.ps1 -RequireScreenEvidence
```

If browser authentication is required:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-model-driven-screen-test.ps1 -InteractiveLogin -Headed
```
