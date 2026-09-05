# Wheelchair 1.2.6 General Parallel Fabric

## Status

Wheelchair 1.2.6 promotes schedulerless sparse causal execution from a narrow
experimental lane into the general parallel semantic fabric.

This is a **semantic and execution-fabric generalization**, not a demand that
all mature numerical kernels be replaced by a generic runtime. A narrower
native realization is allowed only when it is semantically equivalent and
preserves or improves the mature technical peak.

## Universal rule

For every canonical Wheelchair program:

1. executable top-level bindings form causal nodes;
2. edges come only from actual value/data references;
3. source position does not create an execution edge;
4. independent nodes remain independent;
5. a true recurrence (`iterate`, causal cascade recurrence, fixed-point state)
   remains a causal enclave rather than becoming a global sequential spine;
6. readiness is the exact declared-dependency zero transition;
7. no global ready scan, runnable queue, root scheduler, work stealing,
   global phase barrier, runtime profitability selector, or serial fallback is
   permitted in the general parallel fabric.

## Physical authority

`build/topology-parallel` is the 1.2.6 general execution-fabric authority. It is
byte-identical to `build/topology-fabric-schedulerless`.

The 1.2.5 causal-return binaries remain regression witnesses. They are not the
semantic authority for new general parallel lowering.

Tensor/WHEX/Rank-N/shared-dependency kernels may continue to use their dedicated
native physicalizations. This is not a bypass of the universal semantics. It is
the Technical Peak Preservation Contract: a proven narrower physical kernel may
replace generic fabric overhead, but may not add ordering absent from the causal
graph or flatten an existing peak.

## General WH

The general WH surface now derives a workload-name-blind binding dependency DAG
after closed compile-time constructs are erased. `compute`, `map`, `reduce`,
`iterate`, nested operations, and other retained bindings participate through
actual references rather than declaration order.

A current direct-general native program slot is never falsely reported as
multi-executor. Its inter-binding universal plan is emitted independently, and
the compiler metadata distinguishes the general parallel authority from the
narrow physical code path. Future physical fusion must satisfy the same graph,
not invent a new scheduler.

## WHEX / structural WH

WHEX and structural WH attach the same General Parallel Fabric plan to their
existing Region/Effect/Dependency plan. Their mature specialized topology
machine code remains the preferred physical realization when it is sharper than
the generic fabric.

## Performance admission

The schedulerless authority was tested on 27 points per runner:

- chain, binary tree, layered DAG;
- work 0, 1,000, 20,000;
- 1, 2, 4 execution slots;
- 9 measured repetitions per point;
- three independent GitHub hosted runners.

After the per-slot MPSC causal inbox upgrade, the three runner whole-matrix
ratios against the 1.2.5 fabric were:

| CPU | New / 1.2.5 | Whole-matrix change | Q1 | Q2 | Q4 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Intel Xeon 6973P-C | 0.919860192 | +8.01% | 0.826820400 | 0.963756363 | 0.976758124 |
| Intel Xeon Platinum 8573C | 0.914272723 | +8.57% | 0.816117847 | 0.973129818 | 0.962284816 |
| AMD EPYC 7763 | 0.996728605 | +0.33% | 0.871262891 | 1.061491605 | 1.070693056 |

Cross-runner geometric mean of whole-matrix ratios: **0.942883791**, about
**5.71% faster overall**.

The AMD Q2/Q4 width-specific regression remains an explicit optimization target.
It does not authorize a hidden runtime selector or reintroduction of the old
serial spine. Architecture-specific improvements must be AOT physical mappings
under the same causal semantics.

## Hard invariants

- `global_ready_scan = 0`
- `global_queue_ops = 0`
- `root_scheduler_ops = 0`
- `parent_chain_updates = 0`
- `handoff_collisions = 0`
- `local_fallbacks = 0`
- `runtime_cost_selector = 0`
- `serial_fallback = 0`
- old abandoned TP126 implementation reuse = 0

The optimization problem is therefore moved to compile-time physical mapping and
local causal handoff, never back to a global scheduler.
