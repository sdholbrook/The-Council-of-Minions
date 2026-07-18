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
<!-- ringer-origin: human -->                        # story authorship: human|factory (FR-8)
<!-- ringer-coupon: true -->                         # planted fault injection (FR-14)
```

Adding a `ringer-check` per story is the single highest-value habit — it makes
"done" executable. Without it the bridge falls back to `--check-command`.

`ringer-origin` records Story authorship on every Catch the Gates emit
(`meridian:origin`). Absent marker = the emitter's default (`factory`) — the
producer owns the default; the Bridge and Gate never duplicate it. An invalid
value refuses the whole dispatch (exit 2, naming the story): FR-8 is a closed
vocabulary. `ringer-coupon: true` marks the Story as planted fault injection:
every Catch for the key carries `meridian:coupon: true`, so recognition,
apply-refusal, and gate-liveness all key on a typed field the Bridge alone can
assert (the Bridge is the only component that knows what it planted).

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

## Story-review watcher (verdicts.jsonl receipts)

`story_review_watcher.py` is the productized form of the Shape-A event loop: it
tails a bmad-loop run journal and, on each `story-done` event, builds review
materials + a multi-lens ringer manifest, dispatches the swarm, then harvests
each lens's `report.md` into a **structured receipt** appended to
`<run-dir>/verdicts.jsonl`. Other journal events (`run-paused`,
`story-deferred`, `escalation`) become receipts too. It is stdlib-only
(Python 3.11+), append-only, and crash-safe — a failure on one story writes a
`review-skip` receipt and never kills the `--follow` loop.

`checks/review_check.py` is the per-lens report validator (substance +
anchoring): a report must exist, name its model, end with a `VERDICT:` line,
have ≥ `--min-findings` finding-shaped entries, and anchor to at least one real
materials file.

### Receipt schema

One JSON object per line, appended to `<run-dir>/verdicts.jsonl`. Common
fields: `ts` (UTC ISO-8601), `kind`, `run_dir`, and `story_key` (when known).

| kind             | extra fields                                                                                  |
|------------------|-----------------------------------------------------------------------------------------------|
| `review-dispatch`| `sha`, `manifest`, `lenses` (list), `dry_run` (bool)                                          |
| `review-verdict` | `lens`, `model`, `verdict` (`APPROVE`\|`FINDINGS`\|`NO-REPORT`), `findings_count` (int; `-1` for `NO-REPORT`, `0` for `APPROVE`), `report_path`, `sha` |
| `review-skip`    | `reason` (`no-commit` / `build-failed` / `ringer-failed` / `ringer-error` / `handler-exception` / `no-story-key`), plus `detail`/`exit`/`sha` where relevant |
| `run-paused`     | `pause_class` (`usage-limit` / `epic-boundary` / `crash` / `escalation`), `reason` (raw text) |
| `story-deferred` | `source_kind` (original journal kind), plus all raw fields passed through                     |

### Daemon invocation

```bash
python3 tools/ringer-bridge/story_review_watcher.py \
  --repo /srv/bmad/projects/SynSci-Atlas \
  --follow
```

Useful flags: `--replay` (process the journal's existing lines once, then exit
— for tests/backfill), `--dry-run` (build materials+manifest and write
dispatch receipts without invoking ringer), `--harvest STORY_KEY` (re-parse
existing per-lens reports into verdict receipts), `--lenses NAME=SLUG,...`,
`--contracts PATH`, `--check PATH`, `--identity NAME`, `--ringer PATH`,
`--run-dir PATH`, `--base PATH`.

> **Meridian Compass** reads `<run-dir>/verdicts.jsonl` to populate the
> fleet economics panel — each `review-verdict` line is one lens verdict the
> panel rolls up into per-story, per-lens, and per-model cost/quality curves.

