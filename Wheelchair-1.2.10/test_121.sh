#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/interior121

# Generic witness: a pure affine map is loaded through periodic(i-1,n) and
# periodic(i+1,n).  Only the proven interior vector region may erase dynamic
# modulo-n; boundary vectors retain the exact original modulo semantics.
./whexc tests/whex/interior_periodic_composition.whex -o build/interior121/native_1 --executors 1 >/dev/null
./whexc tests/whex/interior_periodic_composition.whex -o build/interior121/native_4 --executors 4 >/dev/null
./whexc tests/whex/interior_periodic_composition.whex -o build/interior121/foundation_1 --executors 1 --isa-limit avx512f >/dev/null
./whexc tests/whex/interior_periodic_radius2_control.whex -o build/interior121/radius2 --executors 1 >/dev/null

python3 - <<'PY'
import random,struct,subprocess
bins={
 'n1':'build/interior121/native_1',
 'n4':'build/interior121/native_4',
 'f1':'build/interior121/foundation_1',
}
ns=[4,5,7,8,9,15,16,17,31,32,33,63,64,65,127,255,257,1023,1024,1025,
    2047,2048,2049,4095,4096,4097,65535,65536,65537,65543,131071,131072,131073]
r=random.Random(121)
ns += [r.randint(4,300000) for _ in range(24)]
def val(out):
    return struct.unpack('>d',bytes.fromhex(out.split('0x',1)[1]))[0]
def p(i): return -0.375 + (((i*37)+11)&2047)/2048.0
def ref(n):
    s=0.0
    for i in range(n):
        s += p((i-1)%n) + 0.5*p(i) + p((i+1)%n)
    return s
for n in ns:
    out={k:subprocess.check_output([b,str(n)],text=True).strip() for k,b in bins.items()}
    vals={k:val(v) for k,v in out.items()}
    for k in ('n4','f1'):
        rel=abs(vals[k]-vals['n1'])/max(1.0,abs(vals['n1']))
        assert rel <= 1e-12,(n,k,vals,rel)
for n in (4,5,7,8,9,16,17,31,32,33,257,1025,4097):
    got=val(subprocess.check_output([bins['n1'],str(n)],text=True).strip())
    want=ref(n)
    assert got==want,(n,got,want)
print(f'INTERIOR_PERIODIC_DIFFERENTIAL_CASES={len(ns)}')
print('INTERIOR_PERIODIC_EXECUTOR_EQUIVALENCE=PASS')
print('INTERIOR_PERIODIC_AVX512F_EQUIVALENCE=PASS')
print('INTERIOR_PERIODIC_REFERENCE=PASS')
PY

tools/disassemble_generated.sh build/interior121/native_1 > build/interior121/native.dis
tools/disassemble_generated.sh build/interior121/radius2 > build/interior121/radius2.dis
python3 - <<'PY'
from pathlib import Path
import re

def regions(path):
    text=Path(path).read_text()
    rows=[]
    for line in text.splitlines():
        m=re.match(r'^\s*([0-9a-fA-F]+):\s+(.*)$',line)
        if m: rows.append((int(m.group(1),16),line,m.group(2)))
    safe=fast_start=None
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
    return fast,boundary

fast,boundary=regions('build/interior121/native.dis')
# The safe ±1 witness has no dynamic modulo quotient/conversion in the proven
# interior body and no repeated qword multiplication there. Boundary code keeps
# the conversion machinery because global wrap remains semantically necessary.
assert not re.search(r'\bvcvttpd2qq\b',fast),fast
assert not re.search(r'\bvpmullq\b',fast),fast
assert re.search(r'\bvcvttpd2qq\b',boundary),boundary

fast2,_=regions('build/interior121/radius2.dis')
# A radius-2 left neighbor is not safe for the whole current interior contract:
# the first interior block contains axis=1. The optimizer must conservatively
# retain dynamic modulo rather than overgeneralize the ±1 proof.
assert re.search(r'\bvcvttpd2qq\b',fast2),fast2
print('INTERIOR_PERIODIC_MODULO_ERASURE=PASS')
print('BOUNDARY_PERIODIC_SEMANTICS_RETAINED=PASS')
print('INTERIOR_PERIODIC_UNPROVEN_CONTROL_RETAINED=PASS')
PY

python3 - <<'PY'
from pathlib import Path
src=(Path('compiler/tensor_frontend_x86_64.S').read_text()+Path('compiler/topologyc_x86_64.S').read_text()).lower()
for bad in ('newton_jv','newton','jacobian','heat_diffusion','stenciloptimizer','moonbit','rust'):
    assert bad not in src,bad
assert 'vec_interior_affine_residue_safe' in src
assert 'call eval_slot' not in Path('runtime/tensor_runtime_template_x86_64.S').read_text()
print('INTERIOR_PERIODIC_NO_WORKLOAD_DISPATCH=PASS')
print('INTERIOR_PERIODIC_SCALAR_FALLBACK=0')
PY

echo 'WHEX_INTERIOR_PERIODIC_COMPOSITION_1_2_1=PASS'
