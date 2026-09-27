# Global Stiffness Degradation-Resistance Benchmark

This benchmark compares four CPU implementations of the same matrix-free global stiffness action:

- Wheelchair 1.2.4, WHEX surface;
- matched expert C, forced toward a 512-bit native vector preference;
- Java 25 HotSpot, standard Java without Vector API, Unsafe, JNI, Panama, or native libraries;
- Taichi 1.7.4 CPU backend.

The purpose is not to manufacture a best-case throughput benchmark. The operator contains neighbor coupling, periodic boundaries, chunked reduction, and global coordination pressure. These properties make it a useful hostile or non-ideal workload for studying how much performance an execution model retains when the problem is less friendly to embarrassingly parallel execution.

This is therefore a **degradation-resistance benchmark**, not a claim that global stiffness action is intrinsically serial. Its pointwise stencil is highly parallelizable; the difficult part is coordination, reduction, boundary handling, and preserving efficient native realization around those constraints.

## Mathematical problem

For periodic indexing,

```text
(Kx)[i] = (k[i] + k[i+1]) * x[i]
          - k[i]   * x[i-1]
          - k[i+1] * x[i+1]
```

with

```text
x[i]      = -0.5 + ((29*i + 7) mod 1024) / 1024
edge_k[i] =  1.0 + ((17*i + 3) mod 256)  / 1024
```

and the reported scalar is

```text
sum_i ((Kx)[i]^2)
```

The benchmark uses `N = 10,000,000` and `N = 100,000,000`, each with `1`, `2`, and `4` executors or CPU threads.

## Sources

- `stiffness.whex` — Wheelchair program.
- `Global_Stiffness_expert_C_matched.c` — matched expert-C control.
- `GlobalStiffnessJava.java` — Java 25 HotSpot control.
- `taichi_stiffness.py` — Taichi 1.7.4 CPU control.
- `results_intel_2026-09-04.csv` — measured two-host result table.

The four source files are preserved from the measured benchmark rather than rewritten after seeing the result.

Original benchmark experiment commit:

```text
23ac0243bd2e5e39ccc901753729c5986db825de
```

Original source blob identities from that experiment:

```text
stiffness.whex                         4abad61304dd008b887a9bfca19801d16a7ba943
Global_Stiffness_expert_C_matched.c   d228e2b7bd4889a350e1134f5f7dbc848a165458
GlobalStiffnessJava.java              eff5989e694d16c8ed18cde7ad6d2d24ae8a08f0
taichi_stiffness.py                   2fa2cd98aa57b2e9afe7311b96bcfc0c30bce7b2
```

## Toolchains and execution policy

### Wheelchair

Wheelchair 1.2.4 uses its native AVX-512F realizer. The benchmark was compiled at executor counts 1, 2, and 4.

### Expert C

The matched C control was built with GCC using:

```text
-O3 -march=native -mtune=native -flto -ffast-math
-mprefer-vector-width=512 -pthread
```

It uses the same residue algebra, chunk size `65536`, four local accumulation carriers, pthread executor partition, and deterministic adjacent binary-tree reduction.

### Java

The Java control used Temurin OpenJDK 25.0.4.1 HotSpot with:

```text
-XX:+TieredCompilation
-XX:TieredStopAtLevel=4
-XX:+UseFMA
```

It uses ordinary `double`, a fixed thread pool, the same chunk size, four local accumulation carriers, and the same tree-reduction shape. No Vector API, Unsafe, JNI, Panama, or native library is used.

Eight warm-up computations were executed before the eleven measured runs.

### Taichi

The Taichi control used Taichi 1.7.4, LLVM 15.0.4, Python 3.11.16, with:

```text
arch=ti.cpu
default_fp=ti.f64
default_ip=ti.i64
cpu_max_num_threads=1/2/4
advanced_optimization=True
fast_math=True
offline_cache=False
```

The kernel is compiled before reported timing. Eight warm-up computations were executed before the eleven measured runs. Reported time covers the steady-state kernel invocation plus `ti.sync()`.

## Hosts

The four-way benchmark was reproduced on two AVX-512F-qualified Intel hosted runners:

```text
Intel Xeon Platinum 8573C
CPU family 6, model 207
2 logical threads per core
2 reported cores per socket
AVX-512F usable

Intel Xeon Platinum 8370C @ 2.80 GHz
CPU family 6, model 106
2 logical threads per core
2 reported cores per socket
AVX-512F usable
```

All contestants at a given executor/thread count were pinned to the same first `q` allowed logical CPUs. Because these were hosted runners, logical-CPU numbering is not treated as proof of distinct physical-core placement.

## Results: Xeon Platinum 8573C

| N | q | Wheelchair ms | Expert C512 ms | Java 25 ms | Taichi 1.7.4 ms |
|---:|---:|---:|---:|---:|---:|
| 10M | 1 | 6.517 | 6.627 | 33.845 | 40.287 |
| 10M | 2 | 6.183 | 6.406 | 31.124 | 39.097 |
| 10M | 4 | 3.676 | 3.818 | 16.043 | 19.570 |
| 100M | 1 | 61.229 | 57.809 | 329.240 | 402.034 |
| 100M | 2 | 57.198 | 56.243 | 323.243 | 387.654 |
| 100M | 4 | 29.787 | 30.296 | 158.179 | 196.710 |

