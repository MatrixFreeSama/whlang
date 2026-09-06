#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

LOG=.general_parallel_native_126_build.log
rm -f "$LOG"
./build.sh > "$LOG" 2>&1
grep -Fq 'GENERAL_PARALLEL_SLOT_ENGINE=BUILT' "$LOG"
mkdir -p build/general_parallel_126

SRC=tests/general_parallel_126/branch_probe.wh
for q in 1 2 4; do
  ./wheelchairc "$SRC" -o "build/general_parallel_126/q$q" --executors "$q" \
    --semantic-plan "build/general_parallel_126/q$q.plan.json" \
    > "build/general_parallel_126/q$q.compile.json"
  "build/general_parallel_126/q$q" 7 > "build/general_parallel_126/q$q.out"
  readelf -d "build/general_parallel_126/q$q" 2>&1 | grep -Fq 'There is no dynamic section'
done
cmp build/general_parallel_126/q1.out build/general_parallel_126/q2.out
cmp build/general_parallel_126/q1.out build/general_parallel_126/q4.out

python3 - <<'PY'
import json
from pathlib import Path
for q in (1,2,4):
    c=json.loads(Path(f'build/general_parallel_126/q{q}.compile.json').read_text())
    assert c['effective_executors']==q,(q,c['effective_executors'])
    p=json.loads(Path(f'build/general_parallel_126/q{q}.plan.json').read_text())
    n=p['native_physicalization']
    assert n['executor_materialization']==q,(q,n)
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
        assert g['native_fragment_count']==8,g
        deps=g['dependencies']
        assert deps['a']==[] and deps['b']==[]
        assert deps['c']==['a'] and deps['d']==['b']
        assert deps['e']==['c','d']
        assert deps['@wheelchair.output.0']==['e']
        assert deps['@wheelchair.output.1']==['c']
        assert deps['@wheelchair.output.2']==['d']
print('GENERAL_PARALLEL_NATIVE_Q1_Q2_Q4_EQUIVALENCE=PASS')
PY

grep -Fq '"effective_executors": 4' build/general_parallel_126/q4.compile.json
grep -Fq '"executor_materialization": 4' build/general_parallel_126/q4.plan.json

echo 'GENERAL_PARALLEL_NATIVE_FRAGMENTATION=PASS'
echo 'GENERAL_PARALLEL_NATIVE_SOURCE_ORDER_SERIALIZATION=0'
echo 'GENERAL_PARALLEL_NATIVE_GLOBAL_READY_QUEUE=0'
echo 'GENERAL_PARALLEL_NATIVE_RUNTIME_SELECTOR=0'
echo 'GENERAL_PARALLEL_NATIVE_SERIAL_FALLBACK=0'
echo 'WHEELCHAIR_GENERAL_PARALLEL_NATIVE_1_2_6=PASS'
