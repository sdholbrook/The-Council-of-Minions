---
title: 'Fix Receipt curated view routing in Council Queue'
type: 'bugfix'
created: '2026-07-11'
status: 'done'
baseline_revision: '07de479'
review_loop_iteration: 0
followup_review_recommended: false
context:
  - '{project-root}/_bmad-output/project-context.md'
  - '{project-root}/_bmad-output/planning-artifacts/model-driven-screen-red-green-test-plan-2026-07-11.md'
warnings: []
---

<intent-contract>

## Intent

**Problem:** The live Council Queue app ignores the selected `Recent Receipts` system-view ID and renders `Active Council Receipts`. This leaves the screen-driven MVP gate red even though the saved view and its app component exist in Dataverse.

**Approach:** Correct the Dataverse view or model-driven app curation that controls selectable Receipt views, deploy the correction to `sdhdev`, and prove the actual rendered screen honors the requested curated Receipt view before continuing through the seeded record forms.

## Boundaries & Constraints

**Always:** Preserve Council semantic contracts and receipt records; treat the rendered model-driven app as the acceptance surface; keep Source Record, Work Item, Receipt, Brief, graph, and audit concepts distinct; make tenant writes idempotent and solution-aware; retain screenshots, trace, browser diagnostics, and machine-readable results for every live gate run.

**Block If:** The correction would require replacing `Recent Receipts` with `Active Council Receipts` as the accepted product behavior, deleting tenant data, changing the canonical Council object model, or deploying outside the configured `sdhdev` environment.

**Never:** Make the screen test pass by weakening expected view-name markers, accepting the default view fallback, using fixed sleeps, bypassing the model-driven app, or treating metadata/API success as proof of screen success.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|---------------|----------------------------|----------------|
| Curated Receipt view | Council Queue URL names `com_councilreceipt` and the `Recent Receipts` system-view ID | Screen title/body identify `Recent Receipts` and show seeded receipt rows | Fail with target/final URL, title, screenshot, trace, and missing markers |
| Default-view fallback | Platform replaces the requested view with `Active Council Receipts` | Gate remains red | Report requested and rendered view IDs/names; do not continue as green |
| Other curated Receipt view | Another active curated Receipt view ID is requested | The matching named view renders, proving table-level curation works | Distinguish a single-view metadata defect from table/app curation failure |
| Record form continuation | Receipt view passes and seeded IDs exist | Source Record, Work Item, Receipt, and Brief forms render their expected record markers | Fail at the first user-visible form defect with complete evidence |

</intent-contract>

## Code Map

- `_bmad-output/implementation-artifacts/dataverse-apply-app-curation.ps1` -- creates curated system views, adds them to Council Queue, publishes, validates, and records evidence.
- `_bmad-output/implementation-artifacts/council-model-driven-screen-test.ps1` -- resolves live app/view/record IDs and defines screen-level journeys.
- `_bmad-output/test-artifacts/model-driven-screen/council-model-driven-screen-test.js` -- drives the actual Power Apps browser and captures red/green evidence.
- `_bmad-output/implementation-artifacts/dataverse-mvp-schema-manifest.json` -- declares Receipt view names and the target tenant/app.
- `_bmad-output/implementation-artifacts/app-curation-evidence.json` -- current deployed component and curated-view evidence.
- `_bmad-output/planning-artifacts/model-driven-screen-red-green-test-plan-2026-07-11.md` -- quality contract and latest live red result.

## Tasks & Acceptance

**Execution:**
- `_bmad-output/implementation-artifacts/dataverse-apply-app-curation.ps1` -- diagnose and correct the idempotent Receipt view/app curation path, including post-publish verification that intended curated views are live app components -- prevent silent metadata-only success.
- `_bmad-output/implementation-artifacts/council-model-driven-screen-test.ps1` -- exercise at least two curated Receipt view IDs before forms and retain strict view-name checks -- expose table-wide versus single-view routing defects.
- `_bmad-output/test-artifacts/model-driven-screen/council-model-driven-screen-test.js` -- preserve or improve requested-versus-rendered diagnostics without weakening observable readiness -- make any future fallback immediately actionable.
- `_bmad-output/planning-artifacts/model-driven-screen-red-green-test-plan-2026-07-11.md` and generated evidence -- record the final live result and any next visible defect -- keep BMAD status aligned with tenant reality.

**Acceptance Criteria:**
- Given the published Council Queue app and active curated Receipt views, when the screen gate opens each requested Receipt view by its system-view ID, then the rendered screen displays the matching view name and expected seeded rows without falling back to `Active Council Receipts`.
- Given the curated views are green, when the full screen suite continues, then seeded Source Record, Work Item, Receipt, and Brief forms render their expected record markers or the suite records a new precise red failure with full browser evidence.
- Given the implementation is rerun, when app curation executes again, then it does not create duplicate views or app components and validation still succeeds.
- Given local and live validation complete, when the MVP screen evidence gate is evaluated, then it passes only against a successful current run produced by the strict browser journey.

## Spec Change Log

## Review Triage Log

## Design Notes

The likely fault boundary is narrower than saved-view creation: live metadata confirms `Recent Receipts` is active and structurally valid, while the browser normalizes its route to the table default. Compare a passing Source/Work Item view with at least two Receipt views and verify both the app component set and runtime route. Repair the first tenant metadata boundary that explains the difference; do not hard-code a browser workaround.

## Verification

**Commands:**
- `powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\dataverse-apply-app-curation.ps1 -ExecuteWrites` -- expected: idempotent publish and successful app validation in `sdhdev`.
- `powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-model-driven-screen-test.ps1` -- expected: all curated views and seeded forms pass with a new successful evidence run.
- `powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-mvp-local-validate.ps1 -RequireScreenEvidence` -- expected: `COUNCIL_MVP_LOCAL_VALIDATE_OK` backed by current screen evidence.
- `git diff --check` -- expected: no whitespace errors.

## Auto Run Result

Status: done

The live Council Queue now honors both `Recent Receipts` and `Failed Receipts` system-view IDs instead of falling back to `Active Council Receipts`. App curation is convergent across repeat deployment, verifies all intended published components, and records strict requested-versus-rendered browser diagnostics.

Verification completed:

- Repeat `dataverse-apply-app-curation.ps1 -ExecuteWrites`: all 18 curated views current, 30 views pinned, 12 forms pinned, and zero `ValidateApp` issues.
- Live screen run `2026-07-12T02-37-29-450Z`: all curated list views passed, including both Receipt views.
- `council-mvp-local-validate.ps1`: passed with `COUNCIL_MVP_LOCAL_VALIDATE_OK`.
- JavaScript syntax and Git whitespace checks: passed.

Residual risk: the strict live journey is RED at the next independent defect. The Source Record form opens the correct seeded record but does not display `manual-demo-source-001`; form curation must be corrected before subsequent Work Item, Receipt, and Brief forms can be proven.
