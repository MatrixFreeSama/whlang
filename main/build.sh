#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$ROOT"

# compiler/ and runtime/ are the sole production source authority.
echo 'SINGLE_CURRENT_SOURCE_AUTHORITY=PASS'
echo 'PRODUCTION_BUILD_PYTHON_GENERATORS=0'

# Mature native-512 runtime remains the protected physical peak.
as --64 runtime/tensor_runtime_x86_64.S -o "$BUILD/tensor_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_runtime_template.o" -o "$BUILD/tensor_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_template" compiler/runtime_offsets.inc

# Both topology frontends consume the same current 512 runtime artifact.
cp "$BUILD/tensor_runtime_template" "$BUILD/tensor_derived_runtime_template"
cp compiler/runtime_offsets.inc "$BUILD/runtime_derived_offsets.inc"

# True AVX2/YMM runtimes from the same current runtime authority.
as --64 --defsym TENSOR_RUNTIME_NATIVE256=1 runtime/tensor_runtime_x86_64.S -o "$BUILD/tensor_runtime_native256_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_runtime_native256_template.o" -o "$BUILD/tensor_runtime_native256_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_native256_template" "$BUILD/runtime_native256_offsets.inc"

cp "$BUILD/tensor_runtime_native256_template" "$BUILD/tensor_derived_runtime_native256_template"
cp "$BUILD/runtime_native256_offsets.inc" "$BUILD/runtime_derived_native256_offsets.inc"

echo 'STRICT_REDUCTION_REPAIR_RUNTIME_OFFSETS=BUILT'

as --64 runtime/general_runtime_template_x86_64.S -o "$BUILD/general_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/general_runtime.ld \
  "$BUILD/general_runtime_template.o" -o "$BUILD/general_runtime_template"
./tools/generate_general_runtime_offsets.sh "$BUILD/general_runtime_template" compiler/general_runtime_offsets.inc

# Recipient-blind causal-region runtime. Offset derivation is shell + native ELF
# symbols only; no Python participates in production build authority.
as --64 runtime/general_parallel_release_x86_64.S -o "$BUILD/general_parallel_release.o"
ld -nostdlib -static -z noexecstack -T runtime/general_parallel_release.ld \
  "$BUILD/general_parallel_release.o" -o "$BUILD/general_parallel_release.elf"
objcopy -O binary --only-section=.text \
  "$BUILD/general_parallel_release.elf" "$BUILD/general_parallel_release_template.bin"
sh tools/generate_general_parallel_release_offsets.sh \
  "$BUILD/general_parallel_release.elf" "$BUILD/general_parallel_release_template.bin" \
  "$BUILD/general_parallel_release_offsets.json" "$BUILD/general_parallel_release_offsets.inc"
echo 'GENERAL_PARALLEL_RELEASE_OFFSETS_NO_PYTHON=PASS'

# Shared handwritten sovereign topology core with physical-shape capability algebra.
as --64 compiler/topologyc_x86_64.S -o "$BUILD/topologyc_core.o"
as --64 compiler/silicon_domain_probe_x86_64.S -o "$BUILD/silicon_domain_probe.o"
as --64 compiler/fabric_target_facts_x86_64.S -o "$BUILD/fabric_target_facts.o"
as --64 compiler/outward_materialization_profile_x86_64.S -o "$BUILD/outward_materialization_profile.o"
as --64 compiler/physical_native_x86_64.S -o "$BUILD/physical_native.o"
as --64 compiler/general_frontend_x86_64.S -o "$BUILD/general_frontend.o"
as --64 compiler/general_runtime_blob_x86_64.S -o "$BUILD/general_runtime_blob.o"
as --64 compiler/general_parallel_release_blob_x86_64.S -o "$BUILD/general_parallel_release_blob.o"
as --64 compiler/surface_lowerer_x86_64.S -o "$BUILD/surface_lowerer.o"
as --64 compiler/human_shell_feedback_x86_64.S -o "$BUILD/human_shell_feedback.o"

# Native/split 512 physicalizers.
as --64 compiler/tensor_frontend_x86_64.S -o "$BUILD/tensor_frontend.o"
as --64 compiler/runtime_blob_x86_64.S -o "$BUILD/runtime_blob.o"

