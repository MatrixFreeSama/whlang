# Wheelchair 1.2.14

Wheelchair 1.2.14 is the **Dense Caretaker Completion** release.

1.2.13 compressed low-entropy Rank-N coordinates into induction state. 1.2.14 continues the same compression principle upward: if a value, loop boundary, reduction step, or affine address component is predictable from static structure, the physicalizer should not repeatedly reconstruct it.

## Core rule

> Compress not only coordinates, but also value lifetime and loop lifetime.

The derived native512 path now combines:

- derived-affine induction (`c * axis` follows the axis recurrence instead of repeating `vpmullq`);
- axis-dependency LICM;
- true dense physical loop-nest reconstruction and safe loop interchange;
- static inner-axis full unroll / strip mining;
- delayed ZMM reduction under explicit tolerance contracts;
- strict reduction-order preservation when no tolerance contract authorizes reassociation;
- boundary identity elimination;
- proven-zero SIMD-tail elimination;
- lifetime-first persistent register ownership and faster body-local CSE reclamation;
- direct EVEX memory-broadcast constants where a resident constant register is unnecessary.

## No negative compression

The irregular sparse authority remains byte-identical:

```text
q1 sha256 80a55d919a0ba6df6416d59b0cb31c178e2215b15cba9766e251044671ef9102
q2 sha256 97b8178e7059996b257925fb72d2482b5faa50e0eb8804fc67625c6ba209d30d
q4 sha256 5cf07ded263e5a17df6355ef39702bf09dcab817ce62eb3b8878f91c91a7f906
```

The new dense passes do not recognize benchmark names and do not use runtime timing or profitability feedback.

## Dense authority result

On the development AMD EPYC 9V74 runner, the 128x128 dense bilinear Rank-3 benchmark was measured at 33.6M, 67.1M and 134.2M interactions with q1/q2/q4.

Direct 1.2.13 vs 1.2.14 interleaved nine-point geometric mean:

```text
Wheelchair 1.2.14 speedup = 1.722x
```

With the three competitors left in their aggressive modes:

```text
Expert C        -O3 -ffast-math -fopenmp-simd ...  1.000x time
Wheelchair 1.2.14 (no global fast-math)            1.385x time
Taichi 1.7.4    fast_math=True                     1.480x time
Expert Fortran  -Ofast -fopenmp                     1.702x time
```

At q4, Wheelchair/C geometric-mean time ratio is about 1.311x. Across all nine points, Wheelchair uses about 6.4% less elapsed time than Taichi fast and about 18.6% less than Expert Fortran Ofast. The authority result is the pointwise geometric aggregate of two independently randomized/interleaved passes after explicitly rebuilding C with `-fopenmp-simd`; an earlier C build without that pragma-enabling flag is not release authority. These are diagnostic measurements from one host, not universal performance claims.

Raw data is in `benchmarks/caretaker_1214/`.

## Numerical contract

Wheelchair still has no global fast-math switch. Integer/address caretaker transforms are exact. Floating reduction lifetime extension is enabled only when an explicit tolerance contract authorizes the changed association; strict programs keep the historical reduction order.

## Preserved architecture

- handwritten x86-64 production compiler;
- no Python in production build/compiler/runtime;
- AOT only, no JIT;
- no C or LLVM code-generation backend for Wheelchair programs;
- blind release `OWNED -> FREE`;
- no scheduler recipient, work stealing, global ready queue, peer-load query, or runtime profitability selector;
- 1.2.12 causal-width preservation;
- 1.2.13 no-negative-structural-compression rule;
- native256 direct fallback when register pressure makes dense compression unattractive.

## Release gate

```sh
./test_release_native_1214.sh
```

New 1.2.14 gates include:

```text
DERIVED_AFFINE_INDUCTION=PASS
CROSS_AXIS_LICM=PASS
TRUE_DENSE_LOOP_NEST_RECONSTRUCTION=PASS
DENSE_STATIC_INNER_UNROLL=PASS
DELAYED_ZMM_REDUCTION=PASS
BOUNDARY_IDENTITY_ELIMINATION=PASS
PROVEN_ZERO_TAIL_ELIMINATION=PASS
RANKN_LIFETIME_REGISTER_REUSE=PASS
DENSE_CARETAKER_BOUNDARY_CORRECTNESS=PASS
STRICT_REDUCTION_ORDER_PRESERVATION=PASS
IRREGULAR_SPARSE_1_2_13_BYTE_IDENTITY=PASS
NO_NEGATIVE_STRUCTURAL_COMPRESSION=PASS
DENSE_CARETAKER_OPTIMIZATION_1_2_14=PASS
```
