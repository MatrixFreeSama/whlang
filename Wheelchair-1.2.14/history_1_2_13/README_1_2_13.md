# Wheelchair 1.2.13

Wheelchair 1.2.13 is the **Execution Representation Compression** release.

1.2.12 reduced unnecessary execution-lifetime fragmentation. 1.2.13 attacks a different form of waste: repeatedly reconstructing low-entropy Rank-N coordinates that can be represented more cheaply as induction state.

## Core rule

> Low-entropy execution structure is compressed into induction state. High-entropy structure remains explicit.

This is deliberately analogous to data compression. A dense static Rank-N traversal contains highly predictable coordinate information and is therefore compressible. An irregular sparse address stream has high structural entropy; forcing it into dense induction state would be negative compression.

## 1.2.13 caretaker optimizations

The native512 derived frontend now provides:

- canonical dense Rank-N coordinate recognition for static power-of-two suffix axes;
- coordinate common-subexpression elimination through persistent physical carriers;
- induction-variable realization instead of repeated flat-index decoding;
- strength reduction from repeated shift/mask reconstruction to recurrence updates;
- loop-nest reconstruction through coalesced axis carry;
- row/batch boundary updates only when the corresponding logical axis changes;
- register-pressure admission: if persistent carrier capacity is unavailable, direct addressing remains authoritative;
- tiny-period protection for Rank-N axes whose full pattern fits inside one SIMD packet.

The optimization is structural only. It never uses workload names, benchmark identities, wall-clock measurements, JIT profiling, or runtime profitability selection.

## No negative structural compression

The irregular sparse authority program is intentionally rank-1 and contains ten long-distance modulo permutations. 1.2.13 compiles its q1/q2/q4 executables byte-for-byte identically to 1.2.12:

```text
q1 sha256 80a55d919a0ba6df6416d59b0cb31c178e2215b15cba9766e251044671ef9102
q2 sha256 97b8178e7059996b257925fb72d2482b5faa50e0eb8804fc67625c6ba209d30d
q4 sha256 5cf07ded263e5a17df6355ef39702bf09dcab817ce62eb3b8878f91c91a7f906
```

Native256 has no spare high persistent register bank in the mature profile, so 1.2.13 deliberately keeps its direct-addressing realization rather than forcing state that would increase pressure.

## Dense Rank-N result

On the development AMD EPYC 9V74 runner, the 128x128 dense bilinear Rank-3 benchmark was measured by interleaving 1.2.12 and 1.2.13 binaries over 33.6M, 67.1M and 134.2M interactions at q1/q2/q4.

Nine-point geometric mean speedup:

```text
Wheelchair 1.2.13 vs 1.2.12 = 1.230x
```

This is a version-to-version diagnostic, not a universal language-wide speed claim. The raw data is stored under `benchmarks/execution_compression_1213/`.

The same dense four-way benchmark still leaves Expert C ahead. 1.2.13 narrows the dense deficit but does not claim to have completed all future dense loop optimization work.

## Numerical contract

Wheelchair still provides no global fast-math mode. The new optimization changes only integer coordinate realization and execution representation. Floating-point ordering and the declared numerical contract are preserved.

## Existing invariants retained

- pure handwritten assembly production compiler;
- no Python in production build/compiler/runtime;
- AOT only, no JIT;
- blind resource release `OWNED -> FREE`;
- no work stealing, global ready queue, peer-load query, or runtime profitability selector;
- causal-width preservation from 1.2.12;
- 1.2.11 structural base/wide/derived selection;
- sparse high-entropy path remains direct and byte-stable.

## Release gate

```sh
./test_release_native_1213.sh
```

Key new gates include:

```text
STRUCTURAL_COMPRESSIBILITY_ANALYSIS=PASS
DENSE_RANKN_COORDINATE_CSE=PASS
DENSE_RANKN_INDUCTION_CARRIERS=PASS
DENSE_RANKN_COALESCED_AXIS_CARRY=PASS
DENSE_RANKN_CARRY_BOUNDARIES=PASS
DENSE_SMALL_PERIOD_FALLBACK=PASS
NATIVE256_REGISTER_PRESSURE_FALLBACK=PASS
IRREGULAR_SPARSE_1_2_12_BYTE_IDENTITY=PASS
NO_NEGATIVE_STRUCTURAL_COMPRESSION=PASS
EXECUTION_REPRESENTATION_COMPRESSION_1_2_13=PASS
```
