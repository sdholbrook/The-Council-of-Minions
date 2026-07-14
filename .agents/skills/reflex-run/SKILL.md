---
name: reflex-run
description: >-
  Launches and supervises a Reflex run (bmad-loop orchestration, with the
  optional Ringer worker lane) on THIS project. TRIGGER whenever the user asks
  to "run the reflex", "start the loop", "resume the loop", "launch bmad-loop",
  "drive the sprint", when handling a paused run or an ATTENTION file, or when
  choosing between the native dev lane and the ringer swarm lane for ready
  stories. SKIP for: initial setup or policy work (reflex-setup), fleet
  monitoring (Meridian Compass on :8710 is read-only observation), and
  hand-driving a single story outside the loop.
version: 0.1.0
---

# Reflex run — launch, route, supervise

## 0. Standing authorization

Doug (2026-07-13, recorded in Meridian `OPERATIONS.md`): once a project's BMAD
planning is complete — sprint plan exists, `bmad-loop validate` green,
lessons-corrected policy, CLI trust dialogs cleared — launching the Reflex
requires **no further human approval**. Per-epic gates, the verify gate, and
ATTENTION escalation govern from there. Outward-facing or destructive actions
stay human-gated as always. If any precondition is missing, that is a
**reflex-setup** problem — route there, don't improvise.

## 1. Preflight (every launch, cheap)

1. `bmad-loop validate` — must be green (tolerated FAILs per reflex-setup §7).
2. Policy hygiene: `.bmad-loop/policy.toml` has `isolation="worktree"`, a real
   `[verify].commands`, cross-vendor dev/review routing. Fix via reflex-setup
   before running — never launch on a footgun policy.
3. Stories: `_bmad-output/implementation-artifacts/sprint-status.yaml` has
   actionable stories (`ready-for-dev`/`backlog`).
4. Capacity glance: check the Capacity panel on Meridian Compass
   (http://10.1.1.22:8710) or `~/.cache/meridian/capacity.json` — do not launch
   a long run into a nearly-exhausted account or a 402-dead metered key.

## 2. Launch / resume

- New run: `bmad-loop run` (from the repo root; it spawns tmux CLI sessions).
- Paused run (epic boundary, escalation): `bmad-loop resume <run_id>` — the
  run id and reason are in `.bmad-loop/runs/<id>/ATTENTION`.
- Useful: `bmad-loop status`, `bmad-loop list`, `bmad-loop tui`,
  `bmad-loop attach <run_id>`.

## 3. Lane choice — native dev vs ringer swarm

The loop's native lane types with the `[adapter.dev]` frontier model. The
**ringer worker lane** types with cheap verified workers and is preferred when
stories are mechanical, their file ownership is disjoint, and each carries a
real executable check (the Reflex-v2 economics: cheap workers type, frontier
specs and adjudicates):

```bash
python3 tools/ringer-bridge/bmad_to_ringer.py \
  --sprint-status _bmad-output/implementation-artifacts/sprint-status.yaml \
  --story-dir     _bmad-output/implementation-artifacts/stories \
  --repo . --check-command "<real test cmd>" --stories <keys> --out swarm.json
python3 ./ringer/ringer.py lint swarm.json     # always lint first
python3 ./ringer/ringer.py run  swarm.json --identity <who-you-are>
```

Load the `ringer` skill before any swarm work — it owns manifest craft, check
rules, engine selection (scoreboard-driven), and the worktree footguns. Stories
opt in via `<!-- ringer-check: ... -->` / `<!-- ringer-owned: ... -->` markers.

## 4. Supervise (observe from the right places)

- `bmad-loop tui` / `tmux attach` for the loop; Ringside (http://127.0.0.1:8700,
  LAN http://10.1.1.22:8700) for swarm workers.
- Meridian Compass (http://10.1.1.22:8710) shows the whole fleet — it is
  **observation only**; never try to drive a run from Meridian or its host
  session. Driving happens here, in this repo.

## 5. ATTENTION & pauses

A run that needs a human (or a decision) writes `.bmad-loop/runs/<id>/ATTENTION`
and pauses. Classify before acting:

- **epic-boundary** — the per-epic gate. Review the epic's results, then
  `bmad-loop resume <id>`.
- **escalation / deferred story** — use `bmad-loop-resolve <story-key>` for the
  interactive resolution workflow; `bmad-loop sweep` triages the deferred ledger.
- **usage-limit / capacity** — check the Compass capacity panel; resume when the
  lane has headroom (or re-route the lane), don't just retry into a dead key.
- **crash** — read `.bmad-loop/runs/<id>/state.json` (`crash_error`) and
  `journal.jsonl` tail before anything else; `bmad-loop diagnose <id>` helps.

## 6. After the run

- Confirm sprint-status story states advanced and the epic gate/retro entries
  are consistent (traceability is non-negotiable).
- Capture new lessons in Meridian `LESSONS.md`; encode inheritable fixes into
  the `bmad-loop-ringer` seed. Check the Compass board reflects the concluded
  run before walking away.
