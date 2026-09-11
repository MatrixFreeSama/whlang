#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

[ "$(cat VERSION)" = "1.2.4" ]

# The mature handwritten 1.2.1/1.2.3 native source remains frozen. 1.2.4 is
# derived from it at build time rather than rewriting the protected peak.
echo 'e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6  compiler/tensor_frontend_x86_64.S' | sha256sum -c -
echo '2e83af25b6a6188c9ce24497d636206ca5978e59a92b619e6b722909ad2d4f80  compiler/topologyc_x86_64.S' | sha256sum -c -
echo 'e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3  runtime/tensor_runtime_template_x86_64.S' | sha256sum -c -
echo 'GENERIC_NATIVE_1_2_4_FROZEN_SOURCE_BASE=PASS'

# No workload/physics name is allowed to select either accepted optimization.
if grep -Eini '\b(newton|stiffness|fem|cfd|poisson|kkt|fluid|solid)\b' \
    tools/generate_product_subtract_frontend.py tools/generate_vector_reduction_residency.py >/tmp/generic124_names.txt; then
    cat /tmp/generic124_names.txt
    echo 'workload dispatch name leaked into generic optimizer' >&2
    exit 1
fi
echo 'GENERIC_NATIVE_NO_WORKLOAD_DISPATCH=PASS'

# Build a byte-frozen baseline compiler from the old frontend next to 1.2.4.
as --64 compiler/tensor_frontend_x86_64.S -o build/tensor_frontend_baseline_124.o
ld -nostdlib -static -z noexecstack \
  build/topologyc_core.o build/tensor_frontend_baseline_124.o build/general_frontend.o \
  build/runtime_blob.o build/general_runtime_blob.o -o build/topologyc-baseline-124

# Compile the same structural operator under a physical name and a deliberately
# non-physical name. Names must erase before native realization.
for q in 1 2 4; do
    cp build/topologyc build/topologyc-optimized-124
    ./whexc ../benchmarks/global_operator_124/stiffness.whex -o "build/stiffness124_q${q}" --executors "$q" >/dev/null
    ./whexc ../benchmarks/global_operator_124/synthetic_same_structure.whex -o "build/synthetic124_q${q}" --executors "$q" >/dev/null
    cmp "build/stiffness124_q${q}" "build/synthetic124_q${q}"
done
echo 'GENERIC_NATIVE_OPERATOR_NAME_ERASURE=PASS'
echo 'GENERIC_NATIVE_RENAMED_NATIVE_BYTE_EQUIVALENCE=PASS'

# The new machine shape must come from algebra, not a runtime dispatch layer.
sh tools/disassemble_generated.sh build/stiffness124_q1 > /tmp/generic124.dis 2>&1
python3 - <<'PY'
from pathlib import Path
import re
s=Path('/tmp/generic124.dis').read_text(errors='replace').lower()
fn=len(re.findall(r'\bvfnmadd231pd\b',s))
resident=len(re.findall(r'vaddpd[^\n]*zmm12[^\n]*zmm0',s))
vmul=len(re.findall(r'\bvmulpd\b',s))
vsub=len(re.findall(r'\bvsubpd\b',s))
calls=len(re.findall(r'\bcall\b',s))
print(f'GENERIC_NATIVE_VFNMADD231PD={fn}')
print(f'GENERIC_NATIVE_ZMM_RESIDENT_REDUCTION={resident}')
print(f'GENERIC_NATIVE_VMULPD={vmul}')
print(f'GENERIC_NATIVE_VSUBPD={vsub}')
print(f'GENERIC_NATIVE_GENERATED_CALL_EDGES={calls}')
assert fn >= 2
assert resident >= 1
assert vsub == 0
assert calls == 0
PY
echo 'GENERIC_PRODUCT_SUBTRACT_CONTRACTION=PASS'
echo 'GENERIC_VECTOR_REDUCTION_RESIDENCY=PASS'
echo 'GENERIC_NATIVE_SCALAR_FALLBACK=0'

# Newton/Jv does not match the new structural recipe. Its mature native files
# must therefore remain byte-identical, not merely numerically equivalent.
for q in 1 2 4; do
    cp build/topologyc-baseline-124 build/topologyc
    ./whexc tests/whex/newton_jv_mature_regression.whex -o "build/newton124_base_q${q}" --executors "$q" >/dev/null
    cp build/topologyc-optimized-124 build/topologyc
    ./whexc tests/whex/newton_jv_mature_regression.whex -o "build/newton124_opt_q${q}" --executors "$q" >/dev/null
    cmp "build/newton124_base_q${q}" "build/newton124_opt_q${q}"
done
cp build/topologyc-optimized-124 build/topologyc
echo 'NEWTON_JV_NATIVE_BYTE_IDENTITY_ON_1_2_4=PASS'

# Numeric reference and executor equivalence for the generic operator itself.
out1=$(./build/stiffness124_q1 4)
out2=$(./build/stiffness124_q2 4)
out4=$(./build/stiffness124_q4 4)
[ "$out1" = "$out2" ]
[ "$out1" = "$out4" ]
echo 'GENERIC_NATIVE_REFERENCE_1_2_4_EXECUTORS=PASS'

# Preserve the mature Rank-N and Global Coupled Operator / SCE layers.
sh test_rank_n_122.sh | tee /tmp/rankn124.txt
grep -q '^WHEELCHAIR_RANK_N_1_2_2=PASS$' /tmp/rankn124.txt
grep -q '^RANK_N_GENERATED_RX_CALL_EDGES=0$' /tmp/rankn124.txt
grep -q '^RANK_N_SCALAR_FALLBACK=0$' /tmp/rankn124.txt

sh test_sparse_causal_expansion_123.sh | tee /tmp/sce124.txt
grep -q '^WHEELCHAIR_SPARSE_CAUSAL_EXPANSION_1_2_3=PASS$' /tmp/sce124.txt
grep -q '^GLOBAL_OPERATOR_SCALAR_FALLBACK=0$' /tmp/sce124.txt
grep -q '^GLOBAL_OPERATOR_CENTRAL_SPAWN_LOOP=0$' /tmp/sce124.txt
grep -q '^GLOBAL_OPERATOR_CENTRAL_WAIT_LOOP=0$' /tmp/sce124.txt
grep -q '^GLOBAL_OPERATOR_CENTRAL_REDUCTION_LOOP=0$' /tmp/sce124.txt
grep -q '^GLOBAL_OPERATOR_NON_NEIGHBOR_COMMUNICATION=0$' /tmp/sce124.txt

echo 'RANK_N_1_2_2_TECHNICAL_PEAK_PROTECTED_ON_1_2_4=PASS'
echo 'SCE_1_2_3_TECHNICAL_PEAK_PROTECTED_ON_1_2_4=PASS'
echo 'GENERIC_NATIVE_OPTIMIZATION_1_2_4=PASS'
