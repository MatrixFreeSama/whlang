#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
./build.sh

# General sovereign lane through the current human compiler entry point.
./wheelchairc tests/general/compute_u64.wh -o build/general_compute >/dev/null
[ "$(build/general_compute)" = 'out00_bits=0x000000000000002a' ]
./wheelchairc tests/general/add_input_u64.wh -o build/general_add >/dev/null
[ "$(build/general_add 5)" = 'out00_bits=0x000000000000000c' ]

# Topology HPC lane: exact checksums at scalar-tail and vector/chunk scale.
# wheelchairc selects the structural native lane before general physicalization,
# so these remain direct sovereign native builds rather than a foreign wrapper.
for e in 1 2 4; do
  ./wheelchairc tests/topology_cases/heat_diffusion_step_tolerant.wh -o "build/heat_$e" --executors "$e" >/dev/null
  ./wheelchairc tests/topology_cases/wave_leapfrog_step_tolerant.wh -o "build/wave_$e" --executors "$e" >/dev/null
  ./wheelchairc tests/topology_cases/sparse_nonlinear_operator_tolerant.wh -o "build/sparse_$e" --executors "$e" >/dev/null
  [ "$(build/heat_$e 4)" = 'checksum_bits=0x3ff1c80000000000' ]
  [ "$(build/wave_$e 4)" = 'checksum_bits=0x4004340000000000' ]
  [ "$(build/sparse_$e 4)" = 'checksum_bits=0xc0013a2664700000' ]
  [ "$(build/heat_$e 100000)" = 'checksum_bits=0x40f24c3640000000' ]
  [ "$(build/wave_$e 100000)" = 'checksum_bits=0x40fb73bb40000000' ]
  [ "$(build/sparse_$e 100000)" = 'checksum_bits=0x40d42f9f6427c880' ]
done

# Tolerant-FP compiler contract: strict mode must not silently contract,
# tolerant mode may emit f64 FMA, and both remain numerically identical on the
# exact dyadic control case.
./wheelchairc tests/topology_cases/strict_fma_control.wh -o build/strict_fma_control --executors 1 >/dev/null
./wheelchairc tests/topology_cases/tolerant_fma_contract.wh -o build/tolerant_fma_contract --executors 1 >/dev/null
disasm_generated() {
  tools/disassemble_generated.sh "$1"
}
if disasm_generated build/strict_fma_control | grep -q 'vfmadd231pd'; then
  echo 'strict floating-point path incorrectly emitted FMA contraction' >&2; exit 1
fi
disasm_generated build/tolerant_fma_contract | grep -q 'vfmadd231pd'
[ "$(build/strict_fma_control 100000)" = 'checksum_bits=0x40fe7e2380000000' ]
[ "$(build/tolerant_fma_contract 100000)" = 'checksum_bits=0x40fe7e2380000000' ]

# Wide matrix-free linear aggregate regression.
for e in 1 4; do
  ./wheelchairc tests/topology_cases/fem_linear_aggregate_tolerant_regression.wh -o "build/fem_linear_aggregate_$e" --executors "$e" >/dev/null
  [ "$(build/fem_linear_aggregate_$e 262144)" = 'checksum_bits=0xc05ccc38e38e39d8' ]
done

# The former topology-fabric/topology-fabric-run resource-routing executables are
# intentionally absent after 1.2.9. General causal/resource invariants are proved
# by test_1210.sh; this baseline smoke must never resurrect those binaries.
for f in build/topology-fabric build/topology-fabric-run; do
  [ ! -e "$f" ] || { echo "retired resource-routing executable survived: $f" >&2; exit 1; }
done

# Generated programs must remain sovereign static ELF images.
for f in build/general_compute build/general_add build/heat_4 build/wave_4 build/sparse_4; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done

echo 'WHEELCHAIR_TESTS=PASS'
