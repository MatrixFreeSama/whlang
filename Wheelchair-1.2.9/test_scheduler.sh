#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/scheduler

# Different structural graphs prove that synthesized plans reach the generated
# image instead of dying as compiler-only metadata. WHEX tensor programs no
# longer have a transparent scalar fallback: a supported tensor topology must
# remain vector-native through realization.
./whexc tests/whex/scheduler_probe.whex -o build/scheduler/simple >/dev/null
./whexc surface/whex_examples/heat_en.whex -o build/scheduler/heat >/dev/null
build/topologyc tests/topology_cases/fem_linear_aggregate_tolerant_regression.wh -o build/scheduler/fem >/dev/null
./whexc tests/whex/strength_probe.whex -o build/scheduler/strength >/dev/null

[ "$(build/scheduler/simple 4)" = 'checksum_bits=0x4010000000000000' ]
[ "$(build/scheduler/heat 4)" = 'checksum_bits=0x3ff1c80000000000' ]
[ "$(build/scheduler/fem 262144)" = 'checksum_bits=0xc05ccc38e38e39d8' ]
[ "$(build/scheduler/strength 4)" = 'checksum_bits=0x4078400000000000' ]

python3 - <<'PY'
from pathlib import Path
import re,struct,json
inc=Path('compiler/runtime_offsets.inc').read_text()
def off(name):
    m=re.search(rf'^{re.escape(name)},?\s+(0x[0-9A-Fa-f]+)', inc, re.M)
    if not m:
        # assembler .equ spelling
        m=re.search(rf'^\.equ\s+{re.escape(name)},\s*(0x[0-9A-Fa-f]+)', inc, re.M)
    assert m,name
    return int(m.group(1),16)
def plan(path):
    b=Path(path).read_bytes()
    u=lambda n: struct.unpack_from('<I',b,off(n))[0]
    return {'vector':u('RUNTIME_VECTOR_WIDTH_OFF'),'carriers':u('RUNTIME_CARRIERS_OFF'),'unroll':u('RUNTIME_UNROLL_OFF')}
simple=plan('build/scheduler/simple')
heat=plan('build/scheduler/heat')
fem=plan('build/scheduler/fem')
# No-hidden-serial contract: a WHEX tensor graph that reaches this scheduler
# must use the same packed vector width class as the other tensor graphs.
assert heat['vector']==simple['vector'],(heat,simple)
assert heat['carriers']==simple['carriers'],(heat,simple)
assert heat['unroll'] in (1,2,4),heat
# On AVX-512 hosts, all supported tensor graphs remain eight-lane vector native.
# 1.0.13 fuses the evaluator loop into generated code, so the old runtime
# per-call unroll knob is deliberately normalized to one truthful fused body.
if simple['vector']==8 and fem['vector']==8:
    assert heat['vector']==8 and heat['carriers']==4,heat
    assert simple['carriers']==4 and fem['carriers']==4,(simple,fem)
    assert simple['unroll']==heat['unroll']==fem['unroll']==1,(simple,heat,fem)
Path('build/scheduler/plans.json').write_text(json.dumps({'simple':simple,'heat':heat,'fem':fem},indent=2)+'\n')
PY

# The audit may describe proven CPU-profile facts, but it must not claim an
# exhaustive proof of compiler/scheduler correctness. Those are release gates.
build/topologyc --silicon-audit > build/scheduler/silicon_audit.json
grep -q '"compiler_hot_scan":"REGRESSION_GATED_NOT_EXHAUSTIVE"' build/scheduler/silicon_audit.json
grep -q '"general_resource_scheduler":"CONNECTED_RELEASE_GATE"' build/scheduler/silicon_audit.json
grep -q '"computation_elimination":"PARALLEL_PRESERVING_RELEASE_GATE"' build/scheduler/silicon_audit.json

