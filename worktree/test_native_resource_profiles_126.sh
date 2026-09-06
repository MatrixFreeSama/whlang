#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
[ -x build/topologyc ] || ./build.sh >/dev/null
BASE125="$ROOT/../baseline125/worktree"

echo 'e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6  compiler/tensor_frontend_x86_64.S' | sha256sum -c -
echo '2e83af25b6a6188c9ce24497d636206ca5978e59a92b619e6b722909ad2d4f80  compiler/topologyc_x86_64.S' | sha256sum -c -
echo 'e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3  runtime/tensor_runtime_template_x86_64.S' | sha256sum -c -

if grep -Eini '\b(newton|stiffness|fem|cfd|poisson|kkt|fluid|solid|fsi|navier|elastic|electromagnetic|heat)\b' \
  surface/native_resource_profile.py tools/generate_native_resource_profiles.py \
  tools/generate_derived_native_backend.py wheelchairc.py whexc.py; then
  echo 'workload identity leaked into active native capability routing' >&2; exit 1
fi
if grep -En 'shared_dependency_episode|topologyc-sdep|shared_dependency_episode_wide_125|generate_rankn_backend_122|generated_122|runtime_rankn_offsets' \
  build.sh wheelchairc.py whexc.py surface/native_resource_profile.py \
  tools/generate_native_resource_profiles.py tools/generate_derived_native_backend.py; then
  echo 'retired special-purpose route leaked into active compiler path' >&2; exit 1
fi

grep -q 'stmxcsr dword ptr \[rsp\]' build/tensor_frontend_profile_base.S
grep -q 'mov dword ptr \[rsp+4\],0x1f80' build/tensor_frontend_profile_base.S
grep -q 'ldmxcsr dword ptr \[rsp+4\]' build/tensor_frontend_profile_base.S
grep -q 'ldmxcsr dword ptr \[rsp\]' build/tensor_frontend_profile_base.S
grep -q 'ZMM16..29 shared persistent ownership domain' build/tensor_frontend_profile_wide.S
grep -q 'ZMM30..31 constant ownership domain' build/tensor_frontend_profile_wide.S
if grep -Eq 'ZMM14\.\.|ZMM15\.\.' build/tensor_frontend_profile_wide.S; then
  echo 'runtime-reserved ZMM14/15 leaked into expanded register profile' >&2; exit 1
fi

PYTHONPATH=surface python3 - <<'PY'
from pathlib import Path
import whex_surface
from native_resource_profile import analyze
cases=[
 ('../benchmarks/newton_jv/mature.whex',5,'base'),
 ('../benchmarks/global_operator_124/stiffness.whex',6,'base'),
 ('../benchmarks/fluid_solid_coupling_124/fsi_decoupled.whex',11,'wide'),
 ('../benchmarks/fluid_solid_coupling_124/fsi_coupled.whex',12,'wide'),
 ('tests/whex/rank6_native_122.whex',0,'derived'),
]
for path,pressure,backend in cases:
    data,_,_=whex_surface.load_surface(Path(path)); p=analyze(data)
    assert p['distinct_structural_loads']==pressure,(path,p)
    assert p['backend_class']==backend,(path,p)
    assert p['runtime_dispatch'] is False and p['workload_dispatch'] is False
    assert p['source_path_dispatch'] is False and p['benchmark_dispatch'] is False
    assert p['runtime_cost_selector'] is False
    assert p['scalar_fallback']==0 and p['hidden_serial_fallback']==0
    assert p['resource_shortage_scalarization']==0
    print(path,pressure,backend)
print('NATIVE_RESOURCE_PROFILE_STRUCTURAL_ADMISSION=PASS')
print('NATIVE_RESOURCE_PROFILE_WORKLOAD_DISPATCH=0')
print('NATIVE_RESOURCE_PROFILE_RUNTIME_SELECTOR=0')
PY

PYTHONPATH=surface python3 - <<'PY'
from pathlib import Path
import wh_structural,whex_surface
wh,_,_=wh_structural.load_surface(Path('../benchmarks/fluid_solid_coupling_124/fsi_coupled.wh'))
wx,_,_=whex_surface.load_surface(Path('../benchmarks/fluid_solid_coupling_124/fsi_coupled.whex'))
a=wh_structural.canonical_core_bytes(wh)
b=whex_surface.canonical_core_bytes(wx)
assert a==b,(len(a),len(b),wh_structural.core_hash(wh),whex_surface.core_hash(wx))
Path('/tmp/profile_shared.core.wh').write_bytes(a)
print('WH_WHEX_WIDE_CANONICAL_BYTE_EQUIVALENCE=PASS')
print('WH_WHEX_WIDE_CANONICAL_SHA256='+wh_structural.core_hash(wh))
PY

