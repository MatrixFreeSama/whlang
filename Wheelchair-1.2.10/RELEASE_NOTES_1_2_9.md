# Wheelchair 1.2.9 Release Notes

## Parallel resource semantic correction

Wheelchair 1.2.9 removes the resource-routing interpretation that entered the general parallel path after 1.2.5. The correction is semantic, not cosmetic.

The authoritative rule is now:

```text
Compute locally.
Finish locally.
Release blindly.
```

A finishing execution context publishes only true data-dependency transitions. It does not select a future worker, search for work, poll peer load, route a resource token, or preserve ownership merely because later work may exist.

## Dependency plane and resource plane are separated

A true data dependency may name its consumer:

```text
A -> B
```

Resource release may not:

```text
OWNED -> FREE
```

The releaser never performs `OWNED_BY_A -> OWNED_BY_B` by selecting B.

## Removed without compatibility retention

The following incorrect implementations are removed from the 1.2.9 source tree rather than disabled:

```text
runtime/causal_return_fabric_x86_64.S
runtime/causal_return_parallel_x86_64.S
runtime/schedulerless_causal_x86_64.S
runtime/schedulerless_126/
runtime/general_parallel_slot_x86_64.S
runtime/general_parallel_slot.ld
surface/schedulerless_causal_plan.py
tools/generate_general_parallel_slot_offsets.py
test_schedulerless_causal_126.sh
test_general_parallel_126.sh
test_general_parallel_native_126.sh
```

The obsolete top-level schedulerless-causal benchmark directory is also removed.

## New active general parallel path

The new native path is:

```text
surface/general_parallel_plan.py
        |
        | true dependency DAG only
        v
surface/general_parallel_native.py
        |
        | patch indegree/edge graph + native fragment offsets
        v
runtime/general_parallel_release_x86_64.S
```

The runtime contains no home-slot table, per-worker inbox, ready queue, work stealing, resource token router, or idle `pause` loop.

## Finite causal contexts

Each general causal node is represented by a finite execution context. A blocked context waits on its own dependency count with `futex`, thereby relinquishing the CPU. When the dependency count reaches zero, the operating system schedules the runnable context on any CPU inside the requested affinity envelope.

After native execution, the context only publishes outgoing true dependency transitions and returns/exits.

## Meaning of `--executors`

For the blind-release general path, `--executors N` means maximum CPU width, not N permanent work owners.

The runtime derives an N-CPU subset from the caller's existing affinity mask and all finite node contexts inherit that mask. Linux chooses which runnable task executes on which allowed CPU. In-core resource arbitration remains CPU microarchitecture authority.

## General-plan fields

1.2.9 removes runtime-home placement data and adds explicit anti-regression fields:

```text
runtime_fixed_home_ownership = 0
persistent_idle_worker_spin = 0
post_completion_work_search = 0
post_completion_peer_query = 0
resource_release_destination = 0
resource_handoff = 0
resource_consumer_visibility = none
release_rule = owned_to_free_no_recipient
communication_rule = true_dependency_neighbors_only
```

## Technical peak preservation

The correction does not replace the mature tensor/Rank-N physicalizers. Native256, split512x256, native512, fused evaluators, matrix-free reductions, and mature AOT structural peaks remain protected.

The mature tensor runtime already gives each executor a finite static domain and returns after that domain is complete; it is not rewritten into the general node-context runtime merely for uniformity.

## Validation added

`test_129.sh` adds release gates for:

- physical deletion of the retired resource-routing source;
- absence of old ownership/routing symbols from the active general engine;
- absence of idle `pause` spin from that engine;
- plan-level recipient blindness;
- Q1/Q2/Q4 output equivalence for existing branch and iterate general-language probes;
- no fixed home ownership, resource destination, peer query, work acquisition, or resource handoff.

The authoritative doctrine is recorded in `WHEELCHAIR_CHARTER_1_2_9.md`.
