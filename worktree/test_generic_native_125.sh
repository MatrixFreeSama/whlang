#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.test_generic_native_125_derived.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_generic_native_124.sh').read_text(encoding='utf-8')
src=src.replace('[ "$(cat VERSION)" = "1.2.4" ]','[ "$(cat VERSION)" = "1.2.5" ]',1)
Path(sys.argv[1]).write_text(src,encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"
echo 'WHEELCHAIR_1_2_4_GENERIC_NATIVE_PEAKS_ON_1_2_5=PASS'