Geometric-mean time relative to expert C across all six cases:

```text
Wheelchair / C = 0.995x
Java / C       = 5.111x
Taichi / C     = 6.243x
```

Equivalent observed C-normalized retained throughput:

```text
Wheelchair = 100.5%
Java       =  19.6%
Taichi     =  16.0%
```

## Results: Xeon Platinum 8370C

| N | q | Wheelchair ms | Expert C512 ms | Java 25 ms | Taichi 1.7.4 ms |
|---:|---:|---:|---:|---:|---:|
| 10M | 1 | 7.579 | 7.191 | 41.304 | 47.883 |
| 10M | 2 | 7.510 | 7.135 | 39.519 | 45.449 |
| 10M | 4 | 5.703 | 4.321 | 19.952 | 22.820 |
| 100M | 1 | 65.416 | 60.342 | 413.049 | 476.982 |
| 100M | 2 | 65.035 | 59.499 | 394.176 | 452.892 |
| 100M | 4 | 33.342 | 30.670 | 198.110 | 227.330 |

Geometric-mean time relative to expert C across all six cases:

```text
Wheelchair / C = 1.112x
Java / C       = 5.920x
Taichi / C     = 6.812x
```

Equivalent observed C-normalized retained throughput:

```text
Wheelchair = 90.0%
Java       = 16.9%
Taichi     = 14.7%
```

## Java versus Taichi

Java won all twelve measured Java-versus-Taichi cases across the two Intel hosts.

Median Taichi slowdown relative to Java was approximately:

```text
Xeon 8573C: 1.22x
Xeon 8370C: 1.15x
```

The Java implementation is intentionally ordinary HotSpot Java rather than an expert Vector-API implementation. This makes the result useful for characterizing the Taichi CPU path on this workload, but it must not be generalized into a claim about all Taichi GPU workloads or all possible Java implementations.

## Numerical behavior

Wheelchair, expert C, and Java produced identical binary64 checksum bits in the measured cases:

```text
N = 10,000,000  -> 0x41261194696d340b
N = 100,000,000 -> 0x415b95fbcb03acae
```

Taichi remained numerically close but used a different reduction result under the measured `fast_math=True` configuration. Observed relative differences included approximately:

```text
10M, 1 thread  : 1.709e-10
100M, 1 thread : 1.338e-09
```

The latter exceeded the experiment's `1e-9` comparison gate, so the original workflow was intentionally marked failed at the numerical comparison stage even though all performance measurements had completed.

## What “degradation resistance” means here

For this benchmark, define the observed hostile-workload time factor relative to the matched expert-C reference as:

```text
D = T_candidate / T_expert_C
```

Lower is better. `D = 1` matches the expert-C reference on this workload.

A companion retained-throughput quantity is:

```text
R = T_expert_C / T_candidate = 1 / D
```

Higher is better. `R = 1` means expert-C-equivalent throughput.

On the two Intel hosts, Wheelchair remained near the expert-C reference while Java and Taichi were several times slower. In this narrow and explicitly measured sense, Wheelchair showed substantially higher **degradation resistance** on this coordination-heavy global-stiffness workload.

The structural interpretation is that Wheelchair still retained several compile-time/native advantages even when the problem was not an ideal independent map:

- periodic interior structure remained eligible for proof and erasure;
- affine index relations remained recoverable;
- product-subtract expressions could still contract into fused native recipes;
- terminal reduction could remain vector-resident;
- no scalar fallback was introduced merely because the workload became less friendly;
- no generic interpreter, JIT task queue, or hidden scalar execution tier replaced the proven native path.

This matters because performance collapse often occurs when a system's preferred fast path stops applying and execution falls through to a qualitatively slower mechanism. Wheelchair's current design attempts to preserve native structural recipes or reject unsupported cases rather than silently cross such a performance cliff.

## Important limitation

This benchmark is **one hostile-workload point**, not a complete language-wide degradation curve.

A rigorous degradation-resistance study should run the same contestants through a controlled sequence such as:

```text
independent map
-> affine neighbor access
-> periodic boundaries
-> terminal reduction
-> sparse coupling
-> communication-heavy sparse coupling
```

and then measure how each implementation loses throughput relative to its own best-case baseline and to the same expert-C reference.

Therefore the defensible conclusion from this directory is:

> On this measured matrix-free global-stiffness CPU workload, Wheelchair 1.2.4 retained performance close to matched expert C on two Intel AVX-512 hosts, while standard Java 25 HotSpot and Taichi 1.7.4 CPU were several times slower. This is evidence of strong degradation resistance for this workload, not proof of universal degradation resistance across all programs or architectures.

## Timing-boundary caveat

The quick four-way experiment used two timing boundaries:

- Wheelchair and expert C were measured externally around process execution;
- Java and Taichi reported steady-state internal compute/kernel time after warm-up.

This makes the native numbers conservative because process startup is included for Wheelchair and C, while JVM/Python startup and JIT compilation are excluded for Java/Taichi. It does not invalidate the Java-versus-Taichi comparison or the Wheelchair-versus-C comparison, but exact cross-group ratios should be treated as conservative observational evidence rather than a final microbenchmark authority.

For a publication-grade cross-language degradation curve, all contestants should be measured inside one persistent-process harness with identical timer boundaries.
