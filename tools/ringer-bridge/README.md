# Hybrid bridge: BMAD Loop × Ringer

Three ways to turn aligned work into merged code are now set up on this project.
This directory holds the glue for the **hybrid** one and documents how to run a
fair A/B/C comparison across all three.

## The three options

| # | Option | Alignment | Dev | Verify | Cost profile |
|---|--------|-----------|-----|--------|--------------|
| 1 | **BMAD Loop** | BMAD (PRD→arch→epics→stories→sprint) | `bmad-dev-auto`, serial, per-epic gates | self-review + frontier review, escalation to human | frontier tokens per story |
| 2 | **Hybrid** | BMAD (same as #1) | Ringer swarm of cheap OpenCode/OpenRouter workers, **parallel** | executed check per story → **verified patch**; frontier review merges | cheap workers (~$0.01/task) + frontier only for spec+review |
| 3 | **Ringer** | none — you/Claude write the specs directly | Ringer swarm, parallel | executed check per task | cheapest; no BMAD spine |

Key idea of the hybrid: **BMAD owns the layer Ringer lacks** (alignment), and
**Ringer owns the layer BMAD does serially** (cheap parallel implementation).
The swarm never commits to your branch — each worker produces a *verified patch*
that frontier review applies/merges.

## How the bridge works

`bmad_to_ringer.py` reads `sprint-status.yaml`, selects the `ready-for-dev`
stories you name (independence is **your** call — worktrees isolate the
filesystem, not the logic), and emits a Ringer `swarm.json` where each task:

- runs in an **isolated git worktree** (`worktrees: true`) so parallel workers
  never collide;
- carries the **full story spec** as the worker prompt, with BMAD guardrails
  (edit in place, leave uncommitted, stay in scope);
- is verified by `checks/check_bmad_story.py`, which **executes the acceptance
  check**, enforces the ownership boundary, and **exports a patch OUT of the
  worktree** before the worktree is deleted on PASS.

### Per-story overrides (optional HTML comments in the story `.md`)

```
<!-- ringer-check: pytest tests/test_cfg.py -q -->   # exit 0 = PASS (overrides --check-command)
<!-- ringer-owned: src/cfg.py;tests/test_cfg.py -->  # paths this worker may touch
<!-- ringer-expect: notes.md;src/cfg.py -->          # files that must exist post-run
```

Adding a `ringer-check` per story is the single highest-value habit — it makes
"done" executable. Without it the bridge falls back to `--check-command`.

### Usage

```bash
python3 tools/ringer-bridge/bmad_to_ringer.py \
  --sprint-status _bmad-output/implementation-artifacts/sprint-status.yaml \
  --story-dir     _bmad-output/implementation-artifacts/stories \
  --repo          . \
  --check-command "pytest -q" \
  --stories 1-2,1-3 \
  --out swarm.json

python3 ./ringer/ringer.py lint swarm.json   # fix what it flags
python3 ./ringer/ringer.py run  swarm.json   # watch in Ringside
# verified patches land in ~/.ringer/work/bmad-hybrid/patches/<key>.patch
git apply ~/.ringer/work/bmad-hybrid/patches/1-2-config-loader.patch  # after review
```

## This machine's constraints (Linux)

- **Codex-as-Ringer-worker is blocked here.** Codex's `workspace-write` sandbox
  uses bubblewrap, which can't set up its network namespace in this environment
  (`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`). The verified
  demo proved Ringer's *verification* works, but codex workers can't write. Use
  **OpenCode/OpenRouter** as the worker lane. (bmad-loop is unaffected — it runs
  on claude, no bwrap.)
- **No OS sandbox for OpenCode on Linux.** The sandbox wrapper is macOS-only, so
  `~/.config/ringer/config.toml` points at the opencode binary directly. We
  omitted `full_access_args` and keep `allow_full_access = false`, so no task can
  get `--no-sandbox`; **always run with `worktrees: true`** (the bridge does) and
  keep owned-path boundaries tight.

## Fair A/B/C comparison protocol

Pick ONE epic whose `ready-for-dev` stories are genuinely independent, then run
the SAME stories three ways and compare receipts, not vibes:

1. **BMAD Loop (#1):** `bmad-loop run` — let it dev+review the stories serially.
2. **Hybrid (#2):** `bmad_to_ringer.py` → `ringer.py run` → review the exported
   patches → merge.
3. **Ringer (#3):** hand Claude the same stories, have it write a `swarm.json`
   from scratch (no BMAD spine) → `ringer.py run`.

Measure, per option:

- **Correctness:** first-try pass rate (`ringer.py models` for #2/#3), and how
  many stories needed frontier rework afterwards.
- **Cost:** frontier tokens spent vs. cheap-worker $ (Ringside/eval log for #2/#3).
- **Wall-clock:** serial (#1) vs. parallel (#2/#3).
- **Alignment quality:** did the output match the story's intent, or did the
  cheap workers drift where BMAD's spec was thin?

The honest expectation going in: **#2/#3 win on cost and wall-clock for
mechanical, independently-checkable stories; #1 wins on anything needing the
spine, tight coupling, or human escalation.** The comparison tells you *where*
your real backlog falls on that line — which is the actual decision.
