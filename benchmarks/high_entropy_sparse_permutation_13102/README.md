# High-Entropy Sparse Permutation Reduction — Wheelchair 1.3.102

## Purpose

This benchmark is a representative witness for a primary Wheelchair target: workloads where the **necessary arithmetic per logical element is small, but a conventional realization can consume much more physical work than the mathematical relation itself suggests**.

It is deliberately not a dense FMA kernel and not a barrier-sabotaged opponent. Each logical index evaluates six unrelated long-distance affine permutations modulo runtime `n`, samples a cheap virtual field, applies dyadic weights, and reduces the result.

```text
for i in [0,n):
    p0 = (  97 i +  17) mod n
    p1 = ( 193 i +  31) mod n
    p2 = ( 389 i +  47) mod n
    p3 = ( 769 i +  71) mod n
    p4 = (1543 i + 101) mod n
    p5 = (3079 i + 131) mod n

    checksum += x[p0] - 1/2 x[p1] + 1/4 x[p2]
              - 1/8 x[p3] + 1/16 x[p4] - 1/32 x[p5]
```

`n` is runtime input. The formal run uses `n = 50,000,000` only to make timing stable; useful arithmetic per element remains deliberately thin. The benchmark is therefore **high-entropy / low-arithmetic-density**, not low total work.

## Controls

- Wheelchair 1.3.102 native AOT output.
- GCC C: `-O3 -march=native -fopenmp`; Strict adds `-fno-fast-math -ffp-contract=off`; Fast adds `-ffast-math`.
- GFortran: the corresponding flags plus `-fwrapv`.
- No hand-written assembly or AVX intrinsics are supplied to the C or Fortran controls.
- Four-core runs are pinned to CPUs 0-3 with `OMP_WAIT_POLICY=PASSIVE`.
- Host visible to the benchmark: AMD EPYC 9V74, five logical CPUs online; the benchmark is restricted to four.
- Seven interleaved measured rounds.
- Process-tree CPU time includes Wheelchair outward execution children.
- All six implementations produce the same checksum bits:

```text
0x416f48e8e5840000
```

## 1.3.102 measured data

`Task-Manager equivalent` expresses process-tree CPU time as a fraction of the **five visible logical CPUs = 100%** convention. Because the benchmark is restricted to four CPUs, its theoretical display ceiling is 80%.

| Contract / implementation | Wall time | Process-tree CPU time | 4-core slot occupancy | Task-Manager equivalent |
|---|---:|---:|---:|---:|
| **Wheelchair Strict** | **53.160 ms** | **120 ms** | 57.9% | **46.3%** |
| GCC C Strict | 192.998 ms | 700 ms | 90.7% | 72.5% |
| GFortran Strict | 205.297 ms | 720 ms | 84.0% | 67.2% |
| **Wheelchair Tolerance** | **30.674 ms** | **80 ms** | 65.2% | **52.2%** |
| GCC C Fast | 208.127 ms | 730 ms | 87.7% | 70.1% |
| GFortran Fast | 195.657 ms | 680 ms | 86.9% | 69.5% |

Strict wall-time ratios on this run:

- Wheelchair / GCC C throughput: **3.63×**.
- Wheelchair / GFortran throughput: **3.86×**.
- GCC C consumes **5.83×** as much process CPU time as Wheelchair Strict for the same checksum.
- GFortran consumes **6.00×** as much process CPU time as Wheelchair Strict for the same checksum.

The important observation is not high occupancy. Wheelchair's measured occupancy is lower while it finishes much earlier. This is evidence about **physical-work inflation**, not a claim that low occupancy is automatically good or that this benchmark defines a universal language ranking.

## Machine-code observation

In the audited 1.3.102 binaries, the C and Fortran implementations retain runtime integer division in their native realizations. The Wheelchair executable contains no `div`, `idiv`, or `vdiv` instruction. The benchmark therefore exposes a case where reducing realization work matters more than keeping every core visibly busy.

## Interpretation

Wheelchair's target is not maximum hardware occupancy. The architectural objective is to make actual machine work approach the work that is mathematically and causally necessary:

```text
necessary relation
      ↓
semantic / causal facts
      ↓
remove avoidable reconstruction, transport and realization work
      ↓
actual physical work → necessary work
```

This benchmark is one representative witness of that direction. It is not an absolute theoretical lower-bound measurement: the exact theoretical minimum machine cost is not claimed here. The narrow claim is that, for this matched runtime-modulo high-entropy workload, the tested native C/GFortran realizations consume substantially more CPU time than Wheelchair 1.3.102 for the same result.

Raw measurements are in [`raw.csv`](./raw.csv); medians are in [`summary.csv`](./summary.csv).