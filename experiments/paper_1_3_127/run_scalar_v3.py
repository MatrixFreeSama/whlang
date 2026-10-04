#!/usr/bin/env python3
import csv, json, os, platform, shutil, statistics, subprocess, sys, tempfile, time, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'experiments' / 'paper_1_3_127' / 'scalar_v3_20261005'
REPS = 15
STEPS = 20_000_000
CPU = min(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else 0


def run(cmd, cwd=None, check=True):
    cp = subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and cp.returncode:
        raise RuntimeError(f"rc={cp.returncode} cwd={cwd} cmd={cmd!r}\nstdout={cp.stdout!r}\nstderr={cp.stderr!r}")
    return cp


def timed(cmd):
    t0 = time.perf_counter_ns()
    cp = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ms = (time.perf_counter_ns() - t0) / 1e6
    if cp.returncode:
        raise RuntimeError(f"run rc={cp.returncode} cmd={cmd!r}\nstdout={cp.stdout!r}\nstderr={cp.stderr!r}")
    return ms, cp.stdout.strip(), cp.stderr.strip()


def cc(src, out):
    return ['gcc','-O3','-march=x86-64-v3','-mtune=generic','-fno-fast-math','-ffp-contract=off',str(src),'-lm','-o',str(out)]


def fc(src, out):
    return ['gfortran','-O3','-march=x86-64-v3','-mtune=generic','-fno-fast-math','-ffp-contract=off','-fprotect-parens',str(src),'-o',str(out)]


def main():
    if OUT.exists(): shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT/'sources').mkdir()
    env = [
        'experiment=scalar_v3_negative_controls',
        'wheelchair=1.3.127 topologyc-native256',
        'control_isa=x86-64-v3',
        f'repo_commit={run(["git","rev-parse","HEAD"]).stdout.strip()}',
        f'pinned_cpu={CPU}',
        f'python={sys.version}',
        f'platform={platform.platform()}',
    ]
    for cmd in (['uname','-a'],['lscpu'],['gcc','--version'],['gfortran','--version']):
        cp=run(cmd,check=False); env.append('$ '+' '.join(cmd)+'\n'+cp.stdout+cp.stderr)
    (OUT/'environment.txt').write_text('\n'.join(env)+'\n',encoding='utf-8')

    with tempfile.TemporaryDirectory(prefix='wh-paper-v3-') as td:
        td=Path(td); z=ROOT/'dist'/'Wheelchair-1.3.127.zip'; ext=td/'release'; ext.mkdir()
        with zipfile.ZipFile(z) as q: q.extractall(ext)
        W=ext/'Wheelchair-1.3.127'
        if not W.is_dir(): W=next(p for p in ext.iterdir() if p.is_dir())
        compiler=W/'bin'/'topologyc-native256'; compiler.chmod(compiler.stat().st_mode|0o111)
        srcdir=W/'devtrash'/'benchmarks'/'math_generalization_1344'
        bindir=td/'bin'; bindir.mkdir()
        cases=[]; compile_rows=[]
        for k in ('mass3','chem6','rigid7'):
            for e in ('wh','c','f90'): shutil.copy2(srcdir/f'{k}.{e}',OUT/'sources'/f'{k}.{e}')
            kd=bindir/k; kd.mkdir()
            impl={
                'Wheelchair_1.3.127_native256':kd/'wheelchair',
                'GCC_C_v3':kd/'c',
                'GFortran_v3':kd/'fortran',
            }
            commands={
                'Wheelchair_1.3.127_native256':(['./bin/topologyc-native256',f'devtrash/benchmarks/math_generalization_1344/{k}.wh','-o',str(impl['Wheelchair_1.3.127_native256'])],W),
                'GCC_C_v3':(cc(srcdir/f'{k}.c',impl['GCC_C_v3']),None),
                'GFortran_v3':(fc(srcdir/f'{k}.f90',impl['GFortran_v3']),None),
            }
            for name,(cmd,cwd) in commands.items():
                t0=time.perf_counter_ns(); cp=run(cmd,cwd=cwd,check=False); cms=(time.perf_counter_ns()-t0)/1e6
                compile_rows.append([k,name,cms,cp.returncode,cp.stdout.strip(),cp.stderr.strip(),' '.join(map(str,cmd)),str(cwd or '')])
                if cp.returncode: raise RuntimeError(f'compile failed {k}/{name}: {cp.stderr!r}')
            cases.append((k,impl))

        with (OUT/'compile_log.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow(['workload','implementation','compile_ms','returncode','stdout','stderr','command','cwd']); w.writerows(compile_rows)

        raw=[]
        for k,impl in cases:
            names=list(impl)
            for name in names: timed(['taskset','-c',str(CPU),str(impl[name]),str(STEPS)])
            for rep in range(REPS):
                order=names[rep%len(names):]+names[:rep%len(names)]
                for pos,name in enumerate(order):
                    ms,so,se=timed(['taskset','-c',str(CPU),str(impl[name]),str(STEPS)])
                    raw.append([k,rep,pos,name,STEPS,CPU,ms,so,se])
        with (OUT/'raw.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow(['workload','rep','order_index','implementation','steps','cpu','wall_ms','stdout','stderr']); w.writerows(raw)

        summary=[]
        for k,impl in cases:
            med={}
            for name in impl:
                xs=[r[6] for r in raw if r[0]==k and r[3]==name]; med[name]=statistics.median(xs)
            base=med['GCC_C_v3']
            for name in impl:
                rr=[r for r in raw if r[0]==k and r[3]==name]; xs=[r[6] for r in rr]; m=statistics.median(xs)
                mad=statistics.median(abs(x-m) for x in xs); outs=sorted({r[7] for r in rr})
                summary.append([k,name,len(xs),min(xs),m,statistics.mean(xs),max(xs),statistics.pstdev(xs),mad,m/base,base/m,json.dumps(outs,ensure_ascii=False)])
        with (OUT/'summary.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow(['workload','implementation','reps','min_ms','median_ms','mean_ms','max_ms','stdev_ms','mad_ms','time_over_C','speedup_over_C','unique_stdout']); w.writerows(summary)

        lines=['# Scalar x86-64-v3 negative-control pilot','',f'Pinned logical CPU: `{CPU}`. 15 interleaved repetitions. Whole-process wall time.','',
               '| workload | implementation | median ms | MAD ms | time/C | speedup/C |','|---|---|---:|---:|---:|---:|']
        for r in summary: lines.append(f'| {r[0]} | {r[1]} | {r[4]:.6f} | {r[8]:.6f} | {r[9]:.4f} | {r[10]:.4f} |')
        (OUT/'RESULTS.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
        print((OUT/'RESULTS.md').read_text(encoding='utf-8'))

if __name__=='__main__': main()
