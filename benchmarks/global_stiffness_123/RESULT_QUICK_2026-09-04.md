# Wheelchair 1.2.3 vs matched expert C: quick global stiffness benchmark

## Workload

Matrix-free variable-coefficient 1D linear finite-element/bar global stiffness action:

```text
(Kx)_i = (k_i + k_{i+1}) x_i - k_i x_{i-1} - k_{i+1} x_{i+1}
checksum = sum_i ((Kx)_i)^2
```

Periodic boundary conditions remove boundary branches. The C control does not materialize CSR/COO and therefore receives no artificial sparse-matrix storage penalty.

## Measurement

- Wheelchair: 1.2.3 release implementation lineage, benchmark branch only adds the workload/harness.
- C: GCC 11.4.0, `-O3 -march=native -mtune=native -flto -ffast-math -pthread`.
- Host class: GitHub-hosted Ubuntu 22.04, GenuineIntel, AVX-512F usable.
- CPU affinity: first q CPUs returned by `sched_getaffinity`, enforced by `taskset`.
- 3 warm-ups, 11 shuffled/interleaved measured runs, whole-process wall time, median.
- Small independent scalar reference: PASS.
- Large Wheelchair/C checksums: bit-identical for every tested case.
- Workflow run: `33870262720`; qualified benchmark job: `101014286251`.

## Results

| N | executors | Wheelchair 1.2.3 median | Expert C median | Expert C advantage |
|---:|---:|---:|---:|---:|
| 10,000,000 | 1 | 6.924475 ms | 5.957394 ms | 16.23% |
| 10,000,000 | 2 | 6.877056 ms | 5.944107 ms | 15.70% |
| 10,000,000 | 4 | 3.874179 ms | 3.458061 ms | 12.03% |
| 100,000,000 | 1 | 63.549827 ms | 51.353963 ms | 23.75% |
| 100,000,000 | 2 | 62.473203 ms | 50.839906 ms | 22.88% |
| 100,000,000 | 4 | 31.714680 ms | 26.000941 ms | 21.98% |

`Expert C advantage = Wheelchair_time / C_time - 1`.

## Interpretation boundary

This is a quick same-host benchmark of one structured matrix-free global stiffness operator. It is not an assembled sparse-matrix benchmark and not a universal language ranking.

Wheelchair 1.2.3 Sparse Causal Expansion currently supplies compile-time global-coupling/separator evidence but does not yet lower an arbitrary stiffness graph into a new native separator-condensation/Schur execution recipe. Therefore this result primarily measures the existing native periodic/operator backend on a stiffness-shaped workload, not the future physical SCE realization.
