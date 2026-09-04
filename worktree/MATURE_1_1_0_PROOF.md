# Wheelchair 1.1.0 Maturity Proof

## Release theme

Wheelchair 1.1.0 expands WHEX into a general true-parallel semantic foundation while
preserving the 1.0.15 physical tensor backend for existing programs.

The new source-level mechanisms are:

- first-class axis declarations;
- pure and structurally generic functions;
- compile-time records;
- explicit Region / Effect / Parallel contracts;
- binding and region dependency topology;
- compile-time ownership/read-write sets;
- control-topology reporting;
- Serial-Introduction reporting;
- abstraction/runtime erasure reporting;
- proof-gated Rank-N reduction-axis elimination.

## Native backend preservation

The principal native files are byte-identical to 1.0.15:

```text
compiler/tensor_frontend_x86_64.S
f897e112778873868ca3c34048b19d07725572f648c91eb7c441aef06435763f

compiler/topologyc_x86_64.S
2e83af25b6a6188c9ce24497d636206ca5978e59a92b619e6b722909ad2d4f80

runtime/tensor_runtime_template_x86_64.S
e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3
```

The frozen 1.0.15 periodic-heat image also remains byte-identical:

```text
SHA-256 76404fbc1a3b54c7b829a01f44e4716ebcf6db3ec7b441504636e4c5a8c2e0ab
N=16,777,216 checksum_bits=0x4167fc0000000000
```

This release therefore cannot insert extra runtime work into an existing WHEX kernel
without failing the byte-level baseline gate.

## High-level abstraction erasure

A WHEX source using:

```text
axis
record
pure generic fn
region ... effect pure parallel
```

was compiled against a manually inlined equivalent.

Required results:

```text
WHEX_HIGH_LEVEL_CANONICAL_ERASURE=PASS
WHEX_HIGH_LEVEL_MACHINE_CODE_ERASURE=PASS
WHEX_HIGH_LEVEL_MULTILINGUAL_ERASURE=PASS
```

The semantic plan additionally requires:

```text
runtime_function_objects=0
runtime_call_boundaries_from_surface_functions=0
runtime_record_objects=0
runtime_region_objects=0
runtime_effect_dispatch=0
runtime_axis_metadata_objects=0
```

## Dependency and Region topology

Two independent pure regions were compiled into a graph with no synthetic order
between them. A third reduction region depends on both through real expression reads.

Required results:

```text
WHEX_INDEPENDENT_REGIONS_NO_SYNTHETIC_ORDER=PASS
WHEX_DEPENDENCY_TOPOLOGY=PASS
synthetic_order_edges=0
implicit_global_lock=false
implicit_global_allocator_lock=false
```

## Ownership and race contract

The current pure WHEX lane uses unique compile-time output ownership. Every binding has
one immutable write target, dependency references form read sets, and shared mutable
writes are zero.

Required result:

```text
WHEX_TOPOLOGY_OWNERSHIP=PASS
runtime_borrow_table=false
implicit_locking=false
alias_uncertainty_policy=explicit_reject_not_serialization
```

## Serial-Introduction contract

The semantic planner emits the following counters:

```text
new_serial_backedges=0
new_global_barriers=0
new_central_loops=0
new_scalar_regions=0
new_scalar_tails=0
new_scalar_fallbacks=0
new_global_queues=0
new_ordered_dependencies=0
```

Required results:

```text
WHEX_SERIAL_INTRODUCTION_REPORT_ZERO=PASS
WHEX_SEMANTIC_LAYER_SCALAR_FALLBACK=0
WHEX_SEMANTIC_LAYER_CENTRAL_SERIAL_SPINE=0
```

The existing native runtime continues to contain zero `call eval_slot` sites.

## Rank-N Axis Algebra

1.1.0 no longer treats Rank-N only as a future grammar placeholder. It includes one
real generic native-lowering rule for sum reductions whose extra dimensions are
proven irrelevant to the expression.

The test:

```text
sum total[i in n, j in 4]: f64 = cast(f64, i)
```

is proven equivalent to:

```text
sum total[i in n]: f64 = 4.0 * cast(f64, i)
```

The two forms produce byte-identical canonical graphs and byte-identical native ELFs.

Required results:

