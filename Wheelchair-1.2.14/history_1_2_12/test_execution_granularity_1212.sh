#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM

# 1) Tensor causal-tree stack lifetimes are coarsened to one invocation arena.
for f in \
  runtime/tensor_runtime_template_x86_64.S \
  frozen_native/generated_derived/tensor_derived_runtime_template_x86_64.S \
  frozen_native/generated_native256/tensor_runtime_native256_template_x86_64.S \
  frozen_native/generated_native256/tensor_derived_runtime_native256_template_x86_64.S
do
  [ "$(grep -c 'mov eax,SYS_mmap' "$f")" -eq 1 ]
  [ "$(grep -c 'mov eax,SYS_munmap' "$f")" -eq 1 ]
  sed -n '/^run_tree:/,/^# worker/p' "$f" > "$T/run_tree.S"
  ! grep -q 'SYS_mmap' "$T/run_tree.S"
  ! grep -q 'SYS_munmap' "$T/run_tree.S"
  grep -q 'g_stack_arena' "$f"
  grep -q 'g_stack_arena_size' "$f"
done
echo 'TENSOR_INVOCATION_STACK_ARENA=PASS'
echo 'TENSOR_RECURSIVE_STACK_MMAP=0'
echo 'TENSOR_RECURSIVE_STACK_MUNMAP=0'

# 2) Causal mesh materialization is guarded by the assembly proof gate.
grep -q '^g_verify_causal_mesh:' compiler/general_frontend_x86_64.S
grep -A12 '^g_build_parallel_image:' compiler/general_frontend_x86_64.S | grep -q 'call g_verify_causal_mesh'
echo 'CAUSAL_WIDTH_PRESERVATION_GATE=PASS'

# Read physical node/edge counts from the blind-release program slot without Python.
prog_hex=$(awk '$2=="GENERAL_PROGRAM_OFF," {print $3; exit}' compiler/general_runtime_offsets.inc)
node_rel=$(awk -F: '/"gr_node_count"/ {gsub(/[^0-9]/,"",$2); print $2; exit}' frozen_native/general_parallel_release_offsets.json)
edge_rel=$(awk -F: '/"gr_edge_count"/ {gsub(/[^0-9]/,"",$2); print $2; exit}' frozen_native/general_parallel_release_offsets.json)
prog=$((prog_hex))
node_off=$((prog + node_rel))
edge_off=$((prog + edge_rel))
read_u32() { od -An -tu4 -j "$2" -N 4 "$1" | tr -d '[:space:]'; }

# Fork/join frontiers stay separate while the two 1->1 branch tails coarsen.
build/wheelchairc tests/general_parallel_126/causal_mesh_probe.wh -o "$T/mesh" --executors 4 >/dev/null
[ "$("$T/mesh" 1)" = 'out00_bits=0x0000000000000018' ]
[ "$(read_u32 "$T/mesh" "$node_off")" = 4 ]
[ "$(read_u32 "$T/mesh" "$edge_off")" = 4 ]
echo 'CAUSAL_MESH_FORK_JOIN_WIDTH=PASS'
echo 'CAUSAL_MESH_PHYSICAL_REGIONS=4'

# A pure serial chain still becomes exactly one physical region.
{
  echo 'program chain32_1212'
  echo 'contract integer_overflow = wrap'
  echo 'input x: u64'
  echo 'let a0 = x + 1'
  i=1
  while [ "$i" -lt 32 ]; do
    j=$((i-1))
    echo "let a$i = a$j + 1"
    i=$((i+1))
  done
  echo 'output y = a31'
  echo 'test (1) => { y = 33 }'
} > "$T/chain32.wh"
build/wheelchairc "$T/chain32.wh" -o "$T/chain32" --executors 4 >/dev/null
[ "$("$T/chain32" 1)" = 'out00_bits=0x0000000000000021' ]
[ "$(read_u32 "$T/chain32" "$node_off")" = 1 ]
[ "$(read_u32 "$T/chain32" "$edge_off")" = 0 ]
echo 'CAUSAL_MESH_SERIAL_CHAIN_COARSENING=PASS'
echo 'CHAIN32_PHYSICAL_REGIONS=1'

# 3) The arena change must be numerically invisible in base/wide/derived and 256/512 shapes.
check_profile() {
  compiler=$1; src=$2; n=$3; expected=$4
  for q in 1 2 4; do
    out="$T/$(basename "$compiler")_q$q"
    "$compiler" "$src" -o "$out" --executors "$q" >/dev/null
    got=$("$out" "$n")
    [ "$got" = "$expected" ] || { echo "$compiler q$q: $got" >&2; exit 1; }
  done
}
check_profile build/topologyc tests/whex/strength_probe.whex 100000 'checksum_bits=0x4186ef9500000000'
check_profile build/topologyc-wide benchmarks/fluid_solid_coupling_1211/fsi_coupled.whex 100000 'checksum_bits=0x40c5a457a3a332ea'
check_profile build/topologyc-derived tests/whex/rank6_native_122.whex 4 'checksum_bits=0x40bfc00000000000'
check_profile build/topologyc-native256 tests/whex/strength_probe.whex 100000 'checksum_bits=0x4186ef9500000000'
check_profile build/topologyc-wide-native256 benchmarks/fluid_solid_coupling_1211/fsi_coupled.whex 100000 'checksum_bits=0x40c5a457a3a332ea'
check_profile build/topologyc-derived-native256 tests/whex/rank6_native_122.whex 4 'checksum_bits=0x40bfc00000000000'
echo 'EXECUTION_ARENA_NUMERIC_INVISIBILITY=PASS'

# 4) Resource release semantics remain recipient-blind.
grep -q 'GENERAL_PARALLEL_BLIND_RESOURCE_RELEASE=PASS' build.sh
! grep -Eq 'work[_ -]?steal|peer[_ -]?load|global[_ -]?ready[_ -]?queue' runtime/tensor_runtime_template_x86_64.S
echo 'BLIND_RELEASE_SEMANTICS_PRESERVED=PASS'

echo 'ADAPTIVE_EXECUTION_GRANULARITY_1_2_12=PASS'
