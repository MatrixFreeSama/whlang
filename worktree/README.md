# Wheelchair 1.2.6

Wheelchair is an ahead-of-time, native, structure-first programming language project for general programming with HPC and simulation as primary design targets.

Version 1.2.6 makes the **General Parallel Fabric** the universal causal execution model while preserving mature narrow native peaks through generic, structurally selected resource profiles.

## Core contract

Wheelchair has two human-facing source styles over one structural/native core:

- **WH (`.wh`)** is the inference-heavy human surface.
- **WHEX (`.whex`)** is the explicit expert surface.

For semantics implemented by both surfaces, the contract is:

```text
WH source                 WHEX source
   |                          |
   | structural recovery      | explicit structure
   v                          v
        Unified Structural Core
                 |
                 | proof + erasure + causal topology
                 v
        General Parallel Semantics
                 |
                 | AOT physicalization
                 v
          Native x86-64 ELF
```

The central rule is:

```text
No dependency edge = no synchronization edge.
```

Source order is not permission to synthesize an execution dependency. Unsupported structure is rejected rather than silently rebuilt as a scalar fallback, a hidden global queue, a runtime profitability selector, or a conventional sequential spine.

## What 1.2.6 changes

### General Parallel Fabric

Executable bindings form a causal DAG from actual references. Independent bindings remain independent. True recurrences remain local causal enclaves rather than becoming a global serial backbone.

The physical authority is:

```text
build/topology-parallel
```

The release gates require:

```text
global ready scan       = 0
global queue operations = 0
root scheduler          = 0
parent-chain updates    = 0
runtime cost selector   = 0
serial fallback         = 0
source-order edges      = 0
```

General WH native materialization is gated at 1, 2, and 4 execution slots, including independent-binding relocation, fragmented causal graphs, and recurrence enclaves.

### Generic native resource profiles

Mature structural tensor programs are admitted to one of three generic AOT physical classes:

```text
base
wide
derived
```

The selector examines canonical structure and resource pressure. It does **not** inspect workload names, solver names, benchmark identities, source paths, runtime timings, or profitability measurements.

Current release witnesses include:

```text
Newton/Jv             5 distinct structural loads -> base
global stiffness      6 distinct structural loads -> base
two-field decoupled  11 distinct structural loads -> wide
two-field coupled    12 distinct structural loads -> wide
proved Rank-N product                           -> derived
```

These witnesses demonstrate structural admission. They are not named fast paths.

### Technical Peak Preservation Contract

Generality is additive, not flattening. A generalization may not erase information and rebuild a slower common denominator when a mature physical peak can be recovered from structural proof.

1.2.6 therefore protects the 1.2.5 execution implementation at the byte level:

- `base` compiler loadable bytes match the mature 1.2.5 base compiler;
- `wide` compiler loadable bytes match the mature 1.2.5 wide implementation;
- the `derived` frontend loadable image matches the mature Rank-N-derived frontend;
- the `derived` compiler `.text` matches the mature implementation;
- the `derived` runtime loadable image matches the mature implementation;
- the mature tensor and general runtime images remain byte-identical.

Renamed ELF `STT_FILE` / string-table metadata is not execution code. The release gate compares executed/loadable sections rather than requiring retired historical filenames to survive inside non-executing metadata.

### No active special-purpose native routes

The old active implementation names used while developing narrower peaks are not part of the 1.2.6 compiler route. Current build/wrappers use generic structural capabilities only.

Release audit requires:

```text
ACTIVE_SPECIAL_PURPOSE_NATIVE_ROUTE=0
ACTIVE_LEGACY_DERIVED_FILE_ROUTE=0
ACTIVE_HIDDEN_SERIAL_SPINE=0
```

The semantic field `rank_n_product` remains valid. It describes Rank-N Cartesian-product meaning and its AOT patch, not a workload-specific dispatch route.

## Schedulerless performance evidence

The General Parallel Fabric schedulerless authority was measured on 27 points per runner across chain, binary-tree, and layered-DAG topologies; work levels 0, 1,000, and 20,000; and 1, 2, and 4 execution slots.

Three independent hosted runners produced whole-matrix New / 1.2.5 ratios:

| CPU | New / 1.2.5 | Whole-matrix change |
| --- | ---: | ---: |
| Intel Xeon 6973P-C | 0.919860192 | +8.01% |
| Intel Xeon Platinum 8573C | 0.914272723 | +8.57% |
| AMD EPYC 7763 | 0.996728605 | +0.33% |

Cross-runner geometric mean: **0.942883791**, approximately **5.71% faster overall**.

The AMD Q2/Q4 width-specific regression remains an explicit AOT optimization target. It does not authorize a hidden runtime selector.

## AVX-512 authority boundary

The current 512-bit structural tensor realizer requires AVX-512F-class host capability. `--isa-limit` is an audit ceiling, not a fake host-feature override: the native compiler still self-scans the real host ISA.

Therefore release validation separates:

1. host-independent structural/static execution-byte authority, which must pass on every x86-64 CI host; and
2. AVX-512 compile/execution witnesses, which run only on genuinely AVX-512-qualified hosts and otherwise report an explicit `SKIP_HOST_NOT_AVX512F`.

A skip is never recorded as a dynamic PASS.

## Platform

Current native target: Linux x86-64.

Build-time requirements:

- Python 3 for human-facing AOT parsing/proof and source generation;
- GNU `as`, `ld`, `readelf`, `objcopy`, and related binutils;
- POSIX shell.

The emitted program does not execute through Python, C, C++, LLVM, or a JIT.

AVX2 is represented in the capability model, but 1.2.6 does not claim a complete 256-bit structural tensor backend. Unsupported hardware or graphs reject rather than silently scalarizing.

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

With four execution slots:

```bash
./wheelchairc program.wh -o program --executors 4
```

## Compile WHEX

```bash
./whexc program.whex -o program
```

## Inspect structural proof

```bash
./wheelchairc program.wh -o program --semantic-plan plan.json
```

Useful questions include:

- which dependencies are real;
- which objects were erased before runtime;
- which regions or bindings are independent;
- which native resource profile was selected;
- whether any synthetic ordering, runtime selector, scalar fallback, or central control appeared.

## Structural execution rules

A WH `for` does not promise a serial machine loop. If points are independent, the semantic object is an axis map and may be realized with vector lanes, masked tails, executor regions, compile-time partitioning, or another proven parallel mapping.

A scalar final reduction value does not imply a scalar execution history. Reduction is represented as dependency topology.

Structural predicates may lower to select/dataflow structure rather than a central dispatcher.

Arbitrary dynamic `while` is not silently converted into a conventional serial backedge. Unsupported recurrence/control topology rejects until a genuine structural realization exists.

## Release evidence

The 1.2.6 release evidence is documented in:

```text
GENERAL_PARALLEL_FABRIC_1_2_6.md
RELEASE_NOTES_1_2_6.md
RELEASE_GATES_1_2_6.txt
RELEASE_PROOF_1_2_6.md
```

Historical release evidence remains in the repository for audit and comparison.

## Current maturity boundary

Wheelchair 1.2.6 is an active research compiler/language project. It does not claim every systems-language feature is complete.

In particular:

- a complete AVX2 structural backend is not claimed;
- arbitrary unsupported topology may reject;
- arbitrary dynamic `while` has no hidden serial fallback;
- general-language memory safety is not formally claimed as complete;
- performance evidence is bounded to the tested hosts, workloads, and authority matrices.

The final execution authority is the emitted machine code and proven causal topology, not the appearance of the source syntax.
