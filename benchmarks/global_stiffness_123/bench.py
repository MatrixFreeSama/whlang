#!/usr/bin/env python3
import json, math, os, random, statistics, struct, subprocess, time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'worktree'/'build'
NS=(10_000_000,100_000_000)
QS=(1,2,4)
WARMUP=3
RUNS=11

def bits_to_float(text):
    h=text.strip().split('0x',1)[1]
    return struct.unpack('>d', bytes.fromhex(h))[0]

def run(cmd):
    return subprocess.check_output(cmd,text=True).strip()

def cpu_set(q):
    avail=sorted(os.sched_getaffinity(0))
    if len(avail)<q: raise SystemExit(f'need {q} CPUs, have {avail}')
    return ','.join(str(x) for x in avail[:q])

def wh_cmd(n,q):
    return ['taskset','-c',cpu_set(q),str(BUILD/f'global_stiffness_wh_q{q}'),str(n)]

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

# Independent small correctness check.
ref=py_reference(4096)
for q in QS:
    wo=bits_to_float(run(wh_cmd(4096,q)))
    co=bits_to_float(run(c_cmd(4096,q)))
    scale=max(abs(ref),1.0)
    if abs(wo-ref)/scale>1e-12 or abs(co-ref)/scale>1e-12:
        raise SystemExit(f'correctness failure q={q}: py={ref} wh={wo} c={co}')
print('GLOBAL_STIFFNESS_SMALL_REFERENCE=PASS')

results=[]
rng=random.Random(12345)
for n in NS:
    for q in QS:
        cmds={'Wheelchair-1.2.3':wh_cmd(n,q),'Expert-C':c_cmd(n,q)}
        outputs={name:run(cmd) for name,cmd in cmds.items()}
        wf=bits_to_float(outputs['Wheelchair-1.2.3']); cf=bits_to_float(outputs['Expert-C'])
        rel=abs(wf-cf)/max(abs(wf),abs(cf),1.0)
        if rel>1e-11:
            raise SystemExit(f'large correctness mismatch n={n} q={q}: {outputs}, rel={rel}')
        for name,cmd in cmds.items():
            for _ in range(WARMUP): run(cmd)
        samples={name:[] for name in cmds}
        for _ in range(RUNS):
            order=list(cmds); rng.shuffle(order)
            for name in order:
                t0=time.perf_counter_ns(); out=run(cmds[name]); t1=time.perf_counter_ns()
                if out!=outputs[name]: raise SystemExit(f'non-deterministic checksum {name} n={n} q={q}')
                samples[name].append((t1-t0)/1e6)
        med={name:statistics.median(v) for name,v in samples.items()}
        wh=med['Wheelchair-1.2.3']; cc=med['Expert-C']
        row={
            'n':n,'executors':q,'runs':RUNS,'warmups':WARMUP,
            'checksum_wheelchair':outputs['Wheelchair-1.2.3'],
            'checksum_expert_c':outputs['Expert-C'],'relative_checksum_delta':rel,
            'wheelchair_median_ms':wh,'expert_c_median_ms':cc,
            'wheelchair_speedup_vs_c':cc/wh,
            'wheelchair_percent_faster':(cc/wh-1.0)*100.0,
            'wheelchair_samples_ms':samples['Wheelchair-1.2.3'],
            'expert_c_samples_ms':samples['Expert-C'],
        }
        results.append(row)
        print(f"N={n} Q={q} WH={wh:.6f} ms C={cc:.6f} ms C/WH={cc/wh:.4f}x delta={rel:.3e}")

meta={
    'benchmark':'matrix-free variable-coefficient 1D FEM global stiffness action',
    'formula':'(Kx)_i=(k_i+k_{i+1})x_i-k_i*x_{i-1}-k_{i+1}*x_{i+1}; checksum=sum((Kx)_i^2)',
    'measurement':'whole-process wall time, 3 warmups, 11 shuffled/interleaved measured runs, median',
    'compiler_c':'gcc -O3 -march=native -mtune=native -flto -ffast-math -pthread',
    'cpu_affinity':'first q CPUs from sched_getaffinity, enforced with taskset',
    'results':results,
}
print('RESULT_JSON_BEGIN')
print(json.dumps(meta,indent=2))
print('RESULT_JSON_END')
