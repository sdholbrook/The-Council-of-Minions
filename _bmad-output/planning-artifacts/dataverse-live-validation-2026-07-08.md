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
- `ValidateApp` returned success; remaining warnings only state that specific forms/views are not pinned, so app users see all forms/views for each Council table.
- Seeded Source Record row `manual-sample-20260708-095226`.
- Seeded proposed Work Item row `work-sample-20260708-095227`.
- Earlier failed seed retry left an additional sample Source Record row `manual-sample-20260708-095121` with no paired Work Item.
- Ensured deterministic demo Source Record `manual-demo-source-001`.
- Ensured deterministic demo proposed Work Item `CWI-DEMO-001`.
- Ensured deterministic proposal Receipt `CR-DEMO-PROPOSED-001`.
- Ensured Work Item Source and Receipt Source provenance links for the deterministic demo.
- Ensured graph provenance rows `GE-DEMO-SOURCE-001`, `GE-DEMO-WORK-001`, and edge `CWI-DEMO-001 proposed from manual-demo-source-001`.
- Ensured Minion Brief projection `BRIEF-DEMO-001`.

Known remaining UI gap:

- Specific Council forms/views and sitemap group labels still need to be curated for the desired Intake, Work, Brief, Knowledge, and Governance grouping. The app is valid and table-backed, but not yet ergonomically tuned.
