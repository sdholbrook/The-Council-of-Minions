# Model-Driven App Screen Testing

## Purpose

The Dataverse schema/app metadata checks are not enough for MVP acceptance. The Council Queue must be proven through the same surface Doug uses: a rendered model-driven app screen.

This gate drives red/green development for the live Microsoft app:

1. Open the actual `Council Queue` app in `sdhdev`.
2. Capture screenshots and a Playwright trace.
3. Fail on visible model-driven app errors, permission errors, invalid app/module errors, script errors, or missing expected demo records.
4. Prove the deterministic demo slice is visible through the app: Source Record, proposed Work Item, proposal Receipt, receipt-backed state transitions, and Minion Brief.

The first strict screen run reproduced Dynamics error `0x80050016`: the user had no valid navigable app surface because the generated sitemap had an Area but no Groups/SubAreas. The green condition now requires manifest-driven sitemap groups plus visible seeded row markers, including state-transition Work Item titles and terminal Receipt IDs.

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-model-driven-screen-test.ps1
```

If browser auth is not already available in the test profile, use an interactive headed run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File _bmad-output\implementation-artifacts\council-model-driven-screen-test.ps1 -InteractiveLogin -Headed
```

The test stores authenticated browser state under `_bmad-output/test-artifacts/model-driven-screen/.auth/`, which must not be committed.

## Artifacts

Each run writes to `_bmad-output/test-artifacts/model-driven-screen/runs/<timestamp>/`:

- `REPORT.md`
- `result.json`
- `trace.zip`
- `*.png` screenshots
- `console.json`
- `page-errors.json`
- `network-errors.json`

Use the trace to inspect what the app actually rendered:

```powershell
$env:NODE_PATH='C:\Users\DougHolbrook\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\node_modules'
C:\Users\DougHolbrook\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe -e "const { chromium } = require('playwright'); console.log('Use Playwright trace viewer from a full Playwright install if needed.')"
```

## Quality Bar

Do not mark the MVP screen surface complete from `ValidateApp` alone. `ValidateApp` proves app metadata validity; this screen gate proves the user-visible app path.

The current gate is intentionally text-marker based because Power Apps model-driven app DOM selectors are platform-owned and brittle. Missing business markers fail the run even if navigation succeeds.

Current curation evidence: `app-curation-evidence.json` proves the app now pins 12 main forms, 30 views, and 18 manifest-curated views, with `ValidateApp` returning zero issues. Final MVP acceptance still requires the screen gate and tenant evidence to stay current after any further app changes.
