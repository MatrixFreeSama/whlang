#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
[ "$(cat VERSION)" = "1.2.5" ]

echo 'e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6  compiler/tensor_frontend_x86_64.S' | sha256sum -c -
echo '2e83af25b6a6188c9ce24497d636206ca5978e59a92b619e6b722909ad2d4f80  compiler/topologyc_x86_64.S' | sha256sum -c -
echo 'e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3  runtime/tensor_runtime_template_x86_64.S' | sha256sum -c -

if grep -Eini '\b(newton|stiffness|fem|cfd|poisson|kkt|fluid|solid|fsi|navier|elastic|electromagnetic)\b' \
  tools/generate_shared_dependency_episode_125.py surface/shared_dependency_episode.py; then
  echo 'workload-name dispatch leaked into shared dependency episode optimizer' >&2; exit 1
fi

sh build.sh >/dev/null
as --64 build/tensor_frontend_product_subtract_residency.S -o build/tensor_frontend_124_exact.o
ld -nostdlib -static -z noexecstack \
  build/topologyc_core.o build/tensor_frontend_124_exact.o build/general_frontend.o \
  build/runtime_blob.o build/general_runtime_blob.o -o build/topologyc-124-exact

PYTHONPATH=surface python3 - <<'PY'
from pathlib import Path
import whex_surface
from shared_dependency_episode import analyze
for path,pressure,recipe in [
 ('../benchmarks/newton_jv/mature.whex',5,'legacy_1_2_4'),
 ('../benchmarks/global_operator_124/stiffness.whex',6,'legacy_1_2_4'),
 ('../benchmarks/fluid_solid_coupling_124/fsi_decoupled.whex',11,'shared_dependency_episode_wide_125'),
 ('../benchmarks/fluid_solid_coupling_124/fsi_coupled.whex',12,'shared_dependency_episode_wide_125'),
]:
 data,_,_=whex_surface.load_surface(Path(path)); p=analyze(data)
 assert p['distinct_structural_loads']==pressure,(path,p)
 assert p['recipe']==recipe,(path,p)
 assert p['runtime_dispatch'] is False and p['workload_dispatch'] is False
 assert p['scalar_fallback']==0 and p['hidden_serial_fallback']==0
 assert p['resource_shortage_scalarization']==0
 print(path,pressure,recipe)
PY

echo 'SHARED_DEPENDENCY_EPISODE_STRUCTURAL_ADMISSION=PASS'
echo 'SHARED_DEPENDENCY_EPISODE_NO_WORKLOAD_DISPATCH=PASS'
echo 'SHARED_DEPENDENCY_EPISODE_RUNTIME_DISPATCH=0'
echo 'SHARED_DEPENDENCY_EPISODE_SCALAR_FALLBACK=0'

compile_exact124() {
  src=$1 out=$2 q=$3
  PYTHONPATH=surface python3 - "$src" /tmp/sde125.core <<'PY'
import sys
from pathlib import Path
import whex_surface
p=Path(sys.argv[1]); data,_,_=whex_surface.load_surface(p)
Path(sys.argv[2]).write_bytes(whex_surface.canonical_core_bytes(data))
PY
  cmd="build/topologyc-124-exact /tmp/sde125.core -o $out"
  [ "$q" = 1 ] || cmd="$cmd --executors $q"
  sh -c "$cmd"
}
for q in 1 2 4; do
  compile_exact124 ../benchmarks/newton_jv/mature.whex "build/newton125_old_q$q" "$q"
  ./whexc ../benchmarks/newton_jv/mature.whex -o "build/newton125_new_q$q" --executors "$q" >/dev/null
  cmp "build/newton125_old_q$q" "build/newton125_new_q$q"
  compile_exact124 ../benchmarks/global_operator_124/stiffness.whex "build/stiff125_old_q$q" "$q"
  ./whexc ../benchmarks/global_operator_124/stiffness.whex -o "build/stiff125_new_q$q" --executors "$q" >/dev/null
  cmp "build/stiff125_old_q$q" "build/stiff125_new_q$q"
