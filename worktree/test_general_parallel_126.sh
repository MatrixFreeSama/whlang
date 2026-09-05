#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
[ -x build/topology-fabric-schedulerless ]
[ -x build/topology-parallel ]
cmp build/topology-fabric-schedulerless build/topology-parallel
python3 - <<'PY'
import json,subprocess,sys
from pathlib import Path
sys.path.insert(0,'surface')
import general_parallel_plan as gp

# Three independent sources converge through real data references. Source order
# is intentionally hostile to the dependency order and must create no edge.
data={
 'format':'wheelchair.tensor/1',
 'bindings':[
   {'name':'c','op':'compute','expr':{'op':'add','args':[{'var':'a'},{'var':'b'}]}},
   {'name':'a','op':'compute','expr':{'literal':2,'type':'u64'}},
   {'name':'b','op':'compute','expr':{'literal':3,'type':'u64'}},
   {'name':'loop','op':'iterate','states':[{'name':'s','type':'u64','init':{'var':'c'}}],
    'condition':{'literal':False,'type':'bool'},'update':{},'result':{'var':'c'},
    'max_iterations':{'literal':8,'type':'u64'}},
   {'name':'free','op':'compute','expr':{'literal':9,'type':'u64'}},
 ]
}
p=gp.plan(data,4,physical_lane='general_native')
assert p['source_order_edges']==0 and p['synthetic_order_edges']==0
assert p['global_ready_queue']==p['global_ready_scan']==p['root_scheduler']==0
assert p['runtime_cost_selector'] is False and p['serial_fallback']==0
assert p['recurrence_enclaves']==1
rows={x['name']:x for x in p['binding_nodes']}
assert rows['c']['dependencies']==['a','b'],rows['c']
assert rows['loop']['dependencies']==['c'],rows['loop']
assert rows['free']['dependencies']==[]
assert ['free','loop'] in p['independent_binding_pairs'] or ['loop','free'] in p['independent_binding_pairs']
sp=p['schedulerless_causal']
cp=subprocess.run(['build/topology-parallel',*sp['native_argv']],capture_output=True,text=True,check=True)
r=json.loads(cp.stdout)
assert r['completed']==5 and r['dependency_messages']==3,r
for k in ('global_ready_scans','global_queue_ops','root_scheduler_ops','parent_chain_updates'):
    assert r[k]==0,(k,r[k])
assert r['handoff_collisions']==0 and r['local_fallbacks']==0
print('GENERAL_PARALLEL_BINDING_DAG=PASS')
print('GENERAL_PARALLEL_SOURCE_ORDER_EDGES=0')
print('GENERAL_PARALLEL_RECURRENCE_ENCLAVE=PASS')
print('GENERAL_PARALLEL_SCHEDULERLESS_PHYSICALIZATION=PASS')
PY
# Static audit: the new universal plan cannot name a workload or resurrect the
# abandoned runtime 1/2/4 profitability selector.
! grep -Eqi 'heat|fsi|newton|stiffness|tp126|cost[_ -]?selector|work[_ -]?steal' surface/general_parallel_plan.py

echo 'GENERAL_PARALLEL_WORKLOAD_NAME_BLIND=PASS'
echo 'GENERAL_PARALLEL_RUNTIME_SELECTOR=0'
echo 'GENERAL_PARALLEL_GLOBAL_QUEUE=0'
echo 'WHEELCHAIR_GENERAL_PARALLEL_1_2_6=PASS'
