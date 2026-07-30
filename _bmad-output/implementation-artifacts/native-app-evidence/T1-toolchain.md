# T1 evidence — code-first toolchain pinned and verified (story 6-1)

Executed 2026-07-30 (~18:20Z) on the home machine (Doug present, return day),
per ADR-0010: container sessions stop above T1; this ran below the line.

## Environment verify (AC1 prerequisites)

```
$ node -v
v22.23.1        # Node 22 LTS ✓
$ npm -v
10.9.8          # npm 10+ ✓
$ pac
Microsoft PowerPlatform CLI Version: 2.9.3+ga17df1d (.NET 10.0.10)
```

## Marketplace + plugin install state (AC1)

Marketplace and plugins were already installed at user scope (install predates
this gate); T1 verifies and pins the live state rather than re-installing.

```
$ claude plugin marketplace list   # via known_marketplaces.json
power-platform-skills  source=github:microsoft/power-platform-skills
  installLocation=~/.claude/plugins/marketplaces/power-platform-skills
  lastUpdated=2026-07-30T18:11:10Z  autoUpdate=true   ⚠ see PINS.md remedy

$ git -C ~/.claude/plugins/marketplaces/power-platform-skills log -1
c8455acac65f7a3cbdeeeb0fa973032695df74a7  2026-07-30
"docs: correct stale 'Stop hook' wording for skill validators (#334)"

$ claude plugin list        (power-platform-skills plugins, all enabled, user scope)
mobile-app          0.2.0   ← story-named
code-apps-preview   1.1.0   ← story-named
canvas-apps         2.2.2
mcp-apps            1.0.0
model-apps          2.3.0
power-automate      2.3.1
power-pages         2.6.3
```

Live-session proof: the `mobile-app:*` and `code-apps-preview:*` skills load and
respond in the working session (the mobile-app write-safety hook fired during this
very story — the plugin is demonstrably active, not just listed).

## Package universe verify (AC2 inputs)

```
$ npm view @microsoft/power-apps-native-host version   → 0.2.25
$ npm view @microsoft/power-apps-native-auth version   → 0.3.5
$ npm view @microsoft/power-apps-native-common version → 0.1.8
$ npm view @microsoft/power-apps version               → 1.2.7
$ npm view @microsoft/power-apps-native-host@0.2.25 peerDependencies
  expo-constants/linking/web-browser  >=55* <56   → Expo SDK 55 (expo 55.0.28)
  react-native                        >=0.83.4 <0.84 → 0.83.10
  react                               >=19.2.0 <20   → 19.2.8
```

PRD NA-NFR2 §6's verified universe (2026-07-28) re-confirmed against live npm
2026-07-30: unchanged. npm-latest Expo 57.0.9 / RN 0.86.2 rejected — outside
native-host 0.2.25 peer ranges (recorded in PINS.md).

## VERIFY IN TENANT ledger (PRD §7 copy — T1 flip)

| # | Gate | Evidence required | Status |
|---|---|---|---|
| T1 | Plugin marketplace + both plugins install in the working environment | install transcript committed | **GREEN 2026-07-30** (this file) |
| T2 | Wrap/Entra auto-registration permitted by tenant policy | registration record + app id | open (story 6-2+) |
| T3 | Developer app signed in on Doug's iPhone, correct environment | screenshot/receipt | open |
| T4 | Scaffold reads existing tables with Doug's context | first-read receipt | open |
| T5 | Approve/decline write path produces a valid `com_councilreceipt` | receipt row id | open |

Pins recorded in `apps/council-mobile/PINS.md` (AC2, AC3). Gate T1: **GREEN**.
