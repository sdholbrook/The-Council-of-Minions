# Adversarial review receipt — council-native-app architecture

**Lens:** adversarial, in-session (sanctioned in-container receipt form; gauntlet
stage-5 gate). **Method:** attack the draft spine as the implementer who has to live
with it and the operator whose data it mutates; every finding either changed the
architecture or records why not. **Verdict: PASS after 7 resolutions** — the spine
below is the post-review version; findings reference the sections they reshaped.

| # | Sev | Finding (attack) | Resolution (in architecture) |
|---|---|---|---|
| A1 | HIGH | **Mutation-contract vacuum.** Story 6.3 writes state changes, but epic-2's stories (2-3, 2-4) that DEFINE the receipt contract are `backlog` — the native app could invent a second, divergent mutation culture. | §6: implement against the demo-proven contract (`state-transition-demo-evidence.json`: deterministic `CR-<id>-<STATE>` receipt IDs, 12-receipt proof); epic-2 reconciliation named as explicit acceptance; blocking-on-epic-2 considered and rejected with reason. I1 hardened to name the deterministic-ID basis. |
| A2 | HIGH | **Retry double-write.** Mobile networks retry; a naive POST-receipt + PATCH-state pair duplicates receipts or applies states twice. | I1 + §5: idempotency via upsert on deterministic natural keys for BOTH writes; retry of either step is safe. Inherits the demo's `idempotencyBasis` verbatim. |
| A3 | MED | **Crash between the two writes** leaves state-without-receipt (audit hole) or receipt-without-state. | §5: receipt-FIRST ordering makes the only orphan case a receipt naming an intended transition — detectable; reconciliation query added to 6.3 acceptance; `ExecuteTransaction` upgrade path noted with portable fallback. |
| A4 | MED | **View-parity drift.** Hardcoded column lists in the app rot the moment Doug edits a saved view in the tenant; guide and app then lie together. | §3 data-read row: view-driven rendering — SDK view metadata when available, else `view-columns.json` GENERATED from the ALM unpack (same parser as the docs renderer; single source). Hand-typed column lists banned. |
| A5 | MED | **Decline invents schema.** "Decline" has no obvious terminal state in the demo's state groups; a new `declined` choice value would silently violate the zero-schema-drift promise. | §5 (bold): decline maps to demo-proven `held` + decline rationale on the receipt; a real `declined` state is named as a schema change that exits epic-6. Trap defused explicitly. |
| A6 | MED | **Public-repo leakage.** Scaffold output may embed app ids, env URLs, or worse; this repo is PUBLIC. | New invariant I8: committable vs never-committable enumerated (env URL already public in existing evidence — precedent, not a new exposure); secret-bearing artifacts gitignored with existence recorded; apply kit gains a pre-commit scan step (carried to C-e). |
| A7 | LOW | **Toolchain MCP servers as unpinned moving parts** — the plugins themselves update; a scaffold today and a re-scaffold next month may disagree structurally. | I4 extended in spirit by §7/I6: plugin + marketplace versions recorded in PINS.md alongside packages; re-scaffolds are deliberate, receipt-backed events. Accepted residual: preview churn is the price of the exploration (NA-NFR1). |

**Cross-vendor sanity note:** the spine was also read against the Curiosity
axon-export-target stage-5 pattern (receipt-driven staging, pin discipline) — no
contradictions with fleet conventions found.

**Reviewer honesty:** this is a self-review under away-mode authority (D-8). Its
counterweights: every resolution is verifiable in the architecture text, the demo
evidence cited is real and in-repo, and stage 7's readiness check re-walks these
findings with fresh eyes before any story runs.
