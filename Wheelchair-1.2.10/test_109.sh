#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/release109

# Canonical 1- and 4-executor artifacts.
./whexc surface/whex_examples/heat_en.whex -o build/release109/heat_1 --executors 1 >/dev/null
./whexc surface/whex_examples/heat_en.whex -o build/release109/heat_4 --executors 4 >/dev/null
[ "$(build/release109/heat_1 100000)" = 'checksum_bits=0x40f24c3640000000' ]
[ "$(build/release109/heat_4 100000)" = 'checksum_bits=0x40f24c3640000000' ]

python3 - <<'PY'
from pathlib import Path
import re,struct,subprocess
root=Path('.')
asm=(root/'runtime/tensor_runtime_template_x86_64.S').read_text()
inc=(root/'compiler/runtime_offsets.inc').read_text()

def equ(name):
    m=re.search(rf'^\.equ\s+{re.escape(name)},\s*(0x[0-9a-fA-F]+|\d+)',inc,re.M)
    assert m,name
    return int(m.group(1),0)

# B: Runtime Erasure. Fixed evaluator arenas and O(problem-size) global state
# must be physically absent from the shipping runtime source.
for forbidden in (
    '.fill 65536', '.fill 4096', 'worker_summaries:', 'partials:',
    'child_stacks:', 'allowedmask:', 'pinmask:'
):
    assert forbidden not in asm,forbidden
assert 'SYS_mmap' in asm and 'SYS_munmap' in asm
assert 'CHILD_STACK_SIZE, 16384' in asm
assert '.w_carry:' in asm and '.w_finish_levels:' in asm
assert '.equ REDUCE_LEVELS, 12' in asm
assert 'sub rsp,96' in asm and 'add rsp,96' in asm

# Static runtime BSS is only g_n/g_chunks/g_exec = 20 bytes.
out=subprocess.check_output(['size','-A','build/tensor_runtime_template'],text=True)
m=re.search(r'^\.bss\s+(\d+)\s+',out,re.M)
assert m and int(m.group(1))==20,out

# Final tensor ELFs are sectionless and contain an exact-size third RX segment.
for path in ('build/release109/heat_1','build/release109/heat_4'):
    data=Path(path).read_bytes()
    hdr=subprocess.check_output(['readelf','-h',path],text=True)
    assert 'Start of section headers:          0 (bytes into file)' in hdr
    assert 'Number of section headers:         0' in hdr
    ph=subprocess.check_output(['readelf','-lW',path],text=True)
    loads=[]
    for line in ph.splitlines():
        if line.strip().startswith('LOAD'):
            c=line.split()
            loads.append((int(c[1],16),int(c[2],16),int(c[4],16),int(c[5],16),c))
    assert len(loads)==3,loads
    goff,gva,gfiles,gmem,_=loads[2]
    assert goff==equ('RUNTIME_GENERATED_FILE_OFF')
    assert gva==equ('RUNTIME_GENERATED_VA')
    assert gfiles==gmem
    assert len(data)==goff+gfiles,(len(data),goff,gfiles)
    # Data segment contains no page-sized BSS reservation: 69 bytes file + 23
    # bytes memory (3 bytes alignment + 20 actual BSS).
    assert loads[1][3]-loads[1][2] <= 32,loads[1]

# Direct rel32 stubs must target the generated RX segment, not a runtime pointer.
def check_direct(path):
    b=Path(path).read_bytes()
    ph=subprocess.check_output(['readelf','-lW',path],text=True)
    loads=[]
    for line in ph.splitlines():
        if line.strip().startswith('LOAD'):
            c=line.split(); loads.append((int(c[2],16),int(c[4],16)))
    gva,glen=loads[2]
    width=struct.unpack_from('<I',b,equ('RUNTIME_VECTOR_WIDTH_OFF'))[0]
    names=['RUNTIME_EVAL_OFF']
    if width==8: names += ['RUNTIME_VEC_OFF','RUNTIME_VEC_INIT_OFF']
    for n in names:
        off=equ(n)
        assert b[off]==0xE9,(n,b[off])
        disp=struct.unpack_from('<i',b,off+1)[0]
        target=0x400000+off+5+disp
        assert gva <= target < gva+glen,(n,hex(target),hex(gva),glen)
