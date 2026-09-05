import argparse, statistics, time
import taichi as ti

ap=argparse.ArgumentParser()
ap.add_argument('--threads',type=int,required=True)
ap.add_argument('--runs',type=int,default=11)
ap.add_argument('--warm',type=int,default=8)
a=ap.parse_args()

ti.init(arch=ti.cpu, default_fp=ti.f64, cpu_max_num_threads=a.threads, offline_cache=False)

@ti.func
def uval(i):
    return 0.25 + ti.cast((17*i + 3) & 1023, ti.f64) * (1.0/1024.0)

@ti.func
def pval(i):
    return -0.125 + ti.cast((29*i + 7) & 1023, ti.f64) * (1.0/1024.0)

@ti.func
def xval(i):
    return -0.375 + ti.cast((31*i + 5) & 1023, ti.f64) * (1.0/1024.0)

@ti.kernel
def heat(n: ti.i32) -> ti.f64:
    s=0.0
    nn=ti.cast(n,ti.i64)
    for ii in range(n):
        i=ti.cast(ii,ti.i64)
        im=ti.select(i==0,nn-1,i-1)
        ip=ti.select(i+1==nn,0,i+1)
        u=uval(i)
        s += u + 0.125*(uval(im)-2.0*u+uval(ip))
    return s

@ti.kernel
def wave(n: ti.i32) -> ti.f64:
    s=0.0
    nn=ti.cast(n,ti.i64)
    for ii in range(n):
        i=ti.cast(ii,ti.i64)
        im=ti.select(i==0,nn-1,i-1)
        ip=ti.select(i+1==nn,0,i+1)
        u=uval(i)
        s += 2.0*u-pval(i)+0.0625*(uval(im)-2.0*u+uval(ip))
    return s

@ti.kernel
def sparse(n: ti.i32) -> ti.f64:
    s=0.0
    nn=ti.cast(n,ti.i64)
    for ii in range(n):
        i=ti.cast(ii,ti.i64)
        x=xval(i)
        j1=(17*i+3)%nn
        j2=(29*i+7)%nn
        j3=(43*i+11)%nn
        s += 1.75*x - 0.125*xval(j1) + 0.0625*xval(j2) - 0.03125*xval(j3) + 0.015625*x*x*x
    return s

for name,fn in [('heat',heat),('wave',wave),('sparse',sparse)]:
    for n in (10_000_000,100_000_000):
        ref=float(fn(n)); ti.sync()
        for _ in range(a.warm):
            float(fn(n)); ti.sync()
        samples=[]; vals=[]
        for _ in range(a.runs):
            t0=time.perf_counter_ns(); v=float(fn(n)); ti.sync(); dt=(time.perf_counter_ns()-t0)/1e6
            samples.append(dt); vals.append(v)
        med=statistics.median(samples)
        drift=max(abs(v-ref) for v in vals)
        print(f'TAICHI WORKLOAD={name} N={n} Q={a.threads} MEDIAN_MS={med:.6f} CHECKSUM={ref:.17g} DRIFT={drift:.3e}')
