# Wheelchair 1.2.9

Wheelchair is an ahead-of-time native programming-language research project for general programming with HPC and simulation as primary design targets.

The current 1.2.9 source tree is in [`Wheelchair-1.2.9/`](Wheelchair-1.2.9/).

## 1.2.9: blind resource release

Wheelchair 1.2.9 corrects the general parallel resource semantics while preserving the mature Rank-N, Native256, split512x256, Native512, tensor, and matrix-free technical peaks.

The new rule is:

```text
Compute locally.
Finish locally.
Release blindly.
```

The finisher has no recipient.

Two planes are now explicitly separate:

```text
causal/data plane                  resource plane
A ---- true dependency ----> B       OWNED -> FREE
```

A dependency may name its dependent. A resource release may not name another worker, slot, peer, subtree, or future consumer.

The authoritative specification is [`WHEELCHAIR_CHARTER_1_2_9.md`](Wheelchair-1.2.9/WHEELCHAIR_CHARTER_1_2_9.md).

## What was removed

The 1.2.9 tree physically deletes the former general resource-routing implementations. They are not disabled behind feature flags.

Removed concepts include:

```text
fixed runtime home ownership
per-worker MPSC work inboxes
resource-token routing
post-completion work search
peer-load/resource-demand queries
persistent idle worker spin
consumer-aware resource handoff
```

The old causal-return and schedulerless/home-slot runtime source files are absent from the 1.2.9 source tree.

## New general parallel path

For ordinary general WH programs at CPU width 2 or 4:

```text
general_parallel_plan.py
        |
        | true dependency DAG only
        v
general_parallel_native.py
        |
        | indegree/edge graph + native fragment offsets
        v
general_parallel_release_x86_64.S
```

Each causal node is a finite execution context. A node blocked on dependencies sleeps on its own dependency count with Linux `futex`, relinquishing the CPU instead of spinning. When it becomes runnable, Linux chooses which CPU inside the requested affinity envelope executes it.

After completion the node publishes only its true outgoing dependency transitions and returns/exits.

## `--executors` in 1.2.9

The existing command remains:

```bash
./wheelchairc program.wh -o program --executors 4
```

For the general blind-release path, `4` means a maximum four-CPU affinity envelope. It does not create four permanent work owners.

```text
Wheelchair: true causality + allowed width
Linux:      runnable-task to CPU scheduling
CPU:        in-core silicon arbitration
```

## Hard 1.2.9 invariants

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

The key distinction is:

```text
dependency communication may have a destination;
resource release may not.
```

## Preserved technical peaks

1.2.9 does not flatten mature structural/HPC paths into one generic runtime. Preserved areas include:

- Rank-N structural physicalization;
- Native256 AVX2/YMM execution;
- split512x256 physical mapping;
- Native512 AVX-512 execution;
- fused tensor evaluators;
- vector reduction residency;
- matrix-free reductions and structural elimination;
- qualified AOT native specializations.

The mature tensor runtime already gives each executor a finite static domain and returns when that domain is finished; it does not search for another worker's work after completion.

## WH and WHEX

Wheelchair exposes two source styles over one structural/native core:

- **WH (`.wh`)**: inference-heavy human surface;
- **WHEX (`.whex`)**: explicit expert surface.

For shared semantics they converge on the same structural meaning and AOT physicalization rules.

## Build

Current native target: Linux x86-64.

Requirements:

- Python 3 for AOT parsing/proof/source generation;
- GNU `as`, `ld`, `readelf`, `objdump`, `objcopy`, `nm`, and related binutils;
- POSIX shell.

Build:

```bash
cd Wheelchair-1.2.9
./build.sh
```

Compile WH:

```bash
./wheelchairc program.wh -o program
```

Compile WHEX:

```bash
./whexc program.whex -o program
```

Inspect the semantic plan:

```bash
./wheelchairc program.wh -o program --semantic-plan plan.json
```

## 1.2.9 validation

Run:

```bash
./test_129.sh
```

The gate verifies that the retired routing source is physically absent, the active native engine has no idle `pause` spin or old ownership/routing symbols, the semantic plan is recipient-blind, and the existing general branch/iterate probes remain Q1/Q2/Q4 output-equivalent.

The full historical regression harness is:

```bash
./test_complete.sh
```

Release documentation:

- [`WHEELCHAIR_CHARTER_1_2_9.md`](Wheelchair-1.2.9/WHEELCHAIR_CHARTER_1_2_9.md)
- [`RELEASE_NOTES_1_2_9.md`](Wheelchair-1.2.9/RELEASE_NOTES_1_2_9.md)
- [`RELEASE_PROOF_1_2_9.md`](Wheelchair-1.2.9/RELEASE_PROOF_1_2_9.md)
- [`RELEASE_GATES_1_2_9.txt`](Wheelchair-1.2.9/RELEASE_GATES_1_2_9.txt)

Historical archives under `dist/` remain historical evidence and are not silently relabeled as 1.2.9.

## Maturity boundary

Wheelchair remains an active research compiler/language. Unsupported dynamic topology may reject; arbitrary dynamic `while` has no hidden serial fallback; general-language memory safety is not formally claimed complete; performance claims remain bounded to explicit benchmark evidence.

The final execution authority is emitted machine code and proven causality, not source-syntax appearance.
