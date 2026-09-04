#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/complete123

python3 tools/apply_123.py

# Reuse the full mature 1.2.2 authority body, replacing only its obsolete
# whole-file semantic freeze with the stronger 1.2.3 canonical/native behavior
# authority. Every 1.2.2 Rank-N and older technical-peak gate is retained.
python3 - <<'PY'
from pathlib import Path
src=Path('test_complete_122.sh').read_text(encoding='utf-8')
# The derived 1.2.2 harness lives under build/complete123. Keep the release root
# inherited from this caller instead of deriving ROOT from the temporary path.
root_old='ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\ncd "$ROOT"'
if src.count(root_old)!=1:
    raise SystemExit('1.2.3 complete-harness root anchor changed')
src=src.replace(root_old,'ROOT=$(pwd)\ncd "$ROOT"',1)
old="sh test_wh_equivalence_122.sh"
new="sh test_wh_equivalence_123.sh"
if src.count(old)!=1:
    raise SystemExit('1.2.3 complete-harness WH/WHEX anchor changed')
src=src.replace(old,new,1)
p=Path('build/complete123/inherited_122.sh')
p.write_text(src,encoding='utf-8'); p.chmod(0o755)
PY
sh build/complete123/inherited_122.sh

# New 1.2.3 generic Global Coupled Operator / Sparse Causal Expansion authority.
sh test_sparse_causal_expansion_123.sh

echo 'WHEELCHAIR_1_2_2_TECHNICAL_PEAKS_ON_1_2_3=PASS'
echo 'WHEELCHAIR_1_2_3_COMPLETE=PASS'
