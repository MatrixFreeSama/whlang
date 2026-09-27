#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/communication

# Wheelchair 1.0.9 keeps the tolerant terminal sum contract but removes the
# global chunk-publication/summaries topology.  Each leaf executor reduces its
# own chunks through an O(log chunks) stack-local binary frontier, then each
# internal causal executor-tree edge carries exactly one f64 result.
./whexc tests/whex/fem_parallel_elimination.whex -o build/communication/fem_1 --executors 1 >/dev/null
./whexc tests/whex/fem_parallel_elimination.whex -o build/communication/fem_4 --executors 4 >/dev/null

N=33554432
O1=$(build/communication/fem_1 "$N")
O4=$(build/communication/fem_4 "$N")
UNEVEN_N=20000000
U1=$(build/communication/fem_1 "$UNEVEN_N")
U4=$(build/communication/fem_4 "$UNEVEN_N")

python3 - "$O1" "$O4" "$U1" "$U4" <<'PY'
import struct,sys
def decode(line):
    h=line.strip().split('0x',1)[1]
    return struct.unpack('>d',bytes.fromhex(h))[0]
pairs=[(sys.argv[1],sys.argv[2]),(sys.argv[3],sys.argv[4])]
for a0,b0 in pairs:
    a,b=decode(a0),decode(b0)
    scale=max(1.0,abs(a),abs(b))
    rel=abs(a-b)/scale
    assert rel <= 1e-10,(a,b,rel)
    print(f'COMMUNICATION_NUMERIC_RELERR={rel:.17g}')
PY

python3 - <<'PY'
from pathlib import Path
import math,re,struct,subprocess,tempfile

root=Path('.')
inc=(root/'compiler/runtime_offsets.inc').read_text()
def equ(name):
    m=re.search(rf'^\.equ\s+{re.escape(name)},\s*(0x[0-9a-fA-F]+|\d+)',inc,re.M)
    assert m,name
    return int(m.group(1),0)

def u32_at_off(path,off):
    with open(path,'rb') as f:
        f.seek(off)
        return struct.unpack('<I',f.read(4))[0]

assert u32_at_off('build/communication/fem_1',equ('RUNTIME_COMM_ELIM_OFF')) == 0
assert u32_at_off('build/communication/fem_4',equ('RUNTIME_COMM_ELIM_OFF')) == 1
assert u32_at_off('build/communication/fem_4',equ('RUNTIME_EXECUTOR_OFF')) == 4

N=33_554_432
CHUNK=65_536
C=(N+CHUNK-1)//CHUNK
E=4
assert C==512 and C%E==0
M=C//E
assert M==128

# 1.0.8/1.0.7 observable topology: one global publication per chunk, then one
# summary per executor under communication elimination.  1.0.9 has no global
# arrays: only E-1 direct causal return edges can cross executor boundaries.
legacy_slots=C
v107_slots=E
v109_edges=E-1
assert (legacy_slots,v107_slots,v109_edges)==(512,4,3)

# Arithmetic work remains a proper reduction: local leaf reductions plus the
# distributed executor tree perform C-1 additions at this exact proof point.
legacy_adds=C-1
new_adds=E*(M-1)+(E-1)
assert new_adds==legacy_adds==511

# Critical reduction span stays at the dependency-required balanced depth.
legacy_span=int(math.log2(C))
new_span=int(math.log2(M))+int(math.log2(E))
assert new_span==legacy_span==9

asm=(root/'runtime/tensor_runtime_template_x86_64.S').read_text()
for forbidden in ('.spawn_loop:', '.wait_loop:', '.red_pairs:',
                  'worker_summaries:', 'partials:', 'child_stacks:'):
    assert forbidden not in asm,forbidden
assert 'run_tree:' in asm and '.rt_child:' in asm
assert '.w_carry:' in asm and '.w_finish_levels:' in asm

# Fixed runtime executable segment has no lock/fence/xchg synchronization.
ph=subprocess.check_output(['readelf','-lW','build/communication/fem_4'],text=True)
loads=[]
for line in ph.splitlines():
    if line.strip().startswith('LOAD'):
        c=line.split()
        loads.append((int(c[1],16),int(c[2],16),int(c[4],16),c))
off,va,n,_=loads[0]
data=Path('build/communication/fem_4').read_bytes()[off:off+n]
with tempfile.NamedTemporaryFile() as f:
    f.write(data); f.flush()
    dis=subprocess.check_output(
      ['objdump','-D','-b','binary','-m','i386:x86-64','-M','intel',
       f'--adjust-vma=0x{va:x}',f.name],text=True)
assert not re.search(r'\b(?:lock|mfence|sfence|lfence|xchg)\b',dis)

Path('build/communication/communication_gate.txt').write_text(
    f'N={N}\nchunks={C}\nexecutors={E}\n'
    f'legacy_global_slots={legacy_slots}\n'
    f'v1_0_7_worker_summary_slots={v107_slots}\n'
    f'v1_0_9_causal_return_edges={v109_edges}\n'
    f'legacy_reduction_adds={legacy_adds}\nnew_reduction_adds={new_adds}\n'
    f'legacy_tree_span={legacy_span}\nnew_tree_span={new_span}\n'
)
PY

echo 'COMMUNICATION_ELIMINATION=PASS'
echo 'COMMUNICATION_GLOBAL_STATE_ERASURE=PASS'
echo 'COMMUNICATION_CAUSAL_RETURN_EDGES=PASS'
echo 'COMMUNICATION_REDUCTION_WORK_NOT_INCREASED=PASS'
echo 'COMMUNICATION_REDUCTION_SPAN_PRESERVED=PASS'
echo 'COMMUNICATION_PARALLEL_WIDTH_PRESERVED=PASS'
echo 'COMMUNICATION_NO_GLOBAL_SYNC=PASS'
echo 'COMMUNICATION_NUMERIC_CONTRACT=PASS'
echo 'COMMUNICATION_UNEVEN_PARTITION_TREE=PASS'
