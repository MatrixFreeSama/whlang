#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

./build.sh >/dev/null
mkdir -p build/112

# 1.0.12 dynamic affine-modulo gate. This deliberately uses the existing
# sparse nonlinear topology so whole-expression linear-span recovery cannot
# hide the direct vector modulo realization.
./build/topologyc tests/topology_cases/sparse_nonlinear_operator_tolerant.wh -o build/112/sparse1 --executors 1 >/dev/null
./build/topologyc tests/topology_cases/sparse_nonlinear_operator_tolerant.wh -o build/112/sparse4 --executors 4 >/dev/null

python3 - <<'PY'
import subprocess,struct,re,random,math

def decode(path,n):
    s=subprocess.check_output([path,str(n)],text=True).strip()
    b=int(re.search(r'0x([0-9a-fA-F]{16})',s).group(1),16)
    return struct.unpack('<d',struct.pack('<Q',b))[0]

def reference(n):
    def x(j):
        return -0.375 + (((31*j+5)%1024)/1024.0)
    vals=[]
    for i in range(n):
        xi=x(i)
        vals.append(
            1.75*xi
            - 0.125*x((17*i+3)%n)
            + 0.0625*x((29*i+7)%n)
            - 0.03125*x((43*i+11)%n)
            + 0.015625*((xi*xi)*xi)
        )
    return math.fsum(vals)

ns=[4,5,6,7,8,9,15,16,17,31,32,33,63,64,65,127,128,129,
    255,256,257,511,512,513,1023,1024,1025,1537,2047,2048,2049,
    4095,4096,4097]
r=random.Random(112)
ns += [r.randint(4,6000) for _ in range(24)]
for n in ns:
    want=reference(n)
    a=decode('build/112/sparse1',n)
    b=decode('build/112/sparse4',n)
    tol=1e-8 + 1e-10*abs(want)
    assert abs(a-want)<=tol,(n,want,a,tol)
    assert abs(b-want)<=tol,(n,want,b,tol)
    assert abs(a-b)<=tol,(n,a,b,tol)
print(f'DYNAMIC_AFFINE_MODULO_DIFFERENTIAL_CASES={len(ns)}')
print('DYNAMIC_AFFINE_MODULO_NUMERIC=PASS')
print('DYNAMIC_AFFINE_MODULO_EXECUTOR_EQUIVALENCE=PASS')
PY

# Anti-specialization: q*n terms and a compensated negative offset must pass
# through the same integer affine-modulo recognizer. The nonlinear square keeps
# this on ordinary structural vector lowering instead of a named linear fast path.
./build/topologyc tests/topology_cases/dynamic_affine_modulo_general.wh -o build/112/modgen1 --executors 1 >/dev/null
./build/topologyc tests/topology_cases/dynamic_affine_modulo_general.wh -o build/112/modgen4 --executors 4 >/dev/null
python3 - <<'PY'
import subprocess,struct,re,random,math

def decode(path,n):
    s=subprocess.check_output([path,str(n)],text=True).strip()
    b=int(re.search(r'0x([0-9a-fA-F]{16})',s).group(1),16)
    return struct.unpack('<d',struct.pack('<Q',b))[0]

def reference(n):
    def p(j): return ((13*j+7)%1024)/1024.0
    vals=[]
    for i in range(n):
        a=p((17*i+2*n+3)%n)
        b=p((17*i+n-3)%n)
        vals.append(a*a+0.5*b)
    return math.fsum(vals)

ns=[4,5,7,8,9,15,16,17,31,32,33,63,64,65,127,128,129,
    255,256,257,511,512,513,1023,1024,1025,2049,4097]
r=random.Random(1212)
ns += [r.randint(4,8000) for _ in range(20)]
for n in ns:
    want=reference(n)
    a=decode('build/112/modgen1',n)
    b=decode('build/112/modgen4',n)
    tol=1e-9 + 1e-11*abs(want)
    assert abs(a-want)<=tol,(n,want,a,tol)
    assert abs(b-want)<=tol,(n,want,b,tol)
    assert abs(a-b)<=tol,(n,a,b,tol)
print(f'AFFINE_MODULO_QN_SIGNED_OFFSET_CASES={len(ns)}')
print('AFFINE_MODULO_QN_SIGNED_OFFSET=PASS')
PY

# The compiler must remain structure-driven: no test/workload identity may be
# referenced by compiler/runtime sources, and tensor execution must not regain
# a scalar evaluator call.
if grep -RqiE 'sparse_nonlinear_operator|dynamic_affine_modulo_general|heat_diffusion_step|wave_leapfrog_step|fem_linear_aggregate' compiler runtime; then
    echo 'workload-specific dispatch marker found in compiler/runtime source' >&2
    exit 1
fi
if grep -q 'call eval_slot' runtime/tensor_runtime_template_x86_64.S; then
    echo 'tensor scalar evaluator fallback reintroduced' >&2
    exit 1
fi
echo 'STRUCTURAL_ALGEBRA_NO_WORKLOAD_DISPATCH=PASS'
echo 'TENSOR_HIDDEN_SCALAR_FALLBACK=0'

echo 'GENERALIZED_STRUCTURAL_ALGEBRA_1_0_12=PASS'
