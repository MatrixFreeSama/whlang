# Wheelchair 1.2.9 Authoritative Parallel Resource Charter

## Status

This document is the authoritative 1.2.9 amendment for general parallel execution and resource ownership. It supersedes the retired 1.2.6 schedulerless/resource-routing doctrine. Historical release evidence may describe older behavior, but it is not permission to restore that behavior.

Wheelchair keeps two planes separate:

```text
causal/data plane       resource-ownership plane
A ----true dependency--> B        OWNED -> FREE
```

A causal edge may name its dependent because that relationship is mathematical. A resource release may not name a recipient because reuse is outside the releaser's semantic domain.

## Prime rule

```text
Compute locally.
Finish locally.
Release blindly.
```

The finisher has no recipient.

Completion erases ownership.

Resource release has no destination.

A released resource may be reused without the releaser knowing the consumer.

## Legal resource state transition

The only legal completion-side transition is:

```text
OWNED -> FREE
```

The following transition is forbidden when the releaser participates in choosing the destination:

```text
OWNED_BY_A -> OWNED_BY_B
```

A later consumer may acquire free capacity through the operating system, runtime-independent kernel scheduling, or hardware arbitration. That later acquisition is a separate event and is invisible to the releaser.

## Causal communication

Sparse local communication remains a core design rule. An execution node may publish only information required by declared dependency neighbors.

Legal examples include:

```text
remaining_deps[B]--
ready(B) after the exact zero transition
result(A) becomes visible to B
```

These are data/causality events. They are not resource handoff.

The compact distinction is:

```text
dependency communication may have a destination;
resource release may not.
```

## CPU and silicon authority

For the general blind-release runtime, `--executors N` is a maximum CPU-width envelope, not a declaration of N permanent workers. The runtime narrows the inherited Linux CPU-affinity mask to N allowed CPUs. Runnable finite causal contexts are then scheduled by the operating system within that envelope.

Wheelchair does not assign a causal node to a permanent CPU owner. It does not route ALU, execution-port, ROB, rename, cache, SMT, or other in-core silicon resources. Those remain microarchitecture authority.

The software boundary is therefore:

```text
Wheelchair:
  derive true causality
  emit native code
  materialize finite causal contexts
  relinquish CPU while causally blocked
  terminate/release after completion

Linux:
  choose which allowed CPU runs a runnable context

CPU microarchitecture:
  arbitrate in-core physical resources
```

## Finite node contexts

General parallel nodes are finite execution contexts.

A context whose dependencies are not ready waits with a kernel futex. It does not spin, poll peers, scan queues, inspect load, or search for other work. A futex-blocked context relinquishes the CPU until its own dependency state changes.

After its native fragment finishes, the context may only:

1. mark its own completion;
2. publish true outgoing dependency transitions;
3. wake a dependent causal node whose indegree reached zero;
4. return/exit.

It may not acquire another node.

## Lifecycle tree

Binary clone/join topology is permitted only for finite context materialization and terminal lifecycle join. It is not a runnable-work dispatcher and may not carry resource ownership between nodes.

A lifecycle child is identified by a static node interval, not by runtime demand. The lifecycle tree never asks which worker is idle or where spare capacity should go.

## Absolutely forbidden in the active general parallel path

The following mechanisms are prohibited:

```text
work stealing
victim selection
peer-load polling
peer-status polling for resource demand
global runnable queue
global ready scan
root work scheduler
runtime profitability selector
serial fallback
fixed runtime home ownership
per-worker work inbox
resource token routing
resource pull from ancestors
resource push to descendants/siblings
direct worker-to-worker resource handoff
post-completion work search
post-completion peer query
persistent idle worker spin
release_to(worker)
next_owner
resource_destination
consumer-aware release
```

A mechanism is forbidden by semantics even if it is distributed, lock-free, local, or named something other than a scheduler.

`no central scheduler` is insufficient. The stronger rule is:

```text
no finishing execution context has scheduling responsibility for another context.
```

## No hidden serial decision point

Wheelchair forbids algorithmic global serial decision points in the resource-release path. Hardware arbitration, cache coherence, atomic dependency transitions, kernel wakeups, and other physical mechanisms may serialize at implementation boundaries, but Wheelchair must not construct a software master decision that all releasers require.

Atomics are admitted only where they protect true shared causality, such as multiple predecessors decrementing one dependent indegree. They are not admitted merely to implement a work queue, ownership transfer, or load balancer.

## Technical Peak Preservation Contract

The 1.2.9 correction does not authorize flattening the mature structural/tensor peaks.

Protected areas include:

```text
Rank-N structural semantics
native512 AVX-512 physicalization
native256 AVX2/YMM physicalization
split512x256 physical mapping
fused tensor evaluators
matrix-free reductions
existing mature AOT specialization gates
```

A mature tensor runtime that statically partitions its true independent domain and terminates after its own finite episode is not the target of this correction.

Generalization may not replace a proven narrow physical peak with a slower generic mechanism merely for uniformity.

## Compiler invariants

Every 1.2.9 semantic/native plan for the general blind-release path must expose and satisfy:

```text
GLOBAL_READY_QUEUE=0
GLOBAL_READY_SCAN=0
ROOT_SCHEDULER=0
RUNTIME_COST_SELECTOR=0
SERIAL_FALLBACK=0
WORK_STEALING=0
RUNTIME_FIXED_HOME_OWNERSHIP=0
PERSISTENT_IDLE_WORKER_SPIN=0
POST_COMPLETION_WORK_SEARCH=0
POST_COMPLETION_PEER_QUERY=0
RESOURCE_RELEASE_DESTINATION=0
RESOURCE_HANDOFF=0
RESOURCE_CONSUMER_VISIBILITY=none
RELEASE_RULE=owned_to_free_no_recipient
COMMUNICATION_RULE=true_dependency_neighbors_only
```

## Source-level anti-regression rule

The active 1.2.9 tree must not contain the retired causal-resource-routing implementations. They are deleted rather than disabled.

In particular, the active tree does not retain the former causal-return runtimes, schedulerless MPSC/home-slot runtime, home-slot planner, or general-parallel slot engine.

If a future implementation needs a different physical strategy, it must be derived again from this charter instead of restoring those files.

## Canonical one-line rule

```text
A worker may know its dependency neighbor; it may never know the future consumer of the resource it releases.
```
