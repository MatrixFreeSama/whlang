#!/usr/bin/env python3
import json, os, random, statistics, struct, subprocess, time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'worktree'/'build'
NS=(10_000_000,100_000_000)
QS=(1,2,4)
WARMUP=3
RUNS=21

def bits_to_float(text):
    h=text.strip().split('0x',1)[1]
    return struct.unpack('>d', bytes.fromhex(h))[0]

def run(cmd):
    return subprocess.check_output(cmd,text=True).strip()

def cpu_set(q):
    avail=sorted(os.sched_getaffinity(0))
    if len(avail)<q: raise SystemExit(f'need {q} CPUs, have {avail}')
    return ','.join(str(x) for x in avail[:q])

def wh_cmd(kind,n,q):
    return ['taskset','-c',cpu_set(q),str(BUILD/f'global_stiffness_{kind}_q{q}'),str(n)]

def c_cmd(n,q):
    return ['taskset','-c',cpu_set(q),str(BUILD/'global_stiffness_c'),str(n),str(q)]

def py_reference(n):
    def x(i): return -0.5 + ((i*29+7)&1023)/1024.0
    def k(i): return 1.0 + ((i*17+3)&255)/1024.0
    s=0.0
    for i in range(n):
        im=(i-1)%n; ip=(i+1)%n
        y=(k(i)+k(ip))*x(i)-k(i)*x(im)-k(ip)*x(ip)
        s += y*y
    return s

ref=py_reference(4096)
for q in QS:
    outs={
        'baseline':run(wh_cmd('base',4096,q)),
        'optimized':run(wh_cmd('opt',4096,q)),
        'c':run(c_cmd(4096,q)),
    }
    vals={k:bits_to_float(v) for k,v in outs.items()}
    scale=max(abs(ref),1.0)
    for name,v in vals.items():
        if abs(v-ref)/scale>1e-12:
            raise SystemExit(f'correctness failure q={q} {name}: py={ref} got={v}')
    if len(set(outs.values())) != 1:
        raise SystemExit(f'bitwise mismatch small q={q}: {outs}')
print('GLOBAL_STIFFNESS_THREEWAY_SMALL_REFERENCE=PASS')

results=[]
rng=random.Random(0x1234C0DE)
for n in NS:
    for q in QS:
        cmds={
            'Wheelchair-1.2.3-baseline':wh_cmd('base',n,q),
            'Wheelchair-generic-product-subtract':wh_cmd('opt',n,q),
            'Expert-C':c_cmd(n,q),
        }
        outputs={name:run(cmd) for name,cmd in cmds.items()}
        if len(set(outputs.values())) != 1:
            vals={k:bits_to_float(v) for k,v in outputs.items()}
            scale=max(max(abs(v) for v in vals.values()),1.0)
            spread=(max(vals.values())-min(vals.values()))/scale
            raise SystemExit(f'large correctness mismatch n={n} q={q}: {outputs}, spread={spread}')
        for cmd in cmds.values():
            for _ in range(WARMUP): run(cmd)
        samples={name:[] for name in cmds}
        for _ in range(RUNS):
            order=list(cmds); rng.shuffle(order)
            for name in order:
                t0=time.perf_counter_ns(); out=run(cmds[name]); t1=time.perf_counter_ns()
                if out!=outputs[name]:
                    raise SystemExit(f'non-deterministic checksum {name} n={n} q={q}')
                samples[name].append((t1-t0)/1e6)
        med={name:statistics.median(v) for name,v in samples.items()}
        base=med['Wheelchair-1.2.3-baseline']
        opt=med['Wheelchair-generic-product-subtract']
        cc=med['Expert-C']
        row={
            'n':n,'executors':q,'runs':RUNS,'warmups':WARMUP,
            'checksum':next(iter(outputs.values())),
            'baseline_ms':base,'optimized_ms':opt,'expert_c_ms':cc,
            'optimization_speedup':base/opt,
            'optimization_percent':(base/opt-1.0)*100.0,
            'optimized_speedup_vs_c':cc/opt,
            'optimized_percent_faster_than_c':(cc/opt-1.0)*100.0,
            'baseline_speedup_vs_c':cc/base,
            'samples':samples,
        }
        results.append(row)
        print(
            f'N={n} Q={q} BASE={base:.6f} ms OPT={opt:.6f} ms C={cc:.6f} ms '
            f'BASE/OPT={base/opt:.4f}x C/OPT={cc/opt:.4f}x'
        )

meta={
    'benchmark':'same-host matrix-free variable-coefficient 1D FEM global stiffness action',
    'formula':'(Kx)_i=(k_i+k_{i+1})x_i-k_i*x_{i-1}-k_{i+1}*x_{i+1}; checksum=sum((Kx)_i^2)',
    'contestants':['Wheelchair 1.2.3 frozen baseline','Wheelchair generic tolerant Product-Subtract Contraction','matched Expert C'],
    'measurement':'whole-process wall time, 3 warmups, 21 shuffled/interleaved measured runs per contestant, median',
    'compiler_c':'gcc -O3 -march=native -mtune=native -flto -ffast-math -pthread',
    'cpu_affinity':'first q CPUs from sched_getaffinity, enforced with taskset',
    'results':results,
}
print('THREEWAY_JSON_BEGIN')
print(json.dumps(meta,indent=2))
print('THREEWAY_JSON_END')
