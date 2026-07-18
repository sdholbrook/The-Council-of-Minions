"""Bridge/Gate regressions for story-declared origin + coupon markers.

FR-8 (origin is recorded) and FR-14 (coupons are declared) — the Bridge is the
only component that knows a Story's authorship and what it planted, so it must
say so in typed fields. These tests drive the REAL bmad_to_ringer.py and the
REAL check_bmad_story.py via the shared harness (AD-21: never a fixture either
side builds); the emitted Catch JSON-LD is the artifact under test.

Run: python3 -m unittest discover -s tools/ringer-bridge/tests -q
"""
import json
import os
import unittest

from _gate_harness import emit_manifest, run_gate


class ManifestMarkerTests(unittest.TestCase):
    """The Bridge parses the markers and plumbs them into the Gate command."""

    def test_declared_origin_and_coupon_reach_the_gate_command(self):
        proc, out = emit_manifest(
            self,
            "# probe\n<!-- ringer-check: true -->\n"
            "<!-- ringer-origin: human -->\n<!-- ringer-coupon: true -->\n",
            "0-t-origin-probe")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        check = json.load(open(out))["tasks"][0]["check"]
        self.assertIn("--origin 'human'", check)
        self.assertIn("--coupon", check)

    def test_absent_markers_omit_both_flags(self):
        proc, out = emit_manifest(
            self, "# probe\n<!-- ringer-check: true -->\n", "0-t-plain-probe")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        check = json.load(open(out))["tasks"][0]["check"]
        self.assertNotIn("--origin", check)
        self.assertNotIn("--coupon", check)
        self.assertNotIn("--tests-docs-roots", check)

    def test_tests_docs_roots_cli_arg_reaches_the_gate_command(self):
        proc, out = emit_manifest(
            self, "# probe\n<!-- ringer-check: true -->\n", "0-t-tdroots",
            extra_args=("--tests-docs-roots", "meridian_control;scripts"))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        check = json.load(open(out))["tasks"][0]["check"]
        self.assertIn("--tests-docs-roots 'meridian_control;scripts'", check)

    def test_invalid_origin_refused_at_dispatch_naming_the_story(self):
        key = "0-t-bad-origin"
        proc, out = emit_manifest(
            self,
            "# probe\n<!-- ringer-check: true -->\n"
            "<!-- ringer-origin: alien -->\n", key)
        self.assertEqual(proc.returncode, 2)
        self.assertIn(key, proc.stderr)
        self.assertIn("alien", proc.stderr)
        self.assertFalse(os.path.exists(out), "no manifest may be written")

    def test_invalid_coupon_refused_at_dispatch(self):
        key = "0-t-bad-coupon"
        proc, out = emit_manifest(
            self,
            "# probe\n<!-- ringer-check: true -->\n"
            "<!-- ringer-coupon: yes -->\n", key)
        self.assertEqual(proc.returncode, 2)
        self.assertIn(key, proc.stderr)
        self.assertFalse(os.path.exists(out))


class GateEmissionTests(unittest.TestCase):
    """The real Gate stamps declared origin/coupon on every emitted Catch."""

    def test_declared_origin_stamps_every_node(self):
        proc, nodes = run_gate(self, "0-t-gate-human",
                               args=("--origin", "human"))
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(nodes)
        for n in nodes:
            self.assertEqual(n.get("meridian:origin"), "human", n)

    def test_absent_origin_gets_the_emitter_default(self):
        proc, nodes = run_gate(self, "0-t-gate-default")
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(nodes)
        for n in nodes:
            self.assertEqual(n.get("meridian:origin"), "factory", n)
            self.assertIs(n.get("meridian:coupon"), False, n)

    def test_expect_list_tolerates_commas(self):
        # Review 2026-07-18: the comma-tolerance fix must cover --expect too,
        # not only --owned — same natural-prose habit, same false-refusal cost.
        proc, nodes = run_gate(self, "0-t-gate-expect",
                               args=("--expect", "mod.py, extra.txt"))
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(nodes)

    def test_coupon_flag_stamps_every_node_true(self):
        proc, nodes = run_gate(self, "0-t-gate-coupon", args=("--coupon",))
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(nodes)
        for n in nodes:
            self.assertIs(n.get("meridian:coupon"), True, n)


if __name__ == "__main__":
    unittest.main()
