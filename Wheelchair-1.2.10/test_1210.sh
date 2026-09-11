#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

./build.sh > .wheelchair_1210_build.log 2>&1
grep -Fq 'GENERAL_PARALLEL_BLIND_RESOURCE_RELEASE=PASS' .wheelchair_1210_build.log

# 1.2.9 semantic correction remains a hard floor. Retired routing implementations
# must not re-enter the active tree.
for p in \
  runtime/causal_return_fabric_x86_64.S \
  runtime/causal_return_parallel_x86_64.S \
  runtime/schedulerless_causal_x86_64.S \
  runtime/schedulerless_126 \
  runtime/general_parallel_slot_x86_64.S \
  runtime/general_parallel_slot.ld \
  surface/schedulerless_causal_plan.py \
  tools/generate_general_parallel_slot_offsets.py; do
  [ ! -e "$p" ] || { echo "retired resource-routing source survived: $p" >&2; exit 1; }
done

if objdump -d build/general_parallel_release.elf | grep -Eq '(^|[[:space:]])pause([[:space:]]|$)'; then
  echo 'causal-region engine contains idle PAUSE spin' >&2; exit 1
fi
if nm build/general_parallel_release.elf | grep -Ei 'home_slot|remote_head|inbox|route_token|try_pull|direct_assign|steal|victim'; then
  echo 'retired ownership/routing symbol survived in causal-region engine' >&2; exit 1
fi

# Recursive region materialization may not allocate/free a stack per region.
[ "$(grep -c 'mov eax, SYS_mmap' runtime/general_parallel_release_x86_64.S)" -eq 2 ]
awk '/^gr_run_node_tree:/{f=1} /^gr_node_task:/{f=0} f{print}' runtime/general_parallel_release_x86_64.S > build/grt_lifecycle_1210.txt
if grep -Eq 'SYS_mmap|SYS_munmap' build/grt_lifecycle_1210.txt; then
  echo 'per-context stack mmap/munmap returned to recursive lifecycle path' >&2; exit 1
fi

python3 - <<'PY'
import sys
sys.path.insert(0,'surface')
import general_parallel_plan as g

def check_fused_edges(p,edges):
    pred=[[] for _ in range(p['node_count'])]
    succ=[[] for _ in range(p['node_count'])]
    for u,v in edges: succ[u].append(v); pred[v].append(u)
    for region in p['causal_region_indices']:
        for u,v in zip(region,region[1:]):
            assert v in succ[u]
            assert len(succ[u])==1,(u,v,succ[u])
            assert len(pred[v])==1,(u,v,pred[v])

n=32; chain=[(i,i+1) for i in range(n-1)]
p=g.causal_geometry([f'c{i}' for i in range(n)],chain,4)
assert p['causal_region_count']==1 and p['materialized_node_contexts']==1
assert p['fused_node_count']==31 and p['max_region_nodes']==32
assert p['region_edge_uv_u32']==[]
check_fused_edges(p,chain)

diamond=[(0,1),(0,2),(1,3),(2,3)]
p=g.causal_geometry(['a','b','c','d'],diamond,4)
assert p['causal_region_count']==4 and p['fused_node_count']==0
check_fused_edges(p,diamond)

mixed=[(0,1),(0,2),(1,3),(2,4),(3,5),(4,6)]
p=g.causal_geometry([str(i) for i in range(7)],mixed,4)
assert p['causal_region_count']==3 and p['max_region_nodes']==3
assert p['fusion_rule']=='producer_outdegree_one_and_consumer_indegree_one'
assert p['fusion_runtime_selector'] is False and p['fusion_workload_identity'] is False
assert p['runtime_fixed_home_ownership']==0 and p['persistent_idle_worker_spin']==0
assert p['post_completion_work_search']==0 and p['post_completion_peer_query']==0
assert p['resource_release_destination']==0 and p['resource_handoff']==0
assert p['resource_consumer_visibility']=='none'
check_fused_edges(p,mixed)
print('AOT_CAUSAL_REGION_CONTRACTION_1210=PASS')
PY

