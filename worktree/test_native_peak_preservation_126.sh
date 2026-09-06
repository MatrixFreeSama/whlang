#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
BASE125="$ROOT/../baseline125/worktree"
for p in \
  build/topologyc build/topologyc-wide build/topologyc-derived \
  "$BASE125/build/topologyc" "$BASE125/build/topologyc-sdep" "$BASE125/build/topologyc-rankn"; do
  [ -x "$p" ]
done

# objcopy -O binary discards ELF symbol/string metadata and preserves the alloc
# image. For base/wide the compiler alloc images must remain byte-identical.
compare_alloc() {
  new=$1 old=$2 name=$3
  objcopy -O binary "$new" "/tmp/${name}.new.bin"
  objcopy -O binary "$old" "/tmp/${name}.old.bin"
  cmp "/tmp/${name}.new.bin" "/tmp/${name}.old.bin"
  echo "${name}_LOADABLE_BYTE_IDENTITY=PASS"
}
compare_alloc build/topologyc "$BASE125/build/topologyc" BASE_PROFILE_1_2_5_COMPILER
compare_alloc build/topologyc-wide "$BASE125/build/topologyc-sdep" WIDE_PROFILE_1_2_5_COMPILER

# Derived generic filenames intentionally change ELF STT_FILE/.strtab metadata.
# The compiler embeds the whole runtime ELF as a template, so that harmless
# metadata becomes compiler rodata. Prove the execution-bearing pieces directly:
# frontend alloc bytes, compiler text, and embedded runtime alloc image.
compare_alloc build/tensor_frontend_derived.o "$BASE125/build/tensor_rankn_frontend.o" DERIVED_PROFILE_1_2_5_FRONTEND
objcopy -O binary --only-section=.text build/topologyc-derived /tmp/derived_compiler_text.new.bin
objcopy -O binary --only-section=.text "$BASE125/build/topologyc-rankn" /tmp/derived_compiler_text.old.bin
cmp /tmp/derived_compiler_text.new.bin /tmp/derived_compiler_text.old.bin
echo 'DERIVED_PROFILE_1_2_5_COMPILER_TEXT_BYTE_IDENTITY=PASS'
compare_alloc build/tensor_derived_runtime_template "$BASE125/build/tensor_rankn_runtime_template" DERIVED_PROFILE_1_2_5_RUNTIME

cmp build/tensor_runtime_template "$BASE125/build/tensor_runtime_template"
cmp build/general_runtime_template "$BASE125/build/general_runtime_template"
echo 'MATURE_RUNTIME_1_2_5_NATIVE_BYTE_IDENTITY=PASS'

# Canonical-core authority files retain the .wh suffix required by the sovereign
# compiler entry contract. Their contents remain canonical JSON bytes.
PYTHONPATH=surface python3 - <<'PY'
from pathlib import Path
import whex_surface
cases={
 'base': Path('../benchmarks/newton_jv/mature.whex'),
 'wide': Path('../benchmarks/fluid_solid_coupling_124/fsi_coupled.whex'),
 'derived': Path('tests/whex/rank6_native_122.whex'),
}
for name,path in cases.items():
    data,_,_=whex_surface.load_surface(path)
    Path(f'/tmp/peak_{name}.core.wh').write_bytes(whex_surface.canonical_core_bytes(data))
PY

compare_emit_loadable() {
  new=$1 old=$2 core=$3 name=$4
  "$old" "$core" -o "build/${name}.old.elf"
  "$new" "$core" -o "build/${name}.new.elf"
  objcopy -O binary "build/${name}.old.elf" "/tmp/${name}.old.load.bin"
  objcopy -O binary "build/${name}.new.elf" "/tmp/${name}.new.load.bin"
  cmp "/tmp/${name}.new.load.bin" "/tmp/${name}.old.load.bin"
  echo "${name}_EMITTED_LOADABLE_BYTE_IDENTITY=PASS"
}
compare_emit_loadable build/topologyc "$BASE125/build/topologyc" /tmp/peak_base.core.wh BASE_PROFILE_1_2_5
compare_emit_loadable build/topologyc-wide "$BASE125/build/topologyc-sdep" /tmp/peak_wide.core.wh WIDE_PROFILE_1_2_5
compare_emit_loadable build/topologyc-derived "$BASE125/build/topologyc-rankn" /tmp/peak_derived.core.wh DERIVED_PROFILE_1_2_5

echo 'NONEXECUTING_ELF_FILENAME_METADATA_MAY_DIFFER=1'
echo 'WHEELCHAIR_1_2_5_TECHNICAL_PEAK_EXECUTION_BYTES_PRESERVED=PASS'
