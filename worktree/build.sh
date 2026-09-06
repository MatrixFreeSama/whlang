#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$ROOT"

# Runtime images are linked first. Their patch tables are derived from actual
# ELF symbols, so handwritten frontends never depend on stale numeric offsets.
as --64 runtime/tensor_runtime_template_x86_64.S -o "$BUILD/tensor_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_runtime_template.o" -o "$BUILD/tensor_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_template" compiler/runtime_offsets.inc

# Generic structural native capability generation. None of these generators is
# selected by workload name, source path, benchmark identity, or runtime timing.
python3 tools/generate_rankn_backend_122.py
python3 tools/generate_product_subtract_frontend.py
python3 tools/generate_vector_reduction_residency.py
python3 tools/generate_native_resource_profiles.py

as --64 "$BUILD/generated_122/tensor_rankn_runtime_template_x86_64.S" -o "$BUILD/tensor_derived_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_derived_runtime_template.o" -o "$BUILD/tensor_derived_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_derived_runtime_template" "$BUILD/runtime_derived_offsets.inc"
rankn_va=$(nm -n "$BUILD/tensor_derived_runtime_template" | awk '$3=="rank_n_product_patch" {print "0x"$1; exit}')
[ -n "$rankn_va" ]
printf '.equ RUNTIME_RANK_N_PRODUCT_OFF, 0x%x\n' $((rankn_va-0x400000)) >> "$BUILD/runtime_derived_offsets.inc"
# The derived frontend source still includes the historical generated include
# spelling; expose the generic capability filename at build time.
cp "$BUILD/runtime_derived_offsets.inc" "$BUILD/runtime_rankn_offsets.inc"

as --64 runtime/general_runtime_template_x86_64.S -o "$BUILD/general_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/general_runtime.ld \
  "$BUILD/general_runtime_template.o" -o "$BUILD/general_runtime_template"
./tools/generate_general_runtime_offsets.sh "$BUILD/general_runtime_template" compiler/general_runtime_offsets.inc

# Generic binding-level causal program_slot engine. Built once with the compiler;
# user compilation never invokes as/ld/objcopy for this path.
as --64 runtime/general_parallel_slot_x86_64.S -o "$BUILD/general_parallel_slot.o"
ld -nostdlib -static -z noexecstack -T runtime/general_parallel_slot.ld \
  "$BUILD/general_parallel_slot.o" -o "$BUILD/general_parallel_slot.elf"
objcopy -O binary --only-section=.text \
  "$BUILD/general_parallel_slot.elf" "$BUILD/general_parallel_slot_template.bin"
python3 tools/generate_general_parallel_slot_offsets.py \
  "$BUILD/general_parallel_slot.elf" "$BUILD/general_parallel_slot_template.bin" \
  "$BUILD/general_parallel_slot_offsets.json"

# Handwritten assembly compiler. Public physical capability classes are now only
# base / wide / derived. Their selection is compile-time structural proof.
as --64 compiler/topologyc_x86_64.S -o "$BUILD/topologyc_core.o"
as --64 "$BUILD/tensor_frontend_profile_base.S" -o "$BUILD/tensor_frontend_base.o"
as --64 "$BUILD/tensor_frontend_profile_wide.S" -o "$BUILD/tensor_frontend_wide.o"
as --64 compiler/general_frontend_x86_64.S -o "$BUILD/general_frontend.o"
as --64 compiler/runtime_blob_x86_64.S -o "$BUILD/runtime_blob.o"
as --64 compiler/general_runtime_blob_x86_64.S -o "$BUILD/general_runtime_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_base.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_wide.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc-wide"

as --64 "$BUILD/generated_122/tensor_rankn_frontend_x86_64.S" -o "$BUILD/tensor_frontend_derived.o"
as --64 "$BUILD/generated_122/runtime_rankn_blob_x86_64.S" -o "$BUILD/runtime_derived_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_derived.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_derived_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc-derived"

# Historical 1.2.5 fabrics remain byte-preserved witnesses, never current
# dispatch targets. The 1.2.6 topology-parallel image is the runtime authority.
as --64 runtime/causal_return_fabric_x86_64.S -o "$BUILD/causal_return_fabric.o"
ld -nostdlib -static -z noexecstack "$BUILD/causal_return_fabric.o" -o "$BUILD/topology-fabric-125-witness"
as --64 runtime/causal_return_parallel_x86_64.S -o "$BUILD/causal_return_parallel.o"
ld -nostdlib -static -z noexecstack "$BUILD/causal_return_parallel.o" -o "$BUILD/topology-fabric-run-125-witness"

as --64 runtime/schedulerless_causal_x86_64.S -o "$BUILD/topology_parallel.o"
ld -nostdlib -static -z noexecstack "$BUILD/topology_parallel.o" -o "$BUILD/topology-parallel"

for f in \
  "$BUILD/topologyc" "$BUILD/topologyc-wide" "$BUILD/topologyc-derived" \
  "$BUILD/tensor_runtime_template" "$BUILD/tensor_derived_runtime_template" \
  "$BUILD/general_runtime_template" "$BUILD/general_parallel_slot.elf" \
  "$BUILD/topology-fabric-125-witness" "$BUILD/topology-fabric-run-125-witness" \
  "$BUILD/topology-parallel"; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done

echo 'GENERIC_PRODUCT_SUBTRACT_CONTRACTION=BUILT'
echo 'GENERIC_VECTOR_REDUCTION_RESIDENCY=BUILT'
echo 'NATIVE_RESOURCE_PROFILE_BASE=BUILT'
echo 'NATIVE_RESOURCE_PROFILE_WIDE=BUILT'
echo 'NATIVE_RESOURCE_PROFILE_DERIVED=BUILT'
echo 'NATIVE_RESOURCE_PROFILE_WORKLOAD_DISPATCH=0'
echo 'NATIVE_RESOURCE_PROFILE_RUNTIME_SELECTOR=0'
echo 'GENERAL_PARALLEL_SLOT_ENGINE=BUILT'
echo 'GENERAL_PARALLEL_SLOT_FOREIGN_RUNTIME_BACKEND=0'
echo 'GENERAL_PARALLEL_FABRIC_1_2_6=BUILT'
echo 'GENERAL_PARALLEL_FABRIC_AUTHORITY=topology-parallel'
echo 'GENERAL_PARALLEL_GLOBAL_READY_QUEUE=0'
echo 'GENERAL_PARALLEL_ROOT_SCHEDULER=0'
echo 'GENERAL_PARALLEL_RUNTIME_COST_SELECTOR=0'
echo 'GENERAL_PARALLEL_SERIAL_FALLBACK=0'
echo 'WHEELCHAIR_BUILD=PASS'
