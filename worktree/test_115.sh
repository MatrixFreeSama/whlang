#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/boundary115

# Generic vector-region partition witness. The source contains two global
# boundary selects around an otherwise affine periodic map. Both executor widths
# must preserve the same tensor semantics on awkward vector and chunk sizes.
build/topologyc tests/topology_cases/heat_diffusion_step_tolerant.wh -o build/boundary115/native_1 --executors 1 >/dev/null
build/topologyc tests/topology_cases/heat_diffusion_step_tolerant.wh -o build/boundary115/native_4 --executors 4 >/dev/null
build/topologyc tests/topology_cases/heat_diffusion_step_tolerant.wh -o build/boundary115/foundation_1 --executors 1 --isa-limit avx512f >/dev/null

python3 - <<'PY'
import random,struct,subprocess
bins={
    'n1':'build/boundary115/native_1',
    'n4':'build/boundary115/native_4',
    'f1':'build/boundary115/foundation_1',
}
ns=[4,5,7,8,9,15,16,17,31,32,33,63,64,65,1023,1024,1025,
    65535,65536,65537,65543,131071,131072,131073,262143,262144,262145]
r=random.Random(115)
ns += [r.randint(4,300000) for _ in range(30)]
for n in ns:
    out={k:subprocess.check_output([b,str(n)],text=True).strip() for k,b in bins.items()}
    # Tolerant reductions may change association across executors; require a
    # strict numerical contract rather than accidental bit equality.
    vals={k:struct.unpack('>d',bytes.fromhex(v.split('0x',1)[1]))[0] for k,v in out.items()}
    for k in ('n4','f1'):
        rel=abs(vals[k]-vals['n1'])/max(1.0,abs(vals['n1']))
        assert rel <= 1e-12,(n,k,vals,rel)
print(f'BOUNDARY_REGION_DIFFERENTIAL_CASES={len(ns)}')
print('BOUNDARY_REGION_EXECUTOR_EQUIVALENCE=PASS')
print('BOUNDARY_REGION_AVX512F_EQUIVALENCE=PASS')

# Small awkward extents are dyadic for this witness, so the scalar mathematical
# reference is exact and checks that the boundary body was not erased.
def u(i): return 0.25 + (((i*17)+3)&1023)/1024.0
def ref(n):
    s=0.0
    for i in range(n):
        l=n-1 if i==0 else i-1
        rr=0 if i+1==n else i+1
        ui=u(i)
        s += ui + 0.125*((u(l)-2.0*ui)+u(rr))
    return s
for n in (4,5,7,8,9,16,17,31,32,33,257,1025,4097):
    out=subprocess.check_output([bins['n1'],str(n)],text=True).strip()
    got=struct.unpack('>d',bytes.fromhex(out.split('0x',1)[1]))[0]
    assert got==ref(n),(n,got,ref(n))
print('BOUNDARY_REGION_REFERENCE=PASS')
PY

# Machine-code proof: the generated episode contains two mutually-exclusive
# vector bodies. Interior code has erased boundary predicate materialization and
# reused the affine induction carrier; the boundary body retains exact masks.
tools/disassemble_generated.sh build/boundary115/native_1 > build/boundary115/native.dis
python3 - <<'PY'
from pathlib import Path
import re
text=Path('build/boundary115/native.dis').read_text()
rows=[]
for line in text.splitlines():
    m=re.match(r'^\s*([0-9a-fA-F]+):\s+(.*)$',line)
    if m: rows.append((int(m.group(1),16),line,m.group(2)))
safe=None; fast_start=None
for i,(addr,line,ins) in enumerate(rows):
    m=re.search(r'\bje\s+0x([0-9a-fA-F]+)',ins)
    if not m: continue
    target=int(m.group(1),16)
    for j in range(i+1,min(i+8,len(rows))):
        m2=re.search(r'\bjae\s+0x([0-9a-fA-F]+)',rows[j][2])
        if m2 and int(m2.group(1),16)==target:
            safe=target; fast_start=rows[j+1][0]; break
    if safe is not None: break
assert safe is not None and fast_start is not None
common=None
for addr,line,ins in rows:
    if fast_start <= addr < safe:
        m=re.search(r'\bjmp\s+0x([0-9a-fA-F]+)',ins)
        if m and int(m.group(1),16)>safe: common=int(m.group(1),16)
assert common is not None
fast='\n'.join(line for addr,line,ins in rows if fast_start <= addr < safe)
boundary='\n'.join(line for addr,line,ins in rows if safe <= addr < common)
assert not re.search(r'\b(?:vpcmpeqq|vpmovm2q)\b',fast),fast
assert not re.search(r'\bvpmullq\b',fast),fast
assert re.search(r'\bvpcmpeqq\b',boundary),boundary
assert re.search(r'\bvpmovm2q\b',boundary),boundary
# Scalar control selects only a vector body; it never computes a tensor value.
assert re.search(r'\btest\s+rsi,rsi\b',text)
assert re.search(r'\blea\s+rax,\[rsi\+0x8\]',text)
assert re.search(r'\badd\s+rsi,0x8\b',text)
Path('build/boundary115/interior.asm').write_text(fast+'\n')
Path('build/boundary115/boundary.asm').write_text(boundary+'\n')
print('PROVEN_INTERIOR_PREDICATE_ERASURE=PASS')
print('BOUNDARY_VECTOR_SEMANTICS_RETAINED=PASS')
print('INTERIOR_AFFINE_RELATION_REUSE=PASS')
PY

# No hidden scalar or workload-name dispatch may be introduced by region split.
python3 - <<'PY'
from pathlib import Path
runtime=Path('runtime/tensor_runtime_template_x86_64.S').read_text()
assert 'call eval_slot' not in runtime
src=(Path('compiler/tensor_frontend_x86_64.S').read_text()+Path('compiler/topologyc_x86_64.S').read_text()).lower()
for bad in ('heat_diffusion','moonbit','rust','projectoroptimizer','krylovoptimizer','toeplitzoptimizer'):
    assert bad not in src,bad
assert 'vec_select_interior_false' in src
print('BOUNDARY_REGION_SCALAR_FALLBACK=0')
print('BOUNDARY_REGION_NO_WORKLOAD_DISPATCH=PASS')
PY

echo 'WHEX_VECTOR_REGION_PARTITION_1_0_15=PASS'