# If AVX-512 lowering is active, freeze the retained machine-code regressions:
# repeated sibling-field topology indices are shared, and x*64 becomes one shift.
FEM_VEC=$(python3 -c 'import json; print(json.load(open("build/scheduler/plans.json"))["fem"]["vector"])')
if [ "$FEM_VEC" = 8 ]; then
    tools/disassemble_generated.sh build/scheduler/fem > build/scheduler/fem.asm
    # 1.0.15 emits two mutually-exclusive vector regions: a proven-interior
    # fast body and an exact boundary-safe body. Static instruction totals may
    # therefore nearly double even though no runtime path executes both. Audit
    # each path independently instead of mistaking code alternatives for work.
    python3 - <<'PYREGION'
from pathlib import Path
import re
text=Path('build/scheduler/fem.asm').read_text()
rows=[]
for line in text.splitlines():
    m=re.match(r'^\s*([0-9a-fA-F]+):\s+(.*)$',line)
    if m: rows.append((int(m.group(1),16),line,m.group(2)))
safe=None
fast_start=None
for i,(addr,line,ins) in enumerate(rows):
    m=re.search(r'\bje\s+0x([0-9a-fA-F]+)',ins)
    if m:
        safe=int(m.group(1),16)
        # The matching JAE is the second half of the region discriminator.
        for j in range(i+1,min(i+8,len(rows))):
            m2=re.search(r'\bjae\s+0x([0-9a-fA-F]+)',rows[j][2])
            if m2 and int(m2.group(1),16)==safe:
                fast_start=rows[j+1][0]
                break
        break
assert safe is not None and fast_start is not None,(safe,fast_start)
common=None
for addr,line,ins in rows:
    if not (fast_start <= addr < safe): continue
    m=re.search(r'\bjmp\s+0x([0-9a-fA-F]+)',ins)
    if m and int(m.group(1),16)>safe:
        common=int(m.group(1),16)
assert common is not None,(safe,fast_start)
regions={
    'interior':[line for addr,line,ins in rows if fast_start <= addr < safe],
    'boundary':[line for addr,line,ins in rows if safe <= addr < common],
}
for name,lines in regions.items():
    body='\n'.join(lines)
    addq=len(re.findall(r'\bvpaddq\b',body))
    andq=len(re.findall(r'\bvpandq\b',body))
    assert addq <= 75,(name,addq)
    assert andq <= 75,(name,andq)
Path('build/scheduler/fem_regions.txt').write_text(
    '\n'.join(f'{k}: vpaddq={len(re.findall(r"\bvpaddq\b", "\n".join(v)))} vpandq={len(re.findall(r"\bvpandq\b", "\n".join(v)))}' for k,v in regions.items())+'\n')
PYREGION
    tools/disassemble_generated.sh build/scheduler/strength > build/scheduler/strength.asm
    grep -q 'vpsllq' build/scheduler/strength.asm
    if grep -q 'vpmullq' build/scheduler/strength.asm; then
        echo 'power-of-two strength probe still emitted vpmullq' >&2; exit 1
    fi
    echo 'AVX512_RESOURCE_MODEL=PASS'
    echo 'TOPOLOGY_INDEX_CSE=PASS'
    echo 'COST_AWARE_STRENGTH_REDUCTION=PASS'
else
    echo 'AVX512_RESOURCE_MODEL=SKIP_NO_AVX512'
    echo 'TOPOLOGY_INDEX_CSE=SKIP_NO_AVX512'
    echo 'COST_AWARE_STRENGTH_REDUCTION=SKIP_NO_AVX512'
fi

if grep -q 'call eval_slot' runtime/tensor_runtime_template_x86_64.S; then
    echo 'tensor runtime still contains scalar evaluator fallback' >&2; exit 1
fi
echo 'TENSOR_HIDDEN_SCALAR_FALLBACK=0'
echo 'RESOURCE_SCHEDULER_CONNECTED=PASS'
echo 'SILICON_AUDIT_TRUTHFUL=PASS'
