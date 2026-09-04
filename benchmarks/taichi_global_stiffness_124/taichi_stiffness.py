import argparse
import json
import math
import statistics
import time

import taichi as ti

parser = argparse.ArgumentParser()
parser.add_argument("--threads", type=int, required=True, choices=(1, 2, 4))
parser.add_argument("--runs", type=int, default=11)
parser.add_argument("--warm", type=int, default=3)
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
def xval(i):
    # Same power-of-two residue algebra as the matched expert-C control.
    return -0.5 + ti.cast((i * 29 + 7) & 1023, ti.f64) * (1.0 / 1024.0)

@ti.func
def kval(i):
    return 1.0 + ti.cast((i * 17 + 3) & 255, ti.f64) * (1.0 / 1024.0)

@ti.kernel
def global_stiffness(n: ti.i64):
    checksum[None] = 0.0
    for ii in range(n):
        i = ti.cast(ii, ti.i64)
        im1 = ti.select(i == 0, n - 1, i - 1)
        ip1 = ti.select(i + 1 == n, 0, i + 1)
        ki = kval(i)
        kip = kval(ip1)
        yi = (ki + kip) * xval(i) - ki * xval(im1) - kip * xval(ip1)
        checksum[None] += yi * yi

# Compile before any reported steady-state timing.
global_stiffness(4)
ti.sync()

records = []
for n in (10_000_000, 100_000_000):
    for _ in range(args.warm):
        global_stiffness(n)
        ti.sync()
    samples = []
    vals = []
    for _ in range(args.runs):
        t0 = time.perf_counter_ns()
        global_stiffness(n)
        ti.sync()
        dt_ms = (time.perf_counter_ns() - t0) / 1e6
        samples.append(dt_ms)
        vals.append(float(checksum[None]))
    v0 = vals[0]
    drift = max(abs(v - v0) for v in vals) / max(abs(v0), 1.0)
    rec = {
        "n": n,
        "threads": args.threads,
        "median_ms": statistics.median(samples),
        "min_ms": min(samples),
        "max_ms": max(samples),
        "checksum": v0,
        "drift": drift,
    }
    records.append(rec)
    print(
        f"TAICHI N={n} Q={args.threads} MEDIAN_MS={rec['median_ms']:.6f} "
        f"MIN_MS={rec['min_ms']:.6f} MAX_MS={rec['max_ms']:.6f} "
        f"CHECKSUM={rec['checksum']:.17g} DRIFT={drift:.3e}"
    )

print("TAICHI_JSON=" + json.dumps(records, separators=(",", ":")))
