"""The Tests+Docs Gate (FR-10 / AD-18) — story 0-3.

No test = not done; no doc = not done — enforced mechanically on the changed
file set, decidable via AD-11's 1:1 module↔test pairing, scoped by
--tests-docs-roots. Drives the REAL Gate (AD-21) via the shared harness.

Run: python3 -m unittest discover -s tools/ringer-bridge/tests -q
"""
import json
import unittest

from _gate_harness import run_gate

ROOTS = ("--tests-docs-roots", "pkg")

# A committed baseline holding a module, its paired test, and a docs page.
SEED = {
    "pkg/mod.py": "X = 1\n",
    "tests/test_mod.py": "import unittest\n",
    "docs/readme.md": "docs\n",
}


def _td_nodes(nodes):
    return [n for n in nodes if n.get("meridian:gate") == "tests-docs"]


class PairingRule(unittest.TestCase):
    def test_module_without_paired_test_is_refused_naming_both(self):
        proc, nodes = run_gate(
            self, "0-t-td-nopair", seed=SEED,
            change={"pkg/mod.py": "X = 2\n"}, args=ROOTS)
        self.assertEqual(proc.returncode, 1, proc.stdout)
        refusals = _td_nodes(nodes)
        self.assertTrue(refusals)
        node = refusals[0]
        self.assertEqual(node["meridian:locus"],
                         ["pkg/mod.py", "tests/test_mod.py"])
        self.assertIn("pkg/mod.py", node["meridian:reason"])
        self.assertIn("tests/test_mod.py", node["meridian:reason"])

    def test_module_with_paired_test_passes(self):
        proc, nodes = run_gate(
            self, "0-t-td-paired", seed=SEED,
            change={"pkg/mod.py": "X = 2\n",
                    "tests/test_mod.py": "import unittest  # upd\n"},
            args=ROOTS)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_init_py_is_exempt_from_pairing(self):
        proc, nodes = run_gate(
            self, "0-t-td-init",
            seed=dict(SEED, **{"pkg/__init__.py": "\n"}),
            change={"pkg/__init__.py": "# comment\n"}, args=ROOTS)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


class DocsRule(unittest.TestCase):
    def test_new_module_without_docs_change_is_refused(self):
        proc, nodes = run_gate(
            self, "0-t-td-newmod", seed=SEED,
            change={"pkg/newmod.py": "Y = 1\n",
                    "tests/test_newmod.py": "import unittest\n"},
            args=ROOTS)
        self.assertEqual(proc.returncode, 1, proc.stdout)
        node = _td_nodes(nodes)[0]
        self.assertEqual(node["meridian:locus"], ["pkg/newmod.py", "docs/"])

    def test_new_module_with_docs_change_passes(self):
        proc, nodes = run_gate(
            self, "0-t-td-newmod-doc", seed=SEED,
            change={"pkg/newmod.py": "Y = 1\n",
                    "tests/test_newmod.py": "import unittest\n",
                    "docs/readme.md": "docs + newmod\n"},
            args=ROOTS)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


class LegalPatches(unittest.TestCase):
    def test_tests_only_patch_is_legal(self):
        proc, nodes = run_gate(
            self, "0-t-td-testsonly", seed=SEED,
            change={"tests/test_mod.py": "import unittest  # harden\n"},
            args=ROOTS)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_docs_only_patch_is_legal(self):
        proc, nodes = run_gate(
            self, "0-t-td-docsonly", seed=SEED,
            change={"docs/readme.md": "docs v2\n"}, args=ROOTS)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


class AbsenceRules(unittest.TestCase):
    def test_no_declared_roots_means_gate_is_inert(self):
        # AD-20: absence of config is not a determination — never refuses.
        proc, nodes = run_gate(
            self, "0-t-td-noroots", seed=SEED,
            change={"pkg/mod.py": "X = 2\n"})
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertFalse(_td_nodes(nodes))

    def test_refusal_is_a_recorded_catch_before_exit(self):
        # AD-2: the Gate that refuses writes the Catch at the moment it
        # decides; the refusal node must exist even though the process
        # exited non-zero.
        proc, nodes = run_gate(
            self, "0-t-td-recorded", seed=SEED,
            change={"pkg/mod.py": "X = 2\n"}, args=ROOTS)
        self.assertEqual(proc.returncode, 1)
        refusals = _td_nodes(nodes)
        self.assertEqual(len(refusals), 1)
        self.assertEqual(refusals[0]["axon:result"],
                         {"@id": "axon:result/rejected"})


if __name__ == "__main__":
    unittest.main()
