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


class FalseRefusalGuards(unittest.TestCase):
    """Review 2026-07-18: the AD-6 class — never refuse legitimate work."""

    def test_deletion_only_cleanup_is_legal(self):
        proc, nodes = run_gate(
            self, "0-t-td-delete", seed=SEED,
            change={"pkg/mod.py": None,
                    "docs/readme.md": "removed mod\n"}, args=ROOTS)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertFalse(_td_nodes(nodes))

    def test_nested_module_is_outside_the_convention_and_skipped(self):
        proc, nodes = run_gate(
            self, "0-t-td-nested",
            seed=dict(SEED, **{"pkg/sub/deep.py": "Z = 1\n"}),
            change={"pkg/sub/deep.py": "Z = 2\n"}, args=ROOTS)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_support_files_are_exempt_from_pairing(self):
        proc, nodes = run_gate(
            self, "0-t-td-support",
            seed=dict(SEED, **{"pkg/conftest.py": "\n", "pkg/_helpers.py": "\n"}),
            change={"pkg/conftest.py": "# c\n", "pkg/_helpers.py": "# h\n"},
            args=ROOTS)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

    def test_staged_new_module_still_caught_by_docs_rule(self):
        # NEW-ness comes from HEAD-absence, not porcelain staging codes: a
        # worker that git-adds its new module must not escape the docs rule.
        import os
        import subprocess
        from _gate_harness import GATE, write
        import tempfile, shutil, sys, json
        tmp = tempfile.mkdtemp(prefix="gate-staged-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        repo = os.path.join(tmp, "repo"); os.makedirs(repo)
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
                   GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        def git(*ar):
            subprocess.run(["git", *ar], cwd=repo, env=env, check=True,
                           capture_output=True)
        git("init", "-q")
        for rel, text in SEED.items():
            write(os.path.join(repo, rel), text)
        git("add", "-A"); git("commit", "-qm", "seed")
        write(os.path.join(repo, "pkg/staged.py"), "S = 1\n")
        write(os.path.join(repo, "tests/test_staged.py"), "import unittest\n")
        git("add", "pkg/staged.py")          # 'A ' — then edit again -> 'AM'
        write(os.path.join(repo, "pkg/staged.py"), "S = 2\n")
        export = os.path.join(tmp, "export")
        proc = subprocess.run(
            [sys.executable, GATE, "--key", "0-t-td-staged",
             "--check-command", "true", "--export-dir", export,
             "--run-id", "test-harness", *ROOTS],
            cwd=repo, capture_output=True, text=True, env=env)
        self.assertEqual(proc.returncode, 1, proc.stdout)
        cpath = os.path.join(export, "0-t-td-staged.catches.jsonld")
        nodes = [json.loads(l) for l in open(cpath) if l.strip()]
        self.assertTrue(any(n.get("meridian:gate") == "tests-docs"
                            and n["meridian:locus"] == ["pkg/staged.py", "docs/"]
                            for n in nodes), nodes)


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