[ -x "$BASE125/build/topologyc-sdep" ]
objcopy -O binary build/topologyc-wide /tmp/topologyc_wide.loadable.bin
objcopy -O binary "$BASE125/build/topologyc-sdep" /tmp/topologyc_sdep125.loadable.bin
cmp /tmp/topologyc_wide.loadable.bin /tmp/topologyc_sdep125.loadable.bin
echo 'WIDE_PROFILE_1_2_5_LOADABLE_BYTE_IDENTITY=PASS'

# AOT cross-target authority: host ISA must not decide whether we can compare the
# AVX-512F target image.
"$BASE125/build/topologyc-sdep" /tmp/profile_shared.core.wh -o build/profile_baseline125_direct --isa-limit avx512f
build/topologyc-wide /tmp/profile_shared.core.wh -o build/profile_direct_wide --isa-limit avx512f
cmp build/profile_baseline125_direct build/profile_direct_wide
echo 'WIDE_PROFILE_SAME_CORE_NATIVE_BYTE_IDENTITY=PASS'

./wheelchairc ../benchmarks/fluid_solid_coupling_124/fsi_coupled.wh -o build/profile_wh --executors 1 --isa-limit avx512f --semantic-plan /tmp/profile_wh.plan.json >/tmp/profile_wh.json
./whexc ../benchmarks/fluid_solid_coupling_124/fsi_coupled.whex -o build/profile_whex --executors 1 --isa-limit avx512f --semantic-plan /tmp/profile_whex.plan.json >/tmp/profile_whex.json
cmp build/profile_wh build/profile_whex
cmp build/profile_wh build/profile_direct_wide
python3 - <<'PY'
import json
w=json.load(open('/tmp/profile_wh.plan.json'))['native_resource_profile']
x=json.load(open('/tmp/profile_whex.plan.json'))['native_resource_profile']
assert w==x,(w,x)
assert w['backend_class']=='wide',w
print('WH_WHEX_NATIVE_RESOURCE_PROFILE_EQUIVALENCE=PASS')
PY

echo 'WH_WHEX_WIDE_NATIVE_BYTE_EQUIVALENCE=PASS'

if grep -qm1 -w avx512f /proc/cpuinfo; then
  [ "$(build/profile_wh 10000000)" = 'checksum_bits=0x4130e896f42e1dd6' ]
  echo 'HOST_AVX512_QUALIFIED=1'
  echo 'NATIVE_RESOURCE_PROFILE_NUMERIC_REFERENCE=PASS'
else
  echo 'HOST_AVX512_QUALIFIED=0'
  echo 'NATIVE_RESOURCE_PROFILE_NUMERIC_REFERENCE=SKIP_HOST_NOT_AVX512F'
fi

sh tools/disassemble_generated.sh build/profile_whex > /tmp/profile_wide.dis 2>&1
python3 - <<'PY'
from pathlib import Path
import re
rows=[]; targets=[]
for line in Path('/tmp/profile_wide.dis').read_text(errors='replace').lower().splitlines():
    m=re.match(r'\s*([0-9a-f]+):\s+(?:[0-9a-f]{2}\s+)+\s*([a-z][a-z0-9.]*)\b',line)
    if not m: continue
    addr=int(m.group(1),16); ins=m.group(2); rows.append((addr,ins,line))
    t=re.search(r'#\s*0x([0-9a-f]+)',line)
    if t: targets.append(int(t.group(1),16))
assert targets
limit=min(targets)
hot=[r for r in rows if r[0] < limit]
count=lambda p:sum(ins.startswith(p) for _,ins,_ in hot)
assert count('vdivpd')==0,count('vdivpd')
assert count('call')==0,count('call')
print('NATIVE_RESOURCE_PROFILE_WIDE_VDIVPD=0')
print('NATIVE_RESOURCE_PROFILE_WIDE_REACHABLE_CALLS=0')
PY

echo 'NATIVE_RESOURCE_PROFILE_RUNTIME_ABI_ZMM12_15_PROTECTED=PASS'
echo 'NATIVE_RESOURCE_PROFILE_SPECIAL_PURPOSE_ROUTE=0'
echo 'WHEELCHAIR_NATIVE_RESOURCE_PROFILES_1_2_6=PASS'
