#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/complete122

# Reuse the complete mature 1.2.1 regression body, replacing only historical
# assertions whose physical/build envelope is intentionally superseded by
# 1.2.2 Rank-N. All mathematical, runtime, serial-spine, WH/WHEX, periodic and
# Newton/Jv invariants remain intact.
python3 - <<'PY'
from pathlib import Path
src=Path('test_complete.sh').read_text(encoding='utf-8')
# This generated script lives under build/, therefore preserve the caller's
# release-tree root instead of deriving ROOT from the temporary script path.
src=src.replace('ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\ncd "$ROOT"', 'ROOT=$(pwd)\ncd "$ROOT"', 1)
# 1.0.9's blanket build.sh `python` keyword proxy predates the exact,
# hash-protected Rank-N assembly bootstrap generator. The 1.2.2 inherited gate
# keeps the sovereign-backend proof and narrows only that proxy.
src=src.replace('./test_109.sh','./test_109_122.sh')
# 1.1.0's non-erasable Rank-N rejection was a physical Rank-1 ceiling, not a
# permanent semantic invariant. 1.2.2 replaces it with positive native proof.
src=src.replace('./test_whex_semantic_parallel_121.sh','./test_whex_semantic_parallel_122.sh')
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
