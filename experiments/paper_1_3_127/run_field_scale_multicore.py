#!/usr/bin/env python3
import array,csv,json,math,os,platform,re,shutil,statistics,struct,subprocess,sys,tempfile,time,zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'experiments'/'paper_1_3_127'/'field_scale_multicore_20261005'
SIZES=(128,192,256)
REPS=15
AFF=sorted(os.sched_getaffinity(0)) if hasattr(os,'sched_getaffinity') else [0]
SETS=[('1cpu',AFF[:1])]
if len(AFF)>=4: SETS.append(('4cpu',AFF[:4]))


def sh(cmd,cwd=None,env=None,check=True):
    cp=subprocess.run(cmd,cwd=cwd,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if check and cp.returncode: raise RuntimeError(f"failed {cmd}\n{cp.stdout}\n{cp.stderr}")
    return cp


def write_field(path,n):
    total=n*n*n;h=bytearray(256);h[:8]=b'WHFLD217'
    struct.pack_into('<I',h,8,2);struct.pack_into('<I',h,12,1);struct.pack_into('<Q',h,16,3);struct.pack_into('<Q',h,24,256);struct.pack_into('<Q',h,32,total)
    for i,x in enumerate((n,n,n)):struct.pack_into('<Q',h,64+8*i,x)
    for i,x in enumerate((n*n*4,n*4,4)):struct.pack_into('<Q',h,88+8*i,x)
    vals=array.array('f',(((i*37+11)&4095)/4096.0 for i in range(4096)))
    if sys.byteorder!='little':vals.byteswap()
    b=vals.tobytes();q,r=divmod(total,4096)
    with path.open('wb') as f:
        f.write(h)
        for _ in range(q):f.write(b)
        if r:f.write(b[:4*r])


def unpack(w):
    d=w/'pkg';d.mkdir()
    with zipfile.ZipFile(ROOT/'dist'/'Wheelchair-1.3.127.zip') as z:z.extractall(d)
    r=d/'Wheelchair-1.3.127'
    if not r.is_dir():r=[x for x in d.iterdir() if x.is_dir()][0]
    for p in (r/'bin').iterdir():
        if p.is_file():p.chmod(p.stat().st_mode|0o111)
    return r


def parse(text):
    m=re.search(r'checksum_f32_bits=0x([0-9a-fA-F]{8})',text)
    if not m:return None
    bits=int(m.group(1),16);return struct.unpack('<f',bits.to_bytes(4,'little'))[0]


def timed(cmd,cpus,env):
    cs=','.join(map(str,cpus));t=time.perf_counter_ns();cp=subprocess.run(['taskset','-c',cs]+cmd,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE);ms=(time.perf_counter_ns()-t)/1e6
    if cp.returncode:raise RuntimeError(f"run failed {cmd}\n{cp.stdout}\n{cp.stderr}")
    return ms,cp.stdout.strip()


def main():
    if OUT.exists():shutil.rmtree(OUT)
    OUT.mkdir(parents=True);(OUT/'sources').mkdir()
    rows=[];comp=[]
    with tempfile.TemporaryDirectory(prefix='w-field-scale-') as td:
        w=Path(td);wr=unpack(w);src=wr/'devtrash'/'benchmarks'/'real_sparse_1326';bins=w/'bins';bins.mkdir()
        fields={}
        for n in SIZES:
            p=w/f'field_{n}.whfld';write_field(p,n);fields[n]=p
        for stem,label in [('miniamr27','miniAMR_27point'),('minife_heat21','miniFE_heat21')]:
            cfg=json.loads((src/f'{stem}.json').read_text());cfg['contracts']['floating_point']='strict';cfgp=w/f'{stem}_strict.json';cfgp.write_text(json.dumps(cfg,separators=(',',':')))
            shutil.copy2(cfgp,OUT/'sources'/f'{stem}_strict.json');shutil.copy2(src/f'{stem}.c',OUT/'sources'/f'{stem}.c');shutil.copy2(src/f'{stem}.f90',OUT/'sources'/f'{stem}.f90')
            d=bins/stem;d.mkdir();wh=d/'wh';cc=d/'c';ff=d/'f'
            commands=[
              ('Wheelchair_1.3.127_strict_native256',['./bin/fieldc-native256',str(cfgp),'-o',str(wh)],wr),
              ('GCC_C_strict_v3',['gcc','-O3','-march=x86-64-v3','-mtune=generic','-fopenmp','-fno-fast-math','-ffp-contract=off',str(src/f'{stem}.c'),'-lm','-o',str(cc)],None),
              ('GFortran_strict_v3',['gfortran','-O3','-march=x86-64-v3','-mtune=generic','-fopenmp','-fno-fast-math','-ffp-contract=off','-fprotect-parens','-ffree-line-length-none',str(src/f'{stem}.f90'),'-o',str(ff)],None)]
            for name,cmd,cwd in commands:
                t=time.perf_counter_ns();cp=sh(cmd,cwd=cwd,check=False);dt=(time.perf_counter_ns()-t)/1e6;comp.append([label,name,dt,cp.returncode,cp.stderr.strip()]);
                if cp.returncode:raise RuntimeError(f'compile {name}: {cp.stderr}')
            impls={'Wheelchair_1.3.127_strict_native256':wh,'GCC_C_strict_v3':cc,'GFortran_strict_v3':ff}
            for n in SIZES:
                for setname,cpus in SETS:
                    env=os.environ.copy();env.update({'OMP_NUM_THREADS':str(len(cpus)),'OMP_PROC_BIND':'true','OMP_PLACES':'cores','OMP_WAIT_POLICY':'PASSIVE'})
                    cmds={k:([str(v),str(fields[n])] if k.startswith('Wheelchair') else [str(v),str(fields[n]),str(n)]) for k,v in impls.items()}
                    names=list(cmds)
                    for name in names:timed(cmds[name],cpus,env)
                    for rep in range(REPS):
                        order=names[rep%3:]+names[:rep%3]
                        for oi,name in enumerate(order):
                            ms,out=timed(cmds[name],cpus,env);rows.append([label,n,setname,','.join(map(str,cpus)),rep,oi,name,ms,out,parse(out)])
        with (OUT/'raw.csv').open('w',newline='') as f:
            x=csv.writer(f);x.writerow(['workload','n','cpu_set','cpus','rep','order','implementation','wall_ms','stdout','value_f32']);x.writerows(rows)
        with (OUT/'compile_log.csv').open('w',newline='') as f:
            x=csv.writer(f);x.writerow(['workload','implementation','compile_ms','returncode','stderr']);x.writerows(comp)
        sums=[]
        for label in sorted({r[0] for r in rows}):
            for n in SIZES:
                for setname,_ in SETS:
                    base=statistics.median([r[7] for r in rows if r[0]==label and r[1]==n and r[2]==setname and r[6]=='GCC_C_strict_v3'])
                    for impl in ['Wheelchair_1.3.127_strict_native256','GCC_C_strict_v3','GFortran_strict_v3']:
                        xs=[r[7] for r in rows if r[0]==label and r[1]==n and r[2]==setname and r[6]==impl];med=statistics.median(xs);mad=statistics.median(abs(v-med) for v in xs)
                        sums.append([label,n,setname,impl,med,mad,med/base,base/med])
        with (OUT/'summary.csv').open('w',newline='') as f:
            x=csv.writer(f);x.writerow(['workload','n','cpu_set','implementation','median_ms','mad_ms','time_over_C','speedup_over_C']);x.writerows(sums)
        md=['# Wheelchair 1.3.127 strict Field scaling and CPU-set pilot','',f'Allowed CPUs: `{AFF}`. Sizes: `{SIZES}`. 15 interleaved repetitions per point. Strict Wheelchair/C/Fortran, x86-64-v3/native256.','', '| workload | n | CPUs | implementation | median ms | MAD ms | speedup/C |','|---|---:|---|---|---:|---:|---:|']
        for r in sums:md.append(f'| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]:.6f} | {r[5]:.6f} | {r[7]:.4f} |')
        md+=['','No speedup is aggregated across sizes or CPU sets. The 4cpu rows are emitted only if the hosted runner exposes at least four CPUs in its affinity set.','']
        (OUT/'RESULTS.md').write_text('\n'.join(md))
        (OUT/'environment.txt').write_text(f'repo={sh(["git","rev-parse","HEAD"]).stdout.strip()}\nallowed_cpus={AFF}\nplatform={platform.platform()}\n'+sh(['lscpu']).stdout)

if __name__=='__main__':main()
