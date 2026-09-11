# Wheelchair 1.2.3

## Theme: generic Sparse Causal Expansion for Global Coupled Operators

- Added `surface/sparse_causal_expansion.py`, a workload-agnostic compile-time coupling-graph planner.
- The planner borrows the decomposition idea of Laplace expansion but never enumerates cofactors or minors.
- Bounded separators produce independent interiors and Causal Separator Signatures.
- Separator composition is binary; no central spawn/wait/reduction sweep or global task queue is introduced.
- Every region appears exactly once in the decomposition tree; repeated minor/subproblem expansion is forbidden.
- Conservative symbolic work, storage, and communication amplification are release-gated.
- A required decomposition explicitly rejects when no bounded separator is proved or an amplification limit is exceeded.
- Small graphs use exact bounded separator search; larger graphs use bounded deterministic BFS-frontier search.
- Structural hashes ignore node names. Renamed isomorphic graphs therefore prove that optimization does not depend on solver/workload labels.
- Existing WHEX/WH Region dependency topology automatically feeds the same generic operator algebra when enough structure exists.
- Separator plans remain compile-time evidence in 1.2.3. No runtime operator tags, separator objects, or workload dispatch are emitted.
- Added strict synthetic path, dense-rejection, name-erasure, WH/WHEX sharing, and 1/2/4-executor native regressions.
- The complete 1.2.2 authority is rerun, preserving Rank-N and the 1.2.1 Interior Periodic/Newton-Jv technical peaks.

## Scope boundary

1.2.3 does not claim a finished arbitrary runtime CSR/COO importer or a fully native generic Schur-complement solver. Those remain future physical-realization work and may not be silently substituted by a serial fallback.