```text
WHEX_RANK_N_AXIS_ERASURE=PASS
WHEX_RANK_N_MACHINE_CODE_ERASURE=PASS
```

A second-axis expression that actually depends on that axis remains Rank-N and is
rejected by the current rank-1 physical realizer.

Required result:

```text
WHEX_RANK_N_NO_FAKE_FLATTEN=PASS
```

This is deliberate: early flattening into a nested sequential loop is forbidden.

## Effect contract

The semantic vocabulary includes pure/local_state/region_write/shared_state/atomic/
io/device/external. Only pure has a completed native WHEX realization in 1.1.0.

An `effect io parallel` region is rejected during semantic planning.

Required result:

```text
WHEX_EFFECT_NO_HIDDEN_SERIALIZATION=PASS
```

No lock, central queue, general-lane retry, or scalar implementation is substituted.

## Inherited true-parallel gates

The following constituent release gates were rerun on the 1.1.0 tree and passed:

```text
WHEX_SURFACE_ERASURE=PASS
WHEX_CANONICAL_IR_IDENTICAL=PASS
WHEX_MACHINE_CODE_IDENTICAL=PASS
WHEX_MULTILINGUAL=PASS
WHEX_AUTO_REPAIR=PASS
WHEX_EXTENSION_ISOLATION=PASS

AVX512_RESOURCE_MODEL=PASS
TOPOLOGY_INDEX_CSE=PASS
COST_AWARE_STRENGTH_REDUCTION=PASS
TENSOR_HIDDEN_SCALAR_FALLBACK=0
RESOURCE_SCHEDULER_CONNECTED=PASS
SILICON_AUDIT_TRUTHFUL=PASS

COMPUTATION_ELIMINATION=PASS
ELIMINATION_PARALLEL_WIDTH_PRESERVED=PASS
ELIMINATION_NO_NEW_SYNC=PASS

COMMUNICATION_ELIMINATION=PASS
COMMUNICATION_PARALLEL_WIDTH_PRESERVED=PASS
COMMUNICATION_NO_GLOBAL_SYNC=PASS

RUNTIME_ERASURE=PASS
SERIAL_SPINE_ERASURE=PASS
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
GLOBAL_TASK_QUEUE=0
ASSEMBLY_ONLY_NATIVE_BUILD=PASS
NO_FOREIGN_HIGH_LEVEL_BACKEND=PASS
NO_DYNAMIC_RUNTIME_OR_INTERPRETER=PASS

OPERATOR_PERIODIC_DIFFERENTIAL_CASES=89
OPERATOR_SUBSPACE_1_0_11_FIX=PASS
OPERATOR_SPAN_MATURE_1_0_11=PASS

GENERALIZED_STRUCTURAL_ALGEBRA_1_0_12=PASS
WHEX_TRUE_PARALLEL_1_0_13=PASS
WHEX_ISA_CAPABILITY_GENERALIZATION_1_0_14=PASS
WHEX_VECTOR_REGION_PARTITION_1_0_15=PASS
WHEX_GENERAL_TRUE_PARALLEL_SEMANTICS_1_1_0=PASS
```

The legacy general-language 1.0.8 gate was also exercised in constituent form,
including mixed numeric semantics, topology recovery, FEM topology/native identity,
feature showcase execution, and conservative rejection of dynamic complex constructs.

## Monolithic harness note

The full `test_complete.sh` was started from the final tree. The current execution
sandbox exceeded its single-command wall-time window while repeating the heavy general
and FEM portions; no assertion failure was observed before termination. The component
gates above were therefore executed separately and are the authoritative 1.1.0 release
evidence. This document does not claim a monolithic completion marker that the sandbox
did not actually emit.

## Claim boundary

1.1.0 completes the general true-parallel **semantic foundation**, not every future
physical realization.

It does not claim:

- arbitrary used Rank-N native execution;
- mutable/shared-state WHEX runtime regions;
- I/O/device/external WHEX effects;
- runtime closure objects;
- runtime variants/objects/modules;
- a complete AVX2 256-bit tensor physical realizer.

Those features must extend the same Axis/Region/Effect/Dependency/Control machinery
and must satisfy correctness, erasure, parallelism, serial-introduction, and
non-regression gates before being admitted.
