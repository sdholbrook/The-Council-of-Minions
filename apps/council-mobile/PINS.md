# council-mobile — pinned toolchain (NA-NFR2; arch I4 + A7)

Verified in tenant 2026-07-30 (gate T1 — evidence:
`_bmad-output/implementation-artifacts/native-app-evidence/T1-toolchain.md`).

## The rule

Every version below is **exact**. No floating ranges — not in this file, not in
`package.json` once the scaffold exists (story 6-2's lockfile becomes the second
enforcement point). Any change to any pin is a **deliberate commit citing the
manifest diff** (what moved, why, and the compatibility evidence), never a silent
update. Preview churn is absorbed as planned rebases, not drift.

## Claude Code toolchain

| Component | Pin |
|---|---|
| Marketplace `microsoft/power-platform-skills` | commit `c8455acac65f7a3cbdeeeb0fa973032695df74a7` (2026-07-30) |
| Plugin `mobile-app` | 0.2.0 |
| Plugin `code-apps-preview` | 1.1.0 |

⚠ The marketplace is registered with `autoUpdate: true` in
`~/.claude/plugins/known_marketplaces.json` — that is silent drift of the skill
layer. Remedy (Doug's call, recorded at T1): flip it to `false` so marketplace
moves become deliberate `claude plugin marketplace update` runs committed against
this file.

## npm package universe (native-host 0.2.25-era; PRD NA-NFR2 §6)

| Package | Pin | Compatibility source |
|---|---|---|
| `@microsoft/power-apps-native-host` | 0.2.25 | anchor of the universe |
| `@microsoft/power-apps-native-auth` | 0.3.5 | native-host dep `^0.3.5` |
| `@microsoft/power-apps-native-common` | 0.1.8 | native-host dep `^0.1.8` |
| `@microsoft/power-apps` | 1.2.7 | peer `*`; current verified |
| Expo SDK | 55 (`expo` 55.0.28) | peers `expo-* >=55 <56` |
| React Native | 0.83.10 | peer `>=0.83.4 <0.84` |
| React | 19.2.8 | peer `>=19.2.0 <20` |

npm-latest Expo is 57.0.9 and RN 0.86.2 — **deliberately not used**: native-host
0.2.25's peer ranges cap at Expo <56 / RN <0.84. An Expo/RN bump happens only as
part of a native-host rebase whose new peer ranges admit it.

`@microsoft/*` scope only — unscoped npm lookalikes are squats.

## Environment floor (recorded, not pinned)

Node 22 LTS (v22.23.1 at T1) · npm 10+ (10.9.8 at T1) · pac CLI 2.9.3.
