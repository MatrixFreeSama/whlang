#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
TMP="$ROOT/.test_wh_equivalence_123_derived.$$"
trap 'rm -f "$TMP"' EXIT INT TERM

# 1.2.3 intentionally extends whex_semantics.py with the generic Global Coupled
# Operator proof layer. Preserve the 1.2.2 compatibility authority by keeping
# the unchanged WH human surface byte-frozen and rerunning all old canonical and
# native byte-equivalence cases. Only the obsolete whole-file semantic SHA is
# removed.
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path('test_wh_equivalence_122.sh').read_text(encoding='utf-8')
needle=" 'surface/whex_semantics.py':'32518611fad6079c91b68d67e11f09e902f8f86d62136532dac993e5929f2551',\n"
if src.count(needle)!=1:
    raise SystemExit('1.2.3 WH/WHEX inherited semantic-freeze anchor changed')
src=src.replace(needle,'',1)
src=src.replace("print('WHEX_1_2_0_UNCHANGED_SEMANTIC_FOUNDATION_FREEZE=PASS')",
                "print('WHEX_1_2_0_UNCHANGED_HUMAN_SURFACE_FREEZE=PASS')",1)
src=src.replace("echo 'WH_WHEX_SURFACE_EQUIVALENCE_1_2_2=PASS'",
                "echo 'WH_WHEX_LEGACY_AND_RANK_N_EQUIVALENCE_ON_1_2_3=PASS'",1)
Path(sys.argv[1]).write_text(src,encoding='utf-8')
PY
chmod +x "$TMP"
sh "$TMP"

python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0,'surface')
import whex_surface, wh_structural

# The old independent-regions program keeps its exact canonical graph while both
# surfaces gain the same compile-time operator proof.
w=Path('tests/whex/semantic_independent_regions.whex')
h=Path('tests/wh_equivalence/independent_regions.wh')
dw,pw,_=whex_surface.load_surface(w)
dh,ph,_=wh_structural.load_surface(h)
assert whex_surface.canonical_core_bytes(dw)==wh_structural.canonical_core_bytes(dh)
for p in (pw,ph):
    g=p.semantic_plan['global_operator_algebra']
    assert g['model']=='global_coupled_operator'
    assert g['workload_dispatch'] is False
    assert g['laplace_minor_enumeration'] is False
    assert p.semantic_plan['parallelism_contract']['global_operator_root_dispatch'] is False
    assert p.semantic_plan['serial_introduction']['new_global_operator_serial_spines']==0
    assert p.semantic_plan['erasure']['runtime_separator_plan_objects']==0
print('WH_WHEX_GLOBAL_OPERATOR_CANONICAL_EQUIVALENCE=PASS')
print('GLOBAL_OPERATOR_SEMANTIC_EXTENSION_RUNTIME_ERASURE=PASS')
PY

echo 'WH_WHEX_SURFACE_EQUIVALENCE_1_2_3=PASS'
