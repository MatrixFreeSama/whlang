#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

[ -x build/topologyc-native256 ]
[ -x build/topologyc-wide-native256 ]
[ -x build/topologyc-derived-native256 ]

./build/topologyc --probe > /tmp/wheelchair127_probe.txt
grep -Fq 'AVX2: available' /tmp/wheelchair127_probe.txt || {
  echo 'NATIVE256_REAL_ELF_EXECUTION=FAIL_HOST_NOT_AVX2' >&2
  exit 1
}

SRC=testdata/generic_vector_equivalence_127.whex
OUT=/tmp/wheelchair127-native256.elf
PLAN=/tmp/wheelchair127-native256-plan.json
AUTO=/tmp/wheelchair127-auto.elf
AUTOPLAN=/tmp/wheelchair127-auto-plan.json
rm -f "$OUT" "$PLAN" "$AUTO" "$AUTOPLAN"

# Forced AVX2 is an AOT capability ceiling. It must select the generic
# native256 physicalizer regardless of whether a wider ISA exists on the host.
python3 whexc.py "$SRC" -o "$OUT" --executors 1 --isa-limit avx2 --semantic-plan "$PLAN" \
  > /tmp/wheelchair127-native256-driver.json

python3 - <<'PY'
import json
from pathlib import Path
p=json.loads(Path('/tmp/wheelchair127-native256-plan.json').read_text())
b=p['native_physical_backend']
assert b['physical_shape']=='native256', b
assert b['compiler_image'].endswith('native256'), b
assert b['selection_authority']=='native_topologyc_silicon_audit', b
assert b['aot_only'] is True, b
assert b['workload_dispatch']==0, b
assert b['source_path_dispatch']==0, b
assert b['benchmark_dispatch']==0, b
assert b['runtime_selector']==0, b
assert b['runtime_profitability_selector']==0, b
assert b['scalar_fallback']==0, b
assert b['python_native_authority'] is False, b
print('NATIVE256_AOT_MATRIX_SELECTION=PASS')
PY

readelf -d "$OUT" 2>&1 | grep -Fq 'There is no dynamic section'
objdump -d "$OUT" > /tmp/wheelchair127-native256.dis
# Generated executable must contain real AVX/YMM work and no AVX-512 state.
grep -Eq '%ymm[0-9]+' /tmp/wheelchair127-native256.dis
if grep -Eq '%zmm[0-9]+|%k[1-7]([^0-9]|$)' /tmp/wheelchair127-native256.dis; then
  echo 'native256 generated ELF leaked AVX-512 register state' >&2
  exit 1
fi

# y[i] = 2*i+1; exact sum over i=0..n-1 is n^2. All selected n^2 values are
# exactly representable in binary64, so this is a bit-exact runtime oracle.
for n in 4 5 17 257; do
  got=$($OUT "$n" | sed -n 's/^checksum_bits=0x//p')
  expected=$(python3 - "$n" <<'PY'
import struct,sys
n=int(sys.argv[1])
bits=struct.unpack('>Q',struct.pack('>d',float(n*n)))[0]
print(f'{bits:016x}')
PY
)
  [ "$got" = "$expected" ] || {
    echo "native256 runtime mismatch n=$n got=$got expected=$expected" >&2
    exit 1
  }
done

# Native/no-ceiling routing must agree with the sovereign native audit. This is
# a compile-time decision only; the resulting user ELF contains no dispatcher.
python3 whexc.py "$SRC" -o "$AUTO" --executors 1 --semantic-plan "$AUTOPLAN" \
  > /tmp/wheelchair127-auto-driver.json
python3 - <<'PY'
import json
from pathlib import Path
p=json.loads(Path('/tmp/wheelchair127-auto-plan.json').read_text())
b=p['native_physical_backend']
aid=int(b['native_audit_shape_id'])
expected={1:'native256',2:'split512x256',3:'native512'}.get(aid)
if expected is not None:
    assert b['physical_shape']==expected, (aid,b)
if b['physical_shape']=='native256':
    assert b['compiler_image'].endswith('native256'), b
else:
    assert not b['compiler_image'].endswith('native256'), b
assert b['runtime_selector']==0 and b['runtime_profitability_selector']==0, b
print('NATIVE_AUTO_PHYSICAL_SHAPE_EQ_NATIVE_AUDIT=PASS')
PY

# Current hosted Zen3 witnesses the fully automatic path as well. On another
# qualified host the generic equality check above remains authoritative.
shape=$(python3 - <<'PY'
import json
print(json.load(open('/tmp/wheelchair127-auto-plan.json'))['native_physical_backend']['physical_shape'])
PY
)
if [ "$shape" = native256 ]; then
  for n in 5 17; do
    "$AUTO" "$n" >/tmp/wheelchair127-auto-run.txt
    grep -Fq 'checksum_bits=0x' /tmp/wheelchair127-auto-run.txt
  done
  echo 'NATIVE256_AUTOMATIC_HOST_ROUTE=PASS'
else
  echo "NATIVE256_AUTOMATIC_HOST_ROUTE=NOT_APPLICABLE_HOST_SHAPE_$shape"
fi

echo 'NATIVE256_REAL_ELF_EXECUTION=PASS'
echo 'NATIVE256_AVX2_YMM_ONLY=PASS'
echo 'NATIVE256_TAIL_VECTOR=PASS'
echo 'NATIVE256_WORKLOAD_SPECIALIZATION=0'
echo 'NATIVE256_RUNTIME_SELECTOR=0'
echo 'NATIVE256_SCALAR_FALLBACK=0'
echo 'WHEELCHAIR_NATIVE256_1_2_7=PASS'
