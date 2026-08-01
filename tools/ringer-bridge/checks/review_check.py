#!/usr/bin/env python3
"""Executable check for ringer review-worker reports.

Validates SUBSTANCE, tolerant on format:
  - report exists, names the expected model, ends with a VERDICT line
  - >= --min-findings findings, each anchored to a file that actually exists
    in the scenario materials (flexible: any materials filename mentioned)
Prints WHY it fails.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def fail(msg: str) -> None:
    print(f"CHECK FAIL: {msg}")
    sys.exit(1)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", required=True)
    ap.add_argument("--materials", required=True)
    ap.add_argument("--expected-model", required=True)
    ap.add_argument("--min-findings", type=int, default=1)
    args = ap.parse_args()

    report_path = Path(args.report)
    if not report_path.is_file():
        fail(f"report missing: {report_path}")
    text = report_path.read_text(encoding="utf-8", errors="replace")
    low = text.lower()

    model_token = args.expected_model.split("/")[-1].split(":")[0].lower()
    if model_token not in low:
        fail(f"report never names its model (expected token '{model_token}')")

    if not re.search(r"^\s*VERDICT:\s*(APPROVE|FINDINGS)", text, re.M | re.I):
        fail("no final 'VERDICT: APPROVE|FINDINGS ...' line")

    materials_dir = Path(args.materials)
    if not materials_dir.is_dir():
        fail(f"materials dir missing: {materials_dir}")
    materials = {p.name for p in materials_dir.iterdir() if p.is_file()}
    anchored = set()
    for name in materials:
        if name.lower() in low:
            anchored.add(name)
    findings_blocks = re.findall(r"^\s*(?:\d+[.)]|[-*])\s+.{20,}", text, re.M)
    if len(findings_blocks) < args.min_findings:
        fail(
            f"only {len(findings_blocks)} finding-shaped entries; need >= {args.min_findings} "
            "(numbered or bulleted lines of substance)"
        )
    if not anchored:
        fail(f"no finding anchored to any material file ({sorted(materials)})")

    print(f"CHECK PASS: {len(findings_blocks)} findings, anchored to {sorted(anchored)}")


if __name__ == "__main__":
    main()
