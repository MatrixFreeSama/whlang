# Wheelchair 1.2.6 — Schedulerless Sparse Causal Execution Charter

## Baseline and exclusion

Wheelchair 1.2.6 is derived only from the mature 1.2.5 line. The abandoned earlier 1.2.6 experiment is not an implementation ancestor and must not be reconstructed through a 1x/2x/4x runtime selector, runtime cost model, TP126 backend, or benchmark-specific dispatch.

The 1.2.5 native tensor/WHEX hot path remains a protected technical peak. Static independent domains are already AOT partitioned and must not be routed through a heavier generic runtime merely for architectural uniformity.

## Prime directive

Execution and the decision of what executes next are held to the same rule:

> No hidden serial spine.

A parallel program is not a serial controller surrounded by workers. Runtime readiness, continuation and resource use must arise from the declared sparse causal relation itself.

## Scheduler erasure

Wheelchair 1.2.6 does not introduce a faster central scheduler. It eliminates scheduling as an independent runtime control phase wherever the causal relation is known or locally discoverable.

The dynamic causal fabric therefore forbids in its hot path:

- a global runnable queue;
- a global ready scan;
- a root scheduler or dispatcher;
- a master-worker assignment loop;
- a root readiness epoch;
- a parent-demand summary tree;
- work stealing from a shared global head;
- avoidable global barriers or global phase progression;
- runtime 1x/2x/4x cost selection;
- hidden serial or scalar fallback.

The compile-time silicon resource scheduler in `topologyc` is not a runtime work scheduler. It remains valid AOT code-generation machinery and is protected.

## Sparse causal readiness

For a declared dependency edge `u -> v`, completion of `u` modifies only the state required by its actual consumers. A node becomes ready only on the unique transition:

```
remaining_deps[v] : 1 -> 0
```

No unrelated node is inspected. No runtime all-node scan discovers readiness. If the number of causally affected neighbors is `k` in a domain of `N` nodes, execution-control work follows the sparse relation rather than the ambient domain size.

## Direct continuation and handoff

A ready successor has only two normal physicalizations:

1. **Local causal continuation** — the producer retains the successor in private continuation storage when locality permits.
2. **Direct causal handoff** — the producer writes the successor directly to the successor's AOT home slot through one inbound handoff cell and wakes only that slot.

The handoff cell is not a runnable queue. If it is occupied, the producer does not wait, enqueue globally, scan for a worker, or consult a scheduler. It retains the successor as a private local continuation.

Cross-slot control communication may therefore be caused only by a true dependency edge.

## Local causal time

Each home domain progresses and terminates from its own causal state. Independent regions do not wait for a global epoch. A slot whose home domain is complete and that has no private continuation or inbound handoff may terminate independently.

A global verification scan is permitted only after execution has ended, as proof instrumentation. It is not scheduling.

## Work belongs to topology

Logical work is not owned by a thread. A CPU core, SMT context, SIMD lane or other compute resource is a physical realization site. AOT home placement is a locality hint, not semantic ownership: a producer may legally continue a ready successor locally when doing so removes coordination.

## Generality

The schedulerless mechanism may inspect only generic causal structure and resource constraints. Workload names, benchmark identities and hard-coded physics domains are forbidden from placement and readiness decisions.

The compile-time planner uses structural DAG relations to preserve independent width and dependency locality. Requested execution width is never silently reduced by a runtime profitability selector. If a topology has less intrinsic parallel width than the requested hardware, that is a property of the dependency relation, not a runtime retreat to serial execution.

## Matrix-free control

No global dependency matrix or global runnable graph is required at runtime. The native bounded proof stores only declared adjacency and local dependency state. Production realizers should derive or preserve the same relation directly whenever it can be represented implicitly.

The architectural target is:

```
Matrix-free computation
+ sparse/matrix-free dependency
+ scheduler-erased continuation
```

## No overhead laundering

Parallelism is not considered successful merely because a selector avoids its expensive cases. For useful gain `G` and coordination cost `C`, a negative result `G - C < 0` is an architectural defect to expose and reduce, not a reason to hide the path behind a cost model.

Performance reports must retain the requested execution width and report overhead directly.

## Technical-peak preservation

1.2.6 must preserve established mature peaks, including where applicable:

- direct native AOT machine code;
- no C/LLVM authoritative backend;
- no JIT;
- AVX-512 vector realization;
- no mature-vector scalar fallback or scalar tail oracle;
- no unnecessary hot calls;
- persistent CSE and induction;
- product-subtract contraction;
- vector reduction residency;
- Rank-N derivation;
- shared-dependency episode widening;
- WH/WHEX semantic equivalence;
- the existing causal binary lifecycle tree that avoids root O(P) spawn/wait/reduce sweeps.

A new general abstraction is incomplete if it erases an old technical peak.

## Release evidence

The 1.2.6 schedulerless causal lane must prove at minimum:

- native static executable construction;
- single-source, fan-out/fan-in and multi-source DAG correctness;
- cycle rejection;
- randomized sparse DAG stress;
- zero runtime global ready scans;
- zero runtime global queue operations;
- zero root scheduler operations;
- zero parent-chain demand updates;
- zero runtime cost selector;
- zero serial fallback;
- workload-name-blind compile-time planning;
- unchanged mature 1.2.5 compiler/runtime witnesses where the new lane is not semantically involved;
- benchmark reporting against the previous 1.2.5 causal fabric and an Expert C Q1 control without using the benchmark result to select a narrower runtime path.

## Final red lines

**Be radical.**

**True parallelism must not hide serial control.**

**Scheduling must not regrow a central serial spine.**

**No dependency edge means no synchronization edge.**

**Do not compute for management.**

**Do not schedule for scheduling's sake.**

**Do not use a cost selector to conceal unprofitable parallelism.**

**Do not specialize by workload identity.**

**Do not flatten a proven technical peak for abstraction uniformity.**

The end state is not "many threads." It is the highest attainable density of useful physical computation under the actual causal relation and hardware limits.
