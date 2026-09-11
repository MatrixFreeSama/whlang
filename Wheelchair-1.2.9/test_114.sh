#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/isa114

# Capability discovery must expose semantic capabilities independently of the
# instruction names used to realize them.
CAPS=$(build/topologyc --isa-capabilities)
printf '%s\n' "$CAPS" | grep -q '^ISA capability algebra:'
printf '%s\n' "$CAPS" | grep -q 'vector-512'
printf '%s\n' "$CAPS" | grep -q 'i64-vector-multiply:synthesizable'
printf '%s\n' "$CAPS" | grep -q 'i64-f64-vector-convert:synthesizable'
printf '%s\n' "$CAPS" | grep -q 'predicate-to-i64-mask:synthesizable'
printf '%s\n' "$CAPS" | grep -q 'cross-vector-state'
printf '%s\n' "$CAPS" | grep -q 'reduction-tree'
echo 'ISA_CAPABILITY_ALGEBRA=PASS'

# Native-DQ and forced AVX512F-foundation realizations must be semantically
# identical on control-heavy, nonlinear, dynamic-modulo and FEM workloads.
for case in heat_diffusion_step_tolerant sparse_nonlinear_operator_tolerant fem_linear_aggregate_tolerant_regression; do
    build/topologyc "tests/topology_cases/${case}.wh" -o "build/isa114/${case}_native_1" --executors 1 --isa-limit native >/dev/null
    build/topologyc "tests/topology_cases/${case}.wh" -o "build/isa114/${case}_fnd_1" --executors 1 --isa-limit avx512f >/dev/null
    build/topologyc "tests/topology_cases/${case}.wh" -o "build/isa114/${case}_fnd_4" --executors 4 --isa-limit avx512f >/dev/null
    case "$case" in
        fem_linear_aggregate_tolerant_regression) NS="262144" ;;
        *) NS="4 5 7 8 9 16 31 32 33 1024 1025 2049 4097" ;;
    esac
    for n in $NS; do
        A=$("build/isa114/${case}_native_1" "$n")
        B=$("build/isa114/${case}_fnd_1" "$n")
        C=$("build/isa114/${case}_fnd_4" "$n")
        [ "$A" = "$B" ] || { echo "native/foundation mismatch: $case n=$n" >&2; exit 1; }
        [ "$B" = "$C" ] || { echo "foundation executor mismatch: $case n=$n" >&2; exit 1; }
    done
done
echo 'AVX512F_FOUNDATION_NUMERIC=PASS'
echo 'AVX512F_FOUNDATION_EXECUTOR_EQUIVALENCE=PASS'

# AVX512VL is not a semantic requirement of the 512-bit tensor realization.
build/topologyc tests/topology_cases/heat_diffusion_step_tolerant.wh -o build/isa114/heat_dq_no_vl --executors 1 --isa-limit avx512dq >/dev/null
[ "$(build/isa114/heat_dq_no_vl 1025)" = "$(build/isa114/heat_diffusion_step_tolerant_native_1 1025)" ]
echo 'AVX512VL_NOT_REQUIRED=PASS'

# Foundation-generated hot code must not contain DQ-only instructions. It must
# contain the AVX512F recipes that realize the same semantic capabilities.
tools/disassemble_generated.sh build/isa114/heat_diffusion_step_tolerant_fnd_1 > build/isa114/heat_foundation.dis
if grep -Eiq '\b(vpmullq|vcvtqq2pd|vcvttpd2qq|vpmovm2q)\b' build/isa114/heat_foundation.dis; then
    echo 'DQ-only instruction leaked into AVX512F foundation target' >&2
    exit 1
fi
grep -Eiq '\bvpmuludq\b' build/isa114/heat_foundation.dis
grep -Eiq '\bvcvtdq2pd\b' build/isa114/heat_foundation.dis
grep -Eiq 'vpbroadcastq .*\{k1\}\{z\}' build/isa114/heat_foundation.dis
echo 'AVX512F_RECIPE_AUDIT=PASS'

# AVX2 participates in capability discovery, but there is no 256-bit physical
# WHEX tensor realizer yet. The compiler must reject explicitly rather than
# emulate a 512-bit parallel region through a scalar fallback.
if build/topologyc tests/topology_cases/heat_diffusion_step_tolerant.wh -o build/isa114/heat_avx2 --executors 1 --isa-limit avx2 >/dev/null 2>&1; then
    echo 'AVX2 ceiling incorrectly accepted without a 256-bit tensor realizer' >&2
    exit 1
fi
echo 'AVX2_NO_SCALAR_EMULATION=PASS'

# Source audit: semantic capability dispatch is allowed; workload/solver-name
# dispatch is not. Tensor runtime still has zero scalar evaluator calls.
python3 - <<'PY'
from pathlib import Path
src=(Path('compiler/tensor_frontend_x86_64.S').read_text()+Path('compiler/topologyc_x86_64.S').read_text()+Path('runtime/tensor_runtime_template_x86_64.S').read_text()).lower()
for bad in ('heat_diffusion','rust','projectoroptimizer','krylovoptimizer','toeplitzoptimizer'):
    assert bad not in src,bad
runtime=Path('runtime/tensor_runtime_template_x86_64.S').read_text()
assert 'call eval_slot' not in runtime
cap=Path('compiler/isa_capabilities.inc').read_text()
for name in ('ISA_CAP_I64_MUL_SYNTH','ISA_CAP_I64_FP_CONVERT_SYNTH','ISA_CAP_MASK_TO_I64_SYNTH','ISA_CAP_TENSOR512_BASE'):
    assert name in cap,name
print('ISA_GENERALIZATION_NO_WORKLOAD_DISPATCH=PASS')
print('ISA_GENERALIZATION_SCALAR_FALLBACK=0')
PY

echo 'WHEX_ISA_CAPABILITY_GENERALIZATION_1_0_14=PASS'
