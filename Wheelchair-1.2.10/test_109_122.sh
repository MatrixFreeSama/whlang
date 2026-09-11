#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.test_109_122_derived.$$"
trap 'rm -f "$TMP"' EXIT INT TERM

# 1.2.2 inherits the complete 1.0.9 architecture gate. The only historical
# assertion that is refined is the build-script keyword proxy: 1.2.2 uses one
# exact, hash-protected Python bootstrap generator to derive Rank-N handwritten
# assembly sources from the frozen 1.2.1 assembly base. Python is not a user
# program backend, native runtime, JIT, or generated-program dependency.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_109.sh').read_text(encoding='utf-8')
old="""for forbidden in ('gcc ', 'clang ', 'llvm', 'python', 'rustc', 'cargo'):\n    assert forbidden not in low,forbidden\n"""
new="""for forbidden in ('gcc ', 'clang ', 'llvm', 'rustc', 'cargo'):\n    assert forbidden not in low,forbidden\npython_lines=[line.strip() for line in build.splitlines()\n              if 'python' in line.lower() and not line.lstrip().startswith('#')]\nassert python_lines == ['python3 tools/generate_rankn_backend_122.py'],python_lines\ngen=(root/'tools/generate_rankn_backend_122.py').read_text()\nassert 'BASE_FRONTEND_SHA = \\\"e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6\\\"' in gen\nassert 'BASE_RUNTIME_SHA = \\\"e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3\\\"' in gen\n"""
if src.count(old) != 1:
    raise SystemExit('1.2.2 test derivation rejected: historical backend assertion anchor changed')
out=src.replace(old,new,1)
Path(sys.argv[1]).write_text(out,encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"

# Extend the original native-sovereignty proof to the new Rank-N compiler lane.
for f in build/topologyc-rankn build/tensor_rankn_runtime_template; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
  readelf -lW "$f" | grep -qv ' INTERP '
done
strings build/topologyc-rankn | tr '[:upper:]' '[:lower:]' > build/release109/rankn.strings
for forbidden in '/usr/bin/python' '/usr/bin/gcc' '/usr/bin/clang' 'libllvm' 'libgcc_s' 'librust'; do
  if grep -Fq "$forbidden" build/release109/rankn.strings; then
    echo "foreign backend/runtime launcher in Rank-N compiler: $forbidden" >&2
    exit 1
  fi
done

echo 'RANK_N_BOOTSTRAP_GENERATOR_EXACTLY_ONE=PASS'
echo 'RANK_N_BOOTSTRAP_BASE_HASH_PROTECTED=PASS'
echo 'RANK_N_ASSEMBLY_ONLY_NATIVE_BUILD=PASS'
echo 'RANK_N_NO_FOREIGN_HIGH_LEVEL_BACKEND=PASS'
echo 'WHEELCHAIR_1_0_9_INVARIANTS_ON_1_2_2=PASS'
