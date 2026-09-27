#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/semantic110

# 1. New high-level abstractions must erase to byte-identical canonical graph
# and native machine code compared with the manually inlined source.
python3 surface/whex_surface.py compile tests/whex/semantic_abstraction_showcase.whex -o build/semantic110/abstract.core >/dev/null
python3 surface/whex_surface.py compile tests/whex/topology_showcase.whex -o build/semantic110/inline.core >/dev/null
cmp build/semantic110/abstract.core build/semantic110/inline.core
./whexc tests/whex/semantic_abstraction_showcase.whex -o build/semantic110/abstract --semantic-plan build/semantic110/abstract.plan >/dev/null
./whexc tests/whex/topology_showcase.whex -o build/semantic110/inline >/dev/null
cmp build/semantic110/abstract build/semantic110/inline
[ "$(build/semantic110/abstract 4)" = 'checksum_bits=0xc000000000000000' ]
echo 'WHEX_HIGH_LEVEL_CANONICAL_ERASURE=PASS'
echo 'WHEX_HIGH_LEVEL_MACHINE_CODE_ERASURE=PASS'
# New semantic vocabulary is still an erasable multilingual shell.
python3 surface/whex_surface.py compile tests/whex/semantic_abstraction_showcase_zh.whex -o build/semantic110/abstract_zh.core >/dev/null
cmp build/semantic110/abstract.core build/semantic110/abstract_zh.core
python3 surface/whex_surface.py format tests/whex/semantic_abstraction_showcase.whex --language zh-hant > build/semantic110/abstract_zh_hant.whex
python3 surface/whex_surface.py compile build/semantic110/abstract_zh_hant.whex -o build/semantic110/abstract_zh_hant.core >/dev/null
cmp build/semantic110/abstract.core build/semantic110/abstract_zh_hant.core
echo 'WHEX_HIGH_LEVEL_MULTILINGUAL_ERASURE=PASS'

python3 - <<'PY'
import json
p=json.load(open('build/semantic110/abstract.plan'))
e=p['erasure']; s=p['serial_introduction']; q=p['parallelism_contract']
assert e['surface_functions']==1 and e['runtime_function_objects']==0
assert e['runtime_call_boundaries_from_surface_functions']==0
assert e['surface_records']==1 and e['runtime_record_objects']==0
assert e['runtime_region_objects']==0 and e['runtime_effect_dispatch']==0
assert all(v==0 for v in s.values()),s
assert q['scalar_fallback_allowed'] is False
assert q['central_scheduler_allowed'] is False
assert q['global_queue_allowed'] is False
assert q['global_barrier_allowed_without_dependency'] is False
o=p['ownership']
assert o['shared_mutable_writes']==0 and o['runtime_borrow_table'] is False
assert o['implicit_locking'] is False and o['data_race_free_by_current_pure_lane'] is True
assert o['alias_uncertainty_policy']=='explicit_reject_not_serialization'
print('WHEX_TOPOLOGY_OWNERSHIP=PASS')
print('WHEX_ABSTRACTION_ERASURE_REPORT=PASS')
print('WHEX_SERIAL_INTRODUCTION_REPORT_ZERO=PASS')
PY

# 2. Independent regions must remain unrelated in the dependency topology.
./whexc tests/whex/semantic_independent_regions.whex -o build/semantic110/regions --semantic-plan build/semantic110/regions.plan >/dev/null
[ "$(build/semantic110/regions 4)" = 'checksum_bits=0x4036000000000000' ]
python3 - <<'PY'
import json
p=json.load(open('build/semantic110/regions.plan'))
t=p['dependency_topology']
pairs={tuple(x) for x in t['independent_binding_pairs']}
assert ('a','b') in pairs or ('b','a') in pairs,pairs
assert t['synthetic_order_edges']==0
rt=p['region_topology']
assert rt['synthetic_order_edges']==0 and rt['implicit_global_lock'] is False
assert rt['implicit_global_allocator_lock'] is False
rpairs={tuple(x) for x in rt['independent_region_pairs']}
assert ('left','right') in rpairs or ('right','left') in rpairs
rows={x['name']:x for x in p['bindings']}
assert rows['a']['dependencies']==[] and rows['b']['dependencies']==[]
assert rows['total']['dependencies']==['a','b']
assert all(x['parallel_required'] for x in p['bindings'])
print('WHEX_INDEPENDENT_REGIONS_NO_SYNTHETIC_ORDER=PASS')
print('WHEX_DEPENDENCY_TOPOLOGY=PASS')
PY

# 3. `select` is recognized as dataflow/predicate control, not a source-level
# permission for a hidden sequential dispatcher.
python3 surface/whex_surface.py plan tests/whex/semantic_control_topology.whex > build/semantic110/control.plan
python3 - <<'PY'
import json
p=json.load(open('build/semantic110/control.plan'))
assert p['control_topology']['select_nodes']>=1
assert p['control_topology']['source_loop_implies_serial_loop'] is False
assert p['control_topology']['predicate_regions_are_dataflow'] is True
print('WHEX_CONTROL_TOPOLOGY=PASS')
PY

