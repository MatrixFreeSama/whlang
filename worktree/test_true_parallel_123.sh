#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.true_parallel_123_derived.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM

# Preserve every 1.0.13 numeric, executor, fused-backedge, induction and no-call
# invariant. Only normalize GNU objdump's two spellings of EVEX qword broadcast:
# older `QWORD BCST [rip+...]` and newer `QWORD PTR [rip+...]{1to8}`.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_true_parallel_113.sh').read_text(encoding='utf-8')
old=r"m=re.search(r'vpaddq\s+zmm(\d+),zmm\1,QWORD BCST \[rip\+0x([0-9a-fA-F]+)\].*#\s*0x([0-9a-fA-F]+)',line)"
new=r"m=re.search(r'vpaddq\s+zmm(\d+),zmm\1,QWORD(?: BCST| PTR) \[rip\+0x([0-9a-fA-F]+)\](?:\{1to8\})?.*#\s*0x([0-9a-fA-F]+)',line)"
if src.count(old)!=1:
    raise SystemExit('1.2.3 true-parallel audit anchor changed')
src=src.replace(old,new,1)
src=src.replace("print('CROSS_VECTOR_AXIS_INDUCTION=PASS')",
                "print('TRUE_PARALLEL_OBJDUMP_BROADCAST_SYNTAX_INDEPENDENT_1_2_3=PASS')\nprint('CROSS_VECTOR_AXIS_INDUCTION=PASS')",1)
Path(sys.argv[1]).write_text(src,encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"
