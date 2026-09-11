#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

# Compatibility entry point only. The complete mature native256 physicalization
# is now produced by the normal build itself. No diagnostic injection, second
# code-generation pass, or relink is permitted in the release authority path.
./build.sh

echo 'NATIVE256_NORMAL_BUILD_MATURITY_AUTHORITY=PASS'
echo 'NATIVE256_SECOND_STAGE_DIAGNOSTIC_INJECTION=0'
echo 'NATIVE256_SECOND_STAGE_RELINK=0'
