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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import catch_emit  # noqa: E402  (vendored sibling, stdlib-only)

# Set once in main(); a Gate needs these to record its own decision.
# "origin" stays None when the Story declared no marker — _catch() then omits
# the kwarg entirely so catch_emit.emit() supplies its own default. The
# producer owns the default; duplicating it here would be a second copy that
# can drift (FR-8, AD-14).
_CTX = {"export_dir": None, "key": None, "run_id": "unknown", "coupon": False,
        "origin": None}


def sh(cmd, cwd=None, shell=False):
    return subprocess.run(cmd, cwd=cwd, shell=shell, capture_output=True, text=True)


def _split_paths(raw):
    """Split a path-list argument on ';' (bridge convention) OR ',' — one rule
    for owned, expect, and contract-artifacts alike, so the comma-tolerance fix
    can't be half-applied (review 2026-07-18: the first cut fixed only owned,
    and ringer-expect kept the retry-per-story cost of
    L-2026-07-17-gitfile-wave1). Natural prose authors these lists with commas.
    CONSEQUENCE, by fleet convention: a repo-relative path may not contain a
    comma — treating one as a literal path char is unsupported here.
    """
    return [x.strip() for x in raw.replace(",", ";").split(";") if x.strip()]


def _catch(gate, decision, reason, cause=catch_emit.VERIFICATION, locus=()):
    """Record a Gate decision as evidence. Never let recording break the Gate.

    A Catch that cannot be written must not turn a clean refusal into a crash —
    the refusal is the load-bearing part. The failure to record is surfaced on
    stderr rather than swallowed, because silent evidence loss is the bug this
    whole mechanism exists to prevent.
    """
    if not _CTX["export_dir"] or not _CTX["key"]:
        return
    try:
        kw = {}
        if _CTX["origin"] is not None:
            kw["origin"] = _CTX["origin"]
        catch_emit.emit(_CTX["export_dir"], _CTX["key"], gate, decision, reason,
                        run_id=_CTX["run_id"], cause=cause, locus=locus,
                        coupon=_CTX["coupon"], **kw)
    except Exception as exc:                                  # noqa: BLE001
        print(f"WARNING: could not record Catch for gate '{gate}': {exc}",
              file=sys.stderr)


