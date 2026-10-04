#!/usr/bin/env python3
import array,csv,json,math,os,platform,re,shutil,statistics,struct,subprocess,sys,tempfile,time,zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'experiments'/'paper_1_3_127'/'field_strict_reference_20261005'
N=256
REPS=15
CPU=min(os.sched_getaffinity(0)) if hasattr(os,'sched_getaffinity') else 0


def sh(cmd,cwd=None,env=None,check=True):
    cp=subprocess.run(cmd,cwd=cwd,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if check and cp.returncode!=0: raise RuntimeError(f"failed {cmd}\n{cp.stdout}\n{cp.stderr}")
    return cp


def write_field(path,n):
    total=n*n*n; h=bytearray(256); h[:8]=b'WHFLD217'
    struct.pack_into('<I',h,8,2); struct.pack_into('<I',h,12,1); struct.pack_into('<Q',h,16,3)
    struct.pack_into('<Q',h,24,256); struct.pack_into('<Q',h,32,total); struct.pack_into('<Q',h,40,0)
    for i,x in enumerate((n,n,n)): struct.pack_into('<Q',h,64+8*i,x)
    for i,x in enumerate((n*n*4,n*4,4)): struct.pack_into('<Q',h,88+8*i,x)
    vals=array.array('f',(((i*37+11)&4095)/4096.0 for i in range(4096)))
    if sys.byteorder!='little': vals.byteswap()
    block=vals.tobytes(); q,r=divmod(total,4096)
    with path.open('wb') as f:
        f.write(h)
        for _ in range(q): f.write(block)
        if r: f.write(block[:4*r])


def unpack(work):
    d=work/'w'; d.mkdir();
    with zipfile.ZipFile(ROOT/'dist'/'Wheelchair-1.3.127.zip') as z:z.extractall(d)
    r=d/'Wheelchair-1.3.127'
    if not r.is_dir(): r=[p for p in d.iterdir() if p.is_dir()][0]
    for p in (r/'bin').iterdir():
        if p.is_file(): p.chmod(p.stat().st_mode|0o111)
    return r


def parse_f32(text):
    m=re.search(r'checksum_f32_bits=0x([0-9A-Fa-f]{8})',text)
    if not m:return None
    bits=int(m.group(1),16); return struct.unpack('<f',bits.to_bytes(4,'little'))[0]


def run(cmd,env):
    t=time.perf_counter_ns(); cp=subprocess.run(['taskset','-c',str(CPU)]+cmd,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    ms=(time.perf_counter_ns()-t)/1e6
    if cp.returncode: raise RuntimeError(f"run failed {cmd}\n{cp.stdout}\n{cp.stderr}")
    return ms,cp.stdout.strip()


def make_reference(src,dst):
    s=src.read_text()
    s=s.replace('float sum=0.0f;','double sum=0.0;').replace('float sum=0.0f;', 'double sum=0.0;')
    s=s.replace('sum+=s*s;', 'sum+=(double)s*(double)s;')
    s=s.replace('sum += s*s;', 'sum += (double)s*(double)s;')
    # Replace final f32 checksum print block in either compact or expanded source.
    s=re.sub(r'uint32_t b;memcpy\(&b,&sum,4\);printf\("checksum_f32_bits=0x%08x\\n",b\);',
             lambda _: 'printf("reference_f64=%.17g\\n",sum);',s)
    s=re.sub(r'uint32_t bits; memcpy\(&bits,&sum,4\);\s*printf\("checksum_f32_bits=0x%08x\\n",bits\);',
             lambda _: 'printf("reference_f64=%.17g\\n",sum);',s)
    dst.write_text(s)


def main():
    if OUT.exists(): shutil.rmtree(OUT)
    OUT.mkdir(parents=True); (OUT/'sources').mkdir()
    env=os.environ.copy(); env.update({'OMP_NUM_THREADS':'1','OMP_PROC_BIND':'true','OMP_PLACES':'cores','OMP_WAIT_POLICY':'PASSIVE'})
    with tempfile.TemporaryDirectory(prefix='w-paper-strict-') as td:
        w=Path(td); wr=unpack(w); src=wr/'devtrash'/'benchmarks'/'real_sparse_1326'; bins=w/'bins';bins.mkdir()
        fld=w/'paper_field_256.whfld'; write_field(fld,N)
        field_sha=sh(['sha256sum',str(fld)]).stdout.split()[0]
        (OUT/'field_input_sha256.txt').write_text(f'{field_sha}  paper_field_256.whfld\n')
        rows=[]; refs=[]; compile_rows=[]
        cases=[]
        for stem,label in [('miniamr27','miniAMR_27point'),('minife_heat21','miniFE_heat21')]:
            cfg=json.loads((src/f'{stem}.json').read_text()); cfg['contracts']['floating_point']='strict'
            cfgp=w/f'{stem}_strict.json'; cfgp.write_text(json.dumps(cfg,separators=(',',':')))
            shutil.copy2(cfgp,OUT/'sources'/f'{stem}_strict.json')
            shutil.copy2(src/f'{stem}.c',OUT/'sources'/f'{stem}.c')
            shutil.copy2(src/f'{stem}.f90',OUT/'sources'/f'{stem}.f90')
            refsrc=w/f'{stem}_reference.c'; make_reference(src/f'{stem}.c',refsrc); shutil.copy2(refsrc,OUT/'sources'/refsrc.name)
            d=bins/stem; d.mkdir(); wh=d/'wh'; cc=d/'c'; ff=d/'f'; rr=d/'ref'
            cmds=[
              (f'{label}/Wheelchair_strict',['./bin/fieldc-native256',str(cfgp),'-o',str(wh)],wr),
              (f'{label}/C_strict',['gcc','-O3','-march=x86-64-v3','-mtune=generic','-fopenmp','-fno-fast-math','-ffp-contract=off',str(src/f'{stem}.c'),'-lm','-o',str(cc)],None),
              (f'{label}/Fortran_strict',['gfortran','-O3','-march=x86-64-v3','-mtune=generic','-fopenmp','-fno-fast-math','-ffp-contract=off','-fprotect-parens','-ffree-line-length-none',str(src/f'{stem}.f90'),'-o',str(ff)],None),
              (f'{label}/Reference_f64',['gcc','-O2','-march=x86-64-v3','-fno-fast-math','-ffp-contract=off',str(refsrc),'-lm','-o',str(rr)],None),
            ]
            for name,cmd,cwd in cmds:
                t=time.perf_counter_ns(); cp=sh(cmd,cwd=cwd,check=False); dt=(time.perf_counter_ns()-t)/1e6
                compile_rows.append([name,dt,cp.returncode,cp.stdout.strip(),cp.stderr.strip(),' '.join(cmd)])
                if cp.returncode: raise RuntimeError(f'compile failed {name}\n{cp.stdout}\n{cp.stderr}')
            refout=sh([str(rr),str(fld),str(N)],env=env).stdout.strip(); m=re.search(r'reference_f64=([^\s]+)',refout)
            if not m: raise RuntimeError('reference output missing')
            ref=float(m.group(1)); refs.append([label,ref,refout])
            cases.append((label,{'Wheelchair_1.3.127_strict_native256':[str(wh),str(fld)],'GCC_C_strict_v3':[str(cc),str(fld),str(N)],'GFortran_strict_v3':[str(ff),str(fld),str(N)]},ref))
        with (OUT/'compile_log.csv').open('w',newline='') as f:
            cw=csv.writer(f);cw.writerow(['case','compile_ms','returncode','stdout','stderr','command']);cw.writerows(compile_rows)
        with (OUT/'reference.csv').open('w',newline='') as f:
            cw=csv.writer(f);cw.writerow(['workload','reference_f64','stdout']);cw.writerows(refs)
        for label,impls,ref in cases:
            names=list(impls)
            for n in names: run(impls[n],env)
            for rep in range(REPS):
                order=names[rep%len(names):]+names[:rep%len(names)]
                for oi,n in enumerate(order):
                    ms,out=run(impls[n],env); val=parse_f32(out)
                    rows.append([label,rep,oi,n,ms,out,val,abs(val-ref)/abs(ref) if val is not None and ref else ''])
        with (OUT/'raw.csv').open('w',newline='') as f:
            cw=csv.writer(f);cw.writerow(['workload','rep','order_index','implementation','wall_ms','stdout','value_f32','relative_error_vs_reference']);cw.writerows(rows)
        sums=[]
        for label,impls,ref in cases:
            base=statistics.median([r[4] for r in rows if r[0]==label and r[3]=='GCC_C_strict_v3'])
            for n in impls:
                rs=[r for r in rows if r[0]==label and r[3]==n]; xs=[r[4] for r in rs]; med=statistics.median(xs);mad=statistics.median(abs(x-med) for x in xs); vals=[r[6] for r in rs if r[6] is not None];v=statistics.median(vals)
                sums.append([label,n,len(xs),med,mad,med/base,base/med,v,ref,abs(v-ref)/abs(ref)])
        with (OUT/'summary.csv').open('w',newline='') as f:
            cw=csv.writer(f);cw.writerow(['workload','implementation','reps','median_ms','mad_ms','time_over_C','speedup_over_C','value_f32','reference_f64','relative_error_vs_reference']);cw.writerows(sums)
        md=['# Wheelchair 1.3.127 strict Field + numerical reference','',f'Pinned CPU `{CPU}`, {REPS} interleaved repetitions. Wheelchair JSON contract is changed only from `tolerant` to `strict`; C/Fortran use strict floating-point flags. The same deterministic WHFLD217 bytes are shared by all implementations.','', '| workload | implementation | median ms | MAD ms | time/C | speedup/C | rel. error vs f64 reference |','|---|---|---:|---:|---:|---:|---:|']
        for r in sums: md.append(f'| {r[0]} | {r[1]} | {r[3]:.6f} | {r[4]:.6f} | {r[5]:.4f} | {r[6]:.4f} | {r[9]:.3e} |')
        md += ['','The f64 oracle preserves each kernel\'s local `float` arithmetic and changes only the final accumulation to `double`; it is a numerical diagnostic, not a timed competitor.','']
        (OUT/'RESULTS.md').write_text('\n'.join(md))
        (OUT/'environment.txt').write_text(f'repo={sh(["git","rev-parse","HEAD"]).stdout.strip()}\nCPU={CPU}\nplatform={platform.platform()}\n'+sh(['lscpu']).stdout+'\n'+sh(['gcc','--version']).stdout+'\n'+sh(['gfortran','--version']).stdout)

if __name__=='__main__': main()
