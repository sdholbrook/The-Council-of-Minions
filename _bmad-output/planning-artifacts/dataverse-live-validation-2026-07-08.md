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
- Created and published model-driven app shell `Council Queue`.
- Seeded Source Record row `manual-sample-20260708-095226`.
- Seeded proposed Work Item row `work-sample-20260708-095227`.
- Earlier failed seed retry left an additional sample Source Record row `manual-sample-20260708-095121` with no paired Work Item.

Known remaining UI gap:

- The `Council Queue` app shell exists and is published, but table navigation/pages still need to be configured in the model-driven app designer or with a later reviewed app-component/sitemap implementation.
