# Wheelchair 1.2.11 General Physicalization Charter

## Status

This is the authoritative 1.2.11 charter. It inherits the 1.2.9 recipient-blind resource charter and the 1.2.10 causal-region physicalization amendment. 1.2.11 corrects compile-time native resource-profile selection without changing resource-release semantics.

## Unchanged prime rule

```text
Compute locally.
Finish locally.
Release blindly.
```

The completion-side resource transition remains only:

```text
OWNED -> FREE
```

A finisher never selects a later resource consumer, searches for work, polls peer load, or transfers ownership to a sibling/parent/worker.

## New AOT causal-region rule

Source bindings are not required to map one-to-one to execution contexts.

The compiler may contract a causal edge `u -> v` if and only if both conditions are statically proved:

```text
outdegree(u) == 1
indegree(v)  == 1
```

This is a structural proof, not a profitability heuristic.

Why it is legal: completion of `u` can release only `v`, and `v` can become ready only because `u` completed. Therefore the boundary cannot expose additional runnable parallel width. The two fragments may be emitted as one finite causal region without hiding parallelism.

The rule may repeat transitively to form a maximal region. It must stop at every fork, join, or other boundary where observable causal width could change.

## Forbidden fusion inputs

Region formation may not inspect:

```text
workload name
benchmark identity
measured runtime
historical timing
CPU utilization feedback
peer status
resource demand
future consumer identity
```

There is no runtime fusion selector. Region topology is frozen AOT from the dependency graph.

## Physical runtime contract

A runtime context represents one fused causal region, not one permanent worker and not necessarily one source node.

A context may only:

1. wait on its own true incoming dependency count;
2. execute its statically fused native region;
3. publish true outgoing dependency transitions;
4. terminate/release.

A blocked region uses a kernel wait rather than busy spinning. A completed region never searches for another region.

## Stack-lifecycle rule

1.2.9 paid one `mmap`/`munmap` stack pair per recursively materialized context. 1.2.10 forbids that physicalization.

For an invocation with more than one causal region, the runtime reserves one bounded stack arena. Recursive finite contexts receive statically disjoint slices of that arena. The arena is released once at terminal join.

For a single fused region, no child-stack arena is allocated.

This arena is storage, not a work queue, owner table, home-slot map, or resource router.

## Parallel red lines retained from 1.2.9

The active general path still forbids work stealing, victim selection, fixed runtime home ownership, per-worker inboxes, global runnable queues, global ready scans, root schedulers, runtime profitability selectors, serial fallback, peer-load polling, post-completion work search, post-completion peer queries, persistent idle spin, resource handoff, and recipient-aware release.

## Technical Peak Preservation

Causal-region contraction is additive physicalization. It does not replace or flatten mature Rank-N, native512, native256, split512x256, tensor-fusion, matrix-free reduction, or other narrower proven native peaks.

A narrow mature native route remains legal only when it is semantically equivalent and non-regressive. No benchmark-specific route may be introduced under the name of region fusion.

## Required inherited 1.2.10 physicalization evidence

The release gate must prove at minimum:

```text
CHAIN_32 -> 1 causal region
DIAMOND_4 -> 4 causal regions
MIXED_BRANCH_TAILS_7 -> 3 causal regions
PER_CONTEXT_STACK_MMAP=0
PER_CONTEXT_STACK_MUNMAP=0
GLOBAL_READY_QUEUE=0
GLOBAL_READY_SCAN=0
ROOT_SCHEDULER=0
WORK_STEALING=0
RUNTIME_FIXED_HOME_OWNERSHIP=0
PERSISTENT_IDLE_WORKER_SPIN=0
POST_COMPLETION_WORK_SEARCH=0
POST_COMPLETION_PEER_QUERY=0
RESOURCE_RELEASE_DESTINATION=0
RESOURCE_HANDOFF=0
RELEASE_RULE=owned_to_free_no_recipient
```

## Canonical summary

```text
Fuse what cannot expose parallelism.
Preserve every boundary that can.
Release resources without naming their next owner.
```

## Final pure-assembly production closure

The 1.2.10 production path added a native x86-64 surface lowerer and native launcher. Python is not part of source parsing, AOT causality planning, causal-region physicalization, backend emission, runtime execution, or release-resource semantics.

The release distribution contains no Python source files. Historical Python reference/generator implementations are not production authority and are not shipped in the final ZIP.

The native launcher performs static structural classification only. It never selects a backend by workload name, measured timing, peer state, runtime profitability, or failed compilation retry.

## 1.2.11 native resource-profile authority

Physical capability selection is compile-time structural analysis, never runtime scheduling.

The canonical graph may select `base`, `wide`, or `derived` before native code generation. The selector may inspect proved structural pressure and Rank-N Cartesian metadata only. It must not inspect workload identity, source path, benchmark identity, observed runtime, peer load, or future resource consumers.

A failed compiler is never evidence for selecting another physicalizer. Failure-driven base->wide->derived retry is forbidden.

The selected physicalizer changes only the native resource realization. It may not change WH/WHEX semantics, causal dependencies, blind-release ownership rules, executor width, or numerical contract.
