# Wheelchair 1.2.5 Release Notes

Wheelchair 1.2.5 expands the mature native optimizer from strong single-field episodes toward general high-pressure multi-field / multi-channel computation without introducing workload dispatch, a scalar fallback, or a hidden serial runtime.

## Added

- Shared Dependency Episode structural pressure analysis.
- A proved wide AVX-512 persistent ownership recipe using `ZMM16..ZMM29`.
- Two immutable resident constant registers (`ZMM30..ZMM31`) with vector RIP-broadcast overflow handling.
- Tolerant literal reciprocal erasure for finite non-zero binary64 literal divisors when the rounded reciprocal is normal; subnormal-reciprocal cases retain the existing vector division recipe.
- Canonical AOT MXCSR handling for deterministic reciprocal construction.
- WH/WHEX shared selection, semantic-plan evidence, and native-byte-equivalence coverage.
- Dedicated structural, ABI, numerical, native-byte, sovereignty, inherited-peak, and multi-host performance authority gates.

## Preserved

- the frozen mature tensor frontend source;
- the frozen runtime source;
- Newton/Jv native bytes when the new recipe is not structurally required;
- global-stiffness native bytes when the new recipe is not structurally required;
- Rank-N 1.2.2 physicalization;
- Sparse Causal Expansion 1.2.3;
- Product-Subtract contraction and Vector Reduction Residency 1.2.4;
- AOT-only native sovereignty;
- zero scalar fallback and zero workload-name dispatch.

## Multi-host authority

Authority run `33902157205` produced two AVX-512-qualified AMD EPYC 9V74 hosts and zero qualified failures.

Across the 12 decoupled/coupled two-field cases per host (`10M/100M`, `q=1/2/4`):

- host slot 2 median 1.2.4 -> 1.2.5 speedup: **2.4486x**;
- host slot 2 geometric-mean speedup: **2.4478x**;
- host slot 3 median speedup: **2.4508x**;
- host slot 3 geometric-mean speedup: **2.4480x**.

The predeclared release threshold was >=1.50x for both median and geometric mean. Both qualified hosts passed.

The same authority run preserved bit-identical 1.2.4/1.2.5 checksums for every tested two-field case and passed the Newton/Jv, global-stiffness, Rank-N, Sparse Causal Expansion, native-sovereignty, no-hidden-serial, and no-scalar-fallback gates.

On these AMD hosts Expert C AVX-512 remained faster in aggregate: Wheelchair 1.2.5 was approximately **1.34x** slower geometrically. 1.2.5 therefore claims a large general multi-field recovery, not a general C-performance victory.

## Important scope statement

This release does not contain a fluid-solid special case. The two-field benchmark is a validation witness for a general structural property: multiple map dependencies with overlapping structural coordinates feeding a terminal consumer.
