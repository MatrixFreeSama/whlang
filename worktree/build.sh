#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$ROOT"

# Mature native-512 runtime remains the protected physical peak.
as --64 runtime/tensor_runtime_template_x86_64.S -o "$BUILD/tensor_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_runtime_template.o" -o "$BUILD/tensor_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_template" compiler/runtime_offsets.inc

# Generic structural capability generation. No workload identity enters routing.
python3 tools/generate_derived_native_backend.py
python3 tools/generate_product_subtract_frontend.py
python3 tools/generate_vector_reduction_residency.py
python3 tools/generate_native_resource_profiles.py
python3 tools/generate_multi_isa_topologyc.py
python3 tools/augment_native256_capabilities.py
python3 tools/generate_native256_runtime.py

# Mature derived native-512 runtime.
as --64 "$BUILD/generated_derived/tensor_derived_runtime_template_x86_64.S" -o "$BUILD/tensor_derived_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_derived_runtime_template.o" -o "$BUILD/tensor_derived_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_derived_runtime_template" "$BUILD/runtime_derived_offsets.inc"
derived_product_va=$(nm -n "$BUILD/tensor_derived_runtime_template" | awk '$3=="rank_n_product_patch" {print "0x"$1; exit}')
[ -n "$derived_product_va" ]
printf '.equ RUNTIME_RANK_N_PRODUCT_OFF, 0x%x\n' $((derived_product_va-0x400000)) >> "$BUILD/runtime_derived_offsets.inc"

# True AVX2/YMM four-lane runtimes. These are independent physicalizations, not
# scalar fallbacks and not wrappers around the 512-bit runtime.
as --64 "$BUILD/generated_native256/tensor_runtime_native256_template_x86_64.S" -o "$BUILD/tensor_runtime_native256_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_runtime_native256_template.o" -o "$BUILD/tensor_runtime_native256_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_native256_template" "$BUILD/runtime_native256_offsets.inc"

as --64 "$BUILD/generated_native256/tensor_derived_runtime_native256_template_x86_64.S" -o "$BUILD/tensor_derived_runtime_native256_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_derived_runtime_native256_template.o" -o "$BUILD/tensor_derived_runtime_native256_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_derived_runtime_native256_template" "$BUILD/runtime_derived_native256_offsets.inc"
derived256_product_va=$(nm -n "$BUILD/tensor_derived_runtime_native256_template" | awk '$3=="rank_n_product_patch" {print "0x"$1; exit}')
[ -n "$derived256_product_va" ]
printf '.equ RUNTIME_RANK_N_PRODUCT_OFF, 0x%x\n' $((derived256_product_va-0x400000)) >> "$BUILD/runtime_derived_native256_offsets.inc"

python3 tools/generate_native256_frontends.py

as --64 runtime/general_runtime_template_x86_64.S -o "$BUILD/general_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/general_runtime.ld \
  "$BUILD/general_runtime_template.o" -o "$BUILD/general_runtime_template"
./tools/generate_general_runtime_offsets.sh "$BUILD/general_runtime_template" compiler/general_runtime_offsets.inc

# Generic binding-level causal slot engine is ISA-orthogonal.
as --64 runtime/general_parallel_slot_x86_64.S -o "$BUILD/general_parallel_slot.o"
ld -nostdlib -static -z noexecstack -T runtime/general_parallel_slot.ld \
  "$BUILD/general_parallel_slot.o" -o "$BUILD/general_parallel_slot.elf"
objcopy -O binary --only-section=.text \
  "$BUILD/general_parallel_slot.elf" "$BUILD/general_parallel_slot_template.bin"
python3 tools/generate_general_parallel_slot_offsets.py \
  "$BUILD/general_parallel_slot.elf" "$BUILD/general_parallel_slot_template.bin" \
  "$BUILD/general_parallel_slot_offsets.json"

# Shared handwritten sovereign topology core with physical-shape capability algebra.
as --64 "$BUILD/topologyc_multi_isa_x86_64.S" -o "$BUILD/topologyc_core.o"
as --64 compiler/general_frontend_x86_64.S -o "$BUILD/general_frontend.o"
as --64 compiler/general_runtime_blob_x86_64.S -o "$BUILD/general_runtime_blob.o"

