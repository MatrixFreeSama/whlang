#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/complete122

# Reuse the complete mature 1.2.1 regression body, replacing only historical
# assertions whose physical/build or host-tool syntax envelope is intentionally
# superseded by 1.2.2. Mathematical/runtime/parallel invariants stay intact.
python3 - <<'PY'
from pathlib import Path
src=Path('test_complete.sh').read_text(encoding='utf-8')
# This generated script lives under build/, therefore preserve the caller's
# release-tree root instead of deriving ROOT from the temporary script path.
src=src.replace('ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\ncd "$ROOT"', 'ROOT=$(pwd)\ncd "$ROOT"', 1)
# 1.0.9's blanket build.sh `python` keyword proxy predates the exact,
# hash-protected Rank-N assembly bootstrap generator. The 1.2.2 inherited gate
# keeps the sovereign-backend proof and narrows only that proxy.
src=src.replace('./test_109.sh','sh test_109_122.sh')
# Keep the scheduler/resource machine-code assertions unchanged while using a
# parser-version-independent spelling of its diagnostic summary expression.
src=src.replace('./test_scheduler.sh','sh test_scheduler_122.sh')
# Preserve the 1.0.11 numeric/executor/vector-native invariant without requiring
# one exact register-pressure manifestation on every AVX-512 microarchitecture.
src=src.replace('./test_operator_span_mature_1011.sh','sh test_operator_span_mature_122.sh')
# 1.1.0's non-erasable Rank-N rejection was a physical Rank-1 ceiling, not a
# permanent semantic invariant. 1.2.2 replaces it with positive native proof.
src=src.replace('./test_whex_semantic_parallel_121.sh','sh test_whex_semantic_parallel_122.sh')
# 1.2.1 froze the entire WHEX routing-surface source because it was a physical-
# only release. 1.2.2 intentionally extends that surface for Rank-N, so preserve
# the old canonical/native corpus instead of imposing the obsolete whole-file SHA.
src=src.replace('./test_wh_equivalence_121.sh','sh test_wh_equivalence_122.sh')
src=src.replace("echo 'WHEELCHAIR_1_1_0_SEMANTIC_INVARIANTS_ON_1_2_1=PASS'",
                "echo 'WHEELCHAIR_1_1_0_SEMANTIC_INVARIANTS_ON_1_2_2=PASS'")
src=src.replace("echo 'WHEELCHAIR_1_2_0_SURFACE_INVARIANTS_ON_1_2_1=PASS'",
                "echo 'WHEELCHAIR_1_2_0_SURFACE_INVARIANTS_ON_1_2_2=PASS'")
src=src.replace("echo 'WHEELCHAIR_1_2_1_COMPLETE=PASS'",
                "echo 'WHEELCHAIR_1_2_1_INVARIANTS_ON_1_2_2=PASS'")
p=Path('build/complete122/inherited.sh')
p.write_text(src,encoding='utf-8')
p.chmod(0o755)
PY
sh build/complete122/inherited.sh

# New 1.2.2 native Rank-N authority gate. It also rechecks the exact 1.2.1
# periodic and Newton/Jv peak witnesses after the new physical capability exists.
sh test_rank_n_122.sh

echo 'WHEELCHAIR_1_2_2_COMPLETE=PASS'
