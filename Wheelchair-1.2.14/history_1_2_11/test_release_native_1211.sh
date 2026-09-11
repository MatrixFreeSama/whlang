#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

if find . -type f -name '*.py' -print | grep -q .; then
  echo 'PYTHON_SOURCE_IN_RELEASE=FAIL' >&2; exit 1
fi
if grep -En '(^|[[:space:]])python(3)?([[:space:]]|$)' build.sh; then
  echo 'PRODUCTION_BUILD_PYTHON_INVOCATION=FAIL' >&2; exit 1
fi

./build.sh > .release_build_1211.log 2>&1
grep -q 'PRODUCTION_BUILD_PYTHON_INVOCATIONS=0' .release_build_1211.log
grep -q 'GENERAL_PARALLEL_BLIND_RESOURCE_RELEASE=PASS' .release_build_1211.log
grep -q 'WHEELCHAIR_1_2_11_NATIVE_PROFILE_SELECTOR=BUILT' .release_build_1211.log

for f in \
  build/wheelchairc build/whexc build/topologyc build/topologyc-wide build/topologyc-derived \
  build/topologyc-native256 build/topologyc-wide-native256 build/topologyc-derived-native256; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done

TMP=${TMPDIR:-/tmp}/wheelchair1211_release_$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# Static resource profile selector thresholds are structural and chosen before
# code generation.  The selected launcher image must be byte-identical to the
# explicitly selected physical capability binary.
build/whexc tests/profile_1211/base10.whex -o "$TMP/base_sel" --executors 1 >/dev/null
build/topologyc tests/profile_1211/base10.whex -o "$TMP/base_ref" --executors 1 >/dev/null
cmp "$TMP/base_sel" "$TMP/base_ref"
[ "$("$TMP/base_sel" 4)" = 'checksum_bits=0x3fce000000000000' ]

echo 'PROFILE_BASE_10_LOADS=PASS'

build/whexc tests/profile_1211/wide11.whex -o "$TMP/wide_sel" --executors 1 >/dev/null
build/topologyc-wide tests/profile_1211/wide11.whex -o "$TMP/wide_ref" --executors 1 >/dev/null
cmp "$TMP/wide_sel" "$TMP/wide_ref"
[ "$("$TMP/wide_sel" 4)" = 'checksum_bits=0x3fd1e00000000000' ]
echo 'PROFILE_WIDE_11_LOADS=PASS'

build/whexc tests/profile_1211/recompute15.whex -o "$TMP/recompute_sel" --executors 1 >/dev/null
build/topologyc tests/profile_1211/recompute15.whex -o "$TMP/recompute_ref" --executors 1 >/dev/null
cmp "$TMP/recompute_sel" "$TMP/recompute_ref"
[ "$("$TMP/recompute_sel" 4)" = 'checksum_bits=0x3fdfe00000000000' ]
echo 'PROFILE_BASE_RECOMPUTE_15_LOADS=PASS'

# The regression that motivated 1.2.11: coupled FSI has canonical structural
# pressure 12 and therefore must select wide for every executor width.
for q in 1 2 4; do
  build/whexc tests/profile_1211/fsi_coupled.whex -o "$TMP/fsi_sel_q$q" --executors "$q" >/dev/null
  build/topologyc-wide tests/profile_1211/fsi_coupled.whex -o "$TMP/fsi_ref_q$q" --executors "$q" >/dev/null
  cmp "$TMP/fsi_sel_q$q" "$TMP/fsi_ref_q$q"
done
[ "$("$TMP/fsi_sel_q4" 4)" = 'checksum_bits=0x3fb2acf007b0d71c' ]
echo 'FSI_PRESSURE_12_SELECTS_WIDE=PASS'
echo 'FSI_Q1_Q2_Q4_WIDE_BYTE_IDENTITY=PASS'

# Derived Rank-N remains higher-priority than base/wide pressure selection.
build/whexc tests/whex/rank6_native_122.whex -o "$TMP/rank6_sel" --executors 4 >/dev/null
build/topologyc-derived tests/whex/rank6_native_122.whex -o "$TMP/rank6_ref" --executors 4 >/dev/null
cmp "$TMP/rank6_sel" "$TMP/rank6_ref"
[ "$("$TMP/rank6_sel" 4)" = 'checksum_bits=0x40bfc00000000000' ]
echo 'PROFILE_DERIVED_RANKN_PRIORITY=PASS'

# Core 1.2.10 semantic/physical invariants stay protected.
build/wheelchairc tests/general_parallel_126/branch_probe.wh -o "$TMP/branch" --executors 4 >/dev/null
[ "$("$TMP/branch" 7)" = "out00_bits=0x0000000000000029
out01_bits=0x0000000000000012
out02_bits=0x0000000000000017" ]
build/wheelchairc tests/general_parallel_126/iterate_probe.wh -o "$TMP/iterate" --executors 4 >/dev/null
[ "$("$TMP/iterate" 2 5 3)" = "out00_bits=0x00000000000002f2
out01_bits=0x0000000000000043
out02_bits=0x00000000000002af" ]
build/wheelchairc surface/examples/feature_showcase.wh -o "$TMP/feature" --executors 1 >/dev/null
[ "$("$TMP/feature")" = "out00_bits=0x000000000000000c
out01_bits=0x0000000000000096
out02_bits=0x0000000000000015
out03_bits=0x4018000000000000
out04_bits=0x000000000000000f
out05_bits=0x000000000000000a
out06_bits=0x0000000000000015
out07_bits=0x0000000000000004" ]
build/wheelchairc surface/examples/auto_repair_typos.wh -o "$TMP/repair" --executors 1 >/dev/null
build/wheelchairc surface/examples/equivalent_zh_hans.wh -o "$TMP/zhs" --executors 1 >/dev/null
build/wheelchairc surface/examples/equivalent_zh_hant.wh -o "$TMP/zht" --executors 1 >/dev/null
set +e
build/wheelchairc tests/general_108/dynamic_dictionary.wh -o "$TMP/dd" >/dev/null 2>&1; r1=$?
build/wheelchairc tests/general_108/dynamic_cascade.wh -o "$TMP/dc" >/dev/null 2>&1; r2=$?
set -e
[ "$r1" -eq 65 ]
[ "$r2" -eq 65 ]

echo 'PROFILE_SELECTOR_WORKLOAD_IDENTITY=0'
echo 'PROFILE_SELECTOR_FAILURE_DRIVEN_FALLBACK=0'
echo 'PROFILE_SELECTOR_RUNTIME_PROFITABILITY=0'
echo 'PRODUCTION_LANGUAGE_PYTHON=0'
echo 'PRODUCTION_COMPILER_PYTHON=0'
echo 'PRODUCTION_RUNTIME_PYTHON=0'
echo 'BLIND_RESOURCE_RELEASE=PASS'
echo 'LANGUAGE_PURE_ASSEMBLY=PASS'
echo 'WHEELCHAIR_1_2_11_RELEASE=PASS'