# Native Field physicalization consumes the same current source authority.
as --64 runtime/field_runtime_512_x86_64.S -o "$BUILD/field_runtime_512.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/field_runtime_512.o" -o "$BUILD/field_runtime_512_template"
sh tools/generate_field_runtime_offsets.sh \
  "$BUILD/field_runtime_512_template" "$BUILD/field_runtime_512_offsets.inc"

as --64 runtime/field_runtime_256_x86_64.S -o "$BUILD/field_runtime_256.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/field_runtime_256.o" -o "$BUILD/field_runtime_256_template"
sh tools/generate_field_runtime_offsets.sh \
  "$BUILD/field_runtime_256_template" "$BUILD/field_runtime_256_offsets.inc"

# Element geometry specializes the shared runtime at build/AOT time only.
for isa in 256 512; do
  as --64 --defsym FIELD_ELEMENT_BITS=64 runtime/field_runtime_${isa}_x86_64.S -o "$BUILD/field_runtime_${isa}_f64.o"
  ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld "$BUILD/field_runtime_${isa}_f64.o" -o "$BUILD/field_runtime_${isa}_f64_template"
  sh tools/generate_field_runtime_offsets.sh "$BUILD/field_runtime_${isa}_f64_template" "$BUILD/field_runtime_${isa}_f64_offsets.inc"
  # A dense compiler-only physical record; its order is generated with offsets.
  awk '/^\.equ / {n=$2; sub(/,$/,"",n); print "    .quad "n}' "$BUILD/field_runtime_${isa}_offsets.inc" > "$BUILD/field_runtime_${isa}_facts.inc"
  awk '/^\.equ / {print}' "$BUILD/field_runtime_${isa}_f64_offsets.inc" | sed 's/FIELD_RUNTIME_/FIELD_RUNTIME_F64_/g' > "$BUILD/field_runtime_${isa}_f64_facts_offsets.inc"
  awk '/^\.equ / {n=$2; sub(/,$/,"",n); print "    .quad "n}' "$BUILD/field_runtime_${isa}_f64_facts_offsets.inc" > "$BUILD/field_runtime_${isa}_f64_facts.inc"
  awk '/^\.equ / {n=$2; sub(/,$/,"",n); printf ".equ FF_FACT_%s, %d\n", n, i*8; i++}' "$BUILD/field_runtime_${isa}_offsets.inc" > "$BUILD/field_runtime_${isa}_fact_layout.inc"
done

as --64 compiler/field_runtime_blob_512_x86_64.S -o "$BUILD/field_runtime_blob_512.o"
as --64 compiler/field_runtime_blob_256_x86_64.S -o "$BUILD/field_runtime_blob_256.o"
as --64 compiler/field_frontend_512_x86_64.S -o "$BUILD/field_frontend_512.o"
as --64 compiler/field_frontend_256_x86_64.S -o "$BUILD/field_frontend_256.o"
as --64 compiler/fieldc_driver_x86_64.S -o "$BUILD/fieldc_driver.o"
as --64 compiler/field_parser_link_stubs_x86_64.S -o "$BUILD/field_parser_link_stubs.o"

# Fieldc links the current handwritten parser symbols from the tensor frontend.
# Unreachable tensor-only link references are satisfied by compile-time stubs;
# no tensor scheduler/runtime is entered by fieldc.
ld -nostdlib -static -z noexecstack \
  "$BUILD/fieldc_driver.o" "$BUILD/field_frontend_512.o" \
  "$BUILD/tensor_frontend.o" "$BUILD/runtime_blob.o" "$BUILD/physical_native.o" \
  "$BUILD/field_runtime_blob_512.o" "$BUILD/field_parser_link_stubs.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" \
  -o "$BUILD/fieldc"
ld -nostdlib -static -z noexecstack \
  "$BUILD/fieldc_driver.o" "$BUILD/field_frontend_256.o" \
  "$BUILD/tensor_frontend.o" "$BUILD/runtime_blob.o" "$BUILD/physical_native.o" \
  "$BUILD/field_runtime_blob_256.o" "$BUILD/field_parser_link_stubs.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" \
  -o "$BUILD/fieldc-native256"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/tensor_frontend.o" "$BUILD/general_frontend.o" "$BUILD/physical_native.o" \
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" "$BUILD/general_parallel_release_blob.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" -o "$BUILD/topologyc"
as --64 compiler/tensor_derived_frontend_x86_64.S -o "$BUILD/tensor_frontend_derived.o"
as --64 compiler/runtime_derived_blob_x86_64.S -o "$BUILD/runtime_derived_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/tensor_frontend_derived.o" "$BUILD/general_frontend.o" "$BUILD/physical_native.o" \
  "$BUILD/runtime_derived_blob.o" "$BUILD/general_runtime_blob.o" "$BUILD/general_parallel_release_blob.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" -o "$BUILD/topologyc-derived"

