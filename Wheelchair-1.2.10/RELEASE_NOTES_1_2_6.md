# Wheelchair 1.2.6 Release Notes

## Theme

**General parallel semantics without flattening mature native peaks.**

Wheelchair 1.2.6 promotes schedulerless causal execution into the general language fabric and replaces active narrow native route identities with generic structural resource profiles.

The release is intentionally strict about both sides of that change:

- general semantics may not hide a serial scheduler;
- generalization may not erase a mature physical peak merely to make the implementation look uniform.

## General Parallel Fabric

`build/topology-parallel` is the general execution-fabric authority.

Executable bindings form a causal DAG from actual data/value references. Source order contributes no synthetic dependency edge. Independent bindings remain independent. True recurrence is contained in a causal enclave rather than promoted into a program-wide sequential spine.

Release invariants include:

```text
source-order edges       = 0
global ready scan        = 0
global queue operations  = 0
root scheduler           = 0
parent-chain updates     = 0
runtime cost selector    = 0
serial fallback          = 0
work stealing            = 0
global phase barrier     = 0
```

General WH native tests cover 1, 2, and 4 execution slots, independent-binding relocation, fragmented causal graphs, and multiple recurrence enclaves.

## Schedulerless causal handoff

The general fabric uses local causal readiness and per-slot MPSC handoff rather than a global runnable queue.

The release gate covers:

- native schedulerless cases;
- 300 randomized DAGs;
- multisource graphs;
- MPSC inbox behavior;
- zero handoff collisions;
- zero local fallbacks;
- zero global ready scans/queue operations;
- zero root-scheduler operations;
- zero parent-chain updates.

The three-runner schedulerless benchmark matrix has a whole-matrix geometric New / 1.2.5 ratio of `0.942883791`, approximately 5.71% faster overall. The AMD Q2/Q4 width-specific regression remains an explicit AOT optimization target, not a reason to reintroduce runtime profitability selection.

## Generic native resource profiles

The active native resource classes are:

```text
base
wide
derived
```

They are selected from canonical structural properties and resource pressure. The selector is forbidden from using workload names, solver names, source paths, benchmark identities, runtime timings, or a runtime cost model.

Release witnesses classify as:

```text
Newton/Jv             -> base
global stiffness      -> base
two-field decoupled   -> wide
two-field coupled     -> wide
proved Rank-N product -> derived
```

These names appear only in tests as witnesses. They do not participate in compiler routing.

## Retired active route identities

The 1.2.6 active compiler path no longer contains the previous narrow-route files/names used during development of the mature peaks. In particular, current routing does not depend on a shared-dependency workload lane or a `topologyc-sdep` identity, and the old Rank-N generator/file naming is replaced by the generic `derived` capability.

The semantic `rank_n_product` field remains. It is mathematical structure, not a dispatch identity.

Release audit requires:

```text
ACTIVE_SPECIAL_PURPOSE_NATIVE_ROUTE=0
ACTIVE_LEGACY_DERIVED_FILE_ROUTE=0
ACTIVE_HIDDEN_SERIAL_SPINE=0
```

## Technical Peak Preservation

1.2.6 protects the mature 1.2.5 execution implementation while generalizing its admission and naming.

Host-independent gates require:

- base compiler loadable-byte identity;
- wide compiler loadable-byte identity;
- derived frontend loadable-byte identity;
- derived compiler `.text` identity;
- derived runtime loadable-byte identity;
- mature tensor/general runtime byte identity.

On an AVX-512F-qualified host, emitted base/wide/derived program loadable images are also compared old-vs-new, and the derived program is executed as a differential witness.

A narrow historical ELF filename may change when a generator/file is renamed. Such `STT_FILE`/string-table metadata is not treated as executable semantics. Execution/loadable sections remain the authority.

## WH/WHEX equivalence

For the current wide witness, WH and WHEX produce byte-identical canonical cores and identical native-resource-profile analysis.

On an AVX-512F-qualified witness run, they also produced byte-identical native output and the expected coupled numeric checksum.

## AVX-512 host qualification

`--isa-limit` is a capability ceiling for backend audit. It does not spoof CPUID and does not turn a non-AVX-512 host into an AVX-512 compiler host.

The final workflow therefore separates:

- mandatory static/structural/execution-byte authority on any x86-64 runner;
- host-qualified AVX-512 compilation/execution subgates.

A non-qualified host reports `SKIP_HOST_NOT_AVX512F` for those dynamic subgates. It is never reported as a dynamic PASS.

## Authority evidence

Pre-seal full-green static/general authority:

```text
workflow run: 34005715246
head: 8fb4a502bc7373290a5ec462b58775b456b1fe7d
result: success
artifact: 9980851385
artifact SHA-256: f16096d1a66efd163c54c0aa443a9d32830a5bfe34ce22353ef489a9536ec673
```

That runner was not AVX-512F-qualified, so AVX-512-only subgates were explicitly skipped.

Qualified dynamic witness:

```text
workflow run: 34005158707
head: 4382fa12caad304057eff99d63f172773a06d180
```

Before the later obsolete whole-derived-ELF metadata gate failed, this qualified run had already passed the 1.2.5 dynamic self-test, general Q1/Q2/Q4 tests, wide old/new same-core native identity, WH/WHEX wide native identity, the coupled numeric checksum, zero wide `VDIVPD`, zero reachable wide hot calls, and schedulerless/general semantic gates.

A repository compare from `4382fa12...` to the pre-seal `8fb4a502...` shows that the intervening changes touched only the validation workflow and two authority test scripts. Compiler/runtime/build/wrapper execution implementation did not change, so that AVX-512 dynamic witness applies to the same execution implementation sealed by the final static gates.

## Claim boundary

1.2.6 is a general-parallel architecture release, not a claim of universal performance victory. Architecture-specific physical mapping remains open work, especially AMD Q2/Q4 schedulerless width behavior.

No future optimization may use that open work as justification for a hidden runtime selector, global scheduler, scalar fallback, or workload-name fast path.
