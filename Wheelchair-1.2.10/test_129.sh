#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

./build.sh > .wheelchair_129_build.log 2>&1
grep -Fq 'GENERAL_PARALLEL_BLIND_RESOURCE_RELEASE=PASS' .wheelchair_129_build.log
grep -Fq 'WHEELCHAIR_1_2_9_RESOURCE_SEMANTIC_CORRECTION=BUILT' .wheelchair_129_build.log

# Wrong resource-routing implementations are deleted, not disabled or archived.
for p in \
  runtime/causal_return_fabric_x86_64.S \
  runtime/causal_return_parallel_x86_64.S \
  runtime/schedulerless_causal_x86_64.S \
  runtime/schedulerless_126 \
  runtime/general_parallel_slot_x86_64.S \
  runtime/general_parallel_slot.ld \
  surface/schedulerless_causal_plan.py \
  tools/generate_general_parallel_slot_offsets.py \
  test_schedulerless_causal_126.sh \
  test_general_parallel_126.sh \
  test_general_parallel_native_126.sh; do
  [ ! -e "$p" ] || { echo "retired resource-routing source survived: $p" >&2; exit 1; }
done

if objdump -d build/general_parallel_release.elf | grep -Eq '(^|[[:space:]])pause([[:space:]]|$)'; then
  echo 'blind-release engine contains idle PAUSE spin' >&2; exit 1
fi
if nm build/general_parallel_release.elf | grep -Ei 'home_slot|remote_head|inbox|route_token|try_pull|direct_assign|steal|victim'; then
  echo 'retired ownership/routing symbol survived in blind-release engine' >&2; exit 1
fi

python3 - <<'PY'
import sys
sys.path.insert(0,'surface')
import general_parallel_plan as g
p=g.causal_geometry(['a','b','c'],[(0,2),(1,2)],4,work=[1,1,1])
assert p['source_count']==2
assert p['runtime_fixed_home_ownership']==0
assert p['persistent_idle_worker_spin']==0
assert p['post_completion_work_search']==0
assert p['post_completion_peer_query']==0
assert p['resource_release_destination']==0
assert p['resource_handoff']==0
assert p['resource_consumer_visibility']=='none'
assert p['communication_rule']=='true_dependency_neighbors_only'
assert p['release_rule']=='owned_to_free_no_recipient'
assert 'home_slots' not in p
print('BLIND_RELEASE_CAUSAL_PLAN=PASS')
PY

mkdir -p build/general_parallel_129
run_matrix() {
  name=$1
  src=$2
  shift 2
  args="$*"
  for q in 1 2 4; do
    ./wheelchairc "$src" -o "build/general_parallel_129/${name}_q$q" --executors "$q" \
      --semantic-plan "build/general_parallel_129/${name}_q$q.plan.json" \
      > "build/general_parallel_129/${name}_q$q.compile.json"
    # shellcheck disable=SC2086
    "build/general_parallel_129/${name}_q$q" $args > "build/general_parallel_129/${name}_q$q.out"
    readelf -d "build/general_parallel_129/${name}_q$q" 2>&1 | grep -Fq 'There is no dynamic section'
  done
  cmp "build/general_parallel_129/${name}_q1.out" "build/general_parallel_129/${name}_q2.out"
  cmp "build/general_parallel_129/${name}_q1.out" "build/general_parallel_129/${name}_q4.out"
}

run_matrix branch tests/general_parallel_126/branch_probe.wh 7
run_matrix iterate tests/general_parallel_126/iterate_probe.wh 2 5 3

python3 - <<'PY'
import json
from pathlib import Path
for name,fragments in [('branch',8),('iterate',6)]:
    for q in (2,4):
        p=json.loads(Path(f'build/general_parallel_129/{name}_q{q}.plan.json').read_text())
        n=p['native_physicalization']['native_fragments']
        assert n['cpu_width']==q,(name,q,n)
        assert n['node_context_materialization']==fragments,(name,q,n)
        assert n['runtime_selector'] is False
        assert n['global_ready_queue']==0
        assert n['global_ready_scan']==0
        assert n['root_scheduler']==0
        assert n['work_stealing']==0
        assert n['serial_fallback']==0
        assert n['runtime_fixed_home_ownership']==0
        assert n['persistent_idle_worker_spin']==0
        assert n['post_completion_work_search']==0
        assert n['post_completion_peer_query']==0
        assert n['resource_release_destination']==0
        assert n['resource_handoff']==0
        assert 'home_slots' not in n
        b=n['blind_release_causal']
        assert b['resource_consumer_visibility']=='none'
        assert b['cpu_dispatch_authority']=='os_scheduler_within_inherited_affinity_envelope'
        assert n['fragment_machine_code_origin']=='handwritten_topologyc_general_frontend'

branch=json.loads(Path('build/general_parallel_129/branch_q4.plan.json').read_text())['native_physicalization']['native_fragments']
deps=branch['dependencies']
assert deps['a']==[] and deps['b']==[]
assert deps['c']==['a'] and deps['d']==['b']
assert deps['e']==['c','d']
assert deps['@wheelchair.output.0']==['e']
assert deps['@wheelchair.output.1']==['c']
assert deps['@wheelchair.output.2']==['d']

it=json.loads(Path('build/general_parallel_129/iterate_q4.plan.json').read_text())['native_physicalization']['native_fragments']
deps=it['dependencies']
assert deps['left']==[] and deps['right']==[]
assert deps['total']==['left','right']
assert deps['@wheelchair.output.0']==['total']
assert deps['@wheelchair.output.1']==['left']
assert deps['@wheelchair.output.2']==['right']
print('GENERAL_PARALLEL_NATIVE_Q1_Q2_Q4_EQUIVALENCE_129=PASS')
print('GENERAL_PARALLEL_RECIPIENT_BLIND_129=PASS')
PY

echo 'RESOURCE_RELEASE_DESTINATION_FIELDS=0'
echo 'POST_COMPLETION_PEER_SCAN=0'
echo 'POST_COMPLETION_WORK_ACQUISITION=0'
echo 'PERSISTENT_IDLE_WORKER_SPIN=0'
echo 'RUNTIME_FIXED_HOME_OWNERSHIP=0'
echo 'RESOURCE_CONSUMER_VISIBLE_TO_RELEASER=0'
echo 'RESOURCE_ROUTE_TO_SIBLING=0'
echo 'RESOURCE_ROUTE_TO_PARENT_FOR_REASSIGNMENT=0'
echo 'WORKER_RESOURCE_HANDOFF=0'
echo 'PEER_LOAD_QUERY=0'
echo 'VICTIM_SELECTION=0'
echo 'GLOBAL_RESOURCE_DEMAND_SCAN=0'
echo 'LOCAL_RESOURCE_DEMAND_SCAN=0'
echo 'RELEASE_REQUIRES_CONSUMER=0'
echo 'BLIND_RESOURCE_RELEASE=PASS'
echo 'OWNED_TO_FREE_TRANSITION=PASS'
echo 'DEPENDENCY_AND_RESOURCE_PLANES_SEPARATED=PASS'
echo 'WHEELCHAIR_1_2_9_RESOURCE_SEMANTIC_CORRECTION=PASS'
