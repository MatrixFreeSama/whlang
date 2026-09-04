# Wheelchair 1.2.5 Release Notes

Wheelchair 1.2.5 expands the mature native optimizer from strong single-field episodes toward general high-pressure multi-field / multi-channel computation without introducing workload dispatch, a scalar fallback, or a hidden serial runtime.

## Added

- Shared Dependency Episode structural pressure analysis.
- A proved wide AVX-512 persistent ownership recipe using `ZMM16..ZMM29`.
- Two immutable resident constant registers (`ZMM30..ZMM31`) with vector RIP-broadcast overflow handling.
- Tolerant literal reciprocal erasure for finite non-zero binary64 literal divisors when the rounded reciprocal is normal; subnormal-reciprocal cases retain the existing vector division recipe.
- WH/WHEX shared selection, semantic-plan evidence, and native-byte-equivalence coverage.
- Dedicated structural, ABI, numerical, native-byte, sovereignty, and performance authority gates.

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

## Important scope statement

This release does not contain a fluid-solid special case. The two-field benchmark is a validation witness for a general structural property: multiple map dependencies with overlapping structural coordinates feeding a terminal consumer.
