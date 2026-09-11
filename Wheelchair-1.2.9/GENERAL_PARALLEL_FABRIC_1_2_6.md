# Wheelchair 1.2.6 General Parallel Fabric

## Status

Wheelchair 1.2.6 promotes schedulerless sparse causal execution into the general parallel semantic fabric while preserving mature native technical peaks through generic structural resource profiles.

This is a semantic and execution-fabric generalization. It is not permission to replace a proven narrow physical realization with a slower common denominator merely for implementation uniformity.

## Universal rule

For every canonical Wheelchair program:

1. executable top-level bindings form causal nodes;
2. edges come only from actual value/data references;
3. source position does not create an execution edge;
4. independent nodes remain independent;
5. a true recurrence (`iterate`, causal cascade recurrence, fixed-point state) remains a causal enclave rather than becoming a global sequential spine;
6. readiness is the exact declared-dependency zero transition;
7. no global ready scan, runnable queue, root scheduler, work stealing, global phase barrier, runtime profitability selector, or serial fallback is permitted in the general parallel fabric.

The compact rule remains:

```text
No dependency edge = no synchronization edge.
```

## Physical authority

`build/topology-parallel` is the 1.2.6 general execution-fabric authority.

The mature 1.2.5 causal-return implementation remains a regression/performance witness. It is not the semantic authority for new general binding lowering.

Structural tensor programs may use one of three generic AOT native resource profiles:

```text
base
wide
derived
```

These are capability/resource classes selected from canonical structure. They are not workload lanes. A proven resource profile may eliminate generic fabric overhead only when it preserves the same causal semantics and satisfies the Technical Peak Preservation Contract.

The active selector is forbidden from inspecting workload/solver names, benchmark identity, source path, runtime timing, or a runtime profitability score.

## General WH

The general WH surface derives a workload-name-blind binding dependency DAG after closed compile-time constructs are erased. `compute`, `map`, `reduce`, `iterate`, nested operations, and other retained bindings participate through actual references rather than declaration order.

General native materialization is gated at 1, 2, and 4 execution slots. Release tests include independent-binding relocation, fragmented graphs, and recurrence enclaves.

A direct-general native program is not allowed to report synthetic parallelism. Its universal inter-binding plan and physical slot realization must agree with the causal graph.

## WHEX / structural WH

WHEX and structural WH converge on the same canonical structural meaning for shared mature semantics. Native resource profile admission is performed on that canonical structure.

For the current wide release witness:

```text
WH/WHEX canonical bytes = identical
WH/WHEX native resource profile = identical
```

On an AVX-512F-qualified dynamic witness, the native images and numeric result were also identical.

## Native resource profiles

Current structural witnesses are:

```text
Newton/Jv             5 distinct structural loads -> base
global stiffness      6 distinct structural loads -> base
two-field decoupled  11 distinct structural loads -> wide
two-field coupled    12 distinct structural loads -> wide
proved Rank-N product                           -> derived
```

The witness names are tests only. They do not occur in active compiler routing.

The semantic property `rank_n_product` remains part of the canonical structure and AOT patch contract. It is not a dedicated runtime route.

## Technical Peak Preservation

1.2.6 generalizes admission/naming without flattening mature 1.2.5 execution peaks.

Mandatory host-independent byte gates protect:

- base compiler loadable bytes;
- wide compiler loadable bytes;
- derived frontend loadable bytes;
- derived compiler `.text` bytes;
- derived runtime loadable bytes;
- mature tensor/general runtime images.

AVX-512F-qualified hosts additionally compare emitted old/new program loadable images and execute dynamic differential witnesses.

ELF `STT_FILE` and string-table names are non-executing metadata. Retired historical filenames are not preserved merely to force a whole-file equality that says nothing about executed instructions. Execution/loadable sections are the authority.

## Schedulerless physicalization

The general fabric uses local causal readiness and per-slot MPSC handoff. The release gate requires:

```text
global_ready_scan = 0
global_queue_ops = 0
root_scheduler_ops = 0
parent_chain_updates = 0
handoff_collisions = 0
local_fallbacks = 0
runtime_cost_selector = 0
serial_fallback = 0
```

The gate also covers 300 randomized DAGs, multisource graphs, MPSC inbox behavior, and native schedulerless cases.

## Performance admission

The schedulerless authority was measured on 27 points per runner:

- chain, binary tree, layered DAG;
- work 0, 1,000, 20,000;
- 1, 2, 4 execution slots;
- 9 measured repetitions per point;
- three independent GitHub hosted runners.

After the per-slot MPSC causal inbox upgrade, the three runner whole-matrix ratios against the 1.2.5 fabric were:

| CPU | New / 1.2.5 | Whole-matrix change | Q1 | Q2 | Q4 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Intel Xeon 6973P-C | 0.919860192 | +8.01% | 0.826820400 | 0.963756363 | 0.976758124 |
| Intel Xeon Platinum 8573C | 0.914272723 | +8.57% | 0.816117847 | 0.973129818 | 0.962284816 |
| AMD EPYC 7763 | 0.996728605 | +0.33% | 0.871262891 | 1.061491605 | 1.070693056 |

Cross-runner geometric mean of whole-matrix ratios: **0.942883791**, about **5.71% faster overall**.

The AMD Q2/Q4 width-specific regression remains an explicit optimization target. It does not authorize a hidden runtime selector or reintroduction of a serial spine. Architecture-specific improvements must be AOT physical mappings under the same causal semantics.

## AVX-512 qualification

`--isa-limit` constrains semantic/backend capabilities but does not spoof host ISA. The native compiler intentionally self-scans the real host.

Release authority is therefore split cleanly:

- structural/static/execution-byte gates run on every x86-64 validation host;
- AVX-512 compile/execution subgates run only when the host genuinely exposes `avx512f`;
- non-qualified hosts report `SKIP_HOST_NOT_AVX512F` for those subgates;
- a SKIP is never described as dynamic PASS.

## Hard invariants

```text
ACTIVE_SPECIAL_PURPOSE_NATIVE_ROUTE=0
ACTIVE_LEGACY_DERIVED_FILE_ROUTE=0
ACTIVE_HIDDEN_SERIAL_SPINE=0
ABANDONED_OLD_1_2_6_IMPLEMENTATION_REUSED=0
```

The optimization problem therefore lives in compile-time structural proof, native resource mapping, and local causal handoff, never in a hidden global scheduler or workload-specific dispatch table.
