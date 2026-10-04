# Wheelchair 1.3.127 paper experiment protocol

This directory is the reproducibility root for the Wheelchair 1.3.127 paper snapshot.

## Question

The experiment is not designed to show that Wheelchair wins every kernel. It tests whether compile-time mathematical and causal structure can reduce real physical work enough to repay the wider ValueFact representation and associated instruction overhead.

The retained negative control is therefore part of the result: dense/deep-causal scalar arithmetic may be modestly slower than optimized C because a Wheelchair value can carry more semantic structure than a bare C scalar.

## Frozen implementation

- Wheelchair: 1.3.127 paper snapshot.
- Archive: `dist/Wheelchair-1.3.127.zip`.
- Archive SHA-256: `e4b7090a48f5751748fb0eaf6e072c0874939f5bc76a8b4f4ceb252b1847bfeb`.
- No publication-only compiler branch, workload-name dispatch, JIT route, scheduler family, or benchmark-specific fast path is admitted.

## ISA-normalized first pilot

The first fresh paper pilot fixes the physical ISA class to **x86-64-v3 / AVX2** so a hosted runner with AVX-512 cannot silently give C/Fortran a wider vector ISA than Wheelchair's native256 profile.

Wheelchair uses the production `bin/topologyc-native256` shipped in the frozen release. This is an existing compile-time physical profile built from the same semantic authorities, not a compatibility backend or paper-only route.

Strict C:

```text
gcc -O3 -march=x86-64-v3 -mtune=generic -fno-fast-math -ffp-contract=off
```

Strict Fortran:

```text
gfortran -O3 -march=x86-64-v3 -mtune=generic -fno-fast-math -ffp-contract=off -fprotect-parens
```

A later AVX-512 table must be run separately on one fixed AVX-512 host. Results from the v3/AVX2 and AVX-512 profiles are never merged into one speedup claim.

## Pilot matrix

### A. Scalar/deep-causal negative controls

`mass3`, `chem6`, and `rigid7` from the retained General benchmark family. These are intentionally unfavorable to structural amortization and expose ValueFact / pure-arithmetic overhead.

Controls:
- Wheelchair 1.3.127 Strict, native256
- GCC C Strict, x86-64-v3
- GFortran Strict, x86-64-v3

### B. Localized elastoplastic support

The retained 1.3.127 localized-plasticity benchmark, where about 3999 of 8,000,000 integration points yield.

Controls:
- Wheelchair 1.3.127 native256
- Wheelchair 1.3.126 native256 on the exact same source, used as a mechanism ablation when compilation is admitted
- natural GCC C
- natural GFortran
- hand-bounded C ceiling
- hand-bounded Fortran ceiling

### C. Disconnected Level-Set / VOF support

The retained two-interface Level-Set benchmark used by 1.3.126 and still compiled by the 1.3.127 paper snapshot.

Controls:
- Wheelchair 1.3.127 native256
- natural GCC C
- natural GFortran
- hand-bounded C ceiling
- hand-bounded Fortran ceiling

## Timing protocol

- One warm-up invocation per implementation and workload.
- 15 measured repetitions in rotating implementation order.
- All measured processes pinned to the same logical CPU chosen from the runner's allowed affinity set.
- Whole-process wall time measured with `time.perf_counter_ns()`.
- Raw rows are retained. Summary reports min, median, mean, max, standard deviation, median absolute deviation, time/C, and speedup over C.
- Program output is retained as a correctness/checksum witness.
- CPU model, ISA flags, compiler versions, repository commit, and affinity are recorded with every run.

## Publication policy

Positive and negative results remain in the same table. A result is not removed merely because C or Fortran wins. Manual ceiling implementations are labeled as ceilings rather than natural-language baselines. Measurements from different machines or different ISA profiles are not merged into one speedup claim. Hosted-runner measurements are pilot evidence; final submission numbers should be repeated on a fixed documented machine.
