#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.test_scheduler_122_derived.$$"
trap 'rm -f "$TMP"' EXIT INT TERM

# Preserve the complete scheduler/resource audit while rewriting one historical
# Python f-string whose expression embeds backslashes. Newer hosted Python
# parsers reject that syntax before the actual machine-code assertions execute.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_scheduler.sh').read_text(encoding='utf-8')
old='''Path('build/scheduler/fem_regions.txt').write_text(\n    '\\n'.join(f'{k}: vpaddq={len(re.findall(r"\\bvpaddq\\b", "\\n".join(v)))} vpandq={len(re.findall(r"\\bvpandq\\b", "\\n".join(v)))}' for k,v in regions.items())+'\\n')\n'''
new='''summary=[]\nfor k,v in regions.items():\n    body='\\n'.join(v)\n    addq=len(re.findall(r'\\bvpaddq\\b',body))\n    andq=len(re.findall(r'\\bvpandq\\b',body))\n    summary.append(f'{k}: vpaddq={addq} vpandq={andq}')\nPath('build/scheduler/fem_regions.txt').write_text('\\n'.join(summary)+'\\n')\n'''
if src.count(old) != 1:
    raise SystemExit('1.2.2 scheduler test derivation rejected: Python compatibility anchor changed')
Path(sys.argv[1]).write_text(src.replace(old,new,1),encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"
echo 'SCHEDULER_AUDIT_PYTHON_VERSION_INDEPENDENT_1_2_2=PASS'
