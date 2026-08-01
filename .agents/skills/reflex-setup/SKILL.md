---
name: reflex-setup
description: >-
  Sets up "the Reflex" (bmad-loop + Ringer) on THIS project with the fleet's
  lessons-corrected defaults. TRIGGER whenever the user asks to "set up the
  reflex", "stand up the loop", "prepare this repo for bmad-loop", "install
  loop tooling", or before a first `bmad-loop run` in a repo that has no
  .bmad-loop/ directory or a pre-lessons policy.toml; also for upgrades
  ("re-seed", "refresh loop tooling"). SKIP for: driving or resuming a run
  (that is reflex-run), doing BMAD planning itself (PRD/architecture/epics
  skills), and the SynSci-Meridian control plane — Meridian observes the
  fleet and never gets the Reflex installed.
version: 0.2.0
---

# Reflex setup — stand up bmad-loop + Ringer on this project

**The Reflex** = the bmad-loop + Ringer execution harness: loop orchestration,
cross-vendor review, and a cheap-worker ringer lane. It is installed from the
`bmad-loop-ringer` seed repo (canonical clone: `/srv/bmad/projects/bmad-loop-ringer`).
The fleet control plane is `/srv/bmad/projects/SynSci-Meridian` — **read its
`LESSONS.md` before starting**: every default below exists because a project
taught it the hard way, and newer lessons supersede this file.

## 1. Prerequisites gate (hard — check before touching tooling)

The loop consumes BMAD planning artifacts. Verify, in order, under
`_bmad-output/`:

| Artifact | Where | If missing, produce it with |
|---|---|---|
| PRD | `planning-artifacts/prd*.md` or `prds/prd-*/` | `bmad-create-prd` (validate with `bmad-validate-prd`) |
| Architecture | `planning-artifacts/architecture*/` | `bmad-architecture` |
| Epics & stories | `planning-artifacts/epics*` | `bmad-create-epics-and-stories` |
| Sprint plan | `implementation-artifacts/sprint-status.yaml` | `bmad-sprint-planning` |

Missing PRD/architecture/epics → **HALT and route to BMAD planning first** (name
the producing skill to the user). Missing only the sprint plan → you may proceed
with setup, but say clearly that `reflex-run` will be blocked until
`bmad-sprint-planning` has produced `sprint-status.yaml`.

Additionally every story the loop will pick up needs a **real executable check**
(exercise behavior — a test command, never `--help` or `test -f`). Budget or
shrink the first story: the seed story is historically the expensive one.

## 2. Repo & branch decisions

- Standalone repo vs worktree of an existing repo — decide before init.
- Base the loop branch off the project's BMAD develop line (create
  `develop-bmad` off `develop` if absent). Feature branches → small PRs.

## 3. Install / upgrade the tooling

- Fresh project: from the seed, `./install.sh <this-repo> --cli claude --cli codex --cli copilot`
  (overlay-safe: it will not clobber an existing `_bmad/`).
- Then (or for upgrades): `bmad-loop init --cli claude --cli codex --cli copilot --force-skills`
  — registers hooks and lays down the loop skills for every harness. The
  `bmad-loop-setup` skill covers init details (fresh vs upgrade, version skew
  reconciliation for a committed `_bmad/`); delegate to it for that mechanics.

## 4. Meridian MCP — designation confers Compass access

Anything designated a project in Meridian gets the Meridian MCP server
(project mode) and with it the ability to work with Meridian Compass. Install
the `mcp.json` bundled beside this skill as **`.mcp.json` at the repo root**:

- No `.mcp.json` yet → copy it verbatim.
- `.mcp.json` already exists → merge the `meridian` entry into its
  `mcpServers` — **never clobber other declared servers**.

The declared command must be exactly
`python3 /srv/bmad/projects/SynSci-Meridian/scripts/meridian-mcp.py --mode project`
— project mode only (fleet/branch/handoff reads + idempotent `request_reflex`);
control mode is Meridian-owned and is never installed in a project scope
(ADR-0005). Commit the `.mcp.json`. Note: Claude Code lists `.mcp.json`
servers as pending until approved once in that repo.

## 5. policy.toml — the lessons, encoded (verify EVERY line)

`.bmad-loop/policy.toml` is machine-local. Confirm each value; these are the
fleet's paid-for defaults:

```toml
[scm]      isolation = "worktree"          # NEVER "none"
[verify]   commands  = ["<real test cmd>"]  # the project's actual suite
[gates]    mode      = "per-epic"
[review]   trigger   = "always"             # cheap-worker patches always reviewed
[limits]   cache_read_weight = 0.1          # confirm max_review_cycles, max_dev_attempts, max_tokens_per_story
[adapter.dev]    name = "claude"            # cross-vendor: dev and review on
[adapter.review] name = "codex"  model = "gpt-5.5"  # DIFFERENT companies; pin an account-supported review model
[adapter.triage] name = "copilot"
```

Routing economics (lesson `L-2026-07-14-payroll`): flat-rate lanes first while
headroom >20%, glm-class cheap-metered overflow, premium-metered never for bulk.

## 6. gitignore / untrack

- `.gitignore` gets: `*.bak`, `_bmad/config.user.yaml`, `.bmad-loop/runs`,
  `.bmad-loop/cache`, `.bmad-loop/policy.toml`.
- `git rm --cached .bmad-loop/policy.toml` if it was ever tracked; document the
  routing choices in the project's playbook instead.

## 7. One-time trust dialogs (spawned sessions cannot answer them)

Run `claude`, `codex`, and `copilot` once each interactively in the repo root;
accept trust/hooks/auth prompts for every CLI the policy routes to.

## 8. Validate

`bmad-loop validate` — resolve every FAIL except "no sprint plan yet" (if you
proceeded past the gate) and "dirty worktree" (explain it instead). Green
validate + lessons-corrected policy + cleared trust dialogs = ready.

## 9. Confirm & capture

Report what was installed/changed and the validate outcome. If this setup
taught anything new, append a dated entry to Meridian's `LESSONS.md`, and if
it is a default worth inheriting, encode it into the `bmad-loop-ringer` seed —
that feedback loop is the whole point. Then hand off to **reflex-run**.
