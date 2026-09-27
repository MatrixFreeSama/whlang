#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
./test.sh

mkdir -p build/complete

# Human surface and conservative repair must converge to identical semantics.
./wheelchairc surface/examples/auto_repair_clean.wh -o build/complete/repair_clean > build/complete/repair_clean.json
./wheelchairc surface/examples/auto_repair_typos.wh -o build/complete/repair_typos > build/complete/repair_typos.json
python3 - <<'PY'
import json
c=json.load(open('build/complete/repair_clean.json'))
t=json.load(open('build/complete/repair_typos.json'))
assert c['core_sha256']==t['core_sha256']
assert c['repair_count']==0
assert t['repair_count']>0
PY
[ "$(build/complete/repair_clean 4)" = "$(build/complete/repair_typos 4)" ]

# Affine recurrence: human source -> native ELF, expected result and u64 boundary.
./wheelchairc tests/general/lcg64_iterate_wrap.wh -o build/complete/lcg64 > build/complete/lcg64.json
[ "$(build/complete/lcg64 42 10)" = 'out00_bits=0x06593f7b1358c594' ]
[ "$(build/complete/lcg64 18446744073709551615 0)" = 'out00_bits=0xffffffffffffffff' ]
if build/complete/lcg64 18446744073709551616 0 >/dev/null 2>&1; then
  echo 'u64 overflow argument was incorrectly accepted' >&2; exit 1
fi

# Non-affine counted iterate: verifies register-resident small-state path without
# allowing the affine O(log n) recurrence optimizer to consume the workload.
./wheelchairc tests/general/nonaffine_iterate_wrap.wh -o build/complete/nonaffine > build/complete/nonaffine.json
python3 - <<'PY'
import subprocess,re
A=6364136223846793005; C=1442695040888963407; M=(1<<64)-1
for n in [0,1,2,3,10,1000,20000]:
    x=1
    for i in range(n): x=(((x^i)*A)+C)&M
    out=subprocess.check_output(['build/complete/nonaffine',str(n)],text=True).strip()
    got=int(re.search(r'0x([0-9a-fA-F]{16})',out).group(1),16)
    assert got==x,(n,hex(got),hex(x))
PY

# Main generated artifacts stay static native ELF.
for f in build/complete/repair_clean build/complete/lcg64 build/complete/nonaffine; do
  readelf -d "$f" 2>&1 | grep -q 'There is no dynamic section'
done

echo 'WHEELCHAIR_COMPLETE_TESTS=PASS'

# Wave 1: independent semantic-surface gates.
./test_general_108.sh & p_general=$!
./test_whex.sh & p_whex=$!
wait "$p_general"
wait "$p_whex"

# Wave 2: resource-isolated native topology proof gates. These are executed
# sequentially by the release harness so large numeric proofs cannot perturb
# one another under a constrained CI CPU quota. This affects validation only;
# generated program topology/runtime semantics are unchanged.
./test_scheduler.sh
./test_elimination.sh
./test_communication.sh
./test_109.sh

echo 'WHEELCHAIR_1_0_9_COMPLETE=PASS'

# 1.0.11/1.0.12 structural-algebra maturation gates.
./test_operator_subspace_1011.sh
./test_operator_span_mature_1011.sh
./test_112.sh

echo 'WHEELCHAIR_1_0_12_COMPLETE=PASS'

# 1.0.13 true-parallel fused-episode gate.
./test_true_parallel_113.sh

echo 'WHEELCHAIR_1_0_13_COMPLETE=PASS'

# 1.0.14 ISA capability generalization gate.
./test_114.sh

echo 'WHEELCHAIR_1_0_14_COMPLETE=PASS'

# 1.0.15 vector boundary/interior region partition gate.
./test_115.sh

echo 'WHEELCHAIR_1_0_15_COMPLETE=PASS'


# 1.1.0 general high-level / true-parallel semantic gate.
./test_whex_semantic_parallel_121.sh

echo 'WHEELCHAIR_1_1_0_SEMANTIC_INVARIANTS_ON_1_2_1=PASS'

# 1.2.x WH/WHEX equivalent-surface gate. Human/canonical semantics stay frozen;
# native bytes may improve only while WH and WHEX remain byte-identical peers.
./test_wh_equivalence_121.sh

echo 'WHEELCHAIR_1_2_0_SURFACE_INVARIANTS_ON_1_2_1=PASS'

# 1.2.1 generic interior periodic-composition and mature Newton/Jv regression gates.
./test_121.sh
./test_newton_jv_121.sh

echo 'WHEELCHAIR_1_2_1_COMPLETE=PASS'
