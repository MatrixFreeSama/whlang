# Wheelchair 1.2.9 Resource-Semantic Correction Proof

## Scope

This proof covers the 1.2.9 replacement of the general resource-routing fabric with recipient-blind causal execution. It does not re-claim historical benchmark speedups and does not alter the mature tensor/Rank-N physical peaks merely for uniformity.

## Source deletion proof

The 1.2.9 source tree deletes the old causal-return, schedulerless/home-slot, MPSC-inbox, and fixed-worker general runtime implementations. `test_129.sh` treats the presence of any retired path as a hard failure.

The source is deleted rather than compiled behind a feature flag.

## New native state

The active general runtime stores only mutable causal readiness state:

```text
remaining dependency count per node
completion byte per node
```

AOT immutable data contains:

```text
node count
edge count
CPU-width envelope
indegree per node
first outgoing edge per node
edge target table
next-edge links
native fragment entry offsets
```

There is no home-worker table, per-worker ready head, remote cache, ready-next queue link, worker-local pending count, victim id, or resource token location.

## Runtime transition proof

A node blocked on dependencies executes `FUTEX_WAIT` on its own remaining-dependency word. This releases the CPU while the mathematical prerequisite is absent.

A completing node walks only its declared outgoing dependency edges. For each edge it atomically decrements the dependent node's remaining count. The unique zero transition wakes that dependent node's futex.

The completion path does not read an executor id, peer load, peer queue, availability bitmap, worker state, or recipient field.

The software resource transition is therefore:

```text
OWNED -> FREE
```

not:

```text
OWNED_BY_A -> OWNED_BY_B selected by A
```

## CPU-width proof

The general runtime interprets the requested width as an inherited Linux affinity envelope. It selects the first N CPUs already allowed by the caller and applies that mask before finite causal contexts are materialized. Descendants inherit the same mask.

No node is bound to one selected CPU. Linux chooses among the allowed CPUs at runtime. The original affinity mask is restored after all finite contexts have completed.

This preserves an explicit Q1/Q2/Q4 width contract without creating N permanent software owners.

## Lifecycle proof

Node contexts are materialized through a binary clone/join tree. The tree has no ready-node query and receives no runtime demand metric. It carries static node intervals only.

A leaf represents exactly one finite causal node. After the leaf executes and publishes its true dependency edges, it returns. Child lifecycle processes exit; ancestors may block in `wait4` solely to complete the lifecycle join. There is no post-completion work search.

## Idle-spin proof

The new active general engine contains no `pause` loop. Causal blocking uses futex sleep. `test_129.sh` disassembles the built engine and rejects a `pause` instruction.

## Planner proof

`surface/general_parallel_plan.py` no longer computes `home_slots`. It proves the dependency DAG and reports explicit fields:

```text
runtime_fixed_home_ownership = 0
persistent_idle_worker_spin = 0
post_completion_work_search = 0
post_completion_peer_query = 0
resource_release_destination = 0
resource_handoff = 0
resource_consumer_visibility = none
```

The native linker patches only dependency topology, CPU-width envelope, and native fragment entry offsets.

## Preserved mature path

The structural tensor runtime remains a separate mature physicalization. It already partitions a finite static tensor domain and returns after that finite work. 1.2.9 does not replace its native256/native512/Rank-N peaks with the general node-context runtime.

## Development validation performed during the correction

The new handwritten x86-64 general engine was independently assembled and linked with GNU `as`/`ld` in the editing environment.

A shared-memory native harness used the DAG:

```text
A ----\
       -> C
B ----/
```

where `C` reads results written independently by `A` and `B`. The engine completed correctly for:

```text
CPU width 2: 100 consecutive runs passed
CPU width 4: 100 consecutive runs passed
```

The Python planner, native linker module, offset generator, and updated drivers were also syntax-compiled with Python, and the replacement build/test shell scripts passed shell syntax checks.

## Full-tree release gate

The repository contains `test_129.sh` for the complete source-tree build and Q1/Q2/Q4 compiler/output equivalence gate. The editing environment did not have a network-mounted checkout of every repository file, so this document does not falsely claim that the entire historical regression suite was executed there.

The code and full-tree gate are both committed; running `./test_129.sh` in the 1.2.9 tree is the final release-host validation step.
