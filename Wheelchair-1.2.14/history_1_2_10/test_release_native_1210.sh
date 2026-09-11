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
./build.sh > .release_build.log 2>&1
grep -q 'PRODUCTION_BUILD_PYTHON_INVOCATIONS=0' .release_build.log
grep -q 'GENERAL_PARALLEL_BLIND_RESOURCE_RELEASE=PASS' .release_build.log
for f in build/wheelchairc build/whexc build/topologyc build/topologyc-derived; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done
TMP=${TMPDIR:-/tmp}/wheelchair1210_release_$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
build/wheelchairc tests/general_parallel_126/branch_probe.wh -o "$TMP/branch" --executors 4 >/dev/null
[ "$("$TMP/branch" 7)" = "out00_bits=0x0000000000000029
out01_bits=0x0000000000000012
out02_bits=0x0000000000000017" ]
build/wheelchairc tests/general_parallel_126/iterate_probe.wh -o "$TMP/iterate" --executors 4 >/dev/null
[ "$("$TMP/iterate" 2 5 3)" = "out00_bits=0x00000000000002f2
out01_bits=0x0000000000000043
out02_bits=0x00000000000002af" ]
build/whexc tests/whex/rank6_native_122.whex -o "$TMP/rank6" --executors 4 >/dev/null
[ "$("$TMP/rank6" 4)" = 'checksum_bits=0x40bfc00000000000' ]
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
echo 'PRODUCTION_LANGUAGE_PYTHON=0'
echo 'PRODUCTION_COMPILER_PYTHON=0'
echo 'PRODUCTION_RUNTIME_PYTHON=0'
echo 'BLIND_RESOURCE_RELEASE=PASS'
echo 'LANGUAGE_PURE_ASSEMBLY=PASS'
echo 'WHEELCHAIR_1_2_10_RELEASE=PASS'
