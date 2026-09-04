import argparse
import json
import statistics
import time
import taichi as ti

parser = argparse.ArgumentParser()
parser.add_argument('--threads', type=int, required=True, choices=(1, 2, 4))
parser.add_argument('--mode', required=True, choices=('decoupled', 'coupled'))
parser.add_argument('--runs', type=int, default=11)
parser.add_argument('--warm', type=int, default=8)
args = parser.parse_args()

ti.init(
    arch=ti.cpu,
    default_fp=ti.f64,
    default_ip=ti.i64,
    cpu_max_num_threads=args.threads,
    advanced_optimization=True,
    fast_math=True,
    offline_cache=False,
)

checksum = ti.field(dtype=ti.f64, shape=())

@ti.func
def fluid(i):
    return -0.375 + ti.cast((i * 31 + 11) & 2047, ti.f64) * (1.0 / 2048.0)

@ti.func
def solid(i):
    return 0.25 + ti.cast((i * 23 + 5) & 1023, ti.f64) * (1.0 / 1536.0)

@ti.func
def rho(i):
    return 1.0 + ti.cast((i * 13 + 9) & 255, ti.f64) * (1.0 / 2048.0)

@ti.func
def mu(i):
    return 0.75 + ti.cast((i * 7 + 3) & 127, ti.f64) * (1.0 / 1024.0)

@ti.func
def elastic(i):
    return 1.25 + ti.cast((i * 19 + 1) & 255, ti.f64) * (1.0 / 1024.0)

@ti.func
def gamma_c(i):
    return 0.125 + ti.cast((i * 5 + 7) & 63, ti.f64) * (1.0 / 4096.0)

@ti.func
def base_terms(i, n):
    im1 = ti.select(i == 0, n - 1, i - 1)
    ip1 = ti.select(i + 1 == n, 0, i + 1)
    fi, fm, fp = fluid(i), fluid(im1), fluid(ip1)
    ui, um, up = solid(i), solid(im1), solid(ip1)
    F = rho(i) * (2.0 * fi - fm - fp) + mu(i) * (fp - fm)
    S = elastic(i) * (2.0 * ui - um - up) + 0.0625 * (up - um)
    return F, S, fi, ui

@ti.kernel
def fsi_decoupled(n: ti.i64):
    checksum[None] = 0.0
    for ii in range(n):
        i = ti.cast(ii, ti.i64)
        F, S, _, _ = base_terms(i, n)
        checksum[None] += F * F + S * S

@ti.kernel
def fsi_coupled(n: ti.i64):
    checksum[None] = 0.0
    for ii in range(n):
        i = ti.cast(ii, ti.i64)
        F, S, fi, ui = base_terms(i, n)
        g = gamma_c(i)
        d = fi - ui
        F += g * d
        S -= g * d
        checksum[None] += F * F + S * S

kernel = fsi_coupled if args.mode == 'coupled' else fsi_decoupled
kernel(4)
ti.sync()

records = []
for n in (10_000_000, 100_000_000):
    for _ in range(args.warm):
        kernel(n)
        ti.sync()
    samples = []
    vals = []
    for _ in range(args.runs):
        t0 = time.perf_counter_ns()
        kernel(n)
        ti.sync()
        samples.append((time.perf_counter_ns() - t0) / 1e6)
        vals.append(float(checksum[None]))
    v0 = vals[0]
    drift = max(abs(v - v0) for v in vals) / max(abs(v0), 1.0)
    rec = {
        'mode': args.mode,
        'n': n,
        'threads': args.threads,
        'median_ms': statistics.median(samples),
        'min_ms': min(samples),
        'max_ms': max(samples),
        'checksum': v0,
        'drift': drift,
    }
    records.append(rec)
    print(
        f"TAICHI MODE={args.mode} N={n} Q={args.threads} MEDIAN_MS={rec['median_ms']:.6f} "
        f"MIN_MS={rec['min_ms']:.6f} MAX_MS={rec['max_ms']:.6f} "
        f"CHECKSUM={v0:.17g} DRIFT={drift:.3e}"
    )

print('TAICHI_JSON=' + json.dumps(records, separators=(',', ':')))
