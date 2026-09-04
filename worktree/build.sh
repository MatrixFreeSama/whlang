#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$ROOT"

# Runtime images are linked first. Their patch tables are then derived from
# actual ELF symbols, so the handwritten frontends do not depend on stale offsets.
as --64 runtime/tensor_runtime_template_x86_64.S -o "$BUILD/tensor_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \
  "$BUILD/tensor_runtime_template.o" -o "$BUILD/tensor_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_template" compiler/runtime_offsets.inc

as --64 runtime/general_runtime_template_x86_64.S -o "$BUILD/general_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/general_runtime.ld \
  "$BUILD/general_runtime_template.o" -o "$BUILD/general_runtime_template"
./tools/generate_general_runtime_offsets.sh "$BUILD/general_runtime_template" compiler/general_runtime_offsets.inc

# Handwritten assembly compiler: general sovereign lane + topology HPC lane.
as --64 compiler/topologyc_x86_64.S -o "$BUILD/topologyc_core.o"
as --64 compiler/tensor_frontend_x86_64.S -o "$BUILD/tensor_frontend.o"
as --64 compiler/general_frontend_x86_64.S -o "$BUILD/general_frontend.o"
as --64 compiler/runtime_blob_x86_64.S -o "$BUILD/runtime_blob.o"
as --64 compiler/general_runtime_blob_x86_64.S -o "$BUILD/general_runtime_blob.o"
ld -nostdlib -static -z noexecstack \
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend.o" "$BUILD/general_frontend.o" \
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" \
  -o "$BUILD/topologyc"

# Execution Fabric remains a distinct native runtime layer.
as --64 runtime/causal_return_fabric_x86_64.S -o "$BUILD/causal_return_fabric.o"
ld -nostdlib -static -z noexecstack "$BUILD/causal_return_fabric.o" -o "$BUILD/topology-fabric"
as --64 runtime/causal_return_parallel_x86_64.S -o "$BUILD/causal_return_parallel.o"
ld -nostdlib -static -z noexecstack "$BUILD/causal_return_parallel.o" -o "$BUILD/topology-fabric-run"

for f in "$BUILD/topologyc" "$BUILD/tensor_runtime_template" "$BUILD/general_runtime_template" "$BUILD/topology-fabric" "$BUILD/topology-fabric-run"; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done

echo 'WHEELCHAIR_BUILD=PASS'
