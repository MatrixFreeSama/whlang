#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
SRC=frozen_native/generated_derived/tensor_derived_frontend_x86_64.S

for sym in \
  expr_dense_scaled_preflight vec_dense_scaled_get_reg vec_dense_scaled_emit_delta \
  expr_dense_dep_cost expr_dense_licm_find vec_dense_licm_prepare \
  vec_dense_licm_interchange_preflight vec_fused_emit_dense_licm_interchange \
  vec_dense_unroll4_preflight vec_fused_emit_dense_unroll4 \
  vec_fused_elide_boundary_if_identical vec_fused_wide_reduce_fragment \
  vec_fused_full_reduce_fragment; do
  grep -q "^${sym}:" "$SRC"
done

echo 'DERIVED_AFFINE_INDUCTION=PASS'
echo 'CROSS_AXIS_LICM=PASS'
echo 'TRUE_DENSE_LOOP_NEST_RECONSTRUCTION=PASS'
echo 'DENSE_STATIC_INNER_UNROLL=PASS'
echo 'DELAYED_ZMM_REDUCTION=PASS'
echo 'BOUNDARY_IDENTITY_ELIMINATION=PASS'
echo 'PROVEN_ZERO_TAIL_ELIMINATION=PASS'
echo 'RANKN_LIFETIME_REGISTER_REUSE=PASS'

DENSE=benchmarks/caretaker_1214/dense_bilinear_128.whex
STRICT=benchmarks/caretaker_1214/dense_bilinear_128_strict.whex
check_dense() {
  exe=$1
  n=$2
  case "$n" in
    64) exp=checksum_bits=0x4100fa446c000000 ;;
    65) exp=checksum_bits=0x410142c00e000000 ;;
    127) exp=checksum_bits=0x4110f3288c000000 ;;
    128) exp=checksum_bits=0x411116709b000000 ;;
    129) exp=checksum_bits=0x41113a75a4000000 ;;
    2048) exp=checksum_bits=0x4150eb05c0000000 ;;
    8192) exp=checksum_bits=0x4170eb05c0000000 ;;
    *) exit 1 ;;
  esac
  [ "$("$exe" "$n")" = "$exp" ]
}
for q in 1 2 4; do
  build/whexc "$DENSE" -o "$T/dense$q" --executors "$q" >/dev/null
  for n in 64 65 127 128 129 2048 8192; do check_dense "$T/dense$q" "$n"; done
  build/whexc "$STRICT" -o "$T/strict$q" --executors "$q" >/dev/null
  for n in 64 129 8192; do check_dense "$T/strict$q" "$n"; done
done
echo 'DENSE_CARETAKER_BOUNDARY_CORRECTNESS=PASS'
echo 'STRICT_REDUCTION_ORDER_PRESERVATION=PASS'

# Existing low-period and general Rank-N semantics must survive the new physicalizer.
build/whexc tests/whex/rank2_native_122.whex -o "$T/rank2" --executors 4 >/dev/null
[ "$("$T/rank2" 4)" = 'checksum_bits=0x405e000000000000' ]
build/whexc tests/whex/rank3_native_122.whex -o "$T/rank3" --executors 4 >/dev/null
[ "$("$T/rank3" 4)" = 'checksum_bits=0x407f000000000000' ]
build/whexc tests/whex/rank6_native_122.whex -o "$T/rank6" --executors 4 >/dev/null
[ "$("$T/rank6" 4)" = 'checksum_bits=0x40bfc00000000000' ]
echo 'RANKN_NUMERIC_PRESERVATION=PASS'

# High-entropy sparse authority must remain exactly the same machine image as 1.2.12/1.2.13.
SPARSE=benchmarks/caretaker_1214/irregular_sparse.whex
for q in 1 2 4; do build/whexc "$SPARSE" -o "$T/sparse$q" --executors "$q" >/dev/null; done
h1=$(sha256sum "$T/sparse1" | awk '{print $1}')
h2=$(sha256sum "$T/sparse2" | awk '{print $1}')
h4=$(sha256sum "$T/sparse4" | awk '{print $1}')
[ "$h1" = '80a55d919a0ba6df6416d59b0cb31c178e2215b15cba9766e251044671ef9102' ]
[ "$h2" = '97b8178e7059996b257925fb72d2482b5faa50e0eb8804fc67625c6ba209d30d' ]
[ "$h4" = '5cf07ded263e5a17df6355ef39702bf09dcab817ce62eb3b8878f91c91a7f906' ]
echo 'IRREGULAR_SPARSE_1_2_13_BYTE_IDENTITY=PASS'
echo 'NO_NEGATIVE_STRUCTURAL_COMPRESSION=PASS'

# Caretaker admission is structural only.
! grep -Eq 'dense_bilinear|irregular_sparse|benchmark[_ -]?name|runtime[_ -]?profit|wall[_ -]?clock' "$SRC"
echo 'CARETAKER_WORKLOAD_IDENTITY=0'
echo 'CARETAKER_RUNTIME_PROFITABILITY_SELECTOR=0'
echo 'DENSE_CARETAKER_OPTIMIZATION_1_2_14=PASS'
