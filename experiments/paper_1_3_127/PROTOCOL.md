# Wheelchair 1.3.127 paper experiment protocol

This directory is the reproducibility root for the Wheelchair 1.3.127 paper snapshot.

## Question

The experiment is not designed to show that Wheelchair wins every kernel. It tests whether compile-time mathematical and causal structure can reduce real physical work enough to repay the wider ValueFact representation and associated instruction overhead.

The retained negative control is therefore part of the result: dense/deep-causal scalar arithmetic may be modestly slower than optimized C because a Wheelchair value can carry more semantic structure than a bare C scalar.

## Frozen implementation

- Wheelchair: 1.3.127 paper snapshot.
- Archive: `dist/Wheelchair-1.3.127.zip`.
- The archive SHA-256 recorded by the release is `e4b7090a48f5751748fb0eaf6e072c0874939f5bc76a8b4f4ceb252b1847bfeb`.
- No publication-only compiler branch, workload-name dispatch, JIT route, scheduler family, or benchmark-specific fast path is admitted.

## Pilot matrix

### A. Scalar/deep-causal negative controls

`mass3`, `chem6`, and `rigid7` from the retained General benchmark family. These are intentionally unfavorable to structural amortization and expose ValueFact / pure-arithmetic overhead.

Controls:
- Wheelchair 1.3.127 Strict
- GCC C Strict
- GFortran Strict

### B. Localized elastoplastic support

The retained 1.3.127 localized-plasticity benchmark, where about 3999 of 8,000,000 integration points yield.

Controls:
- Wheelchair 1.3.127
- Wheelchair 1.3.126 on the same source when compilation is admitted, used as a mechanism ablation
- natural GCC C
- natural GFortran
- hand-bounded C ceiling
- hand-bounded Fortran ceiling

### C. Disconnected Level-Set / VOF support

The retained two-interface Level-Set benchmark used by 1.3.126 and still compiled by the 1.3.127 paper snapshot.

Controls:
- Wheelchair 1.3.127
- natural GCC C
- natural GFortran
- hand-bounded C ceiling
- hand-bounded Fortran ceiling

## Compilation contracts

Strict C:

```text
gcc -O3 -march=native -fno-fast-math -ffp-contract=off
```

Strict Fortran:

```text
gfortran -O3 -march=native -fno-fast-math -ffp-contract=off -fprotect-parens
```

Wheelchair uses the production `wheelchairc` from the frozen archive.

## Timing protocol

- One warm-up invocation per implementation and workload.
- 15 measured repetitions in rotating implementation order.
- All measured processes pinned to the same logical CPU chosen from the runner's allowed affinity set.
- Whole-process wall time measured with `time.perf_counter_ns()`.
- Raw rows are retained. Summary reports min, median, mean, max, standard deviation, median absolute deviation, time/C, and speedup over C.
- Program output is retained as a correctness/checksum witness.

## Publication policy

Positive and negative results remain in the same table. A result is not removed merely because C or Fortran wins. Manual ceiling implementations are labeled as ceilings rather than natural-language baselines. Measurements from different machines are not merged into one speedup claim.
