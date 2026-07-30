# Service-selection evidence record — operator surface (code-first tracks)

**Story:** 5-3 record-microsoft-platform-evaluation-evidence (epic 5) — this file is
EVIDENCE toward that story, produced ahead of its story file (5-3 remains `backlog` in
sprint-status until `create-story` runs; nothing here flips a status).
**Requirements exercised:** FR26, FR27, FR28, NFR2.
**Capability under evaluation:** the operator surface — the UI where Doug triages
source records, approves/declines proposed work items, and reads the Minion Brief
(FR26 objects: messages, tasks, approvals, decisions, briefs).
**Date / author:** 2026-07-28 · Claude (Meridian away-week session, D-2026-07-28-15) —
staged via SynSci-Meridian because container sessions hold read-only access to this repo.
**Primary-source base:** SynSci-Meridian `plans/week-2026-07-21/briefs/pp-native-stack-research.md`
(npm registry, microsoft/power-platform-skills repo, licensing docs — all claims
re-verified against primary sources on 2026-07-28, none taken from social posts).

## Candidates evaluated (FR27/NFR2: Microsoft-native before custom)

| # | Candidate | Verdict | Core facts (verified 2026-07-28) |
|---|---|---|---|
| 1 | Keep model-driven app as sole surface | RETAIN as admin/fallback only | Accepted MVP evidence exists (screen-gate, curation, ALM export); weak phone UX for the daily loop |
| 2 | **Power Apps mobile-native (code-first)** | **RECOMMEND — Track M** | `@microsoft/power-apps-native-host` 0.2.25 (pub 07-24), `-auth` 0.3.5, `-common` 0.1.8, `-offline` 0.1.26; Expo 55/RN 0.83/React 19.2 peers; Tamagui + TanStack baked in; scaffold via power-platform-skills mobile-apps plugin (`/create-mobile-app`); preview via Power Apps Developer iOS app (id 6753083462) |
| 3 | **Power Apps Code Apps (desktop web)** | **RECOMMEND — Track C** | `@microsoft/power-apps` SDK 1.2.7 + CLI 0.13.0 (`npx power-apps push`); most mature piece of the stack; code-apps plugin in same marketplace |
| 4 | Canvas app | REJECT | Designer-state authoring, no native mobile story, off Microsoft's visible pro-code direction |
| 5 | Custom React Native straight at Dataverse Web API | REJECT | Custom substrate where a Microsoft-native track exists — exactly what FR27/NFR2 forbid; auth/hosting/lifecycle hand-rolled |
| 6 | Power Pages / Copilot Studio surfaces | OUT OF SCOPE here | Different capability planes (external portal / conversational); not the operator loop |

## FR28 record fields

- **Tenant gates (all `VERIFY IN TENANT` per FR29/story 5-4 before build):**
  1. power-platform-skills marketplace + mobile-apps/code-apps plugins install cleanly
     in the working environment (Claude Code plugin marketplace, MIT).
  2. `/create-mobile-app`'s **Wrap-generated Entra app registration** succeeds under
     tenant policy — README claims no manual redirect URIs/API permissions and no
     tenant-wide admin consent; verify, don't trust.
  3. Power Apps Developer app signed in on Doug's iPhone against the right environment.
  4. Dataverse environment + existing MVP tables reachable from the scaffolded app with
     Doug's user context (reuse story 5-5 preflight pattern: `pac auth who`, `pac env who`).
  5. Doug reports the stack already deployed to his tenant — treat as unverified until
     the above rows produce evidence.
- **Permission / DLP impact:** one new Entra app registration per created app (Wrap
  flow) — inventory them; Dataverse permissions unchanged (same tables, same user);
  connector DLP surface unchanged in MVP (no new connectors); MCP servers in the plugins
  run locally in the dev toolchain, not in the tenant.
- **Licensing / cost:** end users need Power Apps **Premium, pay-as-you-go, or an app
  pass**; per-app SKU retired for new purchase Jan 2026. Single-operator dev tenant →
  no incremental cost now; named cost line if a second user ever appears.
- **Lifecycle / ALM path:** deployment is `npx power-apps push` (environment-targeted);
  Solutions are beginning to accept Mobile App assets platform-side, but the plugin flow
  has **no solution-aware packaging yet** → ALM GAP recorded; existing ALM export
  evidence for the model-driven app is unaffected.
- **Contract gaps:** mobile-native is **Private Preview** ("do not use this in
  production"); iOS-only preview runtime (Android "coming soon"); offline runtime
  deferred (packages exist, flows don't drive them); tight Expo/RN pins churn with each
  release (0.2.25 published 4 days before this record).
- **Decision:** adopt the **two-track exploration** (M then C) as PROPOSED epic-6, with
  the model-driven app retained as admin/fallback; zero schema drift; build gated on
  (a) Doug's approval of the staged plan, (b) tenant-gate rows above turning green.
  Custom-substrate alternatives rejected per FR27/NFR2.
- **Review reference:** Meridian D-2026-07-28-15 (Doug's directive) · gauntlet run
  `_bmad-output/planning-artifacts/gauntlet/council-native-app/` (stages 0–2 + PRFAQ
  skip receipt) · epic-6 proposal staged alongside · Doug's plan review = the pending
  approval that unblocks stage 4+.