def fail(msg, gate="check", cause=catch_emit.VERIFICATION, locus=()):
    """Refuse — and emit the Catch. A refusal nobody can see never happened.

    `locus` is the paths the refusal is ABOUT. Pass it: a Gate that renders its
    locus only into `msg` has destroyed the evidence that decides whether the
    refusal was the Line's own bug, and prose is not evidence (AD-2).
    """
    _catch(gate, catch_emit.REJECTED, msg, cause, locus=locus)
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
    ap.add_argument("--run-id", default="unknown",
                    help="Ringer run name; scopes Catch identity to one run")
    ap.add_argument("--coupon", action="store_true",
                    help="this Work Item is planted fault injection (FR-14). The "
                         "flag is recorded on every Catch either way; absence of "
                         "the FIELD would read as False downstream and authorize "
                         "the patch, which is exactly what a Coupon must never get.")
    ap.add_argument("--contract-artifacts", default="notes.md",
                    help="semicolon-separated artifacts the Line's own prompt "
                         "MANDATES; exempt from ownership and excluded from the "
                         "exported patch. The Bridge supplies these — a Gate must "
                         "not refuse, and an export must not ship, what the Line "
                         "itself ordered.")
    ap.add_argument("--origin", choices=("human", "factory"), default=None,
                    help="Story authorship declared by the Story file's "
                         "ringer-origin marker (FR-8: origin is recorded). "
                         "Omitted = no marker; the emitter supplies its own "
                         "default so this Gate never duplicates it.")
    ap.add_argument("--tests-docs-roots", default="",
                    help="path-list of product-source roots governed by the "
                         "tests+docs gate (FR-10/AD-18): a changed <root>/<m>.py "
                         "must be accompanied by tests/test_<m>.py, and a NEW "
                         "module under a root needs a docs/ change. Empty = the "
                         "gate is inert — absence of config is not a "
                         "determination and must never refuse (AD-20).")
    a = ap.parse_args()
    wt = os.getcwd()
    _CTX.update(export_dir=a.export_dir, key=a.key, run_id=a.run_id,
                coupon=a.coupon, origin=a.origin)
    contract = _split_paths(a.contract_artifacts)

    # 1. expected files exist and are non-empty
    for f in _split_paths(a.expect):
        p = os.path.join(wt, f)
        if not os.path.isfile(p) or os.path.getsize(p) == 0:
            fail(f"expected file missing or empty: {f} (worker did not produce it)",
                 gate="expect", locus=[f])

    # 2. run the acceptance check — this is the contract
    r = sh(a.check_command, cwd=wt, shell=True)
    if r.returncode != 0:
        print("---- acceptance check stdout (tail) ----")
        print(r.stdout[-4000:])
        print("---- acceptance check stderr (tail) ----")
        print(r.stderr[-4000:])
        fail(f"acceptance check '{a.check_command}' exited {r.returncode} "
             f"for {a.key}", gate="check")

    # Change inventory, computed once for gates 3 (ownership) and 3b
    # (tests+docs). -uall expands untracked DIRECTORIES into their files:
    # without it git collapses a new dir to a single entry ("pkg/vendor/")
    # that matches no owned path, so the gate refuses work the Line's own
    # spec ordered.
    st = sh(["git", "status", "--porcelain", "-uall"], cwd=wt)
    entries = [(ln[:2], ln[3:].strip()) for ln in st.stdout.splitlines()
               if ln.strip()]
    changed = [p for _, p in entries]

    # 3. ownership boundary (optional but recommended)
    owned = [x.rstrip("/") for x in _split_paths(a.owned)]
    if owned:
        # An artifact the Line's own prompt ordered is never a stray
        # (L-2026-07-14-epic21-pilot: this contradiction cost a retry per wave).
        stray = [c for c in changed
                 if c not in contract
                 and not any(c == o or c.startswith(o + "/") for o in owned)]
        if stray:
            # `stray` IS the locus. Rendering it only into the message would
            # throw away the fact that decides self_inflicted vs real.
            fail(f"changes outside owned paths for {a.key}: {stray}",
                 gate="ownership", locus=stray)

    # 3b. tests+docs concurrent gate (FR-10/AD-18) — after Ownership, before
    # export, refusing like any other Gate. Decidable via AD-11's 1:1
    # module↔test pairing, keyed off the path PATTERN (fix the class, not the
    # instance): a changed <root>/<m>.py pairs with tests/test_<m>.py; a NEW
    # module under a root is a new public surface and needs a docs/ change.
    # Patches touching ONLY tests or ONLY docs are legal (test-hardening and
    # doc stories). Contract artifacts are exempt (AD-6). __init__.py is
    # exempt from pairing (it pairs with nothing; AD-11 forbids editing it as
    # a shared file anyway, which is the ownership gate's job, not this one's).
    td_roots = [x.rstrip("/") for x in _split_paths(a.tests_docs_roots)]
    if td_roots:
        rel = [(code, p) for code, p in entries if p not in contract]
        touched_docs = any(p == "docs" or p.startswith("docs/")
                           for _, p in rel)
        for code, p in rel:
            in_root = any(p.startswith(r + "/") for r in td_roots)
            if not in_root or not p.endswith(".py"):
                continue
            base = os.path.splitext(os.path.basename(p))[0]
            if base == "__init__":
                continue
            pair = f"tests/test_{base}.py"
            if pair not in changed:
                fail(f"tests+docs: {p} changed without its paired test {pair} "
                     f"for {a.key} (FR-10: no test = not done)",
                     gate="tests-docs", locus=[p, pair])
            if code.strip() in ("??", "A") and not touched_docs:
                fail(f"tests+docs: new public surface {p} without a docs/ "
                     f"change for {a.key} (FR-10: no doc = not done)",
                     gate="tests-docs", locus=[p, "docs/"])

    # 4. export a verified patch OUT of the worktree (survives PASS deletion)
    os.makedirs(a.export_dir, exist_ok=True)
    sh(["git", "add", "-A"], cwd=wt)                       # stage, never commit
    # A contract artifact is the worker's REPORT, not deliverable code.
    # Exempting it from the gate (step 3) is only half the fix: if it rides
    # along in the patch, every patch after the first collides on it and
    # `git apply` — which is atomic — rejects the WHOLE patch, code included.
    diff = sh(["git", "diff", "--cached", "--binary", "--", "."]
              + [f":(exclude){a}" for a in contract], cwd=wt)
    patch_path = os.path.join(a.export_dir, f"{a.key}.patch")
    with open(patch_path, "w") as fh:
        fh.write(diff.stdout)
    if os.path.getsize(patch_path) == 0:
        fail(f"worker produced an empty patch for {a.key} (no code changes detected)",
             gate="export", cause=catch_emit.ERROR)

    _catch("check", catch_emit.ACCEPTED,
           f"acceptance check passed; verified patch exported to {patch_path}")
    print(f"PASS: {a.key} — acceptance check passed; "
          f"verified patch exported to {patch_path}")
    sys.exit(0)


if __name__ == "__main__":
    main()
