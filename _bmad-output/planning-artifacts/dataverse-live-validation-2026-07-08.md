# Dataverse Live Validation - 2026-07-08

Target proven by `pac env who`:

- Environment URL: `https://sdhdev.crm.dynamics.com/`
- Environment ID: `ba9a96b2-f562-40f6-931d-6b55873954ee`
- Organization ID: `0c0fa4db-8614-ef11-9f83-000d3a342d36`
- Unique name: `unq0c0fa4db8614ef119f83000d3a342`

Live writes completed:

- Created publisher `CouncilOfMinions` with prefix `com`.
- Created unmanaged solution `CouncilOfMinionsMVP`.
- Created 15 Council global choices.
- Created 14 Council custom Dataverse tables from the MVP manifest.
- Created non-lookup columns and lookup relationships across the manifest.
- Published Dataverse customizations.
- Created and published model-driven app `Council Queue`.
- Added 12 Council table components to `Council Queue`.
- Replaced the generated empty app sitemap with manifest-driven Intake, Work, Brief, Knowledge, and Governance groups.
- `ValidateApp` initially returned success with warnings that specific forms/views were not pinned.
- Seeded Source Record row `manual-sample-20260708-095226`.
- Seeded proposed Work Item row `work-sample-20260708-095227`.
- Earlier failed seed retry left an additional sample Source Record row `manual-sample-20260708-095121` with no paired Work Item.
- Ensured deterministic demo Source Record `manual-demo-source-001`.
- Ensured deterministic demo proposed Work Item `CWI-DEMO-001`.
- Ensured deterministic proposal Receipt `CR-DEMO-PROPOSED-001`.
- Ensured Work Item Source and Receipt Source provenance links for the deterministic demo.
- Ensured graph provenance rows `GE-DEMO-SOURCE-001`, `GE-DEMO-WORK-001`, and edge `CWI-DEMO-001 proposed from manual-demo-source-001`.
- Ensured Minion Brief projection `BRIEF-DEMO-001`.
- Ensured six deterministic state-transition demo Work Items: `CWI-DEMO-STATE-APPROVED`, `CWI-DEMO-STATE-HELD`, `CWI-DEMO-STATE-BLOCKED`, `CWI-DEMO-STATE-INREVIEW`, `CWI-DEMO-STATE-COMPLETED`, and `CWI-DEMO-STATE-FAILED`.
- Ensured 12 deterministic proposal/transition Receipts for the state-transition demo, with final states `approved`, `held`, `blocked`, `in_review`, `completed`, and `failed`.
- Recorded `_bmad-output/implementation-artifacts/state-transition-demo-evidence.json` with the environment URL, Work Item count, Receipt count, final state groups, deterministic IDs, and `noOutboundAction`.
- Added BMAD TEA screen gate `council-model-driven-screen-test.ps1` and Playwright runner. Initial browser run failed with Dynamics error `0x80050016` because the app sitemap had no navigable groups/subareas. After the sitemap fix, screen runs `2026-07-08T23-22-40-976Z`, `2026-07-09T15-29-54-028Z`, `2026-07-09T15-37-21-204Z`, and `2026-07-09T15-43-41-825Z` passed against the rendered app with screenshots/trace and visible seeded rows for Source Records, Work Items, Receipts, Briefs, and the receipt-backed state-transition demo.
- Exported unmanaged solution `CouncilOfMinionsMVP` from `sdhdev` and unpacked it to `_bmad-output/implementation-artifacts/alm/unpacked/CouncilOfMinionsMVP`.
- Recorded `_bmad-output/implementation-artifacts/alm/export-evidence.json` with 198 unpacked source files, solution XML, customizations XML, app module, and app sitemap evidence.
- Added local validation coverage for the unpacked ALM source, including 14 Council entity folders, 15 Council option set files, and manifest sitemap groups/subareas.
- Applied model-driven app form/view curation with `_bmad-output/implementation-artifacts/dataverse-apply-app-curation.ps1 -ExecuteWrites`.
- Created and pinned 18 manifest-curated system views across Source Records, Work Items, and Receipts.
- Pinned one main form and one baseline system view for each of the 12 `Council Queue` app tables.
- Recorded `_bmad-output/implementation-artifacts/app-curation-evidence.json` with `pinnedFormCount=12`, `pinnedViewCount=30`, `curatedViewCount=18`, `validateAppSuccess=true`, and `formViewWarningsRemaining=0`.
- Re-exported unmanaged solution `CouncilOfMinionsMVP`; refreshed ALM evidence now records 216 unpacked source files, including curated SavedQuery XML files and AppModule form/view components.
- Re-ran strict browser evidence after curation. Screen run `2026-07-09T15-59-14-759Z` passed against the rendered app after form/view pinning and refreshed ALM export.

Known remaining live gap:

- No scoped Dataverse/model-driven app gap remains from current evidence. Live Outlook/Graph reads and broader tenant governance checks remain separate gates.
