#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

python3 tools/apply_123.py
sh build.sh

# Preserve the entire mature 1.2.3 authority first. This may rebuild artifacts;
# the 1.2.4 generic-native gate rebuilds the accepted final lane afterwards.
sh test_complete_123.sh

sh build.sh
sh test_generic_native_124.sh

echo 'WHEELCHAIR_1_2_3_COMPLETE_ON_1_2_4=PASS'
echo 'WHEELCHAIR_GENERIC_NATIVE_1_2_4=PASS'
echo 'WHEELCHAIR_1_2_4_COMPLETE=PASS'
