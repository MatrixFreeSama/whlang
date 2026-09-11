#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

sh tools/relink_native256_mature_128.sh 2>&1 | tee /tmp/build128.log
grep -Fq 'NATIVE256_I64_MUL_TEMPORARIES=1' /tmp/build128.log
grep -Fq 'NATIVE256_SMALL_CONSTANT_ALLOCATOR_TEMPS=0' /tmp/build128.log
grep -Fq 'NATIVE256_I64_F64_CONVERT_TEMPORARIES=1' /tmp/build128.log
grep -Fq 'NATIVE256_PACK_HIDDEN_SCRATCH=0' /tmp/build128.log
grep -Fq 'NATIVE256_WORKLOAD_SPECIALIZATION=0' /tmp/build128.log
grep -Fq 'NATIVE256_SCALAR_FALLBACK=0' /tmp/build128.log
grep -Fq 'NATIVE256_CONST_SHIFT_COUNT_CALLEE_SAVED=PASS' /tmp/build128.log
grep -Fq 'NATIVE256_NORMAL_BUILD_PRESSURE_MATURITY=PASS' /tmp/build128.log
grep -Fq 'NATIVE256_NORMAL_BUILD_LIVERANGE_MATURITY=PASS' /tmp/build128.log
grep -Fq 'NATIVE256_POST_FINALIZE_BUILD_AUTHORITY=PASS' /tmp/build128.log
grep -Fq 'NATIVE256_FIXUP_LEDGER_SIZING=PASS' /tmp/build128.log
grep -Fq 'NATIVE256_NORMAL_BUILD_MATURITY_AUTHORITY=PASS' /tmp/build128.log
grep -Fq 'NATIVE256_SECOND_STAGE_DIAGNOSTIC_INJECTION=0' /tmp/build128.log
grep -Fq 'NATIVE256_SECOND_STAGE_RELINK=0' /tmp/build128.log
grep -Fq 'WHEELCHAIR_BUILD=PASS' /tmp/build128.log

sh test_native256_physicalizer_127.sh | tee /tmp/native256-127-regression.log
grep -Fq 'WHEELCHAIR_NATIVE256_1_2_7=PASS' /tmp/native256-127-regression.log

for q in 1 2 4; do
  python3 whexc.py ../benchmarks/fluid_solid_coupling_124/fsi_coupled.whex \
    -o "build/fsi_cpl_avx2_q${q}" --executors "$q" --isa-limit avx2 \
    --semantic-plan "/tmp/fsi_plan_q${q}.json" > "/tmp/fsi_driver_q${q}.json"
  python3 - "$q" <<'PY'
import json,sys
q=sys.argv[1]
p=json.load(open(f'/tmp/fsi_plan_q{q}.json'))
b=p['native_physical_backend']
assert b['physical_shape']=='native256', b
assert b['compiler_image'].endswith('native256'), b
assert b['runtime_selector']==0 and b['runtime_profitability_selector']==0, b
assert b['scalar_fallback']==0, b
print(f'FSI_Q{q}_NATIVE256_AOT=PASS')
PY
done
echo 'NATIVE256_HIGH_PRESSURE_COUPLED_COMPILE=PASS'

COMMON='-O3 -flto -ffast-math -mprefer-vector-width=256 -mavx2 -mfma -mbmi -mbmi2 -mpopcnt -mno-avx512f -mno-avx512dq -mno-avx512vl -pthread'
gcc $COMMON -DCOUPLED_MODE=1 ../benchmarks/fluid_solid_coupling_124/Fluid_Solid_expert_C_matched.c -o build/fsi_c_avx2
objdump -d build/fsi_c_avx2 > /tmp/c_avx2.dis
if grep -Eq '%zmm[0-9]+|%k[1-7]([^0-9]|$)' /tmp/c_avx2.dis; then
  echo 'expert C AVX2 binary leaked AVX-512 state' >&2
  exit 1
fi
grep -Eq '%ymm[0-9]+' /tmp/c_avx2.dis

audit_rx () {
  elf=$1
  raw=$2
  dis=$3
  python3 - "$elf" "$raw" <<'PY'
import struct,sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes()
assert b[:4]==b'\x7fELF' and b[4]==2 and b[5]==1
phoff=struct.unpack_from('<Q',b,32)[0]
entsz=struct.unpack_from('<H',b,54)[0]
num=struct.unpack_from('<H',b,56)[0]
out=bytearray(); seen=0
for i in range(num):
    p=phoff+i*entsz
    typ,flags=struct.unpack_from('<II',b,p)
    off=struct.unpack_from('<Q',b,p+8)[0]
    sz=struct.unpack_from('<Q',b,p+32)[0]
    if typ==1 and (flags&1) and sz:
        if out: out.extend(b'\x90'*16)
        out.extend(b[off:off+sz]); seen+=1
assert seen>=2, seen
Path(sys.argv[2]).write_bytes(out)
PY
  objdump -D -b binary -m i386:x86-64 "$raw" > "$dis"
  grep -Eq '%ymm[0-9]+' "$dis"
  if grep -Eq '%zmm[0-9]+|%k[1-7]([^0-9]|$)' "$dis"; then
    echo "native256 executable leaked AVX-512 state: $elf" >&2
    exit 1
  fi
}
for q in 1 2 4; do
  audit_rx "build/fsi_cpl_avx2_q${q}" "/tmp/fsi_q${q}.rx" "/tmp/fsi_q${q}.dis"
done
echo 'NATIVE256_HIGH_PRESSURE_AVX2_YMM_ONLY=PASS'

python3 - <<'PY'
import re,struct,subprocess
from pathlib import Path
B=Path('build')
def run(cmd): return subprocess.check_output(cmd,text=True).strip()
def val(s):
    m=re.search(r'0x([0-9a-fA-F]+)',s); assert m,s
    bits=int(m.group(1),16)
    return struct.unpack('>d',bits.to_bytes(8,'big'))[0]
for n in (4,17,100000,10000000):
    for q in (1,2,4):
        w=run([str(B/f'fsi_cpl_avx2_q{q}'),str(n)])
        c=run([str(B/'fsi_c_avx2'),str(n),str(q)])
        rel=abs(val(w)-val(c))/max(abs(val(c)),1.0)
        assert rel <= 1e-8,(n,q,w,c,rel)
        print(f'FSI_AVX2_NUMERIC N={n} Q={q} REL={rel:.3e} PASS')
print('NATIVE256_HIGH_PRESSURE_COUPLED_EXECUTION=PASS')
PY

python3 - <<'PY'
from pathlib import Path
files=[
 Path('build/generated_native256/tensor_frontend_base_native256.S'),
 Path('build/generated_native256/tensor_frontend_wide_native256.S'),
 Path('build/generated_native256/tensor_frontend_derived_native256.S'),
]
forbidden=('fsi','fluid','solid','newton','stiffness','poisson')
for p in files:
    low=p.read_text().lower()
    hits=[w for w in forbidden if w in low]
    assert not hits,(p,hits)
print('NATIVE256_GENERATED_WORKLOAD_BLIND=PASS')
PY

echo 'NATIVE256_MATURE_SPECIAL_PURPOSE_ROUTE=0'
echo 'NATIVE256_RUNTIME_SELECTOR=0'
echo 'NATIVE256_SCALAR_FALLBACK=0'
echo 'WHEELCHAIR_NATIVE256_MATURITY_1_2_8=PASS'
