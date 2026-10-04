#!/usr/bin/env python3
import csv,json,os,shutil,statistics,tempfile,time
from pathlib import Path
from run_field_scale_multicore import ROOT,sh,write_field,unpack,timed

OUT=ROOT/'experiments'/'paper_1_3_127'/'field_shape_cliff_20261005'
SIZES=(128,160,176,184,192,200,208,224,240,248,256)
REPS=7
CPU=min(os.sched_getaffinity(0))


def main():
    if OUT.exists():shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    rows=[]
    with tempfile.TemporaryDirectory(prefix='w-shape-cliff-') as td:
        w=Path(td);wr=unpack(w);src=wr/'devtrash'/'benchmarks'/'real_sparse_1326';bd=w/'bin';bd.mkdir()
        env=os.environ.copy();env.update({'OMP_NUM_THREADS':'1','OMP_PROC_BIND':'true','OMP_PLACES':'cores','OMP_WAIT_POLICY':'PASSIVE'})
        fields={}
        for n in SIZES:
            f=w/f'f{n}.whfld';write_field(f,n);fields[n]=f
        for stem,label in [('miniamr27','miniAMR_27point'),('minife_heat21','miniFE_heat21')]:
            cfg=json.loads((src/f'{stem}.json').read_text());cfg['contracts']['floating_point']='strict';cp=w/f'{stem}.json';cp.write_text(json.dumps(cfg,separators=(',',':')))
            d=bd/stem;d.mkdir();wh=d/'wh';cc=d/'c'
            a=sh(['./bin/fieldc-native256',str(cp),'-o',str(wh)],cwd=wr,check=False)
            if a.returncode:raise RuntimeError(a.stderr)
            a=sh(['gcc','-O3','-march=x86-64-v3','-mtune=generic','-fopenmp','-fno-fast-math','-ffp-contract=off',str(src/f'{stem}.c'),'-lm','-o',str(cc)],check=False)
            if a.returncode:raise RuntimeError(a.stderr)
            for n in SIZES:
                cmds={'Wheelchair':[str(wh),str(fields[n])],'GCC_C':[str(cc),str(fields[n]),str(n)]}
                for k in cmds:timed(cmds[k],[CPU],env)
                for rep in range(REPS):
                    order=['Wheelchair','GCC_C'] if rep%2==0 else ['GCC_C','Wheelchair']
                    for oi,k in enumerate(order):
                        ms,out=timed(cmds[k],[CPU],env);rows.append([label,n,n**3,4*n**3/1048576,rep,oi,k,ms,out])
        with (OUT/'raw.csv').open('w',newline='') as f:
            c=csv.writer(f);c.writerow(['workload','n','elements','input_MiB','rep','order','implementation','wall_ms','stdout']);c.writerows(rows)
        sums=[]
        for label in sorted(set(r[0] for r in rows)):
            for n in SIZES:
                base=statistics.median([r[7] for r in rows if r[0]==label and r[1]==n and r[6]=='GCC_C'])
                for k in ('Wheelchair','GCC_C'):
                    xs=[r[7] for r in rows if r[0]==label and r[1]==n and r[6]==k];m=statistics.median(xs);mad=statistics.median(abs(x-m) for x in xs);sums.append([label,n,4*n**3/1048576,k,m,mad,base/m])
        with (OUT/'summary.csv').open('w',newline='') as f:
            c=csv.writer(f);c.writerow(['workload','n','input_MiB','implementation','median_ms','mad_ms','speedup_C_over_impl']);c.writerows(sums)
        md=['# Field shape-cliff diagnostic','',f'Wheelchair 1.3.127 Strict native256 vs GCC C Strict x86-64-v3, one CPU `{CPU}`, {REPS} interleaved reps. This is a diagnostic sweep, not a publication headline table.','', '| workload | n | input MiB | Wheelchair ms | C ms | speedup/C |','|---|---:|---:|---:|---:|---:|']
        for label in sorted(set(r[0] for r in rows)):
            for n in SIZES:
                wrs=next(r for r in sums if r[0]==label and r[1]==n and r[3]=='Wheelchair');cr=next(r for r in sums if r[0]==label and r[1]==n and r[3]=='GCC_C');md.append(f'| {label} | {n} | {wrs[2]:.2f} | {wrs[4]:.6f} | {cr[4]:.6f} | {wrs[6]:.4f} |')
        (OUT/'RESULTS.md').write_text('\n'.join(md)+'\n')

if __name__=='__main__':main()
