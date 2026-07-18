"""Bridge/Gate regressions for story-declared origin + coupon markers.

FR-8 (origin is recorded) and FR-14 (coupons are declared) — the Bridge is the
only component that knows a Story's authorship and what it planted, so it must
say so in typed fields. These tests drive the REAL bmad_to_ringer.py and the
REAL check_bmad_story.py via subprocess (AD-21: never a fixture either side
builds); the emitted Catch JSON-LD is the artifact under test.

Run: python3 -m unittest discover -s tools/ringer-bridge/tests -q
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

BRIDGE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRIDGE = os.path.join(BRIDGE_DIR, "bmad_to_ringer.py")
GATE = os.path.join(BRIDGE_DIR, "checks", "check_bmad_story.py")


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


class ManifestMarkerTests(unittest.TestCase):
    """The Bridge parses the markers and plumbs them into the Gate command."""

    def _emit_manifest(self, story_md, key="0-t-origin-probe"):
        tmp = tempfile.mkdtemp(prefix="bridge-origin-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        stories = os.path.join(tmp, "stories")
        _write(os.path.join(stories, f"{key}.md"), story_md)
        _write(os.path.join(tmp, "sprint-status.yaml"),
               f"development_status:\n  {key}: ready-for-dev\n")
        out = os.path.join(tmp, "swarm.json")
        proc = subprocess.run(
            [sys.executable, BRIDGE,
             "--sprint-status", os.path.join(tmp, "sprint-status.yaml"),
             "--story-dir", stories, "--repo", tmp,
             "--stories", key,
             "--run-name", "test-origin",
             "--workdir", os.path.join(tmp, "work"),
             "--export-dir", os.path.join(tmp, "patches"),
             "--out", out],
            capture_output=True, text=True)
        return proc, out

    def test_declared_origin_and_coupon_reach_the_gate_command(self):
        proc, out = self._emit_manifest(
            "# probe\n<!-- ringer-check: true -->\n"
            "<!-- ringer-origin: human -->\n<!-- ringer-coupon: true -->\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        check = json.load(open(out))["tasks"][0]["check"]
        self.assertIn("--origin 'human'", check)
        self.assertIn("--coupon", check)

    def test_absent_markers_omit_both_flags(self):
        proc, out = self._emit_manifest(
            "# probe\n<!-- ringer-check: true -->\n")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        check = json.load(open(out))["tasks"][0]["check"]
        self.assertNotIn("--origin", check)
        self.assertNotIn("--coupon", check)

    def test_invalid_origin_refused_at_dispatch_naming_the_story(self):
        key = "0-t-bad-origin"
        proc, out = self._emit_manifest(
            "# probe\n<!-- ringer-check: true -->\n"
            "<!-- ringer-origin: alien -->\n", key=key)
        self.assertEqual(proc.returncode, 2)
        self.assertIn(key, proc.stderr)
        self.assertIn("alien", proc.stderr)
        self.assertFalse(os.path.exists(out), "no manifest may be written")

    def test_invalid_coupon_refused_at_dispatch(self):
        key = "0-t-bad-coupon"
        proc, out = self._emit_manifest(
            "# probe\n<!-- ringer-check: true -->\n"
            "<!-- ringer-coupon: yes -->\n", key=key)
        self.assertEqual(proc.returncode, 2)
        self.assertIn(key, proc.stderr)
        self.assertFalse(os.path.exists(out))


class GateEmissionTests(unittest.TestCase):
    """The real Gate stamps declared origin/coupon on every emitted Catch."""

    def _run_gate(self, extra_args, key="0-t-gate-probe"):
        tmp = tempfile.mkdtemp(prefix="gate-origin-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo)
        env = dict(os.environ,
                   GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
                   GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")

        def git(*args):
            subprocess.run(["git", *args], cwd=repo, env=env,
                           check=True, capture_output=True)

        git("init", "-q")
        _write(os.path.join(repo, "mod.py"), "X = 1\n")
        git("add", "-A")
        git("commit", "-qm", "seed")
        # a real change so the export gate has a non-empty patch
        _write(os.path.join(repo, "mod.py"), "X = 2\n")
        _write(os.path.join(repo, "extra.txt"), "y\n")
        export = os.path.join(tmp, "export")
        proc = subprocess.run(
            [sys.executable, GATE, "--key", key,
             "--check-command", "true",
             "--export-dir", export, "--run-id", "test-origin",
             *extra_args],
            cwd=repo, capture_output=True, text=True, env=env)
        nodes = []
        cpath = os.path.join(export, f"{key}.catches.jsonld")
        if os.path.exists(cpath):
            nodes = [json.loads(l) for l in open(cpath) if l.strip()]
        return proc, nodes

    def test_declared_origin_stamps_every_node(self):
        proc, nodes = self._run_gate(["--origin", "human"])
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(nodes)
        for n in nodes:
            self.assertEqual(n.get("meridian:origin"), "human", n)

    def test_absent_origin_gets_the_emitter_default(self):
        proc, nodes = self._run_gate([])
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(nodes)
        for n in nodes:
            self.assertEqual(n.get("meridian:origin"), "factory", n)
            self.assertIs(n.get("meridian:coupon"), False, n)

    def test_expect_list_tolerates_commas(self):
        # Review 2026-07-18: the comma-tolerance fix must cover --expect too,
        # not only --owned — same natural-prose habit, same false-refusal cost.
        proc, nodes = self._run_gate(["--expect", "mod.py, extra.txt"])
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(nodes)

    def test_coupon_flag_stamps_every_node_true(self):
        proc, nodes = self._run_gate(["--coupon"])
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(nodes)
        for n in nodes:
            self.assertIs(n.get("meridian:coupon"), True, n)


if __name__ == "__main__":
    unittest.main()
