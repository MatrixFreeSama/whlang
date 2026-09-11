#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.test_complete_123_for_124.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM

python3 tools/apply_123.py
sh build.sh

# Preserve the entire mature 1.2.3 authority. The only inherited audit refined
# for 1.2.4 is the historical 1.0.9 build-keyword proxy, which now admits the
# exact, build-time assembly derivations proven by test_109_124.sh.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_complete_123.sh').read_text(encoding='utf-8')
old="src=src.replace('./test_109.sh','sh test_109_122.sh')"
new="src=src.replace('./test_109.sh','sh test_109_124.sh')"
if src.count(old)!=1:
    raise SystemExit('1.2.4 complete derivation rejected: 1.0.9 gate anchor changed')
Path(sys.argv[1]).write_text(src.replace(old,new,1),encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"

# Historical gates may rebuild outputs. Rebuild the accepted final 1.2.4 lane
# before the new structural/native authority.
sh build.sh
sh test_generic_native_124.sh

echo 'WHEELCHAIR_1_2_3_COMPLETE_ON_1_2_4=PASS'
echo 'WHEELCHAIR_GENERIC_NATIVE_1_2_4=PASS'
echo 'WHEELCHAIR_1_2_4_COMPLETE=PASS'
