#!/usr/bin/env python3
import json, os, random, statistics, struct, subprocess, time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'worktree'/'build'
NS=(10_000_000,100_000_000)
QS=(1,2,4)
WARMUP=3
RUNS=21
TOL=1e-10

def bits_to_float(text):
    h=text.strip().split('0x',1)[1]
    return struct.unpack('>d', bytes.fromhex(h))[0]

def run(cmd): return subprocess.check_output(cmd,text=True).strip()
def cpu_set(q):
    avail=sorted(os.sched_getaffinity(0))
    if len(avail)<q: raise SystemExit(f'need {q} CPUs, have {avail}')
    return ','.join(str(x) for x in avail[:q])
def wh(kind,n,q): return ['taskset','-c',cpu_set(q),str(BUILD/f'global_stiffness_{kind}_q{q}'),str(n)]
def cc(n,q): return ['taskset','-c',cpu_set(q),str(BUILD/'global_stiffness_c'),str(n),str(q)]

def close(vals):
    scale=max(max(abs(v) for v in vals),1.0)
    return (max(vals)-min(vals))/scale <= TOL

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
    outs=[run(wh(k,4096,q)) for k in ('base','product','resident')]+[run(cc(4096,q))]
    vals=[bits_to_float(x) for x in outs]
    if not close(vals+[ref]):
        raise SystemExit(f'small correctness failure q={q}: py={ref} vals={vals}')
print('GLOBAL_STIFFNESS_FOURWAY_SMALL_REFERENCE=PASS')

results=[]
rng=random.Random(0x1234C0DE)
for n in NS:
  for q in QS:
    cmds={
      'Wheelchair-1.2.3-baseline':wh('base',n,q),
      'Wheelchair-product-subtract':wh('product',n,q),
      'Wheelchair-product-subtract-plus-residency':wh('resident',n,q),
      'Expert-C':cc(n,q),
    }
    outputs={name:run(cmd) for name,cmd in cmds.items()}
    vals={name:bits_to_float(out) for name,out in outputs.items()}
    if not close(list(vals.values())):
        raise SystemExit(f'large correctness mismatch n={n} q={q}: {vals}')
    for cmd in cmds.values():
      for _ in range(WARMUP): run(cmd)
    samples={name:[] for name in cmds}
    for _ in range(RUNS):
      order=list(cmds); rng.shuffle(order)
      for name in order:
        t0=time.perf_counter_ns(); out=run(cmds[name]); t1=time.perf_counter_ns()
        v=bits_to_float(out)
        scale=max(abs(vals[name]),1.0)
        if abs(v-vals[name])/scale > TOL: raise SystemExit(f'nondeterministic numeric result {name}')
        samples[name].append((t1-t0)/1e6)
    med={name:statistics.median(x) for name,x in samples.items()}
    b=med['Wheelchair-1.2.3-baseline']; p=med['Wheelchair-product-subtract']; r=med['Wheelchair-product-subtract-plus-residency']; c=med['Expert-C']
    row={
      'n':n,'executors':q,'runs':RUNS,'warmups':WARMUP,'checksums':outputs,
      'relative_checksum_spread':(max(vals.values())-min(vals.values()))/max(max(abs(v) for v in vals.values()),1.0),
      'baseline_ms':b,'product_ms':p,'resident_ms':r,'expert_c_ms':c,
      'product_speedup_vs_baseline':b/p,
      'residency_incremental_speedup':p/r,
      'total_speedup_vs_baseline':b/r,
      'resident_speedup_vs_c':c/r,
      'resident_percent_faster_than_c':(c/r-1)*100.0,
      'samples':samples,
    }
    results.append(row)
    print(f'N={n} Q={q} BASE={b:.6f} PRODUCT={p:.6f} RESIDENT={r:.6f} C={c:.6f} BASE/RES={b/r:.4f}x C/RES={c/r:.4f}x spread={row["relative_checksum_spread"]:.3e}')
print('FOURWAY_JSON_BEGIN')
print(json.dumps({'tolerance':TOL,'results':results},indent=2))
print('FOURWAY_JSON_END')
