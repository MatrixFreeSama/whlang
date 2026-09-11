# Wheelchair 1.2.14 Release Notes

## Theme

Dense Caretaker Completion: finish the textbook loop and lifetime optimizations exposed by the 1.2.13 dense audit while preserving the sparse high-entropy path byte-for-byte.

## Added

- derived-affine induction for literal-scaled canonical Rank-N coordinates;
- axis-dependency analysis and cross-axis loop-invariant code motion;
- reconstructed dense physical loop nests with safe loop interchange;
- static full-row / strip-mined inner-axis unrolling;
- delayed ZMM reduction with final horizontal fold under explicit tolerance contracts;
- strict-mode reduction-order preservation;
- boundary-body identity elimination;
- compile-time proven-zero tail elimination;
- lifetime-first persistent register admission and faster reclamation of body-local CSE;
- direct EVEX memory-broadcast use for spilled immutable integer constants.

## Preserved

- no global fast-math;
- AOT-only native compilation;
- pure handwritten assembly production path;
- blind resource release and causal-width rules;
- native256 mature direct path when persistent-register pressure makes compression unattractive;
- irregular sparse q1/q2/q4 machine images byte-identical to 1.2.13 and 1.2.12 authority hashes.

## Measured development result

Dense 128x128 Rank-3 bilinear contraction, 2048/4096/8192 batches x q1/q2/q4:

- direct interleaved 1.2.13 -> 1.2.14 nine-point geometric-mean speedup: about **1.722x**;
- corrected two-pass four-way fast-on geometric mean, Expert C fast = 1.000 time:
  - Expert C `-O3 -ffast-math -fopenmp-simd ...`: 1.000x;
  - Wheelchair 1.2.14, no global fast-math: about 1.385x;
  - Taichi 1.7.4 `fast_math=True`: about 1.480x;
  - Expert Fortran `-Ofast -fopenmp`: about 1.702x.
- q4 Wheelchair/C geometric-mean time ratio: about 1.311x;
- all-nine-point Wheelchair/Taichi time ratio: about 0.936x;
- all-nine-point Wheelchair/Fortran time ratio: about 0.814x;
- authority is the pointwise geometric aggregate of two randomized/interleaved passes. C was explicitly rebuilt with `-fopenmp-simd` so its `#pragma omp simd` path is active; the earlier build without that flag is excluded from release authority.

These are host-specific diagnostics, not universal language-wide performance promises. Raw CSVs are stored under `benchmarks/caretaker_1214/`.
