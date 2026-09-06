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

compare_loadable() {
  new=$1 old=$2 name=$3
  objcopy -O binary "$new" "/tmp/${name}.new.bin"
  objcopy -O binary "$old" "/tmp/${name}.old.bin"
  cmp "/tmp/${name}.new.bin" "/tmp/${name}.old.bin"
  echo "${name}_COMPILER_LOADABLE_BYTE_IDENTITY=PASS"
}
compare_loadable build/topologyc "$BASE125/build/topologyc" BASE_PROFILE_1_2_5
compare_loadable build/topologyc-wide "$BASE125/build/topologyc-sdep" WIDE_PROFILE_1_2_5
compare_loadable build/topologyc-derived "$BASE125/build/topologyc-rankn" DERIVED_PROFILE_1_2_5
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

compare_emit() {
  new=$1 old=$2 core=$3 name=$4
  "$old" "$core" -o "build/${name}.old.elf"
  "$new" "$core" -o "build/${name}.new.elf"
  cmp "build/${name}.new.elf" "build/${name}.old.elf"
  echo "${name}_EMITTED_NATIVE_BYTE_IDENTITY=PASS"
}
compare_emit build/topologyc "$BASE125/build/topologyc" /tmp/peak_base.core.wh BASE_PROFILE_1_2_5
compare_emit build/topologyc-wide "$BASE125/build/topologyc-sdep" /tmp/peak_wide.core.wh WIDE_PROFILE_1_2_5
compare_emit build/topologyc-derived "$BASE125/build/topologyc-rankn" /tmp/peak_derived.core.wh DERIVED_PROFILE_1_2_5

echo 'WHEELCHAIR_1_2_5_TECHNICAL_PEAK_BYTES_PRESERVED=PASS'
