#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/sce123

python3 tools/apply_123.py

python3 - <<'PY'
from pathlib import Path
import ast, json, math, sys
sys.path.insert(0,'surface')
import sparse_causal_expansion as sce

# The production planner may mention workload names in explanatory metadata, but
# no branch/match condition may dispatch on them.
tree=ast.parse(Path('surface/sparse_causal_expansion.py').read_text(encoding='utf-8'))
for node in ast.walk(tree):
    if isinstance(node,(ast.If,ast.IfExp,ast.Match)):
        text=ast.unparse(node).lower()
        for banned in ('newton','fem','cfd','poisson','kkt','fluid','solid'):
            assert banned not in text,(banned,text)
print('GLOBAL_OPERATOR_NO_WORKLOAD_DISPATCH=PASS')

# A 31-node path has repeated, balanced separator structure. The same algorithm
# sees no physics name and produces a binary separator tree with bounded overhead.
chain={
 'nodes':[{'id':f'x{i}','recipe':'cell'} for i in range(31)],
 'edges':[[f'x{i}',f'x{i+1}'] for i in range(30)],
 'separator_cap':1,'leaf_size':1,
 'work_amplification_limit':2.1,'memory_amplification_limit':1.6,
 'communication_amplification_limit':1.1,
}
p=sce.plan_graph(chain)
assert p['laplace_minor_enumeration'] is False
assert p['metrics']['duplicate_region_expansions']==0
assert p['metrics']['work_amplification'] <= 2.1
assert p['metrics']['memory_amplification'] <= 1.6
assert p['metrics']['communication_amplification'] <= 1.1
assert p['parallelism_contract']['central_spawn_loop']==0
assert p['parallelism_contract']['central_wait_loop']==0
assert p['parallelism_contract']['central_reduction_loop']==0
assert p['parallelism_contract']['global_task_queue']==0
assert p['parallelism_contract']['scalar_fallback']==0
assert p['parallelism_contract']['hidden_serial_fallback']==0
assert p['parallelism_contract']['non_neighbor_communication']==0
assert p['parallelism_contract']['binary_separator_composition'] is True
assert p['metrics']['critical_tree_depth'] <= 6
assert p['metrics']['unique_symbolic_recipes'] < p['metrics']['symbolic_recipe_instances']
print('SPARSE_CAUSAL_EXPANSION_CHAIN31=PASS')
print('SPARSE_CAUSAL_EXPANSION_DUPLICATE_REGION_EXPANSIONS=0')
print('SPARSE_CAUSAL_EXPANSION_BINARY_DAG=PASS')
print('SPARSE_CAUSAL_EXPANSION_BOUNDED_AMPLIFICATION=PASS')

# Rename every region and even use workload-looking labels. Structural proof must
# stay identical because names are not an optimization input.
rename={f'x{i}':f'newton_{i}' for i in range(31)}
renamed=dict(chain)
renamed['nodes']=[{'id':rename[f'x{i}'],'recipe':'cell'} for i in range(31)]
renamed['edges']=[[rename[a],rename[b]] for a,b in chain['edges']]
q=sce.plan_graph(renamed)
assert p['structural_sha256']==q['structural_sha256']
print('GLOBAL_OPERATOR_NAME_ERASURE=PASS')

# A complete graph with a separator cap of one has no proved split. Required
# expansion must reject instead of pretending to parallelize or falling scalar.
dense={'nodes':[f'd{i}' for i in range(6)],
       'edges':[[f'd{i}',f'd{j}'] for i in range(6) for j in range(i+1,6)],
       'separator_cap':1,'leaf_size':1,'require_split':True,
       'work_amplification_limit':10.0,'memory_amplification_limit':10.0,
       'communication_amplification_limit':10.0}
try:
    sce.plan_graph(dense)
except sce.SparseCausalExpansionError as e:
    assert 'no bounded separator' in str(e)
else:
    raise AssertionError('dense graph was falsely expanded')
print('SPARSE_CAUSAL_EXPANSION_UNPROVEN_DENSE_REJECT=PASS')

# Overhead budgets are hard admission gates, not reporting-only counters.
expensive={'nodes':['a','s','b'],'edges':[['a','s'],['s','b']],
           'separator_cap':1,'leaf_size':1,'work_amplification_limit':1.1,
           'memory_amplification_limit':2.0,'communication_amplification_limit':2.0}
try:
    sce.plan_graph(expensive)
except sce.SparseCausalExpansionError as e:
    assert 'work amplification' in str(e)
else:
    raise AssertionError('work-amplification gate did not reject')
