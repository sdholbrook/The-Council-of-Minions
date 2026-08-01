---
name: reflex-run
description: >-
  Hand off Reflex start, resume, stop, or sprint-driving requests from a target
  project to the Meridian fleet control plane while preserving all execution
  context and artifacts in that target repo. Trigger whenever the user asks to
  run/start/resume/stop the Reflex, launch bmad-loop, drive the sprint, choose
  native versus Ringer lanes, or handle a paused Reflex run. Use read-only
  Compass/status inspection locally, but never launch workers from the
  project-local session.
---

# Reflex run — hand off to Meridian

Meridian owns fleet orchestration; this repository owns execution context.
Never run `bmad-loop run`, `bmad-loop resume`, `bmad-loop stop`, or
`ringer.py run` from this project-local skill.

## Record the request

Resolve the current repo root and create an idempotent handoff:

```bash
python3 /srv/bmad/projects/SynSci-Meridian/scripts/reflex-handoff.py request \
  --project "$PWD" \
  --intent start \
  --requested-by "project-local reflex-run skill" \
  --note "<the user's request in one sentence>"
```

For resume or stop, use `--intent resume|stop --run-id <id>`. Read the run id
from `.bmad-loop/runs/` or Compass; never guess it.

After the command succeeds:

1. Report the request id and target repo.
2. Direct the user to Meridian Compass at http://10.1.1.22:8710.
3. Stop. Do not preflight, author a route plan, choose a lane, or launch a
   worker in this session. Meridian claims the request and performs those steps.
4. If the handoff command is missing or fails, report that failure and route the
   user to `/srv/bmad/projects/SynSci-Meridian`; do not fall back to a direct
   loop launch.

Repeated requests are safe: the handoff command returns the existing active
request for the same project, intent, and run id.

## What stays here

Meridian will prepare inside this repo and commit a route plan before Compass
enables launch. Story specs, `ringer-check`/`ringer-owned` markers, manifests,
worktrees, patches, tests, sprint updates, commits, and receipts all remain in
this target repository. Only fleet request/supervision state lives in Meridian.

## Read-only status

For status questions, inspect Compass or run `bmad-loop status`; do not mutate
the run. Ringside shows only Ringer worker activity, while Compass shows native
loops, Ringer swarms, and pending Meridian handoffs.
