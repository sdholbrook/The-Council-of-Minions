# Gauntlet intake — council-native-app (stage 0)

- **Idea:** Give the Council a code-first operator surface: a Power Apps **Code App**
  (desktop web) plus a **mobile-native app** (Expo/React Native on
  `@microsoft/power-apps-native-host`), built through Microsoft's
  `power-platform-skills` plugins, against the EXISTING Dataverse MVP schema.
- The model-driven app is not deleted — it becomes the admin/fallback surface; the
  code-first tracks own the daily triage/approve/brief loop (epics 1–3 flows).
- **Origin:** Doug, 2026-07-28 (Meridian D-2026-07-28-15): "instead of a model driven
  app it is worth exploring using code app and a mobile version."
- **Target repo:** The-Council-of-Minions · **target branch:** main (Doug-applied;
  container sessions are read-only here — artifacts staged via Meridian, see
  APPLY-RUNBOOK.md at the staging root).
- **PRFAQ:** opt-OUT — product intent is already carried by the Council PRD (FR26/FR27)
  and Doug's direct directive; a PRFAQ would restate them.
- **Evidence base:** SynSci-Meridian `plans/week-2026-07-21/briefs/pp-native-stack-research.md`
  (primary-source stack research, 2026-07-28) → distilled into the story 5-3 evidence
  record staged alongside this run.
- **Stop line:** gauntlet pauses after stage 2 (D-15: "build work only after Doug
  reviews the plan"). Stages 4+ resume only on his approval.
