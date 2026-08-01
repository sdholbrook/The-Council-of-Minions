#!/usr/bin/env python3
"""Story-review watcher — productized Shape-A event loop.

Tails a bmad-loop run journal and, on each story-done event, dispatches a
multi-lens ringer review swarm, then harvests the resulting reports into
STRUCTURED RECEIPTS appended to <run-dir>/verdicts.jsonl.

Stdlib only (Python 3.11+). One JSON object per line, append-only,
crash-safe (open/append/close per line).

Receipt kinds written to verdicts.jsonl:
  review-skip      story-done that could not be reviewed (no commit / build fail / ...)
  review-dispatch  materials+manifest built (and ringer invoked, unless --dry-run)
  review-verdict   one per lens, parsed from the lens's report.md VERDICT line
  run-paused       pause_class derived from reason/stage text
  story-deferred   passthrough of story-deferred / escalation journal kinds
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_LENSES = "glm=openrouter/z-ai/glm-5.2,grok=openrouter/~x-ai/grok-latest"
MAX_SNAPSHOT_FILES = 30


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def _utcnow_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _sh(args: list[str], **kw) -> subprocess.CompletedProcess:
    """subprocess.run with consistent error capture."""
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    kw.setdefault("errors", "replace")
    return subprocess.run(args, **kw)


def _repo_basename(repo: Path) -> str:
    return repo.resolve().name


def _default_run_dir(repo: Path) -> Path:
    runs = repo / ".bmad-loop" / "runs"
    if not runs.is_dir():
        sys.exit(f"no run dir found under {runs}")
    candidates = sorted(
        (p for p in runs.iterdir() if p.is_dir()),
        key=lambda p: p.name,
        reverse=True,
    )
    if not candidates:
        sys.exit(f"no run dirs under {runs}")
    return candidates[0]


def _parse_lenses(raw: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for chunk in raw.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "=" not in chunk:
            sys.exit(f"bad --lenses entry (need NAME=SLUG): {chunk!r}")
        name, slug = chunk.split("=", 1)
        name, slug = name.strip(), slug.strip()
        if not name or not slug:
            sys.exit(f"empty name/slug in --lenses entry: {chunk!r}")
        out[name] = slug
    if not out:
        sys.exit("--lenses produced no lenses")
    return out


def _pause_class(text: str) -> str:
    low = text.lower()
    if any(k in low for k in ("usage limit", "rate limit", "quota")):
        return "usage-limit"
    if any(k in low for k in ("boundary", "gate", "epic")):
        return "epic-boundary"
    if any(k in low for k in ("crash", "error")):
        return "crash"
    return "escalation"


def _append_receipt(verdicts_path: Path, receipt: dict) -> None:
    verdicts_path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(receipt, separators=(",", ":"), sort_keys=False)
    with verdicts_path.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def _resolve_story_sha(repo: Path, story_key: str) -> str | None:
    """Newest of the last 50 commit lines whose subject contains 'story <key>'."""
    proc = _sh(["git", "-C", str(repo), "log", "--format=%H %s", "-50"])
    if proc.returncode != 0:
        return None
    needle = f"story {story_key}"
    for line in proc.stdout.splitlines():
        if needle in line:
            return line.split(" ", 1)[0]
    return None


def _touched_files(repo: Path, sha: str) -> list[str]:
    proc = _sh(
        ["git", "-C", str(repo), "show", "--name-only", "--format=", sha]
    )
    if proc.returncode != 0:
        return []
    return [ln for ln in proc.stdout.splitlines() if ln.strip()]


def _snapshot_file(repo: Path, sha: str, path: str) -> str | None:
    """Post-change content of `path` at `sha`; None if deleted/missing."""
    proc = _sh(["git", "-C", str(repo), "show", f"{sha}:{path}"])
    if proc.returncode != 0:
        return None
    return proc.stdout


# --------------------------------------------------------------------------- #
# receipt factories
# --------------------------------------------------------------------------- #
def _base_receipt(kind: str, run_dir: Path, story_key: str | None) -> dict:
    r: dict = {"ts": _utcnow_iso(), "kind": kind, "run_dir": str(run_dir)}
    if story_key:
        r["story_key"] = story_key
    return r


# --------------------------------------------------------------------------- #
# materials + manifest
# --------------------------------------------------------------------------- #
def build_materials(
    story_key: str,
    sha: str,
    repo: Path,
    mat: Path,
    contracts: Path | None,
) -> None:
    mat.mkdir(parents=True, exist_ok=True)
    patch = mat / f"{story_key}.patch"
    show = _sh(["git", "-C", str(repo), "show", sha])
    patch.write_text(show.stdout, encoding="utf-8")

    touched = _touched_files(repo, sha)
    # also fold in touched files across the single sha (already have them)
    snap = 0
    for f in sorted(touched):
        if snap >= MAX_SNAPSHOT_FILES:
            break
        content = _snapshot_file(repo, sha, f)
        if content is None:
            continue  # deleted
        # flatten path to its basename to keep materials dir simple & anchored
        (mat / Path(f).name).write_text(content, encoding="utf-8")
        snap += 1

    if contracts is not None and contracts.is_file():
        (mat / contracts.name).write_text(
            contracts.read_text(encoding="utf-8", errors="replace"),
            encoding="utf-8",
        )


def build_manifest(
    story_key: str,
    sha: str,
    repo: Path,
    base: Path,
    lenses: dict[str, str],
    check_path: Path,
    identity: str,
) -> Path:
    repo_bn = _repo_basename(repo)
    manifest_path = base / story_key / "manifest.json"
    mat = base / story_key / "materials"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    tasks = []
    for lens, slug in lenses.items():
        cell = f"{story_key}--{lens}"
        sess = base / story_key / cell
        spec = (
            f"You are an independent, skeptical code reviewer for the {repo_bn} project. "
            f"Boundary: you own ONLY {sess}/ and must write exactly one file: {sess}/report.md. "
            f"Never modify anything under {mat}/ or any repository; strictly read-only. "
            f"SCENARIO: review the change for story '{story_key}' (commit {sha[:12]}). "
            f"Primary material: {mat}/{story_key}.patch (the full change); post-change snapshots "
            f"of touched source files are alongside it in {mat}/. "
            f"Find REAL defects only: contract violations, correctness bugs, unsafe "
            f"subprocess/path handling, isolation risks. No style nits, no invented APIs; "
            f"an evidence-backed APPROVE is a valid outcome; fabricated findings are the worst "
            f"outcome. Mark uncertainty as UNCERTAIN. "
            f"OUTPUT CONTRACT for {sess}/report.md: '# Review Report', 'MODEL: {slug}', "
            f"'## Findings' (numbered: <file> - <HIGH|MEDIUM|LOW> - defect + violated contract), "
            f"'## Evidence' (quoted lines), final line exactly "
            f"'VERDICT: APPROVE' or 'VERDICT: FINDINGS n=<count>'. Under 800 words."
        )
        tasks.append(
            {
                "key": cell,
                "engine": "opencode",
                "model": slug,
                "task_type": "code-review",
                "spec": spec,
                "check": (
                    f"python3 {check_path} --report {sess}/report.md --materials {mat} "
                    f"--expected-model {slug} --min-findings 1"
                ),
                "expect_files": ["report.md"],
                "timeout_s": 1800,
                "verified": "report exists, names its model, anchors to real material files, "
                "ends with a verdict",
            }
        )
    manifest = {
        "run_name": f"{repo_bn}-story-reviews",
        "workdir": str(base / story_key),
        "max_parallel": len(lenses),
        "tasks": tasks,
    }
    manifest_path.write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )
    return manifest_path


# --------------------------------------------------------------------------- #
# dispatch + harvest
# --------------------------------------------------------------------------- #
def dispatch_ringer(
    manifest_path: Path, ringer_path: Path, identity: str
) -> tuple[int, str]:
    """Run `ringer lint` then `ringer run`. cwd = ringer dir."""
    ringer_dir = ringer_path.parent
    lint = _sh(
        [str(ringer_path), "lint", str(manifest_path)], cwd=str(ringer_dir)
    )
    if lint.returncode != 0:
        return lint.returncode, f"lint failed:\n{lint.stdout}\n{lint.stderr}"
    run = _sh(
        [str(ringer_path), "run", str(manifest_path), "--identity", identity],
        cwd=str(ringer_dir),
    )
    msg = run.stdout + ("\n" + run.stderr if run.stderr.strip() else "")
    return run.returncode, msg


_VERDICT_RE = re.compile(
    r"^\s*VERDICT:\s*(APPROVE|FINDINGS)(?:\s+n\s*=\s*(\d+))?",
    re.M | re.I,
)


def _parse_report(report_path: Path, lens: str, slug: str) -> dict:
    """Parse one lens report.md into a review-verdict receipt body."""
    if not report_path.is_file():
        return {
            "lens": lens,
            "model": slug,
            "verdict": "NO-REPORT",
            "findings_count": -1,
            "report_path": str(report_path),
        }
    text = report_path.read_text(encoding="utf-8", errors="replace")
    m = _VERDICT_RE.search(text)
    if not m:
        return {
            "lens": lens,
            "model": slug,
            "verdict": "NO-REPORT",
            "findings_count": -1,
            "report_path": str(report_path),
        }
    verdict = m.group(1).upper()
    if verdict == "APPROVE":
        count = 0
    else:
        raw = m.group(2)
        count = int(raw) if raw and raw.isdigit() else 0
    return {
        "lens": lens,
        "model": slug,
        "verdict": verdict,
        "findings_count": count,
        "report_path": str(report_path),
    }


def harvest_story(
    story_key: str,
    sha: str,
    base: Path,
    lenses: dict[str, str],
    run_dir: Path,
) -> None:
    for lens, slug in lenses.items():
        cell = f"{story_key}--{lens}"
        report = base / story_key / cell / "report.md"
        body = _parse_report(report, lens, slug)
        receipt = _base_receipt("review-verdict", run_dir, story_key)
        receipt.update(body)
        receipt["sha"] = sha
        _append_receipt(run_dir / "verdicts.jsonl", receipt)


# --------------------------------------------------------------------------- #
# event handlers
# --------------------------------------------------------------------------- #
def handle_story_done(
    event: dict,
    repo: Path,
    run_dir: Path,
    base: Path,
    lenses: dict[str, str],
    check_path: Path,
    ringer_path: Path,
    identity: str,
    contracts: Path | None,
    dry_run: bool,
) -> None:
    story_key = event.get("story_key") or ""
    verdicts = run_dir / "verdicts.jsonl"

    if not story_key:
        _append_receipt(verdicts, _base_receipt("review-skip", run_dir, None)
                        | {"reason": "no-story-key"})
        return

    sha = _resolve_story_sha(repo, story_key)
    if not sha:
        _append_receipt(
            verdicts,
            _base_receipt("review-skip", run_dir, story_key)
            | {"reason": "no-commit"},
        )
        return

    try:
        build_materials(story_key, sha, repo, base / story_key / "materials", contracts)
        manifest_path = build_manifest(
            story_key, sha, repo, base, lenses, check_path, identity
        )
    except Exception as exc:  # noqa: BLE001
        _append_receipt(
            verdicts,
            _base_receipt("review-skip", run_dir, story_key)
            | {"reason": "build-failed", "detail": str(exc)},
        )
        return

    _append_receipt(
        verdicts,
        _base_receipt("review-dispatch", run_dir, story_key)
        | {
            "sha": sha,
            "manifest": str(manifest_path),
            "lenses": list(lenses.keys()),
            "dry_run": dry_run,
        },
    )

    if dry_run:
        return

    try:
        rc, _msg = dispatch_ringer(manifest_path, ringer_path, identity)
    except Exception as exc:  # noqa: BLE001
        _append_receipt(
            verdicts,
            _base_receipt("review-skip", run_dir, story_key)
            | {"reason": "ringer-error", "detail": str(exc), "sha": sha},
        )
        return
    if rc != 0:
        _append_receipt(
            verdicts,
            _base_receipt("review-skip", run_dir, story_key)
            | {"reason": "ringer-failed", "exit": rc, "sha": sha},
        )
        return

    harvest_story(story_key, sha, base, lenses, run_dir)


def handle_run_paused(event: dict, run_dir: Path) -> None:
    raw = str(event.get("reason") or event.get("stage") or "")
    receipt = _base_receipt("run-paused", run_dir, event.get("story_key"))
    receipt["pause_class"] = _pause_class(raw)
    receipt["reason"] = raw
    _append_receipt(run_dir / "verdicts.jsonl", receipt)


def handle_deferred(event: dict, run_dir: Path, kind: str) -> None:
    receipt = _base_receipt("story-deferred", run_dir, event.get("story_key"))
    receipt["source_kind"] = kind
    # pass through raw fields (minus the kind we already captured)
    for k, v in event.items():
        if k == "kind":
            continue
        receipt.setdefault(k, v)
    _append_receipt(run_dir / "verdicts.jsonl", receipt)


def process_event(
    line: str,
    repo: Path,
    run_dir: Path,
    base: Path,
    lenses: dict[str, str],
    check_path: Path,
    ringer_path: Path,
    identity: str,
    contracts: Path | None,
    dry_run: bool,
) -> None:
    line = line.strip()
    if not line:
        return
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        return  # ignore unparseable lines silently
    if not isinstance(event, dict):
        return
    kind = event.get("kind")
    try:
        if kind == "story-done":
            handle_story_done(
                event, repo, run_dir, base, lenses, check_path,
                ringer_path, identity, contracts, dry_run,
            )
        elif kind == "run-paused":
            handle_run_paused(event, run_dir)
        elif kind in ("story-deferred", "escalation"):
            handle_deferred(event, run_dir, kind)
        # everything else -> ignore
    except Exception as exc:  # noqa: BLE001  — never kill the follow loop
        story = event.get("story_key") if isinstance(event, dict) else None
        _append_receipt(
            run_dir / "verdicts.jsonl",
            _base_receipt("review-skip", run_dir, story)
            | {"reason": "handler-exception", "detail": str(exc)},
        )


# --------------------------------------------------------------------------- #
# harvest-only mode
# --------------------------------------------------------------------------- #
def harvest_only(
    story_key: str,
    repo: Path,
    run_dir: Path,
    base: Path,
    lenses: dict[str, str],
) -> int:
    sha = _resolve_story_sha(repo, story_key) or ""
    harvest_story(story_key, sha, base, lenses, run_dir)
    return 0


# --------------------------------------------------------------------------- #
# journal tailing
# --------------------------------------------------------------------------- #
def replay(journal: Path, **handler_kw) -> None:
    with journal.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            process_event(line, **handler_kw)


def follow(journal: Path, **handler_kw) -> None:
    """tail -F semantics: read existing then tail live, survive truncation/rotate."""
    inode = None
    fh = None
    try:
        while True:
            try:
                if not journal.exists():
                    time.sleep(1.0)
                    continue
                cur_inode = journal.stat().st_ino
                if fh is None or inode != cur_inode:
                    if fh is not None:
                        fh.close()
                    fh = journal.open("r", encoding="utf-8", errors="replace")
                    inode = cur_inode
                line = fh.readline()
                if line:
                    process_event(line, **handler_kw)
                else:
                    time.sleep(0.5)
            except OSError:
                time.sleep(1.0)
    finally:
        if fh is not None:
            fh.close()


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="story_review_watcher",
        description="Tail a bmad-loop journal and write structured review "
        "receipts to <run-dir>/verdicts.jsonl.",
    )
    ap.add_argument("--repo", required=True, type=Path)
    ap.add_argument("--run-dir", type=Path, default=None)
    ap.add_argument("--base", type=Path, default=None)
    ap.add_argument("--lenses", default=DEFAULT_LENSES)
    ap.add_argument("--contracts", type=Path, default=None)
    ap.add_argument(
        "--check",
        type=Path,
        default=Path(__file__).resolve().parent / "checks" / "review_check.py",
    )
    ap.add_argument("--ringer", type=Path, default=None)
    ap.add_argument("--identity", default="story-review-watcher")
    ap.add_argument("--follow", action="store_true")
    ap.add_argument("--replay", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--harvest", default=None, metavar="STORY_KEY")
    args = ap.parse_args(argv)

    repo = args.repo.resolve()
    if not repo.is_dir():
        sys.exit(f"repo not found: {repo}")

    run_dir = args.run_dir.resolve() if args.run_dir else _default_run_dir(repo)
    if not run_dir.is_dir():
        sys.exit(2)

    base = args.base
    if base is None:
        base = Path.home() / ".ringer" / "work" / f"{_repo_basename(repo)}-story-reviews"
    base = base.resolve()

    lenses = _parse_lenses(args.lenses)

    ringer_path = args.ringer
    if ringer_path is None:
        ringer_path = repo / "ringer" / "ringer.py"
    ringer_path = ringer_path.resolve()

    contracts = args.contracts.resolve() if args.contracts else None

    journal = run_dir / "journal.jsonl"
    if args.harvest:
        return harvest_only(args.harvest, repo, run_dir, base, lenses)

    if not journal.is_file():
        sys.exit(f"journal not found: {journal}")

    handler_kw = dict(
        repo=repo,
        run_dir=run_dir,
        base=base,
        lenses=lenses,
        check_path=args.check,
        ringer_path=ringer_path,
        identity=args.identity,
        contracts=contracts,
        dry_run=args.dry_run,
    )

    if args.replay:
        replay(journal, **handler_kw)
        return 0

    follow(journal, **handler_kw)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
