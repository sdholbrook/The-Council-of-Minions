#!/usr/bin/env python3
"""
bmad_to_ringer.py — HYBRID BRIDGE: BMAD 'ready-for-dev' stories -> Ringer swarm.

Division of labour
------------------
  BMAD (bmm + bmad-loop) owns ALIGNMENT: PRD -> architecture -> epics -> stories
    -> sprint-status.yaml. That is the layer Ringer does not have.
  This bridge takes the INDEPENDENT stories marked 'ready-for-dev' and emits a
    Ringer swarm.json so a swarm of cheap OpenCode/OpenRouter workers implements
    them in parallel, each verified by an executed check that exports a patch.
  Frontier review (bmad-loop review / bmad code-review) still GATES the merge —
    the swarm produces verified patches, it does not commit to your branch.

Independence is YOUR call
-------------------------
Ringer worktrees isolate the filesystem; they do NOT make logically-coupled
stories safe to parallelize. Pass the keys you know are independent via
--stories, or use --all-ready and eyeball the manifest before running it.

Per-story overrides (optional HTML comments anywhere in the story .md)
---------------------------------------------------------------------
  <!-- ringer-check: <shell command, exit 0 = PASS> -->   overrides --check-command
  <!-- ringer-owned: path/one;path/two -->                repo-relative owned paths
  <!-- ringer-expect: file/a;file/b -->                   files that must exist

Usage
-----
  python3 bmad_to_ringer.py \
    --sprint-status _bmad-output/implementation-artifacts/sprint-status.yaml \
    --story-dir     _bmad-output/implementation-artifacts/stories \
    --repo          . \
    --check-command "pytest -q" \
    --stories 1-2,1-3 \
    --out swarm.json

Then:  python3 ./ringer/ringer.py lint swarm.json   (fix what it flags)
       python3 ./ringer/ringer.py run  swarm.json
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, "checks", "check_bmad_story.py")

STORY_STATUS_READY = "ready-for-dev"
# keys in development_status that are NOT stories
SKIP_RE = re.compile(r"(^epic-\d+$)|(-retrospective$)")


def die(msg):
    sys.stderr.write(f"error: {msg}\n")
    sys.exit(2)


def parse_development_status(path):
    """Minimal, dependency-free parse of the `development_status:` block.
    The block is a flat map of `  <key>: <status>` lines (see BMAD
    sprint-status-template.yaml). We deliberately do not parse the rest."""
    if not os.path.isfile(path):
        die(f"sprint-status not found: {path}\n"
            f"       run bmad-sprint-planning first to generate it.")
    out, in_block = {}, False
    with open(path) as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if re.match(r"^\S", line):          # a new top-level key ends the block
                in_block = line.strip().startswith("development_status:")
                continue
            if not in_block:
                continue
            m = re.match(r"^\s+([A-Za-z0-9._-]+)\s*:\s*(\S+)\s*$", line)
            if m:
                out[m.group(1)] = m.group(2)
    if not out:
        die("no development_status entries found — is sprint-planning complete?")
    return out


def find_story_file(story_dir, key):
    for cand in (f"{key}.md", f"story-{key}.md"):
        p = os.path.join(story_dir, cand)
        if os.path.isfile(p):
            return p
    return None


def extract(text, tag):
    m = re.search(rf"<!--\s*ringer-{tag}:\s*(.*?)\s*-->", text)
    return m.group(1).strip() if m else None


def title_of(text, key):
    m = re.search(r"^#\s*(.+)$", text, re.M)
    return m.group(1).strip() if m else f"Story {key}"


def build_spec(key, title, story_md):
    return (
        f"You are a Ringer worker implementing BMAD story '{key}': {title}.\n\n"
        "Your current working directory IS a dedicated git worktree of the repo. "
        "Edit files in place, leave every change UNCOMMITTED, and do NOT run git "
        "commit / git branch / git push or touch .git — Ringer's check exports "
        "your work as a patch.\n\n"
        "Stay inside the story's scope. Do not add dependencies unless the story "
        "requires them; keep the change boring and consistent with existing "
        "patterns; mark unknown product facts as assumptions, do not invent.\n\n"
        "OUTPUT CONTRACT: make the code change the story requires, then write "
        "./notes.md in the worktree listing what you changed, what you read for "
        "conventions, which command verifies it, and any assumptions/follow-ups.\n\n"
        "=== FULL STORY SPEC (source of truth) ===\n"
        f"{story_md.strip()}\n"
        "=== END STORY SPEC ==="
    )


def build_check(key, check_cmd, owned, expect, export_dir):
    parts = ["python3", _q(CHECK), "--key", _q(key),
             "--check-command", _q(check_cmd),
             "--export-dir", _q(export_dir)]
    if owned:
        parts += ["--owned", _q(owned)]
    if expect:
        parts += ["--expect", _q(expect)]
    return " ".join(parts)


def _q(s):
    return "'" + str(s).replace("'", "'\\''") + "'"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sprint-status", required=True)
    ap.add_argument("--story-dir", required=True)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--check-command", default="",
                    help="default acceptance check when a story has no ringer-check override")
    ap.add_argument("--engine", default="opencode")
    ap.add_argument("--model", default="",
                    help="optional per-task model override (else engine model_default)")
    grp = ap.add_mutually_exclusive_group(required=True)
    grp.add_argument("--stories", help="comma-separated story keys to include")
    grp.add_argument("--all-ready", action="store_true",
                     help="include every ready-for-dev story (verify independence yourself)")
    ap.add_argument("--max-parallel", type=int, default=4)
    ap.add_argument("--run-name", default="bmad-hybrid")
    ap.add_argument("--workdir", default="~/.ringer/work/bmad-hybrid")
    ap.add_argument("--export-dir", default="",
                    help="where verified patches land (default: <workdir>/patches)")
    ap.add_argument("--out", default="swarm.json")
    a = ap.parse_args()

    repo = os.path.abspath(os.path.expanduser(a.repo))
    workdir = os.path.expanduser(a.workdir)
    export_dir = os.path.expanduser(a.export_dir) or os.path.join(workdir, "patches")

    status = parse_development_status(a.sprint_status)
    ready = [k for k, v in status.items()
             if v == STORY_STATUS_READY and not SKIP_RE.search(k)]

    if a.all_ready:
        keys = ready
    else:
        keys = [k.strip() for k in a.stories.split(",") if k.strip()]
        bad = [k for k in keys if k not in status]
        if bad:
            die(f"unknown story keys (not in sprint-status): {bad}")
        not_ready = [k for k in keys if status.get(k) != STORY_STATUS_READY]
        if not_ready:
            sys.stderr.write(f"warning: not 'ready-for-dev' (included anyway): "
                             f"{[(k, status[k]) for k in not_ready]}\n")
    if not keys:
        die("no stories selected — nothing to swarm "
            "(are any stories 'ready-for-dev'?)")

    tasks, missing = [], []
    for key in keys:
        sf = find_story_file(a.story_dir, key)
        if not sf:
            missing.append(key)
            continue
        text = open(sf).read()
        check_cmd = extract(text, "check") or a.check_command
        if not check_cmd:
            die(f"story {key} has no <!-- ringer-check --> and no --check-command; "
                f"a Ringer task MUST have an executable check.")
        owned = extract(text, "owned") or ""
        expect = extract(text, "expect") or "notes.md"
        task = {
            "key": key,
            "task_type": "code-feature",
            "engine": a.engine,
            "timeout_s": 2400,
            # empty on purpose: with worktrees, anything inside is deleted on PASS,
            # so Ringer-level expect_files would be flagged as an ephemeral
            # deliverable. The check verifies these files (via --expect) inside
            # the worktree and exports the durable patch outside it.
            "expect_files": [],
            "spec": build_spec(key, title_of(text, key), text),
            "check": build_check(key, check_cmd, owned, expect, export_dir),
            "verified": (f"story {key}: acceptance check passed in an isolated "
                         f"worktree, changes stayed within owned paths, and a "
                         f"non-empty patch was exported for review"),
        }
        if a.model:
            task["model"] = a.model
        tasks.append(task)

    if missing:
        sys.stderr.write(f"warning: no story file found for: {missing} "
                         f"(looked in {a.story_dir}) — skipped\n")
    if not tasks:
        die("no tasks built — check --story-dir and story filenames.")

    manifest = {
        "run_name": a.run_name,
        "workdir": workdir,
        "repo": repo,
        "max_parallel": a.max_parallel,
        "worktrees": True,       # REQUIRED: parallel isolation + patch-export model
        "tasks": tasks,
    }
    with open(a.out, "w") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    print(f"wrote {a.out}: {len(tasks)} task(s) -> engine '{a.engine}', "
          f"worktrees on, patches -> {export_dir}")
    print(f"next: python3 ./ringer/ringer.py lint {a.out}")


if __name__ == "__main__":
    main()
