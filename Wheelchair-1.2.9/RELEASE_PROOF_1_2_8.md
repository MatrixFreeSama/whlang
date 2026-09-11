# Wheelchair 1.2.8 Release Proof

This document defines the evidence required to call the Native256 maturity work complete.

## Release authority

The release compiler is produced directly by:

```bash
./build.sh
```

No second-stage code generation, diagnostic injection, or relink is permitted in the release-authority path.

Required authority markers:

```text
WHEELCHAIR_BUILD=PASS
NATIVE256_NORMAL_BUILD_PRESSURE_MATURITY=PASS
NATIVE256_NORMAL_BUILD_LIVERANGE_MATURITY=PASS
NATIVE256_POST_FINALIZE_BUILD_AUTHORITY=PASS
NATIVE256_NORMAL_BUILD_MATURITY_AUTHORITY=PASS
NATIVE256_SECOND_STAGE_DIAGNOSTIC_INJECTION=0
NATIVE256_SECOND_STAGE_RELINK=0
```

## Physical ISA proof

For Q1, Q2 and Q4, the canonical coupled structural program must compile through the generic native physical selection to `native256` under an AVX2 ISA ceiling.

The executable PT_LOAD code is disassembled. The gate requires:

```text
NATIVE256_HIGH_PRESSURE_COUPLED_COMPILE=PASS
NATIVE256_HIGH_PRESSURE_AVX2_YMM_ONLY=PASS
```

The executable code must contain YMM operations and must contain no ZMM register or AVX-512 mask-register execution state.

## Numeric proof

The generated Wheelchair ELF is compared against the matched expert-C AVX2 reference for:

```text
N = 4, 17, 100000, 10000000
Q = 1, 2, 4
```

All twelve combinations must satisfy the release numeric gate.

Canonical N=4 coupled result:

```text
checksum_bits=0x3fb2acf007b0d71c
```

Required marker:

```text
NATIVE256_HIGH_PRESSURE_COUPLED_EXECUTION=PASS
```

## Structural pressure proof

The diagnostic structural ladder covers increasingly difficult generic expression classes, including:

- affine cast;
- power-of-two modulo cast;
- scaled and shifted fields;
- periodic field access;
- weighted periodic operators;
- separate fluid-like and solid-like operator structures;
- two independent operators;
- coupling delta;
- decoupled full graph;
- coupled full graph.

These cases are diagnostic witnesses only. Their names do not enter compiler routing or generated physicalizers.

## Workload-blindness proof

The actual generated native256 assembly units entering GNU `as` are scanned for workload identity leakage.

Required marker:

```text
NATIVE256_GENERATED_WORKLOAD_BLIND=PASS
```

The release also requires:

```text
NATIVE256_MATURE_SPECIAL_PURPOSE_ROUTE=0
NATIVE256_RUNTIME_SELECTOR=0
NATIVE256_SCALAR_FALLBACK=0
```

## Compiler-resource proof

The unique immutable constant pool and the constant-reference fixup ledger are intentionally separate resources.

```text
NATIVE256_UNIQUE_CONSTANT_POOL_CAP=512
NATIVE256_FIXUP_LEDGER=STRUCTURAL
NATIVE256_FIXUP_LEDGER_SIZING=PASS
```

The fixup ledger is sized from `MAX_NODES * 8`, currently 524288 entries for `MAX_NODES=65536`.

Whole-vector spill and live-range fracture gates require:

```text
NATIVE256_COMPLEX_SIBLING_LIVERANGE_FRACTURE=PASS
NATIVE256_BOUNDARY_SELECT_LIVERANGE_FRACTURE=PASS
NATIVE256_TOLERANT_ACCUMULATOR_LIVERANGE_FRACTURE=PASS
NATIVE256_TOLERANT_SCALED_LIVERANGE_FRACTURE=PASS
NATIVE256_VECTOR_SPILL_BYTES=32
NATIVE256_VECTOR_SPILL_SCALAR_LANES=0
```

## Regression boundary

The pre-existing native256 1.2.7 physicalizer gate remains mandatory:

```text
WHEELCHAIR_NATIVE256_1_2_7=PASS
```

The general causal execution fabric must retain:

```text
GENERAL_PARALLEL_GLOBAL_READY_QUEUE=0
GENERAL_PARALLEL_ROOT_SCHEDULER=0
GENERAL_PARALLEL_RUNTIME_COST_SELECTOR=0
GENERAL_PARALLEL_SERIAL_FALLBACK=0
ACTIVE_SPECIAL_PURPOSE_NATIVE_ROUTE=0
```

## Final seal

The release-validation workflow runs the maturity gate on three independent hosted x86-64 jobs. All jobs must complete successfully on the exact release commit.

The terminal software marker is:

```text
WHEELCHAIR_NATIVE256_MATURITY_1_2_8=PASS
```

A green workflow without this marker is not sufficient; the marker without green jobs is not sufficient. Both are required.