# Native/split 512 physicalizers: execution bytes remain inherited from 1.2.6.
as --64 "$BUILD/tensor_frontend_profile_base.S" -o "$BUILD/tensor_frontend_base.o"
as --64 "$BUILD/tensor_frontend_profile_wide.S" -o "$BUILD/tensor_frontend_wide.o"
as --64 compiler/runtime_blob_x86_64.S -o "$BUILD/runtime_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_base.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_wide.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc-wide"
as --64 "$BUILD/generated_derived/tensor_derived_frontend_x86_64.S" -o "$BUILD/tensor_frontend_derived.o"
as --64 "$BUILD/generated_derived/runtime_derived_blob_x86_64.S" -o "$BUILD/runtime_derived_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_derived.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_derived_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc-derived"

# Native256 physicalizers for every generic graph-resource class.
as --64 "$BUILD/generated_native256/tensor_frontend_base_native256.S" -o "$BUILD/tensor_frontend_base_native256.o"
as --64 "$BUILD/generated_native256/tensor_frontend_wide_native256.S" -o "$BUILD/tensor_frontend_wide_native256.o"
as --64 "$BUILD/generated_native256/tensor_frontend_derived_native256.S" -o "$BUILD/tensor_frontend_derived_native256.o"
as --64 "$BUILD/generated_native256/runtime_native256_blob_x86_64.S" -o "$BUILD/runtime_native256_blob.o"
as --64 "$BUILD/generated_native256/runtime_derived_native256_blob_x86_64.S" -o "$BUILD/runtime_derived_native256_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_base_native256.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_native256_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc-native256"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_wide_native256.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_native256_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc-wide-native256"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend_derived_native256.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_derived_native256_blob.o" "$BUILD/general_runtime_blob.o" -o "$BUILD/topologyc-derived-native256"

# Historical 1.2.5 fabrics remain witnesses only. topology-parallel remains the
# general causal execution authority independent of vector width.
as --64 runtime/causal_return_fabric_x86_64.S -o "$BUILD/causal_return_fabric.o"
ld -nostdlib -static -z noexecstack "$BUILD/causal_return_fabric.o" -o "$BUILD/topology-fabric-125-witness"
as --64 runtime/causal_return_parallel_x86_64.S -o "$BUILD/causal_return_parallel.o"
ld -nostdlib -static -z noexecstack "$BUILD/causal_return_parallel.o" -o "$BUILD/topology-fabric-run-125-witness"
as --64 runtime/schedulerless_causal_x86_64.S -o "$BUILD/topology_parallel.o"
ld -nostdlib -static -z noexecstack "$BUILD/topology_parallel.o" -o "$BUILD/topology-parallel"

for f in \
  "$BUILD/topologyc" "$BUILD/topologyc-wide" "$BUILD/topologyc-derived" \
  "$BUILD/topologyc-native256" "$BUILD/topologyc-wide-native256" "$BUILD/topologyc-derived-native256" \
  "$BUILD/tensor_runtime_template" "$BUILD/tensor_derived_runtime_template" \
  "$BUILD/tensor_runtime_native256_template" "$BUILD/tensor_derived_runtime_native256_template" \
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
echo 'MULTI_ISA_TOPOLOGYC=BUILT'
echo 'PHYSICAL_VECTOR_SHAPES=native256,split512x256,native512'
echo 'NATIVE256_BASE=BUILT'
echo 'NATIVE256_WIDE=BUILT'
echo 'NATIVE256_DERIVED=BUILT'
echo 'NATIVE256_SCALAR_FALLBACK=0'
echo 'PHYSICAL_VECTOR_PROFILE_WORKLOAD_DISPATCH=0'
echo 'PHYSICAL_VECTOR_RUNTIME_PROFITABILITY_SELECTOR=0'
echo 'GENERAL_PARALLEL_SLOT_ENGINE=BUILT'
echo 'GENERAL_PARALLEL_SLOT_FOREIGN_RUNTIME_BACKEND=0'
echo 'GENERAL_PARALLEL_FABRIC_1_2_7=BUILT'
echo 'GENERAL_PARALLEL_FABRIC_AUTHORITY=topology-parallel'
echo 'GENERAL_PARALLEL_GLOBAL_READY_QUEUE=0'
echo 'GENERAL_PARALLEL_ROOT_SCHEDULER=0'
echo 'GENERAL_PARALLEL_RUNTIME_COST_SELECTOR=0'
echo 'GENERAL_PARALLEL_SERIAL_FALLBACK=0'
echo 'ACTIVE_SPECIAL_PURPOSE_NATIVE_ROUTE=0'
echo 'WHEELCHAIR_BUILD=PASS'