# 4. Rank-N axis algebra: dimensions that are mathematically irrelevant are
# removed before native realization, never flattened into a serial nest.
python3 surface/whex_surface.py compile tests/whex/rankn_axis_erasure.whex -o build/semantic110/rankn.core >/dev/null
python3 surface/whex_surface.py compile tests/whex/rankn_axis_erasure_inline.whex -o build/semantic110/rankn_inline.core >/dev/null
cmp build/semantic110/rankn.core build/semantic110/rankn_inline.core
./whexc tests/whex/rankn_axis_erasure.whex -o build/semantic110/rankn --semantic-plan build/semantic110/rankn.plan >/dev/null
./whexc tests/whex/rankn_axis_erasure_inline.whex -o build/semantic110/rankn_inline >/dev/null
cmp build/semantic110/rankn build/semantic110/rankn_inline
[ "$(build/semantic110/rankn 4)" = 'checksum_bits=0x4038000000000000' ]
python3 - <<'PYRANK'
import json
p=json.load(open('build/semantic110/rankn.plan'))
a=p['axis_algebra']
assert a['maximum_source_rank']==2 and a['maximum_native_binding_rank']==1
assert len(a['rank_n_eliminations'])==1
r=a['rank_n_eliminations'][0]
assert r['source_rank']==2 and r['native_rank']==1
assert r['multiplicity']==4 and r['erased_axes']==[{'name':'j','extent':4}]
assert r['proof']=='expression_independent_of_erased_axes'
assert p['parallelism_contract']['rank_n_erasure_is_math_elimination'] is True
print('WHEX_RANK_N_AXIS_ERASURE=PASS')
print('WHEX_RANK_N_MACHINE_CODE_ERASURE=PASS')
PYRANK
# A genuinely used second axis must remain Rank-N and be rejected by the current
# physical realizer.  It may not be silently flattened into a sequential loop.
python3 surface/whex_surface.py plan tests/whex/rankn_axis_nonerasable.whex > build/semantic110/rankn_nonerasable.plan
if ./whexc tests/whex/rankn_axis_nonerasable.whex -o build/semantic110/rankn_bad >/dev/null 2>&1; then
  echo 'non-erasable Rank-N topology was incorrectly accepted' >&2; exit 1
fi
python3 - <<'PYRANK2'
import json
p=json.load(open('build/semantic110/rankn_nonerasable.plan'))
assert p['axis_algebra']['maximum_source_rank']==2
assert p['axis_algebra']['rank_n_eliminations']==[]
assert p['serial_introduction']['new_serial_backedges']==0
print('WHEX_RANK_N_NO_FAKE_FLATTEN=PASS')
PYRANK2

# 5. Effectful regions are not silently serialized, locked, queued, or routed
# through a general frontend. They reject until a genuine native effect topology exists.
if ./whexc tests/whex/semantic_effect_reject.whex -o build/semantic110/effect_bad >/dev/null 2>&1; then
  echo 'effectful WHEX region was incorrectly accepted' >&2; exit 1
fi
echo 'WHEX_EFFECT_NO_HIDDEN_SERIALIZATION=PASS'

# 6. 1.2.1 intentionally improves native realization. Semantic releases before
# it froze the 1.0.15 native image, but the charter allows that baseline to move
# after correctness/topology/performance proof. The historical source/canonical
# semantics remain unchanged; the current native image must still return the
# exact established result and preserve the vector-authoritative runtime.
build/topologyc tests/topology_cases/heat_diffusion_step_tolerant.wh -o build/semantic110/heat_baseline >/dev/null
[ "$(build/semantic110/heat_baseline 16777216)" = 'checksum_bits=0x4167fc0000000000' ]
echo 'WHEX_NATIVE_BASELINE_INTENTIONAL_IMPROVEMENT=PASS'

# 7. Existing tensor runtime remains vector-authoritative.
python3 - <<'PY'
from pathlib import Path
rt=Path('runtime/tensor_runtime_template_x86_64.S').read_text()
src=(Path('compiler/tensor_frontend_x86_64.S').read_text()+Path('compiler/topologyc_x86_64.S').read_text()).lower()
assert 'call eval_slot' not in rt
for bad in ('global_task_queue','central_spawn_loop','central_wait_loop','central_reduction_loop'):
    # Names may appear in proof prose but are forbidden as implementation labels/symbols.
    assert (bad+':') not in src,bad
print('WHEX_SEMANTIC_LAYER_SCALAR_FALLBACK=0')
print('WHEX_SEMANTIC_LAYER_CENTRAL_SERIAL_SPINE=0')
PY

echo 'WHEX_GENERAL_TRUE_PARALLEL_SEMANTICS_1_2_1=PASS'