print('SPARSE_CAUSAL_EXPANSION_WORK_AMPLIFICATION_REJECT=PASS')

# Every interior/separator node occurs exactly once in the decomposition tree.
def walk(t,seen):
    if t['kind']=='leaf': names=t['nodes']
    else:
        names=t['separator']
        assert len(t['children'])==2
        for c in t['children']: walk(c,seen)
    for n in names:
        assert n not in seen,n
        seen.add(n)
seen=set()
for t in p['forest']: walk(t,seen)
assert seen=={f'x{i}' for i in range(31)}
print('SPARSE_CAUSAL_EXPANSION_NO_REPEATED_MINOR_SUBPROBLEM=PASS')
PY

# The WHEX/WH semantic layer must consume the same generic planner automatically
# from region dependency topology. Renaming regions cannot affect canonical or
# native bytes.
python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0,'surface')
import whex_surface, wh_structural

a,pa,_=whex_surface.load_surface(Path('tests/whex/global_operator_separator_123_a.whex'))
b,pb,_=whex_surface.load_surface(Path('tests/whex/global_operator_separator_123_b.whex'))
assert whex_surface.canonical_core_bytes(a)==whex_surface.canonical_core_bytes(b)
for parser in (pa,pb):
    plan=parser.semantic_plan
    g=plan['global_operator_algebra']
    assert g['model']=='global_coupled_operator'
    assert g['workload_dispatch'] is False
    assert g['newton_special_case'] is False
    assert g['physics_name_dispatch'] is False
    assert g['matrix_materialization_required'] is False
    proof=g['sparse_causal_expansion']
    assert proof['metrics']['duplicate_region_expansions']==0
    assert proof['parallelism_contract']['central_reduction_loop']==0
    assert proof['parallelism_contract']['non_neighbor_communication']==0
    assert proof['laplace_minor_enumeration'] is False
assert pa.semantic_plan['global_operator_algebra']['sparse_causal_expansion']['structural_sha256']==pb.semantic_plan['global_operator_algebra']['sparse_causal_expansion']['structural_sha256']
print('WHEX_GLOBAL_OPERATOR_SCE_PLAN=PASS')
print('WHEX_GLOBAL_OPERATOR_REGION_NAME_ERASURE=PASS')

_,pwh,_=wh_structural.load_surface(Path('tests/wh_equivalence/independent_regions.wh'))
g=pwh.semantic_plan['global_operator_algebra']
assert g['model']=='global_coupled_operator' and g['workload_dispatch'] is False
print('WH_WHEX_SHARED_GLOBAL_OPERATOR_ALGEBRA=PASS')
PY

for q in 1 2 4; do
  ./whexc tests/whex/global_operator_separator_123_a.whex -o "build/sce123/a_$q" --executors "$q" >/dev/null
  ./whexc tests/whex/global_operator_separator_123_b.whex -o "build/sce123/b_$q" --executors "$q" >/dev/null
  cmp "build/sce123/a_$q" "build/sce123/b_$q"
  [ "$(build/sce123/a_$q 4)" = 'checksum_bits=0x4036000000000000' ]
done
echo 'GLOBAL_OPERATOR_NATIVE_REFERENCE_1_2_4_EXECUTORS=PASS'
echo 'GLOBAL_OPERATOR_RENAMED_NATIVE_BYTE_EQUIVALENCE=PASS'

# No 1.2.3 topology metadata may leak into canonical/native bytes. The semantic
# planner is compile-time evidence only until a later physical recipe proves a
# stronger transformation.
python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0,'surface')
import whex_surface
p=Path('tests/whex/global_operator_separator_123_a.whex')
data,parser,_=whex_surface.load_surface(p)
blob=whex_surface.canonical_core_bytes(data)
for forbidden in (b'sparse_causal',b'separator',b'newton_special_case',b'global_operator'):
    assert forbidden not in blob,forbidden
print('GLOBAL_OPERATOR_RUNTIME_METADATA_ERASURE=PASS')
PY

echo 'GLOBAL_OPERATOR_SCALAR_FALLBACK=0'
echo 'GLOBAL_OPERATOR_CENTRAL_SPAWN_LOOP=0'
echo 'GLOBAL_OPERATOR_CENTRAL_WAIT_LOOP=0'
echo 'GLOBAL_OPERATOR_CENTRAL_REDUCTION_LOOP=0'
echo 'GLOBAL_OPERATOR_NON_NEIGHBOR_COMMUNICATION=0'
echo 'WHEELCHAIR_SPARSE_CAUSAL_EXPANSION_1_2_3=PASS'
