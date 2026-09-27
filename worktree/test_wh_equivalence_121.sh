#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/wh121

# 0. WHEX human surfaces and canonical semantics remain byte-frozen to 1.2.0.
# 1.2.1 intentionally changes only native realization, so compiler/runtime bytes
# and old native ELF hashes are not required to match the slower 1.2.0 baseline.
python3 - <<'PYFREEZE'
from pathlib import Path
import hashlib
want={
 'surface/wh_surface.py':'c2a2ce61b169de39d8bd4ff7de3e615ea71c86d25dbb64236b2c7ba5f2a59c09',
 'surface/whex_surface.py':'29d75d5f4f41c19a34dff1cca7366a5db6525d143514fa72d025386a3dece42d',
 'surface/whex_semantics.py':'32518611fad6079c91b68d67e11f09e902f8f86d62136532dac993e5929f2551',
}
for f,h in want.items():
    got=hashlib.sha256(Path(f).read_bytes()).hexdigest(); assert got==h,(f,got,h)
print('WHEX_1_2_0_SURFACE_SOURCE_FREEZE=PASS')
PYFREEZE

# Curated canonical hashes remain frozen because this release changes physical
# realization only.
python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0,'surface'); import whex_surface
want={
 'tests/whex/semantic_abstraction_showcase.whex':'891b7e498e92db366f7dd993d58895f9917dfb66df22ea95db14e70ce21503a2',
 'tests/whex/rankn_axis_erasure.whex':'64195e6dcffe5a588b8f06a960b3c286dec6ea7fce259e7b3f17cc2340d3f5bd',
 'tests/whex/semantic_independent_regions.whex':'05ca4e6d7d62ee5fa8b6603b5909d8209e9f6633be88876f697953e7aa3a71be',
 'tests/whex/operator_periodic_relation.whex':'19bebafa0bdddd07f711c5149a3f7f02b95d0cbfc5fbcb48b117f31864846e96',
 'surface/whex_examples/heat_en.whex':'4e928af88613abb9648a52c0d324d69160d4ed9a8df221bd0357d7addcb9b81f',
}
for f,h in want.items():
 d,p,_=whex_surface.load_surface(Path(f)); assert whex_surface.core_hash(d)==h,(f,whex_surface.core_hash(d),h)
print('WHEX_1_2_0_CANONICAL_FREEZE=PASS')
PY

# 1. Every currently accepted WHEX surface program is also a valid WH
# structural surface with identical canonical bytes. Intentional WHEX semantic
# rejection must also remain rejection rather than becoming a WH fallback.
python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0,'surface'); import whex_surface,wh_structural
files=sorted(list(Path('tests/whex').glob('*.whex'))+list(Path('surface/whex_examples').glob('*.whex')))
ok=rej=0
for p in files:
 text=p.read_text(encoding='utf-8')
 assert wh_structural.looks_structural(text),p
 try: dw,pw=whex_surface.compile_surface(text,p); ew=None
 except Exception as e: dw=None; ew=e
 try: dh,ph=wh_structural.compile_surface(text,Path(str(p)+'.wh')); eh=None
 except Exception as e: dh=None; eh=e
 assert (ew is None)==(eh is None),(p,ew,eh)
 if ew is not None:
  rej+=1; continue
 assert whex_surface.canonical_core_bytes(dw)==wh_structural.canonical_core_bytes(dh),p
 ok+=1
print(f'WH_ACCEPTS_WHEX_CANONICAL_CASES={ok}')
print(f'WH_MATCHES_WHEX_EXPLICIT_REJECTIONS={rej}')
PY

# 2. Familiar WH skins erase to the exact WHEX graph.
python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0,'surface'); import wh_structural,whex_surface
pairs=[
 ('tests/wh_equivalence/semantic_abstraction_showcase.wh','tests/whex/semantic_abstraction_showcase.whex'),
 ('tests/wh_equivalence/control_topology.wh','tests/whex/semantic_control_topology.whex'),
 ('tests/wh_equivalence/rankn_axis_erasure.wh','tests/whex/rankn_axis_erasure.whex'),
 ('tests/wh_equivalence/independent_regions.wh','tests/whex/semantic_independent_regions.whex'),
]
for a,b in pairs:
 da,pa,_=wh_structural.load_surface(Path(a)); db,pb,_=whex_surface.load_surface(Path(b))
 assert wh_structural.canonical_core_bytes(da)==whex_surface.canonical_core_bytes(db),(a,b)
print('WH_WHEX_CANONICAL_EQUIVALENCE=PASS')
PY

# The new WH structural skin keeps the existing multilingual shell contract.
python3 - <<'PYMULTI'
from pathlib import Path
import sys
sys.path.insert(0,'surface'); import wh_structural
a,_,_=wh_structural.load_surface(Path('tests/wh_equivalence/semantic_abstraction_showcase.wh'))
b,_,_=wh_structural.load_surface(Path('tests/wh_equivalence/semantic_abstraction_showcase_zh.wh'))
assert wh_structural.canonical_core_bytes(a)==wh_structural.canonical_core_bytes(b)
print('WH_STRUCTURAL_MULTILINGUAL_CANONICAL=PASS')
PYMULTI

