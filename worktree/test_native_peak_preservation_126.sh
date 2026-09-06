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

compare_alloc() {
  new=$1 old=$2 name=$3
  objcopy -O binary "$new" "/tmp/${name}.new.bin"
  objcopy -O binary "$old" "/tmp/${name}.old.bin"
  cmp "/tmp/${name}.new.bin" "/tmp/${name}.old.bin"
  echo "${name}_LOADABLE_BYTE_IDENTITY=PASS"
}
compare_alloc build/topologyc "$BASE125/build/topologyc" BASE_PROFILE_1_2_5_COMPILER
compare_alloc build/topologyc-wide "$BASE125/build/topologyc-sdep" WIDE_PROFILE_1_2_5_COMPILER

compare_alloc build/tensor_frontend_derived.o "$BASE125/build/tensor_rankn_frontend.o" DERIVED_PROFILE_1_2_5_FRONTEND
objcopy -O binary --only-section=.text build/topologyc-derived /tmp/derived_compiler_text.new.bin
objcopy -O binary --only-section=.text "$BASE125/build/topologyc-rankn" /tmp/derived_compiler_text.old.bin
cmp /tmp/derived_compiler_text.new.bin /tmp/derived_compiler_text.old.bin
echo 'DERIVED_PROFILE_1_2_5_COMPILER_TEXT_BYTE_IDENTITY=PASS'
compare_alloc build/tensor_derived_runtime_template "$BASE125/build/tensor_rankn_runtime_template" DERIVED_PROFILE_1_2_5_RUNTIME

cmp build/tensor_runtime_template "$BASE125/build/tensor_runtime_template"
cmp build/general_runtime_template "$BASE125/build/general_runtime_template"
echo 'MATURE_RUNTIME_1_2_5_NATIVE_BYTE_IDENTITY=PASS'

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

# Emitted-program authority requires a real AVX-512F compiler host because
# topologyc intentionally self-scans the host before tensor lowering. The
# compiler/runtime execution bytes above are host-independent and mandatory.
compare_emit_loadable() {
  new=$1 old=$2 core=$3 name=$4
  "$old" "$core" -o "build/${name}.old.elf" --isa-limit avx512f
  "$new" "$core" -o "build/${name}.new.elf" --isa-limit avx512f
  objcopy -O binary "build/${name}.old.elf" "/tmp/${name}.old.load.bin"
  objcopy -O binary "build/${name}.new.elf" "/tmp/${name}.new.load.bin"
  cmp "/tmp/${name}.new.load.bin" "/tmp/${name}.old.load.bin"
  echo "${name}_EMITTED_LOADABLE_BYTE_IDENTITY=PASS"
}

if grep -qm1 -w avx512f /proc/cpuinfo; then
  echo 'TECHNICAL_PEAK_HOST_AVX512_QUALIFIED=1'
  compare_emit_loadable build/topologyc "$BASE125/build/topologyc" /tmp/peak_base.core.wh BASE_PROFILE_1_2_5
  compare_emit_loadable build/topologyc-wide "$BASE125/build/topologyc-sdep" /tmp/peak_wide.core.wh WIDE_PROFILE_1_2_5
  compare_emit_loadable build/topologyc-derived "$BASE125/build/topologyc-rankn" /tmp/peak_derived.core.wh DERIVED_PROFILE_1_2_5

  build/DERIVED_PROFILE_1_2_5.new.elf 8 >/tmp/derived126.dynamic.out
  build/DERIVED_PROFILE_1_2_5.old.elf 8 >/tmp/derived125.dynamic.out
  cmp /tmp/derived126.dynamic.out /tmp/derived125.dynamic.out
  echo 'DERIVED_PROFILE_DYNAMIC_EXECUTION_EQUIVALENCE=PASS'
else
  echo 'TECHNICAL_PEAK_HOST_AVX512_QUALIFIED=0'
  echo 'BASE_PROFILE_1_2_5_EMITTED_LOADABLE_BYTE_IDENTITY=SKIP_HOST_NOT_AVX512F'
  echo 'WIDE_PROFILE_1_2_5_EMITTED_LOADABLE_BYTE_IDENTITY=SKIP_HOST_NOT_AVX512F'
  echo 'DERIVED_PROFILE_1_2_5_EMITTED_LOADABLE_BYTE_IDENTITY=SKIP_HOST_NOT_AVX512F'
  echo 'DERIVED_PROFILE_DYNAMIC_EXECUTION_EQUIVALENCE=SKIP_HOST_NOT_AVX512F'
fi

echo 'NONEXECUTING_ELF_FILENAME_METADATA_MAY_DIFFER=1'
echo 'WHEELCHAIR_1_2_5_TECHNICAL_PEAK_EXECUTION_BYTES_PRESERVED=PASS'
