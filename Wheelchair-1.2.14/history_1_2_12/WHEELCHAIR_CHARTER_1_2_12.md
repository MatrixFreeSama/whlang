# Wheelchair 1.2.12 General Physicalization Charter

## 1. Authority

This charter inherits the recipient-blind resource model, pure-assembly production path, Rank-N physicalization, native resource-profile selection, and all protected numerical peaks of prior releases.

1.2.12 adds **Adaptive Execution Granularity** as a first-class physicalization rule.

## 2. Semantic resolution and physical resolution are separate

A semantic node exists to express and prove program structure. It does not automatically deserve an independent runtime lifetime.

The compiler may keep arbitrarily fine semantic structure while materializing fewer physical regions, provided every contraction is proven to preserve true causality, numerical contracts, observable semantics, and true parallel width.

## 3. Causal Mesh Coarsening

Treat the semantic dependency DAG as an execution mesh.

- one-to-one causal continuations are smooth interior structure and may be coarsened;
- forks, joins, externally observable boundaries, and unresolved dependencies are physical frontiers;
- coarsening must never turn independent causal work into a hidden serial path.

Canonical internal contraction condition:

```text
outdegree(u) == 1
indegree(v)  == 1
u -> v
```

The 1.2.12 assembly proof gate re-walks every physical region and verifies the contract before native emission.

## 4. Causal width preservation

True parallel width is protected.

A physical region is invalid if an internal member transition crosses a fork or join frontier. Any violation must reject physicalization rather than silently serialize the graph.

The compiler is not allowed to justify width loss by timing, hardware occupancy, benchmark identity, or a predicted profitability score.

## 5. Tensor execution-lifetime coarsening

The tensor executor tree is finite and bounded by the compiled executor count.

1.2.12 therefore allocates one invocation-scoped stack arena instead of performing stack mapping at every recursive causal split.

Rules:

- q1: no arena;
- q>1: exactly `(q-1)` 16 KiB stack slices are reserved in one mapping;
- a right subtree's executor-low endpoint identifies its unique slice;
- recursive `run_tree` performs no `mmap`/`munmap`;
- the root releases the arena once all true dependency joins have completed.

This is physical-lifetime coarsening, not a worker pool and not a scheduler.

## 6. Blind resource release remains absolute

The canonical release transition is still:

```text
OWNED -> FREE
```

Forbidden:

- `OWNED_BY_A -> OWNED_BY_B` selected by A;
- future-consumer lookup;
- peer-load query;
- work stealing;
- global ready queue;
- post-completion work search;
- recipient-aware resource release.

Dependency publication may name a true dependency destination. Resource release may not name a future resource consumer.

## 7. No runtime profitability selector

Execution granularity is derived from static causality and finite compiled topology.

Wheelchair must not time alternatives at runtime, retry physicalizers after failure, inspect workload names, or select granularity from benchmark identity.

A development timing scan is evidence for refusing an unsafe universal rule, not authority for introducing a magic constant.

## 8. Numerical contract

No global fast-math mode is provided.

Optimizations must preserve the declared numerical contract. Explicit tolerance may authorize transformations when the compiler/runtime contract covers the resulting numerical behavior; it is not permission to globally discard IEEE semantics.

## 9. Language scope

Wheelchair targets numerical-computing semantic coverage at least comparable to Fortran, plus richer HPC structural semantics and enough ordinary language semantics for single-file program completeness.

The project does not equate generality with importing large application-runtime abstractions that are unrelated to HPC/simulation.

## 10. Performance source

Performance should come from:

- matrix-free structure;
- Rank-N physicalization;
- vectorization;
- AOT specialization;
- causal mesh coarsening;
- execution-lifetime coarsening;
- data/register reuse;
- sparse/local dependency communication;
- elimination of redundant physical boundaries.

Performance must not be borrowed from hidden serial schedulers or an undeclared relaxation of numerical semantics.

## 11. Release requirements

1.2.12 is releasable only if:

```text
TENSOR_INVOCATION_STACK_ARENA=PASS
TENSOR_RECURSIVE_STACK_MMAP=0
TENSOR_RECURSIVE_STACK_MUNMAP=0
CAUSAL_WIDTH_PRESERVATION_GATE=PASS
CAUSAL_MESH_FORK_JOIN_WIDTH=PASS
CAUSAL_MESH_SERIAL_CHAIN_COARSENING=PASS
EXECUTION_ARENA_NUMERIC_INVISIBILITY=PASS
BLIND_RELEASE_SEMANTICS_PRESERVED=PASS
ADAPTIVE_EXECUTION_GRANULARITY_1_2_12=PASS
LANGUAGE_PURE_ASSEMBLY=PASS
WHEELCHAIR_1_2_12_RELEASE=PASS
```
