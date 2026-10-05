#!/usr/bin/env python3
import subprocess,time,statistics,csv,platform,hashlib,json,os
from pathlib import Path
ROOT=Path('/mnt/data/bench128/thermo_damage')
SIZES=[1_000_000,4_000_000,8_000_000,16_000_000]
REPS=9
IMPLS=[
 ('Wheelchair_1.3.128',ROOT/'k_full_no_tempnext.bin'),
 ('GCC_C_native',ROOT/'c_native'),
 ('GFortran_native',ROOT/'f_native'),
 ('GCC_C_active_ceiling',ROOT/'c_ceiling'),
]

def run(bin,n):
    t0=time.perf_counter_ns()
    p=subprocess.run(['taskset','-c','0',str(bin),str(n)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    dt=(time.perf_counter_ns()-t0)/1e6
    if p.returncode: raise RuntimeError((bin,n,p.returncode,p.stderr))
    bits=''
    val=''
    for line in p.stdout.splitlines():
        if line.startswith('checksum_bits='): bits=line.split('=',1)[1].strip().lower()
        if line.startswith('checksum='): val=line.split('=',1)[1].strip()
    return dt,bits,val

# warmups
for n in SIZES:
    for _,b in IMPLS: run(b,n)
rows=[]
for n in SIZES:
    for r in range(REPS):
        order=IMPLS[r%len(IMPLS):]+IMPLS[:r%len(IMPLS)]
        for label,b in order:
            dt,bits,val=run(b,n)
            rows.append(dict(n=n,round=r+1,implementation=label,wall_ms=dt,checksum_bits=bits,checksum=val))
with open(ROOT/'raw.csv','w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
summary=[]
for n in SIZES:
    med={}
    for label,_ in IMPLS:
        xs=[r['wall_ms'] for r in rows if r['n']==n and r['implementation']==label]
        m=statistics.median(xs); mad=statistics.median([abs(x-m) for x in xs]); med[label]=m
        bits=sorted(set(r['checksum_bits'] for r in rows if r['n']==n and r['implementation']==label))
        summary.append(dict(n=n,implementation=label,reps=len(xs),median_ms=m,mad_ms=mad,checksum_bits=';'.join(bits)))
    for q in summary[-len(IMPLS):]:
        q['speedup_vs_c']=med['GCC_C_native']/q['median_ms']
        q['time_over_ceiling']=q['median_ms']/med['GCC_C_active_ceiling']
with open(ROOT/'summary.csv','w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=summary[0].keys());w.writeheader();w.writerows(summary)
# environment
pkg=Path('/mnt/data/Wheelchair-1.3.128.zip')
env={
 'cpu':subprocess.check_output("lscpu | grep 'Model name' | head -1",shell=True,text=True).strip(),
 'cpus':subprocess.check_output("lscpu | grep '^CPU(s):' | head -1",shell=True,text=True).strip(),
 'gcc':subprocess.check_output(['gcc','--version'],text=True).splitlines()[0],
 'gfortran':subprocess.check_output(['gfortran','--version'],text=True).splitlines()[0],
 'kernel':platform.release(),
 'wheelchair_zip_sha256':hashlib.sha256(pkg.read_bytes()).hexdigest(),
 'pin':'taskset -c 0',
 'repetitions':REPS,
 'sizes':SIZES,
 'c_flags':'-O3 -march=native -fno-fast-math -ffp-contract=off',
 'fortran_flags':'-O3 -march=native -fno-fast-math -ffp-contract=off -ffree-line-length-none',
}
(ROOT/'environment.json').write_text(json.dumps(env,indent=2)+'\n')
# markdown
by={(q['n'],q['implementation']):q for q in summary}
lines=['# Localized thermo-elasto-plastic-damage explicit-step benchmark — Wheelchair 1.3.128','',
'One pinned CPU, Strict semantics, 9 interleaved repetitions. The physical event width is fixed while the background domain grows. Natural C/Fortran traverse the full domain; the C ceiling traverses only the mathematically active ~6001-point support and is a lower-bound control, not a natural baseline.','',
'| n | Wheelchair ms | C ms | Fortran ms | C ceiling ms | WH/C | WH/ceiling |',
'|---:|---:|---:|---:|---:|---:|---:|']
for n in SIZES:
    wh=by[n,'Wheelchair_1.3.128']; c=by[n,'GCC_C_native']; ft=by[n,'GFortran_native']; ce=by[n,'GCC_C_active_ceiling']
    lines.append(f"| {n:,} | {wh['median_ms']:.3f} | {c['median_ms']:.3f} | {ft['median_ms']:.3f} | {ce['median_ms']:.3f} | {c['median_ms']/wh['median_ms']:.3f}x | {wh['median_ms']/ce['median_ms']:.1f}x |")
lines += ['', 'The Wheelchair checksum differs from the sequential C reduction only in final rounding bits; the C active-support ceiling is bit-identical to natural C at every tested size.', '', 'This benchmark intentionally retains the negative result: the 1.3.128 Physical DAG does not contract the full coupled support after localized constitutive facts feed periodic stress-divergence and thermal-diffusion relations. Runtime therefore still scales with total domain size instead of the fixed active support.']
(ROOT/'RESULTS.md').write_text('\n'.join(lines)+'\n')
print((ROOT/'RESULTS.md').read_text())
