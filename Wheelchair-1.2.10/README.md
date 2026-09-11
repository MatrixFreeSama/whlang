# Wheelchair 1.2.9

Wheelchair is an ahead-of-time, native, structure-first programming language project for general programming with HPC and simulation as primary design targets.

Wheelchair 1.2.9 is the **parallel resource semantic correction** release. It preserves the mature Rank-N, Native256, split512x256, Native512, tensor, and matrix-free technical peaks while completely replacing the incorrect general resource-routing interpretation introduced by the former schedulerless/home-slot fabric.

## The 1.2.9 rule

```text
Compute locally.
Finish locally.
Release blindly.
```

The finisher has no recipient.

The two planes are deliberately separate:

```text
causal/data plane                  resource plane
A ---- true dependency ----> B       OWNED -> FREE
```

A dependency may name `B` because `B` mathematically depends on `A`. A resource release may not name another worker, slot, subtree, peer, or future consumer.

The authoritative doctrine is [WHEELCHAIR_CHARTER_1_2_9.md](WHEELCHAIR_CHARTER_1_2_9.md).

## Core contract

Wheelchair has two human-facing source styles over one structural/native core:

- **WH (`.wh`)** is the inference-heavy human surface.
- **WHEX (`.whex`)** is the explicit expert surface.

```text
WH source                 WHEX source
   |                          |
   | structural recovery      | explicit structure
   v                          v
        Unified Structural Core
                 |
                 | proof + erasure + true causality
                 v
        AOT Native Physicalization
                 |
                 v
          Native x86-64 ELF
```

The central causality rule remains:

```text
No dependency edge = no synchronization edge.
```

1.2.9 adds the equally important resource rule:

```text
No resource need = no continued software ownership.
```

Unsupported structure rejects rather than silently becoming a scalar fallback, global work queue, work-stealing loop, runtime profitability selector, or conventional sequential spine.

## What 1.2.9 removed

The old general fabric had successfully removed a central scheduler, but it still retained distributed scheduling responsibility through fixed home ownership, per-worker inboxes, resource-token routing, and persistent workers.

Those implementations are deleted from the 1.2.9 source tree, not hidden behind a feature flag.

Removed mechanisms include:

```text
fixed runtime home slots
per-worker MPSC work inboxes
post-completion work search
resource-token routing through parent/child/sibling topology
work stealing / victim selection
peer-load/resource-demand queries
persistent idle PAUSE spin
consumer-aware release
```

The old causal-return and schedulerless runtime sources are not part of the 1.2.9 tree.

## New general parallel physicalization

For ordinary general WH programs at width 2 or 4, the path is:

```text
general_parallel_plan.py
        |
        | true dependency graph only
        v
general_parallel_native.py
        |
        | patch indegree/edge graph + native fragment offsets
        v
general_parallel_release_x86_64.S
```

The new native engine stores no worker ownership map.

Each causal node has a finite execution context. If its dependencies are not ready, it waits on its own dependency count with Linux `futex`, releasing the CPU instead of spinning. When the exact dependency count reaches zero, the context becomes runnable. Linux chooses which allowed CPU executes it.

After its fragment finishes, the context only publishes true outgoing dependency transitions and returns/exits.

## Meaning of `--executors`

The command-line spelling remains compatible:

```bash
./wheelchairc program.wh -o program --executors 4
```

For the 1.2.9 general blind-release path, the number means **maximum CPU width**, not four permanent workers.

The runtime narrows the inherited affinity mask to four already-allowed CPUs. All finite causal contexts inherit that envelope. No causal node is permanently assigned to CPU 0, 1, 2, or 3.

```text
Wheelchair decides: true causality + allowed width
Linux decides:      which allowed CPU runs a runnable context
Intel/AMD decides:  in-core execution-resource arbitration
```

## Neighbor sparse communication remains

Local sparse communication is still a core Wheelchair idea. It is now explicitly separated from resource flow.

Legal:

```text
A finishes
remaining_deps[B]--
if B reaches zero: wake B's causal wait
```

Illegal:

```text
A finishes
find idle/busy worker
choose B's worker
route A's resource to that worker
```

The compact rule is:

```text
dependency communication may have a destination;
resource release may not.
```

## Release invariants

The 1.2.9 general path requires:

