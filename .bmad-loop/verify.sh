#!/usr/bin/env bash
# Seed default verify gate — structural floor so [verify] is never empty (Atlas
# lesson #2). Projects should REPLACE this with their real deterministic gate
# (npm test, pytest -q, ...). BOM-tolerant JSON check (PowerShell Out-File emits BOMs).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, sys
fail = 0
for p in list(pathlib.Path('.').glob('_bmad-output/**/*.json'))[:300]:
    try: json.loads(p.read_text(encoding='utf-8-sig'))
    except Exception as e: print(f"verify: INVALID JSON {p}: {e}"); fail = 1
print("verify: PASS (structural seed gate)" if not fail else "verify: FAIL"); sys.exit(fail)
PY