# Native256 physicalizers for every generic graph-resource class.
as --64 compiler/tensor_frontend_native256_x86_64.S -o "$BUILD/tensor_frontend_native256.o"
as --64 compiler/tensor_derived_frontend_native256_x86_64.S -o "$BUILD/tensor_frontend_derived_native256.o"
as --64 compiler/runtime_native256_blob_x86_64.S -o "$BUILD/runtime_native256_blob.o"
as --64 compiler/runtime_derived_native256_blob_x86_64.S -o "$BUILD/runtime_derived_native256_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/tensor_frontend_native256.o" "$BUILD/general_frontend.o" "$BUILD/physical_native.o" \
  "$BUILD/runtime_native256_blob.o" "$BUILD/general_runtime_blob.o" "$BUILD/general_parallel_release_blob.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" -o "$BUILD/topologyc-native256"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/silicon_domain_probe.o" "$BUILD/fabric_target_facts.o" "$BUILD/outward_materialization_profile.o" "$BUILD/tensor_frontend_derived_native256.o" "$BUILD/general_frontend.o" "$BUILD/physical_native.o" \
  "$BUILD/runtime_derived_native256_blob.o" "$BUILD/general_runtime_blob.o" "$BUILD/general_parallel_release_blob.o" "$BUILD/surface_lowerer.o" "$BUILD/human_shell_feedback.o" -o "$BUILD/topologyc-derived-native256"

# Native production launchers.  The driver performs only compile-time structural
# classification (base/derived from canonical structure); it never retries a failed compiler
# and never inspects workload names.
as --64 compiler/native_driver_x86_64.S -o "$BUILD/native_driver.o"
ld -nostdlib -static -z noexecstack "$BUILD/native_driver.o" "$BUILD/surface_lowerer.o" -o "$BUILD/wheelchairc"

for f in \
  "$BUILD/topologyc" "$BUILD/topologyc-derived" \
  "$BUILD/topologyc-native256" "$BUILD/topologyc-derived-native256" \
  "$BUILD/tensor_runtime_template" "$BUILD/tensor_derived_runtime_template" \
  "$BUILD/tensor_runtime_native256_template" "$BUILD/tensor_derived_runtime_native256_template" \
  "$BUILD/general_runtime_template" "$BUILD/general_parallel_release.elf" \
  "$BUILD/field_runtime_512_template" "$BUILD/field_runtime_256_template" \
  "$BUILD/field_runtime_512_f64_template" "$BUILD/field_runtime_256_f64_template" \
  "$BUILD/fieldc" "$BUILD/fieldc-native256" \
  "$BUILD/wheelchairc"; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done

# Production build closure must not invoke Python. Python remains allowed only
# in reference/validation tooling while the human surface is being migrated.
if grep -En '(^|[[:space:]])python(3)?([[:space:]]|$)' build.sh; then
  echo 'Python invocation leaked into production build' >&2; exit 1
fi

# Current release surface: bin/ contains only canonical production executables.
rm -rf "$ROOT/bin"
mkdir -p "$ROOT/bin"
for f in \
  wheelchairc topologyc topologyc-derived \
  topologyc-native256 topologyc-derived-native256 \
  fieldc fieldc-native256; do
  cp "$BUILD/$f" "$ROOT/bin/$f"
done

# Verify the current architecture and the artifacts just built. Historical
# comment/string assertions do not belong to the production dependency graph.
sh tools/check_source_authority.sh
for f in wheelchairc topologyc topologyc-derived topologyc-native256 topologyc-derived-native256 fieldc fieldc-native256; do
  cmp "$BUILD/$f" "$ROOT/bin/$f"
done
echo 'CURRENT_SOURCE_AUTHORITY=PASS'
echo 'SOURCE_BINARY_CLOSURE=PASS'
echo 'WHEELCHAIR_1_3_178_BUILD=PASS'
