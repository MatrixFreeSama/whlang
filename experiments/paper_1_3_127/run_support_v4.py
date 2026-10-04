#!/usr/bin/env python3
import csv, json, os, platform, shutil, statistics, subprocess, sys, tempfile, time, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'experiments'/'paper_1_3_127'/'support_v4_20261005'
REPS=15
SCALE_REPS=7
N=8_000_000
CPU=min(os.sched_getaffinity(0)) if hasattr(os,'sched_getaffinity') else 0


def run(cmd,cwd=None,check=True):
    cp=subprocess.run(cmd,cwd=cwd,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if check and cp.returncode: raise RuntimeError(f'rc={cp.returncode} cwd={cwd} cmd={cmd!r}\nstdout={cp.stdout!r}\nstderr={cp.stderr!r}')
    return cp


def timed(exe,n):
    cmd=['taskset','-c',str(CPU),str(exe),str(n)]
    t0=time.perf_counter_ns(); cp=subprocess.run(cmd,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE); ms=(time.perf_counter_ns()-t0)/1e6
    if cp.returncode: raise RuntimeError(f'run rc={cp.returncode} cmd={cmd!r}\nstdout={cp.stdout!r}\nstderr={cp.stderr!r}')
    return ms,cp.stdout.strip(),cp.stderr.strip()


def cc(src,out):
    return ['gcc','-O3','-march=x86-64-v4','-mtune=generic','-fno-fast-math','-ffp-contract=off',str(src),'-lm','-o',str(out)]


def fc(src,out):
    return ['gfortran','-O3','-march=x86-64-v4','-mtune=generic','-fno-fast-math','-ffp-contract=off','-fprotect-parens',str(src),'-o',str(out)]


def unpack(ver,work):
    dest=work/f'w{ver.replace(".","_")}'; dest.mkdir()
    with zipfile.ZipFile(ROOT/'dist'/f'Wheelchair-{ver}.zip') as z: z.extractall(dest)
    p=dest/f'Wheelchair-{ver}'
    if not p.is_dir(): p=next(x for x in dest.iterdir() if x.is_dir())
    for name in ('topologyc','wheelchairc'):
        q=p/'bin'/name
        if q.exists(): q.chmod(q.stat().st_mode|0o111)
    return p


def main():
    flags=run(['bash','-lc','grep -m1 "^flags" /proc/cpuinfo || true'],check=False).stdout.lower()
    if 'avx512f' not in flags:
        raise SystemExit('AVX512_REQUIRED: support-v4 experiment intentionally not run on this host')
    if OUT.exists(): shutil.rmtree(OUT)
    OUT.mkdir(parents=True); (OUT/'sources').mkdir()
    env=['experiment=support_v4_structural','wheelchair=1.3.127 topologyc','control_isa=x86-64-v4',f'repo_commit={run(["git","rev-parse","HEAD"]).stdout.strip()}',f'pinned_cpu={CPU}',f'python={sys.version}',f'platform={platform.platform()}']
    for cmd in (['uname','-a'],['lscpu'],['gcc','--version'],['gfortran','--version']):
        cp=run(cmd,check=False); env.append('$ '+' '.join(cmd)+'\n'+cp.stdout+cp.stderr)
    (OUT/'environment.txt').write_text('\n'.join(env)+'\n',encoding='utf-8')

    with tempfile.TemporaryDirectory(prefix='wh-paper-v4-') as td:
        td=Path(td); w127=unpack('1.3.127',td); w126=unpack('1.3.126',td); bins=td/'bin'; bins.mkdir()
        compile_rows=[]; cases=[]
        def comp(label,cmd,cwd=None,optional=False):
            t0=time.perf_counter_ns(); cp=run(cmd,cwd=cwd,check=False); ms=(time.perf_counter_ns()-t0)/1e6
            compile_rows.append([label,ms,cp.returncode,cp.stdout.strip(),cp.stderr.strip(),' '.join(map(str,cmd)),str(cwd or '')])
            if cp.returncode and not optional: raise RuntimeError(f'compile failed {label}: {cp.stderr!r}')
            return cp.returncode==0

        # Localized plasticity, including exact-source 126 ablation.
        pdir=w127/'devtrash'/'benchmarks'/'localized_plasticity_13127'; pcopy=OUT/'sources'/'localized_plasticity'; pcopy.mkdir()
        for f in ('plasticity.whex','plasticity.c','plasticity.f90','plasticity_ceiling.c','plasticity_ceiling.f90','README.md'): shutil.copy2(pdir/f,pcopy/f)
        p126=w126/'paper_inputs'; p126.mkdir(exist_ok=True); shutil.copy2(pdir/'plasticity.whex',p126/'plasticity.whex')
        pd=bins/'plasticity'; pd.mkdir()
        pi={'Wheelchair_1.3.127_v4':pd/'w127','Wheelchair_1.3.126_v4':pd/'w126','GCC_C_v4':pd/'c','GFortran_v4':pd/'f','C_ceiling_v4':pd/'cc','Fortran_ceiling_v4':pd/'fc'}
        comp('plasticity/Wheelchair_1.3.127_v4',['./bin/topologyc','devtrash/benchmarks/localized_plasticity_13127/plasticity.whex','-o',str(pi['Wheelchair_1.3.127_v4'])],cwd=w127)
        if not comp('plasticity/Wheelchair_1.3.126_v4',['./bin/topologyc','paper_inputs/plasticity.whex','-o',str(pi['Wheelchair_1.3.126_v4'])],cwd=w126,optional=True): pi.pop('Wheelchair_1.3.126_v4')
        comp('plasticity/GCC_C_v4',cc(pdir/'plasticity.c',pi['GCC_C_v4'])); comp('plasticity/GFortran_v4',fc(pdir/'plasticity.f90',pi['GFortran_v4']))
        comp('plasticity/C_ceiling_v4',cc(pdir/'plasticity_ceiling.c',pi['C_ceiling_v4'])); comp('plasticity/Fortran_ceiling_v4',fc(pdir/'plasticity_ceiling.f90',pi['Fortran_ceiling_v4']))
        cases.append(('localized_plasticity',pi,'GCC_C_v4',N))

        # Disconnected Level-Set support.
        ldir=w127/'devtrash'/'benchmarks'/'levelset_regionset_13126'; lcopy=OUT/'sources'/'levelset_regionset'; lcopy.mkdir()
        for f in ('levelset_two_regions.whex','levelset.c','levelset.f90','levelset_ceiling.c','levelset_ceiling.f90'): shutil.copy2(ldir/f,lcopy/f)
        ld=bins/'levelset'; ld.mkdir(); li={'Wheelchair_1.3.127_v4':ld/'w127','GCC_C_v4':ld/'c','GFortran_v4':ld/'f','C_ceiling_v4':ld/'cc','Fortran_ceiling_v4':ld/'fc'}
        comp('levelset/Wheelchair_1.3.127_v4',['./bin/topologyc','devtrash/benchmarks/levelset_regionset_13126/levelset_two_regions.whex','-o',str(li['Wheelchair_1.3.127_v4'])],cwd=w127)
        comp('levelset/GCC_C_v4',cc(ldir/'levelset.c',li['GCC_C_v4'])); comp('levelset/GFortran_v4',fc(ldir/'levelset.f90',li['GFortran_v4']))
        comp('levelset/C_ceiling_v4',cc(ldir/'levelset_ceiling.c',li['C_ceiling_v4'])); comp('levelset/Fortran_ceiling_v4',fc(ldir/'levelset_ceiling.f90',li['Fortran_ceiling_v4']))
        cases.append(('levelset_two_regions',li,'GCC_C_v4',N))
        with (OUT/'compile_log.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow(['label','compile_ms','returncode','stdout','stderr','command','cwd']); w.writerows(compile_rows)

        raw=[]
        for workload,impl,base,n in cases:
            names=list(impl)
            for name in names: timed(impl[name],n)
            for rep in range(REPS):
                order=names[rep%len(names):]+names[:rep%len(names)]
                for pos,name in enumerate(order):
                    ms,so,se=timed(impl[name],n); raw.append([workload,rep,pos,name,n,CPU,ms,so,se])
        with (OUT/'raw.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow(['workload','rep','order_index','implementation','n','cpu','wall_ms','stdout','stderr']); w.writerows(raw)

        summary=[]
        for workload,impl,base,n in cases:
            meds={name:statistics.median([r[6] for r in raw if r[0]==workload and r[3]==name]) for name in impl}; c=meds[base]
            for name in impl:
                rr=[r for r in raw if r[0]==workload and r[3]==name]; xs=[r[6] for r in rr]; m=statistics.median(xs); mad=statistics.median(abs(x-m) for x in xs); outs=sorted({r[7] for r in rr})
                summary.append([workload,name,len(xs),min(xs),m,statistics.mean(xs),max(xs),statistics.pstdev(xs),mad,m/c,c/m,json.dumps(outs,ensure_ascii=False)])
        with (OUT/'summary.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow(['workload','implementation','reps','min_ms','median_ms','mean_ms','max_ms','stdev_ms','mad_ms','time_over_C','speedup_over_C','unique_stdout']); w.writerows(summary)

        # Scaling witnesses: enough repetitions for trend, kept separate from main 15-run table.
        scale=[]
        for workload,impl,base,_ in cases:
            sizes=(1_000_000,4_000_000,8_000_000,16_000_000) if workload=='localized_plasticity' else (4_000_000,8_000_000,16_000_000)
            keep=[n for n in ('Wheelchair_1.3.127_v4','Wheelchair_1.3.126_v4','GCC_C_v4','C_ceiling_v4') if n in impl]
            for size in sizes:
                for name in keep: timed(impl[name],size)
                for rep in range(SCALE_REPS):
                    order=keep[rep%len(keep):]+keep[:rep%len(keep)]
                    for name in order:
                        ms,so,se=timed(impl[name],size); scale.append([workload,size,rep,name,ms,so,se])
        with (OUT/'scale_raw.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow(['workload','n','rep','implementation','wall_ms','stdout','stderr']); w.writerows(scale)
        scale_summary=[]
        for workload in sorted({r[0] for r in scale}):
            for size in sorted({r[1] for r in scale if r[0]==workload}):
                for name in sorted({r[3] for r in scale if r[0]==workload and r[1]==size}):
                    xs=[r[4] for r in scale if r[0]==workload and r[1]==size and r[3]==name]; scale_summary.append([workload,size,name,len(xs),statistics.median(xs),statistics.median(abs(x-statistics.median(xs)) for x in xs)])
        with (OUT/'scale_summary.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow(['workload','n','implementation','reps','median_ms','mad_ms']); w.writerows(scale_summary)

        lines=['# AVX-512 structural-support pilot','',f'Pinned logical CPU: `{CPU}`. Main table: 15 interleaved repetitions. Controls fixed to x86-64-v4.','', '| workload | implementation | median ms | MAD ms | time/C | speedup/C |','|---|---|---:|---:|---:|---:|']
        for r in summary: lines.append(f'| {r[0]} | {r[1]} | {r[4]:.6f} | {r[8]:.6f} | {r[9]:.4f} | {r[10]:.4f} |')
        lines+=['','## Scaling medians','','| workload | n | implementation | median ms | MAD ms |','|---|---:|---|---:|---:|']
        for r in scale_summary: lines.append(f'| {r[0]} | {r[1]} | {r[2]} | {r[4]:.6f} | {r[5]:.6f} |')
        (OUT/'RESULTS.md').write_text('\n'.join(lines)+'\n',encoding='utf-8'); print((OUT/'RESULTS.md').read_text(encoding='utf-8'))

if __name__=='__main__': main()