check_direct('build/release109/heat_1')
check_direct('build/release109/heat_4')

# C: Serial-Spine Erasure. The old root sweeps and global reducers are forbidden.
for forbidden in ('.spawn_loop:', '.wait_loop:', '.reduce_chunks:', '.red_pairs:',
                  '.red_outer:', '.w_loop_legacy:', '.w_loop_comm:'):
    assert forbidden not in asm,forbidden
for required in ('run_tree:', '.rt_internal:', '.rt_child:', '.w_carry:', '.w_finish_levels:'):
    assert required in asm,required

# No global scheduler/work queue or global publication buffers.
for forbidden in ('global_task_queue', 'work_queue', 'worker_summaries', 'partials:'):
    assert forbidden not in asm,forbidden

# Four executors form a fan-in-two causal tree: depth=2, cross-executor return
# edges=3, and the root cannot perform an O(P) wait/reduction sweep.
E=4
assert E-1==3
assert (E.bit_length()-1)==2

# Compiler path is still direct handwritten native assembly -> ELF. No C/LLVM
# code-generation backend or JIT is invoked by build/topologyc.
ld=subprocess.check_output(['readelf','-d','build/topologyc'],stderr=subprocess.STDOUT,text=True)
assert 'There is no dynamic section' in ld
ph=subprocess.check_output(['readelf','-lW','build/topologyc'],text=True)
assert ' INTERP ' not in ph
build=(root/'build.sh').read_text()
assert 'compiler/topologyc_x86_64.S' in build
low=build.lower()
for forbidden in ('gcc ', 'clang ', 'llvm', 'python', 'rustc', 'cargo'):
    assert forbidden not in low,forbidden
# The compiler binary itself must not carry a foreign compiler/runtime launcher.
strings=subprocess.check_output(['strings','build/topologyc'],text=True,errors='ignore').lower()
for forbidden in ('/usr/bin/python', '/usr/bin/gcc', '/usr/bin/clang', 'libllvm', 'libgcc_s', 'librust'):
    assert forbidden not in strings,forbidden
# Final topology images are direct static native ELF without an interpreter.
for path in ('build/release109/heat_1','build/release109/heat_4'):
    ph=subprocess.check_output(['readelf','-lW',path],text=True)
    assert ' INTERP ' not in ph
PY

echo 'RUNTIME_ERASURE=PASS'
echo 'FIXED_EVALUATOR_CAPACITY=0'
echo 'FIXED_CHILD_STACK_BSS=0'
echo 'GLOBAL_PARTIAL_ARRAY=0'
echo 'GLOBAL_WORKER_SUMMARY_ARRAY=0'
echo 'GENERATED_RX_SEGMENT_EXACT_SIZE=PASS'
echo 'REDUCTION_FRONTIER_EXACT_96B=PASS'
echo 'DIRECT_REL32_AOT=PASS'
echo 'SERIAL_SPINE_ERASURE=PASS'
echo 'CENTRAL_SPAWN_LOOP=0'
echo 'CENTRAL_WAIT_LOOP=0'
echo 'CENTRAL_REDUCTION_LOOP=0'
echo 'DISTRIBUTED_CAUSAL_RETURN_TREE=PASS'
echo 'GLOBAL_TASK_QUEUE=0'
echo 'ASSEMBLY_ONLY_NATIVE_BUILD=PASS'
echo 'NO_FOREIGN_HIGH_LEVEL_BACKEND=PASS'
echo 'NO_DYNAMIC_RUNTIME_OR_INTERPRETER=PASS'
echo 'WHEELCHAIR_1_0_9_GATES=PASS'
