#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
[ "$(cat VERSION)" = "1.2.5" ]
sh build.sh
sh test_109_125.sh
sh test_shared_dependency_episode_125.sh
sh test_generic_native_125.sh
sh test_rank_n_122.sh
sh test_sparse_causal_expansion_123.sh
echo 'RANK_N_1_2_2_TECHNICAL_PEAK_PROTECTED_ON_1_2_5=PASS'
echo 'SCE_1_2_3_TECHNICAL_PEAK_PROTECTED_ON_1_2_5=PASS'
echo 'GENERIC_NATIVE_1_2_4_TECHNICAL_PEAK_PROTECTED_ON_1_2_5=PASS'
echo 'WHEELCHAIR_1_2_5_COMPLETE=PASS'
