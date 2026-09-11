# Wheelchair 1.2.0 Maturation Proof

## Release thesis

1.2.0 makes WH and WHEX equivalent source surfaces for the currently mature WHEX semantic set without changing WHEX or the native topology backend.

WH is the inference-heavy/familiar surface. WHEX is the explicit structural surface. When they express the same semantics:

```text
Canonical(WH) == Canonical(WHEX)
```

and, whenever the current native realizer accepts that graph:

```text
NativeELF(WH) == NativeELF(WHEX)
```

## WHEX byte freeze

The following 1.1.0 implementation remains byte-identical in 1.2.0:

- `surface/wh_surface.py`
- `surface/whex_surface.py`
- `surface/whex_semantics.py`
- `whexc`, `whexc.py`
- all compiler sources used by general/tensor native lowering
- all general/tensor runtime sources

The authoritative hashes are stored in `tests/WHEX_FROZEN_1_1_0_SHA256.txt` and are checked by `test_wh_equivalence_120.sh`.

Representative WHEX 1.1.0 canonical and native hashes are also frozen. The release gate reports:

```text
WHEX_1_1_0_SOURCE_FREEZE=PASS
WHEX_1_1_0_CANONICAL_FREEZE=PASS
WHEX_1_1_0_NATIVE_FREEZE=PASS
```

## WH surface equivalence

The independent `surface/wh_structural.py` layer adds familiar WH skins without modifying WHEX.

Current accepted WHEX test/example corpus when interpreted through the WH structural surface:

```text
WH_ACCEPTS_WHEX_CANONICAL_CASES=26
WH_MATCHES_WHEX_EXPLICIT_REJECTIONS=1
```

Every accepted case produces byte-identical canonical core.

Explicit WH/WHEX paired examples cover:

- pure generic function + compile-time record + region/effect/parallel;
- familiar WH `for` map and `+=` reduction;
- familiar WH `if { } else { }` -> canonical `select`;
- Rank-N axis erasure;
- independent region dependency topology.

Release result:

```text
WH_WHEX_CANONICAL_EQUIVALENCE=PASS
WH_STRUCTURAL_MULTILINGUAL_CANONICAL=PASS
```

Native-capable paired examples are full ELF byte matches:

```text
semantic abstraction:
2492f60682b80fd40d65d8c71cb120efe89a98b0b71d08bb1e8dc67db9315c59

Rank-N axis erasure:
1c71eb04b8a9d2a36d8024a5043dc10239e03f9b11dcee86cbd32ee15f9c1a3d

independent regions:
0982d36b2947c48ed297f482ebb5f4ae6506dde6bbb7d1070c97d6f1d1f31974
```

For each pair, the WH and WHEX hashes are identical.

## No fake imperative cost

WH `for` is an axis-map/reduction spelling, not a runtime loop object.
WH `if` is predicate/dataflow selection, not a runtime dispatcher.
WH `+=` in structural `for` is a sum-reduction declaration, not mutable scalar state.

The WH semantic report requires:

```text
runtime_loop_objects = 0
runtime_if_dispatchers = 0
runtime_surface_objects = 0
imperative_syntax_implies_serial_execution = false
```

and inherits the WHEX Serial-Introduction Report:

```text
new_serial_backedges = 0
new_global_barriers = 0
new_central_loops = 0
new_scalar_regions = 0
new_scalar_tails = 0
new_scalar_fallbacks = 0
new_global_queues = 0
new_ordered_dependencies = 0
```

Release result:

```text
WH_FAKE_FOR_RUNTIME_LOOP_OBJECTS=0
WH_FAKE_IF_RUNTIME_DISPATCHERS=0
WH_SERIAL_INTRODUCTION_REPORT_ZERO=PASS
WH_PARALLELISM_PRESERVATION_CONTRACT=PASS
```

## Dynamic while boundary

Dynamic WH `while` is recognized as control intent but is not yet admitted by the current unified structural native core. It explicitly rejects with status 65 and never retries the legacy general lane or emits a sequential backedge.

```text
WH_DYNAMIC_WHILE_NO_SERIAL_FALLBACK=PASS
WH_STRUCTURAL_NO_GENERAL_FALLBACK=PASS
```

This is deliberate. A future accepted `while` must first prove a recurrence, fixed-point, wavefront, scan, frontier, or other genuine dependency topology.

## Rank-N

WH inherits exactly the WHEX prove-and-erase policy. A mathematically irrelevant static axis is eliminated before physical realization; a genuinely used extra axis is not flattened to a serial nested loop.

```text
WH_RANK_N_PROVE_AND_ERASE=PASS
```

## Legacy WH non-regression

The existing WH general lane remains available. Final component testing passed:

```text
WHEELCHAIR_TESTS=PASS
GENERAL_MIXED_NUMERIC=PASS
GENERAL_MIXED_SELECT=PASS
GENERAL_F64_BINARY_RHS=PASS
GENERAL_F64_DIFFERENTIAL=PASS
GENERAL_SIGNED_TRAPS=PASS
GENERAL_FASTPATH_FALLBACK=PASS
GENERAL_EXECUTOR_NOT_SILENT=PASS
GENERAL_TOPOLOGY_RECOVERY=PASS
GENERAL_TOPOLOGY_MACHINE_CODE_EQUIVALENT=PASS
GENERAL_FEM_TOPOLOGY_MACHINE_CODE_EQUIVALENT=PASS
GENERAL_FEATURE_SHOWCASE=PASS
GENERAL_DYNAMIC_COMPLEX_CONSERVATIVE=PASS
```

The long general test was executed in two component runs because the container command window ended after the FEM gate; all remaining assertions were then run directly and passed. No failing assertion was ignored.

## Inherited native gates

The unchanged native backend was rechecked through the release gates:

```text
WHEX_SURFACE_ERASURE=PASS
WHEX_CANONICAL_IR_IDENTICAL=PASS
WHEX_MACHINE_CODE_IDENTICAL=PASS
WHEX_EXTENSION_ISOLATION=PASS

RUNTIME_ERASURE=PASS
SERIAL_SPINE_ERASURE=PASS
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
GLOBAL_TASK_QUEUE=0

COMPUTATION_ELIMINATION=PASS
ELIMINATION_PARALLEL_WIDTH_PRESERVED=PASS
COMMUNICATION_ELIMINATION=PASS
COMMUNICATION_NO_GLOBAL_SYNC=PASS

OPERATOR_PERIODIC_DIFFERENTIAL_CASES=89
OPERATOR_SPAN_MATURE_1_0_11=PASS
GENERALIZED_STRUCTURAL_ALGEBRA_1_0_12=PASS
WHEX_TRUE_PARALLEL_1_0_13=PASS
WHEX_ISA_CAPABILITY_GENERALIZATION_1_0_14=PASS
WHEX_VECTOR_REGION_PARTITION_1_0_15=PASS
WHEX_GENERAL_TRUE_PARALLEL_SEMANTICS_1_1_0=PASS
WH_WHEX_SURFACE_EQUIVALENCE_1_2_0=PASS
```

## Current claim boundary

1.2.0 completes WH/WHEX surface equivalence for the **currently mature WHEX semantic set**. It does not claim that arbitrary dynamic `while`, mutable/shared effects, I/O/device/external effects, arbitrary non-erasable Rank-N native execution, or a complete AVX2 tensor realizer already exist. Those remain explicit proof/rejection boundaries rather than hidden serial escape routes.