```text
GENERAL_PARALLEL_GLOBAL_READY_QUEUE=0
GENERAL_PARALLEL_GLOBAL_READY_SCAN=0
GENERAL_PARALLEL_ROOT_SCHEDULER=0
GENERAL_PARALLEL_RUNTIME_COST_SELECTOR=0
GENERAL_PARALLEL_SERIAL_FALLBACK=0
GENERAL_PARALLEL_WORK_STEALING=0
GENERAL_PARALLEL_RUNTIME_FIXED_HOME_OWNERSHIP=0
GENERAL_PARALLEL_PERSISTENT_IDLE_WORKER_SPIN=0
GENERAL_PARALLEL_POST_COMPLETION_WORK_SEARCH=0
GENERAL_PARALLEL_POST_COMPLETION_PEER_QUERY=0
GENERAL_PARALLEL_RESOURCE_RELEASE_DESTINATION=0
GENERAL_PARALLEL_RESOURCE_HANDOFF=0
GENERAL_PARALLEL_BLIND_RESOURCE_RELEASE=PASS
```

`test_129.sh` additionally rejects the physical presence of the retired runtime/planner files.

## Technical Peak Preservation

1.2.9 is not permission to flatten mature HPC paths into the general node runtime.

Protected mature areas include:

- proof-gated Rank-N structural physicalization;
- Native256 four-lane AVX2/YMM execution;
- split512x256 physical mapping;
- Native512 AVX-512 execution;
- fused tensor evaluators;
- vector reduction residency;
- matrix-free reductions and structural elimination;
- existing qualified AOT technical peaks.

The mature tensor runtime already assigns each executor a finite static domain and returns when that domain is complete. It does not search for a neighbor's work after completion, so 1.2.9 leaves that technical peak structurally separate.

## Release lineage

### 1.2.6

Introduced general causal parallelization and correctly removed central ready queues/root schedulers, but its schedulerless/home-slot physicalization still carried distributed scheduling responsibility. That resource interpretation is superseded by 1.2.9.

### 1.2.7

Introduced generic multi-ISA physicalization:

```text
native256
split512x256
native512
```

Physical choice remains AOT and workload-name blind.

### 1.2.8

Matured the Native256 AVX2/YMM path, finite-register live-range fracture, full-YMM spill handling, and compiler-local fixup ledger. Those physical peaks are retained.

### 1.2.9

Separates causality from resource ownership and makes completion recipient-blind.

## WH and WHEX

Both surfaces converge on the same structural meaning. General plans expose the 1.2.9 resource invariants, while mature structural/native paths remain independent physical realizations when they are semantically equivalent and protect technical peaks.

## Platform

Current native target: Linux x86-64.

Build-time requirements:

- Python 3 for AOT parsing, proof, and source generation;
- GNU `as`, `ld`, `readelf`, `objcopy`, `nm`, and related binutils;
- POSIX shell.

Generated programs do not execute through Python, C, C++, LLVM, or a JIT.

## Build

```bash
./build.sh
```

A successful build ends with:

```text
WHEELCHAIR_BUILD=PASS
```

## Compile WH

```bash
./wheelchairc program.wh -o program
```

With a four-CPU execution envelope:

```bash
./wheelchairc program.wh -o program --executors 4
```

## Compile WHEX

```bash
./whexc program.whex -o program
```

For an explicit AOT ISA ceiling:

```bash
./whexc program.whex -o program --isa-limit avx2
```

`--isa-limit` remains an AOT capability ceiling, not a runtime selector or scalar-fallback permission.

## Inspect the semantic plan

```bash
./wheelchairc program.wh -o program --semantic-plan plan.json
```

The 1.2.9 plan makes the corrected boundary visible. Useful fields include:

```text
readiness_rule
communication_rule
release_rule
resource_consumer_visibility
runtime_fixed_home_ownership
persistent_idle_worker_spin
post_completion_work_search
post_completion_peer_query
resource_release_destination
resource_handoff
cpu_dispatch_authority
silicon_dispatch_authority
```

## Validation

The dedicated gate is:

```bash
./test_129.sh
```

It checks source deletion, native-engine structure, plan invariants, static ELF output, and Q1/Q2/Q4 output equivalence on the existing general branch/iterate probes.

The broader historical regression harness remains:

```bash
./test_complete.sh
```

and now invokes `test_129.sh` as the final resource-semantic gate.

Release evidence:

```text
WHEELCHAIR_CHARTER_1_2_9.md
RELEASE_NOTES_1_2_9.md
RELEASE_PROOF_1_2_9.md
RELEASE_GATES_1_2_9.txt
```

## Current maturity boundary

Wheelchair 1.2.9 remains an active research compiler/language. Unsupported dynamic topology may reject. General-language memory safety is not claimed formally complete. Performance evidence is bounded to explicitly measured hosts and workloads.

The release makes one stronger architectural claim than 1.2.8: **a finishing general execution context no longer participates in deciding who gets its former compute resource.**

The final execution authority remains emitted machine code and proven causality, not the appearance of the source syntax.
