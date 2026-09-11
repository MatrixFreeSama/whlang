#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
./build.sh

# These historical fixtures are canonical wheelchair.tensor/1 graphs, not WH
# human-surface source. Feed them directly to the sovereign assembly compiler.
build/topologyc tests/general/compute_u64.wh -o build/general_compute >/dev/null
[ "$(build/general_compute)" = 'out00_bits=0x000000000000002a' ]
build/topologyc tests/general/add_input_u64.wh -o build/general_add >/dev/null
[ "$(build/general_add 5)" = 'out00_bits=0x000000000000000c' ]

# Topology HPC lane: exact checksums at scalar-tail and vector/chunk scale.
for e in 1 2 4; do
  build/topologyc tests/topology_cases/heat_diffusion_step_tolerant.wh -o "build/heat_$e" --executors "$e" >/dev/null
  build/topologyc tests/topology_cases/wave_leapfrog_step_tolerant.wh -o "build/wave_$e" --executors "$e" >/dev/null
  build/topologyc tests/topology_cases/sparse_nonlinear_operator_tolerant.wh -o "build/sparse_$e" --executors "$e" >/dev/null
  [ "$(build/heat_$e 4)" = 'checksum_bits=0x3ff1c80000000000' ]
  [ "$(build/wave_$e 4)" = 'checksum_bits=0x4004340000000000' ]
  [ "$(build/sparse_$e 4)" = 'checksum_bits=0xc0013a2664700000' ]
  [ "$(build/heat_$e 100000)" = 'checksum_bits=0x40f24c3640000000' ]
  [ "$(build/wave_$e 100000)" = 'checksum_bits=0x40fb73bb40000000' ]
  [ "$(build/sparse_$e 100000)" = 'checksum_bits=0x40d42f9f6427c880' ]
done

# Tolerant-FP compiler contract.
build/topologyc tests/topology_cases/strict_fma_control.wh -o build/strict_fma_control --executors 1 >/dev/null
build/topologyc tests/topology_cases/tolerant_fma_contract.wh -o build/tolerant_fma_contract --executors 1 >/dev/null
disasm_generated() { tools/disassemble_generated.sh "$1"; }
if disasm_generated build/strict_fma_control | grep -q 'vfmadd231pd'; then
  echo 'strict floating-point path incorrectly emitted FMA contraction' >&2; exit 1
fi
disasm_generated build/tolerant_fma_contract | grep -q 'vfmadd231pd'
[ "$(build/strict_fma_control 100000)" = 'checksum_bits=0x40fe7e2380000000' ]
[ "$(build/tolerant_fma_contract 100000)" = 'checksum_bits=0x40fe7e2380000000' ]

for e in 1 4; do
  build/topologyc tests/topology_cases/fem_linear_aggregate_tolerant_regression.wh -o "build/fem_linear_aggregate_$e" --executors "$e" >/dev/null
  [ "$(build/fem_linear_aggregate_$e 262144)" = 'checksum_bits=0xc05ccc38e38e39d8' ]
done

# Retired resource-routing executables must remain physically absent.
for f in build/topology-fabric build/topology-fabric-run; do
  [ ! -e "$f" ] || { echo "retired resource-routing executable survived: $f" >&2; exit 1; }
done

for f in build/general_compute build/general_add build/heat_4 build/wave_4 build/sparse_4; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done

echo 'WHEELCHAIR_TESTS=PASS'