# Native-capable equivalence pairs must be byte-identical ELFs.
for row in \
  'tests/wh_equivalence/semantic_abstraction_showcase.wh tests/whex/semantic_abstraction_showcase.whex abstract' \
  'tests/wh_equivalence/rankn_axis_erasure.wh tests/whex/rankn_axis_erasure.whex rankn' \
  'tests/wh_equivalence/independent_regions.wh tests/whex/semantic_independent_regions.whex regions'
do
  set -- $row
  ./wheelchairc "$1" -o "build/wh121/$3.wh.elf" --semantic-plan "build/wh121/$3.plan" >/dev/null
  ./whexc "$2" -o "build/wh121/$3.whex.elf" >/dev/null
  cmp "build/wh121/$3.wh.elf" "build/wh121/$3.whex.elf"
done
echo 'WH_WHEX_NATIVE_BYTE_EQUIVALENCE=PASS'

# 3. Imperative-looking syntax is audited as syntax only, with zero runtime
# loop/dispatcher objects and no introduced serial structure.
./wheelchairc tests/wh_equivalence/control_topology.wh -o build/wh121/control_should_reject --semantic-plan build/wh121/control.plan >/dev/null 2>&1 || true
# control_topology's WHEX graph is semantic-plan-only in the frozen native lane;
# inspect it directly without routing it to another backend.
python3 - <<'PY'
from pathlib import Path
import json,sys
sys.path.insert(0,'surface'); import wh_structural
for f in ['tests/wh_equivalence/semantic_abstraction_showcase.wh','tests/wh_equivalence/control_topology.wh','tests/wh_equivalence/rankn_axis_erasure.wh','tests/wh_equivalence/independent_regions.wh']:
 d,p,_=wh_structural.load_surface(Path(f)); q=p.semantic_plan
 s=q['surface']; r=q['serial_introduction']; c=q['parallelism_contract']
 assert s['runtime_loop_objects']==0 and s['runtime_if_dispatchers']==0 and s['runtime_surface_objects']==0
 assert s['imperative_syntax_implies_serial_execution'] is False
 assert all(v==0 for v in r.values()),(f,r)
 assert c['scalar_fallback_allowed'] is False and c['central_scheduler_allowed'] is False
 assert c['global_queue_allowed'] is False and c['global_barrier_allowed_without_dependency'] is False
print('WH_FAKE_FOR_RUNTIME_LOOP_OBJECTS=0')
print('WH_FAKE_IF_RUNTIME_DISPATCHERS=0')
print('WH_SERIAL_INTRODUCTION_REPORT_ZERO=PASS')
print('WH_PARALLELISM_PRESERVATION_CONTRACT=PASS')
PY

# 4. Rank-N follows the same prove-and-erase/no-fake-flatten policy as WHEX.
python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0,'surface'); import wh_structural
_,p,_=wh_structural.load_surface(Path('tests/wh_equivalence/rankn_axis_erasure.wh'))
a=p.semantic_plan['axis_algebra']
assert a['maximum_source_rank']==2 and a['maximum_native_binding_rank']==1
assert a['rank_n_eliminations'][0]['proof']=='expression_independent_of_erased_axes'
assert a['rank_n_eliminations'][0]['erased_axes']==[{'name':'j','extent':4}]
print('WH_RANK_N_PROVE_AND_ERASE=PASS')
PY

# 5. Dynamic `while` is recognized as intent but cannot create a serial
# backedge. Explicit rejection is the only legal current behavior.
set +e
./wheelchairc tests/wh_equivalence/while_reject.wh -o build/wh121/while_bad >build/wh121/while.out 2>build/wh121/while.err
rc=$?
set -e
[ "$rc" -eq 65 ]
[ ! -e build/wh121/while_bad ]
grep -q "not permission to emit a serial backedge" build/wh121/while.err
echo 'WH_DYNAMIC_WHILE_NO_SERIAL_FALLBACK=PASS'

# 6. Structural WH never falls back to the legacy general lane on native
# rejection. The control example has a canonical WHEX peer that the frozen
# WHEX native realizer itself rejects; WH must reject too.
set +e
./wheelchairc tests/wh_equivalence/control_topology.wh -o build/wh121/control_bad >build/wh121/control.out 2>build/wh121/control.err
rc=$?
set -e
[ "$rc" -ne 0 ]
[ ! -e build/wh121/control_bad ]
grep -q 'structured source rejected' build/wh121/control.err
echo 'WH_STRUCTURAL_NO_GENERAL_FALLBACK=PASS'

echo 'WH_WHEX_SURFACE_EQUIVALENCE_1_2_1=PASS'
