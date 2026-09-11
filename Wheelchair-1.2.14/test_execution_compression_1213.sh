#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM

SRC=frozen_native/generated_derived/tensor_derived_frontend_x86_64.S
grep -q '^expr_dense_rank_coord_key:' "$SRC"
grep -q '^vec_dense_coord_get_reg:' "$SRC"
grep -q '^vec_dense_chain_preflight:' "$SRC"
grep -q '^vec_dense_emit_step_chain:' "$SRC"
grep -q '^vec_dense_emit_init:' "$SRC"
grep -q '^vec_dense_emit_step:' "$SRC"
echo 'STRUCTURAL_COMPRESSIBILITY_ANALYSIS=PASS'
echo 'DENSE_RANKN_COORDINATE_CSE=PASS'
echo 'DENSE_RANKN_INDUCTION_CARRIERS=PASS'
echo 'DENSE_RANKN_COALESCED_AXIS_CARRY=PASS'

# Dense Rank-N correctness across row/batch carry boundaries.
DENSE=benchmarks/execution_compression_1213/dense_bilinear_128.whex
for q in 1 2 4; do
  build/whexc "$DENSE" -o "$T/dense$q" --executors "$q" >/dev/null
  [ "$("$T/dense$q" 64)" = 'checksum_bits=0x4100fa446c000000' ]
  [ "$("$T/dense$q" 127)" = 'checksum_bits=0x4110f3288c000000' ]
  [ "$("$T/dense$q" 128)" = 'checksum_bits=0x411116709b000000' ]
  [ "$("$T/dense$q" 129)" = 'checksum_bits=0x41113a75a4000000' ]
  [ "$("$T/dense$q" 8192)" = 'checksum_bits=0x4170eb05c0000000' ]
done
echo 'DENSE_RANKN_CARRY_BOUNDARIES=PASS'

# Tiny-period Rank-N patterns (< one SIMD packet) must remain exact.
build/whexc tests/whex/rank6_native_122.whex -o "$T/rank6" --executors 4 >/dev/null
[ "$("$T/rank6" 4)" = 'checksum_bits=0x40bfc00000000000' ]
echo 'DENSE_SMALL_PERIOD_FALLBACK=PASS'

# Native256 has no spare persistent high-register bank. It must preserve the
# direct-addressing representation rather than forcing negative compression.
for q in 1 2 4; do
  build/topologyc-derived-native256 "$DENSE" -o "$T/dense256_$q" --executors "$q" >/dev/null
  [ "$("$T/dense256_$q" 64)" = 'checksum_bits=0x4100fa446c000000' ]
done
echo 'NATIVE256_REGISTER_PRESSURE_FALLBACK=PASS'

# High-entropy rank-1 sparse code must be byte-identical to the frozen 1.2.12
# authority images. This proves the compression pass did not infect the sparse
# direct-addressing path.
SPARSE=benchmarks/execution_compression_1213/irregular_sparse.whex
for q in 1 2 4; do
  build/whexc "$SPARSE" -o "$T/sparse$q" --executors "$q" >/dev/null
done
h1=$(sha256sum "$T/sparse1" | awk '{print $1}')
h2=$(sha256sum "$T/sparse2" | awk '{print $1}')
h4=$(sha256sum "$T/sparse4" | awk '{print $1}')
[ "$h1" = '80a55d919a0ba6df6416d59b0cb31c178e2215b15cba9766e251044671ef9102' ]
[ "$h2" = '97b8178e7059996b257925fb72d2482b5faa50e0eb8804fc67625c6ba209d30d' ]
[ "$h4" = '5cf07ded263e5a17df6355ef39702bf09dcab817ce62eb3b8878f91c91a7f906' ]
echo 'IRREGULAR_SPARSE_1_2_12_BYTE_IDENTITY=PASS'
echo 'NO_NEGATIVE_STRUCTURAL_COMPRESSION=PASS'

# No workload identity / runtime timing selector was introduced.
! grep -Eq 'dense_bilinear|irregular_sparse|benchmark[_ -]?name|runtime[_ -]?profit' "$SRC"
echo 'COMPRESSION_WORKLOAD_IDENTITY=0'
echo 'COMPRESSION_RUNTIME_PROFITABILITY_SELECTOR=0'
echo 'EXECUTION_REPRESENTATION_COMPRESSION_1_2_13=PASS'
