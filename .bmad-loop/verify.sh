#!/usr/bin/env bash
# Council deterministic verify gate: every JSON artifact parses (BOM-tolerant —
# PowerShell Out-File emits UTF-8 BOM; note: strict consumers need utf-8-sig)
# + sprint status present.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, sys
fail = 0
for p in list(pathlib.Path('_bmad-output').rglob('*.json'))[:300]:
    try:
        json.loads(p.read_text(encoding='utf-8-sig'))
    except Exception as e:
        print(f"verify: INVALID JSON {p}: {e}"); fail = 1
if not pathlib.Path('_bmad-output/implementation-artifacts/sprint-status.yaml').is_file():
    print("verify: no sprint-status"); fail = 1
print("verify: PASS" if not fail else "verify: FAIL"); sys.exit(fail)
PY
