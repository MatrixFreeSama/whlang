#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN="$ROOT/build/topology-fabric-schedulerless"
PLAN="$ROOT/surface/schedulerless_causal_plan.py"
[ -x "$BIN" ]
python3 -m py_compile "$PLAN"
readelf -d "$BIN" 2>&1 | grep -q 'There is no dynamic section'
if nm -an "$BIN" | grep -Eq 'root_epoch|root_remaining|pending_count|first_child|next_sibling|global_ready_queue|work_steal|mailbox'; then
  echo 'forbidden scheduler/mailbox symbol present' >&2; exit 1
fi
nm -an "$BIN" | grep -q 'remote_head'
nm -an "$BIN" | grep -q 'ready_next'
python3 - "$ROOT" <<'PY'
import json,random,subprocess,sys
from pathlib import Path
root=Path(sys.argv[1]); sys.path.insert(0,str(root/'surface'))
import schedulerless_causal_plan as sc
bin=str(root/'build/topology-fabric-schedulerless')
def run(spec,slots=None):
    p=sc.plan(spec,slots)
    cp=subprocess.run([bin,*p['native_argv']],capture_output=True,text=True,timeout=10)
    if cp.returncode: raise SystemExit(f"native schedulerless failure rc={cp.returncode}: {cp.stdout}{cp.stderr}")
    d=json.loads(cp.stdout)
    assert d['completed']==p['node_count'] and d['dependency_messages']==p['edge_count']
    for k in ('global_ready_scans','global_queue_ops','root_scheduler_ops','parent_chain_updates'): assert d[k]==0,(k,d[k])
    assert d['handoff_collisions']==0,d
    assert d['local_fallbacks']==0,d
    assert p['workload_dispatch'] is False and p['runtime_dispatch'] is False and p['runtime_cost_selector'] is False
    assert p['serial_fallback']==0 and p['remote_collision_fallback']==0
    assert p['collision_rule']=='slot_local_lock_free_causal_inbox'
    assert p['remote_ingress']=='per_slot_mpsc_direct_causal'
    assert p['global_ready_queue']==p['global_ready_scan']==p['root_scheduler']==p['root_epoch']==0
    assert p['parent_demand_tree']==p['work_stealing']==p['global_phase_barrier']==0
    return p,d
run({'format':sc.FORMAT,'nodes':[str(i) for i in range(8)],'edges':[[str(i),str(i+1)] for i in range(7)]},4)
run({'format':sc.FORMAT,'nodes':['a','b','c','d'],'edges':[['a','b'],['a','c'],['b','d'],['c','d']]},4)
p,d=run({'format':sc.FORMAT,'nodes':['a','b','c','d'],'edges':[['a','c'],['b','d']]},2)
assert p['source_count']==2 and d['sources']==2
s={'format':sc.FORMAT,'nodes':[{'id':str(i),'work':(i%7)+1} for i in range(16)],'edges':[[str(i),str(j)] for i in range(16) for j in range(i+1,16) if (i*13+j*7)%19==0]}
a=sc.plan(s,4); b=sc.plan(s,4); assert a['structural_signature_sha256']==b['structural_signature_sha256'] and a['home_slots']==b['home_slots']
rng=random.Random(126)
for case in range(300):
    n=rng.randint(1,32); slots=rng.randint(1,min(8,n)); nodes=[{'id':str(i),'work':rng.choice([0,1,5,50,500])} for i in range(n)]; prob=rng.uniform(.02,.18)
    edges=[[str(i),str(j)] for i in range(n) for j in range(i+1,n) if rng.random()<prob][:256]
    run({'format':sc.FORMAT,'nodes':nodes,'edges':edges},slots)
try: sc.plan({'format':sc.FORMAT,'nodes':['a','b'],'edges':[['a','b'],['b','a']]},2)
except sc.SchedulerlessCausalError: pass
else: raise SystemExit('cycle was not rejected')
print('SCHEDULERLESS_CAUSAL_NATIVE_CASES=PASS')
print('SCHEDULERLESS_CAUSAL_RANDOM_DAG_300=PASS')
print('SCHEDULERLESS_CAUSAL_MULTISOURCE=PASS')
print('SCHEDULERLESS_CAUSAL_MPSC_INBOX=PASS')
print('SCHEDULERLESS_CAUSAL_HANDOFF_COLLISIONS=0')
print('SCHEDULERLESS_CAUSAL_LOCAL_FALLBACKS=0')
print('SCHEDULERLESS_CAUSAL_GLOBAL_READY_SCAN=0')
print('SCHEDULERLESS_CAUSAL_GLOBAL_QUEUE_OPS=0')
print('SCHEDULERLESS_CAUSAL_ROOT_SCHEDULER_OPS=0')
print('SCHEDULERLESS_CAUSAL_PARENT_CHAIN_UPDATES=0')
print('SCHEDULERLESS_CAUSAL_RUNTIME_COST_SELECTOR=0')
print('SCHEDULERLESS_CAUSAL_SERIAL_FALLBACK=0')
PY
echo 'WHEELCHAIR_SCHEDULERLESS_CAUSAL_1_2_6=PASS'
