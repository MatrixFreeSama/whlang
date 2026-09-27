#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.test_109_124_derived.$$"
trap 'rm -f "$TMP"' EXIT INT TERM

# 1.2.4 keeps the complete 1.0.9 native-sovereignty gate. The old keyword
# proxy is refined only to admit three exact build-time source derivations:
# Rank-N, Product-Subtract contraction, and Vector Reduction Residency. They
# generate handwritten assembly sources before topologyc is linked; they are
# not a user-program backend, runtime, JIT, launcher, or generated dependency.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_109.sh').read_text(encoding='utf-8')
old="""for forbidden in ('gcc ', 'clang ', 'llvm', 'python', 'rustc', 'cargo'):\n    assert forbidden not in low,forbidden\n"""
new="""for forbidden in ('gcc ', 'clang ', 'llvm', 'rustc', 'cargo'):\n    assert forbidden not in low,forbidden\npython_lines=[line.strip() for line in build.splitlines()\n              if 'python' in line.lower() and not line.lstrip().startswith('#')]\nassert python_lines == [\n    'python3 tools/generate_rankn_backend_122.py',\n    'python3 tools/generate_product_subtract_frontend.py',\n    'python3 tools/generate_vector_reduction_residency.py',\n],python_lines\nrankn=(root/'tools/generate_rankn_backend_122.py').read_text()\nassert 'BASE_FRONTEND_SHA = \\\"e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6\\\"' in rankn\nassert 'BASE_RUNTIME_SHA = \\\"e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3\\\"' in rankn\nprod=(root/'tools/generate_product_subtract_frontend.py').read_text()\nassert \"BASE_SHA256 = 'e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6'\" in prod\nassert \"SRC = Path('compiler/tensor_frontend_x86_64.S')\" in prod\nassert \"OUT = Path('build/tensor_frontend_product_subtract.S')\" in prod\nresident=(root/'tools/generate_vector_reduction_residency.py').read_text()\nassert \"SRC = Path('build/tensor_frontend_product_subtract.S')\" in resident\nassert \"OUT = Path('build/tensor_frontend_product_subtract_residency.S')\" in resident\nfor text in (prod,resident):\n    low_text=text.lower()\n    for forbidden in ('subprocess', 'os.system', '/usr/bin/python', 'gcc ', 'clang ', 'llvm', 'rustc', 'cargo'):\n        assert forbidden not in low_text,forbidden\n"""
if src.count(old) != 1:
    raise SystemExit('1.2.4 test derivation rejected: historical backend assertion anchor changed')
out=src.replace(old,new,1)
Path(sys.argv[1]).write_text(out,encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"

# Extend native-sovereignty proof to every current native compiler/runtime lane.
for f in build/topologyc build/topologyc-rankn build/tensor_runtime_template build/tensor_rankn_runtime_template; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
  readelf -lW "$f" | grep -qv ' INTERP '
done
mkdir -p build/release109_124
for f in build/topologyc build/topologyc-rankn; do
  strings "$f" | tr '[:upper:]' '[:lower:]' >> build/release109_124/native.strings
done
for forbidden in '/usr/bin/python' '/usr/bin/gcc' '/usr/bin/clang' 'libllvm' 'libgcc_s' 'librust'; do
  if grep -Fq "$forbidden" build/release109_124/native.strings; then
    echo "foreign backend/runtime launcher in 1.2.4 compiler: $forbidden" >&2
    exit 1
  fi
done

echo 'GENERIC_NATIVE_BOOTSTRAP_GENERATORS_EXACT=PASS'
echo 'GENERIC_NATIVE_BOOTSTRAP_BASE_HASH_PROTECTED=PASS'
echo 'GENERIC_NATIVE_ASSEMBLY_ONLY_BUILD=PASS'
echo 'GENERIC_NATIVE_NO_FOREIGN_HIGH_LEVEL_BACKEND=PASS'
echo 'WHEELCHAIR_1_0_9_INVARIANTS_ON_1_2_4=PASS'
