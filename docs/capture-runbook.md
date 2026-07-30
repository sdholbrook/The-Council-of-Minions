# Live-screenshot capture runbook

The images in `docs/screenshots/` are **rendered from this repo's solution metadata**
(real sitemap, real views, real columns, the repo's own sample records) by
`tools/docs-render/render_screens.py`. They are structurally faithful but they are not
the live tenant. To replace any of them with a live capture, keep the **same filename**
— the guide references never change.

## Capture steps (per image, ~30 s each)

1. Open **Council Queue** in a desktop browser, window about **1440×900** (the render
   size — keeps the guide visually consistent).
2. Navigate per the table below and wait for the grid to load.
3. Capture the browser viewport (Windows: `Win+Shift+S` → window snip; or F12 →
   `Ctrl+Shift+P` → "Capture screenshot").
4. Save over the matching file in `docs/screenshots/`, commit.

| File | Navigate to | View selector |
|---|---|---|
| `grid-source-records-new.png` | Intake → Council Source Records | New Source Records |
| `grid-source-records-held.png` | Intake → Council Source Records | Held Source Records |
| `grid-work-items.png` | Work → Council Work Items | Proposed Work Items |
| `grid-work-items-approval.png` | Work → Council Work Items | Needs Human Approval |
| `grid-receipts.png` | Work → Council Receipts | Recent Receipts |
| `grid-briefs.png` | Brief → Council Briefs | Active Council Briefs |

Live captures have no yellow provenance strip — that's the tell for which images have
been replaced. Re-running the renderer regenerates only metadata renders; it will
happily overwrite live captures, so re-run it only if you want to reset to renders.

## Regenerating renders

```bash
python3 tools/docs-render/render_screens.py --repo . --out docs/screenshots
```

Requires any Chromium (`DOCS_RENDER_CHROMIUM` env var, PATH, or the Playwright pod
default). Stdlib Python otherwise.