done
echo 'NEWTON_JV_NATIVE_BYTE_IDENTITY_ON_1_2_5=PASS'
echo 'GLOBAL_STIFFNESS_NATIVE_BYTE_IDENTITY_ON_1_2_5=PASS'

./wheelchairc ../benchmarks/fluid_solid_coupling_124/fsi_coupled.wh -o build/sde125_wh --executors 1 >/tmp/sde125_wh.json
./whexc ../benchmarks/fluid_solid_coupling_124/fsi_coupled.whex -o build/sde125_whex --executors 1 >/tmp/sde125_whex.json
cmp build/sde125_wh build/sde125_whex
[ "$(build/sde125_wh 10000000)" = 'checksum_bits=0x4130e896f42e1dd6' ]
echo 'WH_WHEX_SHARED_DEPENDENCY_NATIVE_BYTE_EQUIVALENCE=PASS'
echo 'SHARED_DEPENDENCY_NUMERIC_REFERENCE=PASS'

compile_exact124 ../benchmarks/fluid_solid_coupling_124/fsi_coupled.whex build/sde125_old 1
sh tools/disassemble_generated.sh build/sde125_old > /tmp/sde125_old.dis 2>&1
sh tools/disassemble_generated.sh build/sde125_whex > /tmp/sde125_new.dis 2>&1
python3 - <<'PY'
from pathlib import Path
import re

def hot(path):
    rows=[]; targets=[]
    for line in Path(path).read_text(errors='replace').lower().splitlines():
        m=re.match(r'\s*([0-9a-f]+):\s+(?:[0-9a-f]{2}\s+)+\s*([a-z][a-z0-9.]*)\b',line)
        if not m: continue
        addr=int(m.group(1),16); ins=m.group(2); rows.append((addr,ins,line))
        t=re.search(r'#\s*0x([0-9a-f]+)',line)
        if t: targets.append(int(t.group(1),16))
    data=min(targets)
    return [r for r in rows if r[0] < data]
old=hot('/tmp/sde125_old.dis'); new=hot('/tmp/sde125_new.dis')
def count(rows,p): return sum(ins.startswith(p) for _,ins,_ in rows)
print('SDE_OLD_HOT_INSTRUCTIONS=%d'%len(old))
print('SDE_NEW_HOT_INSTRUCTIONS=%d'%len(new))
print('SDE_OLD_VDIVPD=%d'%count(old,'vdivpd'))
print('SDE_NEW_VDIVPD=%d'%count(new,'vdivpd'))
print('SDE_NEW_REACHABLE_CALLS=%d'%count(new,'call'))
assert count(old,'vdivpd') > 0
assert count(new,'vdivpd') == 0
assert count(new,'call') == 0
assert len(new) < len(old)*0.80,(len(old),len(new))
PY

echo 'TOLERANT_LITERAL_RECIPROCAL_ERASURE=PASS'
echo 'SHARED_DEPENDENCY_HOT_CODE_CONTRACTION=PASS'
echo 'SHARED_DEPENDENCY_REACHABLE_CALL_EDGES=0'

grep -q 'ZMM16..29 shared persistent ownership domain' build/tensor_frontend_shared_wide_125.S
grep -q 'ZMM30..31 constant ownership domain' build/tensor_frontend_shared_wide_125.S
if grep -Eq 'ZMM14\.\.|ZMM15\.\.' build/tensor_frontend_shared_wide_125.S; then
  echo 'runtime-reserved ZMM14/15 leaked into wide ownership recipe' >&2; exit 1
fi
echo 'SHARED_DEPENDENCY_RUNTIME_ABI_ZMM12_15_PROTECTED=PASS'
echo 'WHEELCHAIR_SHARED_DEPENDENCY_EPISODE_1_2_5=PASS'
