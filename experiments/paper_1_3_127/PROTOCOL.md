# Wheelchair 1.3.127 paper experiment protocol

This directory is the reproducibility root for the Wheelchair 1.3.127 paper snapshot.

## Question

The experiment is not designed to show that Wheelchair wins every kernel. It tests whether compile-time mathematical and causal structure can reduce real physical work enough to repay the wider ValueFact representation and associated instruction overhead.

Negative controls are part of the result. Dense/deep-causal scalar arithmetic may be slower than optimized C because a Wheelchair value can carry more semantic structure than a bare C scalar. Likewise, a mature structural relation may still have an uneven physical realization for some runtime shapes; such cliffs are retained rather than removed from the experiment set.

## Frozen implementation

- Wheelchair: 1.3.127 paper snapshot.
- Archive: `dist/Wheelchair-1.3.127.zip`.
- Archive SHA-256: `e4b7090a48f5751748fb0eaf6e072c0874939f5bc76a8b4f4ceb252b1847bfeb`.
- No publication-only compiler branch, workload-name dispatch, JIT route, scheduler family, compatibility route, or benchmark-specific fast path is admitted.
- Experiment-harness fixes may repair permissions, source-format flags, timing order, or diagnostics, but may not alter the frozen compiler/runtime or choose a different algorithm for Wheelchair.

## ISA normalization

The fresh AVX2 paper tables fix the physical ISA class to **x86-64-v3 / AVX2** so a hosted runner with AVX-512 cannot silently give C/Fortran a wider vector ISA than Wheelchair's native256 profile.

- General/Tensor-style native256 sources use the frozen native256 production entry admitted by the source.
- Field sources use the frozen `bin/fieldc-native256` production entry.
- Historical WHEX sources whose frozen admitted route is `whexc` are not forced through `topologyc-native256` merely to fit a table.

Strict C:

```text
gcc -O3 -march=x86-64-v3 -mtune=generic -fno-fast-math -ffp-contract=off
```

Strict Fortran:

```text
gfortran -O3 -march=x86-64-v3 -mtune=generic -fno-fast-math -ffp-contract=off -fprotect-parens -ffree-line-length-none
```

`-ffree-line-length-none` only admits the retained free-form source lines and does not change arithmetic optimization.

AVX-512 results are kept in separate v4 tables. Results from v3/AVX2 and v4/AVX-512 profiles are never merged into one speedup claim.

## Experiment matrix

### A. Scalar/deep-causal negative controls

`mass3`, `chem6`, and `rigid7` from the retained General benchmark family. These are intentionally unfavorable to structural amortization and expose ValueFact / pure-arithmetic overhead.

Controls:
- Wheelchair 1.3.127 Strict, native256
- GCC C Strict, x86-64-v3
- GFortran Strict, x86-64-v3

### B. Localized elastoplastic support

The retained 1.3.127 localized-plasticity benchmark, where only a small localized region yields.

Controls:
- Wheelchair 1.3.127
- Wheelchair 1.3.126 on the exact same source as a mechanism ablation when admitted
- natural GCC C
- natural GFortran
- hand-bounded C ceiling
- hand-bounded Fortran ceiling

Manual bounded controls are ceilings, not natural-language baselines.

### C. Disconnected Level-Set / VOF support

The retained two-interface Level-Set benchmark used by 1.3.126 and still compiled by the 1.3.127 paper snapshot.

Controls:
- Wheelchair 1.3.127
- natural GCC C
- natural GFortran
- hand-bounded C ceiling
- hand-bounded Fortran ceiling

### D. Strict established Field miniapps

Retained miniAMR 27-point and miniFE heat21 kernels are run from the frozen `real_sparse_1326` source family. The Wheelchair JSON is changed only from its retained `floating_point: tolerant` declaration to `floating_point: strict`; the graph, accesses, operators, and reduction are otherwise unchanged.

Controls:
- Wheelchair 1.3.127 Strict, `fieldc-native256`
- GCC C Strict, x86-64-v3
- GFortran Strict, x86-64-v3

All implementations consume the same deterministic WHFLD217 input bytes.

### E. Numerical-reference diagnostic

For the strict Field miniapps, an independent C diagnostic keeps each local kernel operation in `float` and changes only the final reduction accumulator to `double`. This f64 accumulation is **not timed as a competitor**. It is used to interpret checksum differences rather than assuming bit inequality means one implementation is wrong.

### F. Field size and CPU-set sweep

The strict Field cases are repeated over multiple cubic extents and, when the same hosted runner exposes them, both one and four admitted CPUs. No speedup is averaged across sizes or CPU sets.

A detailed shape sweep is retained specifically to catch runtime-shape cliffs. Power-of-two points are not allowed to stand in for arbitrary extents.

### G. Address-path ablation

A small diagnostic separates:
- center-only Field reduction, which requires no periodic coordinate remap;
- one periodic neighbor;
- the retained 21/27-neighbor miniapp stencils.

This is used only to localize a physical-realization weakness found by the shape sweep. It is not used as a headline benchmark.

## Floating-point contract policy

Strict and tolerant/aggressive results are separate experiment families.

A Wheelchair `tolerant` source must not be presented as a Strict-vs-Strict result merely because the control compiler used strict flags. The first exploratory Field expansion accidentally mixed tolerant Wheelchair JSON with Strict C/Fortran controls; that directory is retained as experiment history and explicitly marked superseded. The corrected strict/reference tables are authoritative for Strict claims.

If tolerant Wheelchair is later compared with aggressive C/GFortran controls, that table must be labeled tolerant/aggressive and must not be merged with Strict speedups.

## Timing protocol

- One warm-up invocation per implementation and workload.
- Main performance tables use 15 measured repetitions in rotating implementation order.
- Diagnostic sweeps may use fewer repetitions but are labeled diagnostic and are not headline tables.
- All compared processes use the same admitted CPU set on a given point.
- Whole-process wall time is measured with `time.perf_counter_ns()`.
- Raw rows are retained.
- Summary reports at least median and median absolute deviation; main harnesses also retain min/mean/max/standard deviation when available.
- Program output is retained as a correctness/checksum witness.
- CPU model, ISA flags, compiler versions, repository commit, and affinity are recorded with each main run.

## Publication policy

- Positive and negative results remain visible. A result is not removed because C or Fortran wins.
- Manual ceiling implementations are labeled as ceilings rather than natural baselines.
- Different machines or ISA profiles are not combined into one speedup claim.
- Historical benchmark results are not silently copied into a fresh 1.3.127 table.
- A historical source rejected by the frozen production entry used for a table is recorded as a coverage limit instead of being made to compile through a publication-only compatibility path.
- Hosted-runner measurements are pilot evidence. Final submission numbers must be repeated on one fixed documented machine without changing the frozen 1.3.127 compiler artifact.

Current evidence and known limitations are summarized in `CURRENT_RESULTS.md`.
