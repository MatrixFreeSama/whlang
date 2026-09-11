# Wheelchair 1.2.8 Release Notes

Wheelchair 1.2.8 matures the generic `native256` physical shape into a clean normal-build authority for admitted structural tensor programs on AVX2-class x86-64 hosts.

## Native256 maturity

`native256` is a true four-lane AVX2/YMM realization. It is not a scalar fallback, an AVX-512 wrapper, or a runtime-selected emergency route.

Release gates require:

```text
NATIVE256_VECTOR_WIDTH=4
NATIVE256_AVX2_YMM_ONLY=PASS
NATIVE256_RUNTIME_SELECTOR=0
NATIVE256_SCALAR_FALLBACK=0
NATIVE256_WORKLOAD_SPECIALIZATION=0
NATIVE256_GENERATED_WORKLOAD_BLIND=PASS
```

The final emitted executable segments are audited for YMM use and for absence of ZMM and AVX-512 mask-register state.

## Finite-register maturation

The AVX2 physicalizer now treats the 16-register YMM file as a first-class physical constraint rather than pretending the AVX-512 register file still exists.

General compiler transformations include:

- one-temporary exact synthesized i64 multiply;
- one-temporary signed i64-to-f64 conversion support;
- whole-YMM live-range fracture for complex binary siblings;
- whole-YMM live-range fracture for boundary selects;
- whole-YMM live-range fracture for tolerant accumulators and scaled/FMA leaves;
- zero scalar-lane spill paths;
- no runtime profitability selector.

The stack spill unit is one complete 32-byte YMM value. It shortens physical live ranges without changing vector width or introducing per-lane scalar execution.

## Constant multiplication correctness

The `2^k ± 1` strength-reduction path now preserves the shift count in callee-saved compiler state across encoder helper calls.

This repairs a machine-register lifetime bug in which a caller-saved shift count could be overwritten by the physical source-register number. For example, the intended relation

```text
31*x = (x << 5) - x
```

could previously become

```text
63*x = (x << 6) - x
```

on a source carried by YMM6. The correction is structural and constant-value based; it has no workload-specific dispatch.

## Compiler-local fixup ledger

The immutable constant pool remains bounded at 512 distinct constants.

Constant-reference fixups are a different resource: one distinct constant may be referenced by many generated instructions. The old 512-reference ledger could therefore reject a valid high-pressure boundary expression even though the unique constant pool was not full.

1.2.8 sizes the compiler-local fixup ledger from the structural graph capacity:

```text
MAX_NODES = 65536
NATIVE256_FIXUP_CAP = MAX_NODES * 8 = 524288
NATIVE256_UNIQUE_CONSTANT_POOL_CAP = 512
```

This changes AOT bookkeeping capacity only. It adds no user-ELF runtime selector, global queue, scalar fallback, or workload route.

## Clean normal-build authority

All mature native256 transformations now run in the ordinary `build.sh` path. The release authority does not rely on a test-only second-stage physicalization or diagnostic relink.

Required markers include:

```text
NATIVE256_NORMAL_BUILD_PRESSURE_MATURITY=PASS
NATIVE256_NORMAL_BUILD_LIVERANGE_MATURITY=PASS
NATIVE256_POST_FINALIZE_BUILD_AUTHORITY=PASS
NATIVE256_NORMAL_BUILD_MATURITY_AUTHORITY=PASS
NATIVE256_SECOND_STAGE_DIAGNOSTIC_INJECTION=0
NATIVE256_SECOND_STAGE_RELINK=0
```

Compiler-only telemetry remains available as a development tool but is not injected into the release-authority compiler.

## Coupled high-pressure execution proof

The canonical coupled fluid-solid structural witness is compiled for AVX2 at executor counts 1, 2, and 4 and compared against the matched expert-C AVX2 reference.

Validated problem sizes:

```text
N = 4
N = 17
N = 100000
N = 10000000
```

For every size, Q1/Q2/Q4 pass the numeric gate. The N=4 coupled checksum is exactly:

```text
checksum_bits=0x3fb2acf007b0d71c
```

The N=17 comparisons differ only at approximately 1.11e-16 under the release metric; the other validated points are bit-equivalent under the reported checksum comparison.

## Preserved architecture contracts

1.2.8 does not weaken the earlier General Parallel Fabric or generic resource-profile contracts:

```text
ACTIVE_SPECIAL_PURPOSE_NATIVE_ROUTE=0
GENERAL_PARALLEL_GLOBAL_READY_QUEUE=0
GENERAL_PARALLEL_ROOT_SCHEDULER=0
GENERAL_PARALLEL_RUNTIME_COST_SELECTOR=0
GENERAL_PARALLEL_SERIAL_FALLBACK=0
```

The mature native-512 physical peaks remain protected. Native256 is an additional physical realization selected from ISA capability and structural resource requirements, not a replacement common denominator.

## Scope

Wheelchair remains an active research language/compiler. 1.2.8 claims mature native256 execution for the admitted structural tensor slice exercised by the release gates; it does not claim that every possible dynamic language construct has an AVX2 realization. Unsupported semantics must reject rather than silently scalarize.
