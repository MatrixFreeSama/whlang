# Wheelchair 1.2.12 Release Notes

## Theme: Adaptive Execution Granularity

1.2.12 addresses physical execution fragmentation without adding a scheduler.

The central distinction is now explicit:

```text
semantic resolution != physical execution resolution
```

Fine semantic nodes are retained for compiler reasoning. Physical lifetime boundaries are coarsened only where true causality proves that no parallel width is lost.

## Tensor runtime change

The tensor executor tree previously performed child-stack `mmap`/`munmap` inside recursive `run_tree` nodes. 1.2.12 replaces that with one invocation-scoped stack arena.

For q>1:

```text
arena bytes = (executor_count - 1) * 16384
```

Each reachable right subtree uses one disjoint stack slice. Recursive `run_tree` contains zero stack mapping/unmapping syscalls. The root unmaps the arena once after the full causal tree has returned. q1 maps nothing.

This applies to:

- native512 base/wide runtime;
- native512 derived runtime;
- native256 base/wide runtime;
- native256 derived runtime.

## General causal mesh proof

The maximal causal-chain contraction introduced earlier is retained, but 1.2.12 adds an independent assembly verification pass before physical code emission.

The pass rejects a region unless all internal edges remain exact one-to-one causal continuations. This turns the no-hidden-serialism rule into a hard compile-time release gate rather than a convention.

Release probes demonstrate:

```text
32-node pure chain -> 1 physical region
fork + two branch chains + join/tail -> 4 physical regions
```

The fork/join structure remains visible to the runtime while redundant serial boundaries inside each arm disappear.

## What 1.2.12 deliberately does not do

A development scan tested tensor leaf sizes from 64 KiB to 4 MiB. The fastest size changed with N and executor width; there was no architecture-independent monotonic rule.

Accordingly 1.2.12 does not hard-code a larger benchmark-derived chunk and does not add runtime timing/profitability selection. The 65,536-element numerical reduction leaf remains protected.

## Correctness

The new arena is numerically invisible across:

- q1/q2/q4;
- base/wide/derived;
- native512/native256;
- representative scalar, FSI, and Rank-N cases.

The 1.2.11 native resource-profile selector gates also remain green.

## FSI diagnostic

The three-way FSI correctness matrix remains 27/27 PASS at relative error <= 1e-8.

A same-host authority pass is included under `benchmarks/fluid_solid_coupling_1212/`. It is a diagnostic, not a universal performance claim. This release primarily removes execution-lifecycle fragmentation; it does not claim that the remaining FSI arithmetic kernel now universally beats Expert C or GFortran `-Ofast`.

## Production closure

```text
.py files in release: 0
production build Python invocations: 0
production language Python: 0
production compiler Python: 0
production runtime Python: 0
```

The release gate was rerun successfully with `python3` absent from PATH.
