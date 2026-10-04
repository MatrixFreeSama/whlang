#!/usr/bin/env python3
import csv,json,os,shutil,statistics,subprocess,tempfile,time
from pathlib import Path
from run_field_scale_multicore import ROOT,sh,write_field,unpack,timed

OUT=ROOT/'experiments'/'paper_1_3_127'/'field_address_ablation_20261005'
SIZES=(128,192,256);REPS=7;CPU=min(os.sched_getaffinity(0))

CENTRAL={"format":"wheelchair.field/1","contracts":{"floating_point":"strict"},"fields":[{"mode":"input","type":"f32","rank":3}],"accesses":[{"field":0,"delta":[0,0,0]}],"ops":[{"op":"load","access":0,"dst":0},{"op":"mul","a":0,"b":0,"dst":1},{"op":"reduce","src":1}]}
SHIFT={"format":"wheelchair.field/1","contracts":{"floating_point":"strict"},"fields":[{"mode":"input","type":"f32","rank":3}],"accesses":[{"field":0,"delta":[0,0,0]},{"field":0,"delta":[0,0,1]}],"ops":[{"op":"load","access":0,"dst":0},{"op":"load","access":1,"dst":1},{"op":"add","a":0,"b":1,"dst":0},{"op":"mul","a":0,"b":0,"dst":1},{"op":"reduce","src":1}]}
C_SRC=r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
static inline size_t I(size_t i,size_t j,size_t k,size_t n){return(i*n+j)*n+k;}
int main(int ac,char**av){if(ac!=4)return 2;size_t n=strtoull(av[2],0,10),N=n*n*n;int shifted=atoi(av[3]);int fd=open(av[1],O_RDONLY);float*u=mmap(0,256+4*N,PROT_READ,MAP_PRIVATE,fd,0);u=(float*)((char*)u+256);float sum=0;for(size_t i=0;i<n;i++)for(size_t j=0;j<n;j++)for(size_t k=0;k<n;k++){float x=u[I(i,j,k,n)];if(shifted)x+=u[I(i,j,(k+1==n)?0:k+1,n)];sum+=x*x;}uint32_t b;memcpy(&b,&sum,4);printf("checksum_f32_bits=0x%08x\n",b);}
'''

def main():
    if OUT.exists():shutil.rmtree(OUT)
    OUT.mkdir(parents=True);(OUT/'sources').mkdir();rows=[]
    with tempfile.TemporaryDirectory(prefix='w-address-ablate-') as td:
        w=Path(td);wr=unpack(w);fields={}
        for n in SIZES:
            p=w/f'f{n}.whfld';write_field(p,n);fields[n]=p
        csrc=w/'control.c';csrc.write_text(C_SRC);(OUT/'sources'/'control.c').write_text(C_SRC)
        cexe=w/'c';cp=sh(['gcc','-O3','-march=x86-64-v3','-mtune=generic','-fno-fast-math','-ffp-contract=off',str(csrc),'-o',str(cexe)],check=False)
        if cp.returncode:raise RuntimeError(cp.stderr)
        for name,cfg,flag in [('central',CENTRAL,'0'),('shift_k_plus_1',SHIFT,'1')]:
            jp=w/f'{name}.json';jp.write_text(json.dumps(cfg,separators=(',',':')));shutil.copy2(jp,OUT/'sources'/jp.name)
            wh=w/f'wh_{name}';cp=sh(['./bin/fieldc-native256',str(jp),'-o',str(wh)],cwd=wr,check=False)
            if cp.returncode:raise RuntimeError(cp.stderr)
            env=os.environ.copy();env.update({'OMP_NUM_THREADS':'1','OMP_WAIT_POLICY':'PASSIVE'})
            for n in SIZES:
                cmds={'Wheelchair':[str(wh),str(fields[n])],'GCC_C':[str(cexe),str(fields[n]),str(n),flag]}
                for k in cmds:timed(cmds[k],[CPU],env)
                for rep in range(REPS):
                    order=['Wheelchair','GCC_C'] if rep%2==0 else ['GCC_C','Wheelchair']
                    for oi,k in enumerate(order):
                        ms,out=timed(cmds[k],[CPU],env);rows.append([name,n,k,rep,oi,ms,out])
        with (OUT/'raw.csv').open('w',newline='') as f:
            x=csv.writer(f);x.writerow(['case','n','implementation','rep','order','wall_ms','stdout']);x.writerows(rows)
        sums=[]
        for case in ('central','shift_k_plus_1'):
            for n in SIZES:
                c=statistics.median([r[5] for r in rows if r[0]==case and r[1]==n and r[2]=='GCC_C'])
                for k in ('Wheelchair','GCC_C'):
                    xs=[r[5] for r in rows if r[0]==case and r[1]==n and r[2]==k];m=statistics.median(xs);mad=statistics.median(abs(v-m) for v in xs);sums.append([case,n,k,m,mad,c/m])
        with (OUT/'summary.csv').open('w',newline='') as f:
            x=csv.writer(f);x.writerow(['case','n','implementation','median_ms','mad_ms','speedup_C_over_impl']);x.writerows(sums)
        md=['# Field address-path ablation','',f'Wheelchair 1.3.127 Strict native256 vs strict GCC C, CPU `{CPU}`, {REPS} interleaved reps. `central` needs no periodic coordinate remap; `shift_k_plus_1` adds one periodic neighbor.','', '| case | n | Wheelchair ms | C ms | speedup/C |','|---|---:|---:|---:|---:|']
        for case in ('central','shift_k_plus_1'):
            for n in SIZES:
                a=next(r for r in sums if r[0]==case and r[1]==n and r[2]=='Wheelchair');c=next(r for r in sums if r[0]==case and r[1]==n and r[2]=='GCC_C');md.append(f'| {case} | {n} | {a[3]:.6f} | {c[3]:.6f} | {a[5]:.4f} |')
        (OUT/'RESULTS.md').write_text('\n'.join(md)+'\n')
if __name__=='__main__':main()
