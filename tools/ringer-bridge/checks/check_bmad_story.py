#!/usr/bin/env python3
"""
check_bmad_story.py — Ringer check for a BMAD story worker.

Runs INSIDE the task's git worktree (Ringer sets cwd to it). Verifies the
worker's output by execution, enforces the ownership boundary, and — because a
worktree is DELETED on PASS — exports a verified git patch OUT of the worktree
so the change survives for frontier review to apply/merge.

Exit 0 = PASS (Ringer's only source of truth). Any nonzero prints WHY and fails.
"""
import argparse
import os
import subprocess
import sys


def sh(cmd, cwd=None, shell=False):
    return subprocess.run(cmd, cwd=cwd, shell=shell, capture_output=True, text=True)


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", required=True)
    ap.add_argument("--check-command", required=True,
                    help="executable acceptance check; exit 0 = pass")
    ap.add_argument("--expect", default="",
                    help="semicolon-separated files that must exist & be non-empty")
    ap.add_argument("--owned", default="",
                    help="semicolon-separated repo-relative paths this worker may touch")
    ap.add_argument("--export-dir", required=True,
                    help="absolute dir OUTSIDE the worktree to write <key>.patch")
    a = ap.parse_args()
    wt = os.getcwd()

    # 1. expected files exist and are non-empty
    for f in [x.strip() for x in a.expect.split(";") if x.strip()]:
        p = os.path.join(wt, f)
        if not os.path.isfile(p) or os.path.getsize(p) == 0:
            fail(f"expected file missing or empty: {f} (worker did not produce it)")

    # 2. run the acceptance check — this is the contract
    r = sh(a.check_command, cwd=wt, shell=True)
    if r.returncode != 0:
        print("---- acceptance check stdout (tail) ----")
        print(r.stdout[-4000:])
        print("---- acceptance check stderr (tail) ----")
        print(r.stderr[-4000:])
        fail(f"acceptance check '{a.check_command}' exited {r.returncode} for {a.key}")

    # 3. ownership boundary (optional but recommended)
    owned = [x.strip().rstrip("/") for x in a.owned.split(";") if x.strip()]
    if owned:
        st = sh(["git", "status", "--porcelain"], cwd=wt)
        changed = [ln[3:].strip() for ln in st.stdout.splitlines() if ln.strip()]
        stray = [c for c in changed
                 if not any(c == o or c.startswith(o + "/") for o in owned)]
        if stray:
            fail(f"changes outside owned paths for {a.key}: {stray}")

    # 4. export a verified patch OUT of the worktree (survives PASS deletion)
    os.makedirs(a.export_dir, exist_ok=True)
    sh(["git", "add", "-A"], cwd=wt)                       # stage, never commit
    diff = sh(["git", "diff", "--cached", "--binary"], cwd=wt)
    patch_path = os.path.join(a.export_dir, f"{a.key}.patch")
    with open(patch_path, "w") as fh:
        fh.write(diff.stdout)
    if os.path.getsize(patch_path) == 0:
        fail(f"worker produced an empty patch for {a.key} (no code changes detected)")

    print(f"PASS: {a.key} — acceptance check passed; "
          f"verified patch exported to {patch_path}")
    sys.exit(0)


if __name__ == "__main__":
    main()
