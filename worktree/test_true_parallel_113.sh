#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
mkdir -p build/true_parallel_113

# Same structural heat kernel that exposed the Rust explicit-AVX512 advantage.
build/topologyc tests/whex/heat_direct_core.wh -o build/true_parallel_113/heat_1 --executors 1 >/dev/null
build/topologyc tests/whex/heat_direct_core.wh -o build/true_parallel_113/heat_4 --executors 4 >/dev/null

for n in 1024 1025 2049 16777216; do
  A=$(build/true_parallel_113/heat_1 "$n")
  B=$(build/true_parallel_113/heat_4 "$n")
  [ "$A" = "$B" ]
done
[ "$(build/true_parallel_113/heat_1 16777216)" = 'checksum_bits=0x4167fc0000000000' ]
echo 'TRUE_PARALLEL_NUMERIC=PASS'
echo 'TRUE_PARALLEL_EXECUTOR_EQUIVALENCE=PASS'

# Runtime contract: one generated evaluator entry per chunk episode, no
# per-vector call loop and no scalar evaluator call anywhere in tensor runtime.
python3 - <<'PY'
from pathlib import Path
import re
s=Path('runtime/tensor_runtime_template_x86_64.S').read_text()
m=re.search(r'(?ms)^eval_chunk:\n(.*?)^# Direct AOT jump stubs\.',s)
assert m
chunk=m.group(1)
assert chunk.count('call eval_vec4') == 1, chunk.count('call eval_vec4')
assert 'call eval_slot' not in s
assert '.ecv_loop' not in chunk
assert 'mov edi,125' in chunk                  # contract violation, not scalar fallback
assert chunk.count('vdivsd') == 1              # dynamic reciprocal once per episode
print('EVALUATOR_LOOP_FUSION=PASS')
print('CROSS_EPISODE_DYNAMIC_CONSTANT_RESIDENCY=PASS')
print('PARALLEL_SCALAR_FALLBACK=0')
PY

# Machine-code proof of generic cross-vector axis induction.  The heat map has
# 17*i+3, so a correct induction realization initializes one c*axis carrier and
# advances that SAME carrier by 17*8 = 136 on the fused back edge.
python3 - <<'PY'
from pathlib import Path
import re,struct,subprocess,tempfile
blob=Path('build/true_parallel_113/heat_1').read_bytes()
inc=Path('compiler/runtime_offsets.inc').read_text()
def equ(name):
    m=re.search(rf'^\.equ\s+{re.escape(name)},\s*(0x[0-9a-fA-F]+|\d+)',inc,re.M)
    assert m,name
    return int(m.group(1),0)
def stub_target(off):
    disp=struct.unpack_from('<i',blob,off+1)[0]
    return 0x400000+off+5+disp
vec=stub_target(equ('RUNTIME_VEC_OFF'))
ini=stub_target(equ('RUNTIME_VEC_INIT_OFF'))
gen_off=equ('RUNTIME_GENERATED_FILE_OFF')
gen_va=equ('RUNTIME_GENERATED_VA')
pos=gen_off+(vec-gen_va)
assert blob[pos] == 0xE9                         # entry -> init island
# Entry target must be forward; hot loop starts at vec+5.
entry_disp=struct.unpack_from('<i',blob,pos+1)[0]
init_va=vec+5+entry_disp
assert init_va > vec+5
with tempfile.NamedTemporaryFile() as f:
    f.write(blob[gen_off:]); f.flush()
    dis=subprocess.check_output([
        'objdump','-D','-b','binary','-m','i386:x86-64','-M','intel',
        f'--adjust-vma=0x{gen_va:x}',f'--start-address=0x{vec:x}',
        f'--stop-address=0x{ini:x}',f.name],text=True)
# Parse vpaddq reg,reg,QWORD BCST targets and find the 136-byte recurrence.
step_regs=[]
for line in dis.splitlines():
    m=re.search(r'vpaddq\s+zmm(\d+),zmm\1,QWORD BCST \[rip\+0x([0-9a-fA-F]+)\].*#\s*0x([0-9a-fA-F]+)',line)
    if not m: continue
    reg=int(m.group(1)); addr=int(m.group(3),16)
    off=gen_off+(addr-gen_va)
    if 0 <= off <= len(blob)-8 and struct.unpack_from('<Q',blob,off)[0] == 136:
        step_regs.append(reg)
assert step_regs, dis
# The same carrier must be initialized from zmm6 by a multiply before the loop.
assert any(re.search(rf'vpmullq\s+zmm{r},zmm6,',dis) for r in step_regs), (step_regs,dis)
# Fused evaluator owns a real backward edge and does not call another evaluator.
back=False
for line in dis.splitlines():
    m=re.match(r'\s*([0-9a-fA-F]+):.*\bjmp\s+0x([0-9a-fA-F]+)',line)
    if m and int(m.group(2),16) < int(m.group(1),16): back=True
assert back
assert not re.search(r'\bcall\b',dis)
print('CROSS_VECTOR_AXIS_INDUCTION=PASS')
print('AFFINE_17_STEP_136=PASS')
print('FUSED_GENERATED_BACKEDGE=PASS')
print('GENERATED_INNER_CALLS=0')
PY

# Source-level ownership contract.  Induction and CSE share one allocator domain;
# no hard-coded workload name or solver name is allowed in the compiler/runtime.
python3 - <<'PY'
from pathlib import Path
s=(Path('compiler/tensor_frontend_x86_64.S').read_text()+Path('runtime/tensor_runtime_template_x86_64.S').read_text()).lower()
for bad in ('heat_diffusion','rust','projectoroptimizer','krylovoptimizer','toeplitzoptimizer'):
    assert bad not in s,bad
assert 'vec_induct_get_reg' in s
assert 'vec_fused_mode' in s
print('TRUE_PARALLEL_NO_WORKLOAD_DISPATCH=PASS')
PY

echo 'WHEX_TRUE_PARALLEL_1_0_13=PASS'
