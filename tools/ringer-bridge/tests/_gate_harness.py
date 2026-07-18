"""Shared scratch-git-repo harness for driving the REAL Gate in tests.

One copy of the repo-build + gate-invocation sequence (review 2026-07-18: two
test files had near-verbatim private copies; a Gate contract change would
update one and leave the other passing against a stale contract). AD-21:
these helpers subprocess the production check_bmad_story.py — they never
build the records they assert on.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

BRIDGE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRIDGE = os.path.join(BRIDGE_DIR, "bmad_to_ringer.py")
GATE = os.path.join(BRIDGE_DIR, "checks", "check_bmad_story.py")

_GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
            "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def run_gate(case, key, *, seed=None, change=None, args=()):
    """Build a scratch repo (``seed`` committed, ``change`` left dirty), run
    the real Gate for ``key`` with extra ``args``, return (proc, nodes).

    ``seed``/``change`` are {relpath: content} dicts. Defaults reproduce the
    minimal one-module repo with a real uncommitted edit so the export gate
    has a non-empty patch. Temp dirs are cleaned via ``case.addCleanup``.
    """
    if seed is None:
        seed = {"mod.py": "X = 1\n"}
    if change is None:
        change = {"mod.py": "X = 2\n", "extra.txt": "y\n"}
    tmp = tempfile.mkdtemp(prefix="gate-harness-")
    case.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
    repo = os.path.join(tmp, "repo")
    os.makedirs(repo)
    env = dict(os.environ, **_GIT_ENV)

    def git(*gargs):
        subprocess.run(["git", *gargs], cwd=repo, env=env,
                       check=True, capture_output=True)

    git("init", "-q")
    for rel, text in seed.items():
        write(os.path.join(repo, rel), text)
    git("add", "-A")
    git("commit", "-qm", "seed")
    for rel, text in change.items():
        write(os.path.join(repo, rel), text)
    export = os.path.join(tmp, "export")
    proc = subprocess.run(
        [sys.executable, GATE, "--key", key, "--check-command", "true",
         "--export-dir", export, "--run-id", "test-harness", *args],
        cwd=repo, capture_output=True, text=True, env=env)
    cpath = os.path.join(export, f"{key}.catches.jsonld")
    nodes = []
    if os.path.exists(cpath):
        nodes = [json.loads(l) for l in open(cpath) if l.strip()]
    return proc, nodes


def emit_manifest(case, story_md, key, extra_args=()):
    """Write a one-story sprint + story file, run the real Bridge, return
    (proc, manifest_path)."""
    tmp = tempfile.mkdtemp(prefix="bridge-harness-")
    case.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
    stories = os.path.join(tmp, "stories")
    write(os.path.join(stories, f"{key}.md"), story_md)
    write(os.path.join(tmp, "sprint-status.yaml"),
          f"development_status:\n  {key}: ready-for-dev\n")
    out = os.path.join(tmp, "swarm.json")
    proc = subprocess.run(
        [sys.executable, BRIDGE,
         "--sprint-status", os.path.join(tmp, "sprint-status.yaml"),
         "--story-dir", stories, "--repo", tmp,
         "--stories", key, "--run-name", "test-harness",
         "--workdir", os.path.join(tmp, "work"),
         "--export-dir", os.path.join(tmp, "patches"),
         "--out", out, *extra_args],
        capture_output=True, text=True)
    return proc, out
