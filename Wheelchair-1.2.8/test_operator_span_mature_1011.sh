#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/operator_span_mature

./whexc tests/whex/operator_power_span_nonperiodic.whex -o build/operator_span_mature/power_1 --executors 1 >/dev/null
./whexc tests/whex/operator_power_span_nonperiodic.whex -o build/operator_span_mature/power_4 --executors 4 >/dev/null
./whexc tests/whex/operator_power_span_nonperiodic_strict.whex -o build/operator_span_mature/power_strict --executors 1 >/dev/null

for n in 1024; do
  A=$(build/operator_span_mature/power_1 "$n")
  B=$(build/operator_span_mature/power_4 "$n")
  C=$(build/operator_span_mature/power_strict "$n")
  [ "$A" = 'checksum_bits=0x40ae5af000000000' ]
  [ "$A" = "$B" ]
  [ "$A" = "$C" ]
done

echo 'OPERATOR_POWER_Q1_Q4=PASS'
echo 'OPERATOR_POWER_EXECUTOR_EQUIVALENCE=PASS'

# Generic modular operator relation: P=0.5*(I+S_{N/2}) on a fixed periodic
# ring is idempotent because S_{N/2}^2=I.  No projector name is visible to the
# compiler; Q1..Q8 collapse only through canonical (source,c,d,modulus) keys.
./whexc tests/whex/operator_periodic_relation.whex -o build/operator_span_mature/periodic_1 --executors 1 >/dev/null
./whexc tests/whex/operator_periodic_relation.whex -o build/operator_span_mature/periodic_4 --executors 4 >/dev/null
P1=$(build/operator_span_mature/periodic_1 1024)
P4=$(build/operator_span_mature/periodic_4 1024)
[ "$P1" = 'checksum_bits=0x4087fc0000000000' ]
[ "$P1" = "$P4" ]
echo 'PERIODIC_OPERATOR_RELATION_Q8=PASS'
echo 'PERIODIC_OPERATOR_EXECUTOR_EQUIVALENCE=PASS'

./whexc tests/whex/affine_constant_pressure.whex -o build/operator_span_mature/pressure_1 --executors 1 >/dev/null
./whexc tests/whex/affine_constant_pressure.whex -o build/operator_span_mature/pressure_4 --executors 4 >/dev/null
./whexc tests/whex/affine_constant_pressure_strict.whex -o build/operator_span_mature/pressure_strict --executors 1 >/dev/null

for n in 1024 1025 2048; do
  A=$(build/operator_span_mature/pressure_1 "$n")
  B=$(build/operator_span_mature/pressure_4 "$n")
  C=$(build/operator_span_mature/pressure_strict "$n")
  [ "$A" = "$B" ]
  [ "$A" = "$C" ]
done

[ "$(build/operator_span_mature/pressure_1 1024)" = 'checksum_bits=0x40a7fb8000000000' ]
[ "$(build/operator_span_mature/pressure_1 1025)" = 'checksum_bits=0x40a7fd3d40000000' ]
[ "$(build/operator_span_mature/pressure_1 2048)" = 'checksum_bits=0x40b7fb8000000000' ]

echo 'AFFINE_CONSTANT_PRESSURE_NUMERIC=PASS'
echo 'AFFINE_CONSTANT_PRESSURE_EXECUTOR_EQUIVALENCE=PASS'

# On an AVX-512DQ/VL host, prove that register pressure stays in the vector
# topology through RIP-relative qword broadcasts rather than scalar fallback.
if grep -qw avx512dq /proc/cpuinfo && grep -qw avx512vl /proc/cpuinfo; then
  ./tools/disassemble_generated.sh build/operator_span_mature/pressure_1 > build/operator_span_mature/pressure.dis
  ./tools/disassemble_generated.sh build/operator_span_mature/pressure_strict > build/operator_span_mature/pressure_strict.dis
  grep -Eq 'vpaddq .*QWORD BCST' build/operator_span_mature/pressure.dis
  echo 'AFFINE_CONSTANT_PRESSURE_VECTOR_SPILL=PASS'
  echo 'STRICT_AFFINE_VECTOR_PRESSURE=PASS'
fi

echo 'OPERATOR_SPAN_MATURE_1_0_11=PASS'
