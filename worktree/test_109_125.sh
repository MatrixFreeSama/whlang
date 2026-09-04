#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.test_109_125_derived.$$"
trap 'rm -f "$TMP"' EXIT INT TERM
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_109.sh').read_text(encoding='utf-8')
old="""for forbidden in ('gcc ', 'clang ', 'llvm', 'python', 'rustc', 'cargo'):\n    assert forbidden not in low,forbidden\n"""
new="""for forbidden in ('gcc ', 'clang ', 'llvm', 'rustc', 'cargo'):\n    assert forbidden not in low,forbidden\npython_lines=[line.strip() for line in build.splitlines() if 'python' in line.lower() and not line.lstrip().startswith('#')]\nassert python_lines == [\n    'python3 tools/generate_rankn_backend_122.py',\n    'python3 tools/generate_product_subtract_frontend.py',\n    'python3 tools/generate_vector_reduction_residency.py',\n    'python3 tools/generate_shared_dependency_episode_125.py',\n],python_lines\nfor name in ('generate_rankn_backend_122.py','generate_product_subtract_frontend.py','generate_vector_reduction_residency.py','generate_shared_dependency_episode_125.py'):\n    text=(root/'tools'/name).read_text().lower()\n    for forbidden in ('subprocess','os.system','/usr/bin/python','gcc ','clang ','llvm','rustc','cargo'):\n        assert forbidden not in text,(name,forbidden)\n"""
if src.count(old)!=1: raise SystemExit('1.2.5 sovereignty derivation anchor changed')
Path(sys.argv[1]).write_text(src.replace(old,new,1),encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"
for f in build/topologyc build/topologyc-sdep build/topologyc-rankn build/tensor_runtime_template build/tensor_rankn_runtime_template; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
  readelf -lW "$f" | grep -qv ' INTERP '
done
mkdir -p build/release109_125
for f in build/topologyc build/topologyc-sdep build/topologyc-rankn; do strings "$f" | tr '[:upper:]' '[:lower:]' >> build/release109_125/native.strings; done
for forbidden in '/usr/bin/python' '/usr/bin/gcc' '/usr/bin/clang' 'libllvm' 'libgcc_s' 'librust'; do
  if grep -Fq "$forbidden" build/release109_125/native.strings; then echo "foreign backend/runtime launcher: $forbidden" >&2; exit 1; fi
done
echo 'SHARED_DEPENDENCY_BOOTSTRAP_GENERATOR_EXACT=PASS'
echo 'SHARED_DEPENDENCY_ASSEMBLY_ONLY_BUILD=PASS'
echo 'SHARED_DEPENDENCY_NO_FOREIGN_HIGH_LEVEL_BACKEND=PASS'
echo 'WHEELCHAIR_1_0_9_INVARIANTS_ON_1_2_5=PASS'
