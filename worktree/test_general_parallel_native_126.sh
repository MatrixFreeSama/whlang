#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

LOG=.general_parallel_native_126_build.log
rm -f "$LOG"
./build.sh > "$LOG" 2>&1
grep -Fq 'GENERAL_PARALLEL_SLOT_ENGINE=BUILT' "$LOG"
mkdir -p build/general_parallel_126

run_matrix() {
  name=$1
  src=$2
  shift 2
  args="$*"
  for q in 1 2 4; do
    ./wheelchairc "$src" -o "build/general_parallel_126/${name}_q$q" --executors "$q" \
      --semantic-plan "build/general_parallel_126/${name}_q$q.plan.json" \
      > "build/general_parallel_126/${name}_q$q.compile.json"
    # shellcheck disable=SC2086
    "build/general_parallel_126/${name}_q$q" $args > "build/general_parallel_126/${name}_q$q.out"
    readelf -d "build/general_parallel_126/${name}_q$q" 2>&1 | grep -Fq 'There is no dynamic section'
  done
  cmp "build/general_parallel_126/${name}_q1.out" "build/general_parallel_126/${name}_q2.out"
  cmp "build/general_parallel_126/${name}_q1.out" "build/general_parallel_126/${name}_q4.out"
}

run_matrix branch tests/general_parallel_126/branch_probe.wh 7
run_matrix iterate tests/general_parallel_126/iterate_probe.wh 2 5 3

python3 - <<'PY'
import json
from pathlib import Path
for name,fragments in [('branch',8),('iterate',6)]:
    for q in (1,2,4):
        c=json.loads(Path(f'build/general_parallel_126/{name}_q{q}.compile.json').read_text())
        assert c['effective_executors']==q,(name,q,c['effective_executors'])
        p=json.loads(Path(f'build/general_parallel_126/{name}_q{q}.plan.json').read_text())
        n=p['native_physicalization']
        assert n['executor_materialization']==q,(name,q,n)
        assert n['foreign_runtime_backend'] is False
        if q>1:
            g=n['native_fragments']
            assert g['executor_materialization']==q
            assert g['runtime_selector'] is False
            assert g['global_ready_queue']==0
            assert g['global_ready_scan']==0
            assert g['root_scheduler']==0
            assert g['work_stealing']==0
            assert g['serial_fallback']==0
            assert g['native_fragment_count']==fragments,(name,g)
            assert g['fragment_machine_code_origin']=='handwritten_topologyc_general_frontend'

branch=json.loads(Path('build/general_parallel_126/branch_q4.plan.json').read_text())['native_physicalization']['native_fragments']
deps=branch['dependencies']
assert deps['a']==[] and deps['b']==[]
assert deps['c']==['a'] and deps['d']==['b']
assert deps['e']==['c','d']
assert deps['@wheelchair.output.0']==['e']
assert deps['@wheelchair.output.1']==['c']
assert deps['@wheelchair.output.2']==['d']

it=json.loads(Path('build/general_parallel_126/iterate_q4.plan.json').read_text())['native_physicalization']['native_fragments']
deps=it['dependencies']
assert deps['left']==[] and deps['right']==[]
assert deps['total']==['left','right']
assert deps['@wheelchair.output.0']==['total']
assert deps['@wheelchair.output.1']==['left']
assert deps['@wheelchair.output.2']==['right']
print('GENERAL_PARALLEL_NATIVE_Q1_Q2_Q4_EQUIVALENCE=PASS')
print('GENERAL_PARALLEL_NATIVE_ITERATE_RELOCATION=PASS')
PY

grep -Fq '"effective_executors": 4' build/general_parallel_126/branch_q4.compile.json
grep -Fq '"executor_materialization": 4' build/general_parallel_126/branch_q4.plan.json

echo 'GENERAL_PARALLEL_NATIVE_FRAGMENTATION=PASS'
echo 'GENERAL_PARALLEL_NATIVE_SOURCE_ORDER_SERIALIZATION=0'
echo 'GENERAL_PARALLEL_NATIVE_GLOBAL_READY_QUEUE=0'
echo 'GENERAL_PARALLEL_NATIVE_RUNTIME_SELECTOR=0'
echo 'GENERAL_PARALLEL_NATIVE_SERIAL_FALLBACK=0'
echo 'WHEELCHAIR_GENERAL_PARALLEL_NATIVE_1_2_6=PASS'
