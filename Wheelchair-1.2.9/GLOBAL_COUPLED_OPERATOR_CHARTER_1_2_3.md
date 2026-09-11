# Wheelchair 1.2.3 Global Coupled Operator Charter

## Thesis

Wheelchair does not define Newton, FEM, CFD, Poisson, KKT, or any other named
workload as a privileged backend category. A globally coupled simulation object
is represented structurally as a dependency/coupling graph. A materialized
matrix is one possible source representation, not the semantic center.

The generic model is

```text
(state, field, topology, parameters) -> field
```

and the physical parallel contract is derived from dependency edges, algebraic
properties, numerical contracts, and ISA capabilities only.

## Sparse Causal Expansion

1.2.3 introduces a compile-time topology algebra inspired by the decomposition
idea behind Laplace expansion, but it never enumerates cofactors or minors.

For a coupling graph G=(V,E), the compiler searches for a bounded separator S
such that removing S produces at least two independent interiors. The interiors
are recursively decomposed and represented externally only by a Causal Separator
Signature. Separator composition is binary, not a central sweep.

The important transformation is conceptual:

```text
global coupling
    -> bounded separator
    -> independent interiors
    -> boundary signatures
    -> binary separator DAG
```

not

```text
determinant -> cofactor -> minor enumeration
```

## Non-negotiable invariants

The 1.2.3 planner enforces or reports these invariants explicitly:

```text
laplace_minor_enumeration = false
duplicate_region_expansions = 0
central_spawn_loop = 0
central_wait_loop = 0
central_reduction_loop = 0
global_task_queue = 0
global_barrier_without_dependency = 0
scalar_fallback = 0
hidden_serial_fallback = 0
non_neighbor_communication = 0
```

No dependency edge implies no synchronization edge.

## Bounded expansion

The planner computes conservative symbolic work, storage, and communication
amplification. A required expansion is rejected when a configured limit is
exceeded. This prevents the Laplace-inspired decomposition from becoming a
combinatorial work explosion.

The mature planner also rejects a required split when no separator within the
configured bound can be proved. Rejection is preferred to hidden serialization,
scalar fallback, or a fabricated parallel result.

## Genericity

Optimization decisions do not depend on program names, region names, physics
names, or solver names. Renaming an isomorphic coupling graph preserves the
structural decomposition hash.

The 1.2.3 authority includes a synthetic 31-node path graph and a renamed peer.
It also includes a dense graph that must reject when the configured separator
bound cannot prove a split.

## WH/WHEX integration

The existing compile-time WHEX/WH Region and Dependency topology is automatically
presented to the same Sparse Causal Expansion algebra when it contains enough
structure to form a meaningful coupling graph. Region names are erased before
canonical native bytes.

The resulting separator plan is semantic evidence only. In 1.2.3 it introduces
no runtime separator object, no runtime workload tag, and no runtime dispatch.
Existing native code generation remains under the 1.2.2 technical-peak contract.

## Technical Peak Preservation Contract

1.2.3 must retain the complete 1.2.2 release authority, including:

- Rank-2, Rank-3, and Rank-6 native Cartesian-product execution;
- 1/2/4 executor equivalence;
- WH/WHEX canonical and native byte equivalence;
- generated Rank-N RX call edges = 0;
- Rank-N scalar fallback = 0;
- 1.2.1 Interior Periodic Composition peak protection;
- 1.2.1 Newton/Jv peak protection;
- central spawn/wait/reduction loops = 0;
- global task queue = 0.

Generality is not allowed to flatten an established technical peak.

## Scope boundary

1.2.3 matures the generic compile-time separator/signature algebra and integrates
it with the language semantic plan. It does not claim that every arbitrary
runtime CSR/COO matrix can already be imported and physically Schur-condensed by
the native backend. Such a claim requires a separate physical realization proof
with the same no-serial/no-amplification constraints.

This boundary is intentional: unsupported physical capability is stated plainly
rather than hidden behind a solver-specific fallback.