mkdir -p build/general_parallel_1210
run_matrix() {
  name=$1; src=$2; shift 2; args="$*"
  for q in 1 2 4; do
    ./wheelchairc "$src" -o "build/general_parallel_1210/${name}_q$q" --executors "$q" \
      --semantic-plan "build/general_parallel_1210/${name}_q$q.plan.json" \
      > "build/general_parallel_1210/${name}_q$q.compile.json"
    # shellcheck disable=SC2086
    "build/general_parallel_1210/${name}_q$q" $args > "build/general_parallel_1210/${name}_q$q.out"
    readelf -d "build/general_parallel_1210/${name}_q$q" 2>&1 | grep -Fq 'There is no dynamic section'
  done
  cmp "build/general_parallel_1210/${name}_q1.out" "build/general_parallel_1210/${name}_q2.out"
  cmp "build/general_parallel_1210/${name}_q1.out" "build/general_parallel_1210/${name}_q4.out"
}
run_matrix branch tests/general_parallel_126/branch_probe.wh 7
run_matrix iterate tests/general_parallel_126/iterate_probe.wh 2 5 3

python3 - <<'PY'
import json
from pathlib import Path
for name in ('branch','iterate'):
  for q in (2,4):
    n=json.loads(Path(f'build/general_parallel_1210/{name}_q{q}.plan.json').read_text())['native_physicalization']['native_fragments']
    assert n['cpu_width']==q
    assert 0<n['node_context_materialization']<n['native_fragment_count']
    assert n['causal_region_count']==n['node_context_materialization']
    assert n['fused_fragment_count']==n['native_fragment_count']-n['causal_region_count']
    assert n['per_context_stack_mmap']==0 and n['per_context_stack_munmap']==0
    assert n['runtime_selector'] is False and n['global_ready_queue']==0 and n['global_ready_scan']==0
    assert n['root_scheduler']==0 and n['work_stealing']==0 and n['serial_fallback']==0
    assert n['runtime_fixed_home_ownership']==0 and n['persistent_idle_worker_spin']==0
    assert n['post_completion_work_search']==0 and n['post_completion_peer_query']==0
    assert n['resource_release_destination']==0 and n['resource_handoff']==0
    b=n['blind_release_causal']
    assert b['resource_consumer_visibility']=='none'
    assert b['release_rule']=='owned_to_free_no_recipient'
    assert b['fusion_rule']=='producer_outdegree_one_and_consumer_indegree_one'
    assert b['fusion_runtime_selector'] is False
print('GENERAL_PARALLEL_NATIVE_CAUSAL_REGION_1210=PASS')
PY

# Current Rank-N authority is the derived capability profile. The retired
# topologyc-rankn binary is deliberately not resurrected.
mkdir -p build/rankn_1210
for q in 1 2 4; do
  ./whexc tests/whex/rank6_native_122.whex -o "build/rankn_1210/r6_q$q" --executors "$q" > "build/rankn_1210/r6_q$q.json"
  [ "$(build/rankn_1210/r6_q$q 4)" = 'checksum_bits=0x40bfc00000000000' ]
  readelf -d "build/rankn_1210/r6_q$q" 2>&1 | grep -Fq 'There is no dynamic section'
done
cmp build/rankn_1210/r6_q1 build/rankn_1210/r6_q2 || true
[ ! -e build/topologyc-rankn ]
echo 'RANK_N_CURRENT_DERIVED_PROFILE_1210=PASS'
echo 'RANK_N_RETIRED_SPECIAL_BINARY=0'

sh ./test_native_resource_profiles_126.sh
python3 ./test_multi_isa_profiles_127.py
sh ./test_native256_physicalizer_127.sh
sh ./test_native256_maturity_128.sh
sh ./test_release_128.sh

echo 'RESOURCE_RELEASE_DESTINATION_FIELDS=0'
echo 'POST_COMPLETION_PEER_SCAN=0'
echo 'POST_COMPLETION_WORK_ACQUISITION=0'
echo 'PERSISTENT_IDLE_WORKER_SPIN=0'
echo 'RUNTIME_FIXED_HOME_OWNERSHIP=0'
echo 'PER_CONTEXT_STACK_MMAP=0'
echo 'AOT_CAUSAL_REGION_FUSION=PASS'
echo 'BLIND_RESOURCE_RELEASE=PASS'
echo 'OWNED_TO_FREE_TRANSITION=PASS'
echo 'WHEELCHAIR_1_2_10_GENERAL_PHYSICALIZATION=PASS'
