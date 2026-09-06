# Wheelchair 1.2.8

Wheelchair is an ahead-of-time, native, structure-first programming language project for general programming with HPC and simulation as primary design targets.

Wheelchair 1.2.8 matures the generic **Native256** physical shape into a clean AVX2/YMM execution authority while preserving the earlier native-512 peaks and the schedulerless General Parallel Fabric.

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
                 | proof + erasure + causal topology
                 v
        General Parallel Semantics
                 |
                 | AOT physicalization
                 v
          Native x86-64 ELF
```

The central execution rule remains:

```text
No dependency edge = no synchronization edge.
```

Unsupported structure rejects rather than silently becoming a scalar fallback, a hidden global queue, a runtime profitability selector, or a conventional sequential spine.

## Release lineage

### 1.2.6: General Parallel Fabric

1.2.6 established the schedulerless sparse causal execution authority. Independent bindings remain independent, recurrence remains local, and source order is not permission to synthesize a runtime dependency.

Required architecture boundaries include:

```text
GENERAL_PARALLEL_GLOBAL_READY_QUEUE=0
GENERAL_PARALLEL_ROOT_SCHEDULER=0
GENERAL_PARALLEL_RUNTIME_COST_SELECTOR=0
GENERAL_PARALLEL_SERIAL_FALLBACK=0
ACTIVE_SPECIAL_PURPOSE_NATIVE_ROUTE=0
```

### 1.2.7: Multi-ISA physicalization

1.2.7 introduced generic physical vector shapes selected from structural requirements and ISA capability:

```text
native256
split512x256
native512
```

The physical-shape choice is AOT structural capability logic. It does not inspect workload names or runtime timing/profitability measurements.

### 1.2.8: Native256 maturity

1.2.8 turns `native256` into a mature four-lane AVX2/YMM physical realization for the admitted structural tensor slice.

It is not:

- a scalar fallback;
- an AVX-512 wrapper;
- a test-only backend;
- a runtime profitability route;
- a named-workload fast path.

Release gates require:

```text
NATIVE256_VECTOR_WIDTH=4
NATIVE256_AVX2_YMM_ONLY=PASS
NATIVE256_RUNTIME_SELECTOR=0
NATIVE256_SCALAR_FALLBACK=0
NATIVE256_WORKLOAD_SPECIALIZATION=0
NATIVE256_GENERATED_WORKLOAD_BLIND=PASS
```

## Finite-register native256 design

AVX2 exposes a much smaller physical vector register file than AVX-512. 1.2.8 treats that as a real physical constraint rather than pretending the wider register topology still exists.

The mature native256 compiler includes:

- one-temporary exact synthesized i64 multiply;
- one-temporary signed i64-to-f64 conversion support;
- whole-YMM live-range fracture for complex binary siblings;
- whole-YMM live-range fracture for boundary selects;
- whole-YMM live-range fracture for tolerant accumulators;
- whole-YMM live-range fracture for scaled/FMA leaves;
- no scalar-lane spill path.

A spill is one complete 32-byte YMM value. It shortens a physical live range without changing the semantic vector width or serializing individual lanes.

Required gates include:

```text
NATIVE256_COMPLEX_SIBLING_LIVERANGE_FRACTURE=PASS
NATIVE256_BOUNDARY_SELECT_LIVERANGE_FRACTURE=PASS
NATIVE256_TOLERANT_ACCUMULATOR_LIVERANGE_FRACTURE=PASS
NATIVE256_TOLERANT_SCALED_LIVERANGE_FRACTURE=PASS
NATIVE256_VECTOR_SPILL_BYTES=32
NATIVE256_VECTOR_SPILL_SCALAR_LANES=0
```

## Constant multiplication lifetime repair

The generic `2^k ± 1` strength-reduction path now preserves the shift count in callee-saved compiler state across encoder helper calls.

This fixes a low-level lifetime bug in which the intended relation

```text
31*x = (x << 5) - x
```

could become

```text
63*x = (x << 6) - x
```

when a helper reused caller-saved `ECX` and the physical source happened to be YMM6.

The correction is based only on the mathematical constant and machine-register lifetime. No workload identity is involved.

## Compiler-local constant reference ledger

The immutable constant pool and constant-reference fixups are deliberately separate resources.

The unique constant pool remains:

```text
NATIVE256_UNIQUE_CONSTANT_POOL_CAP=512
```

The fixup ledger tracks emitted references, so one constant may legitimately require many fixups. 1.2.8 sizes this compiler-only ledger from structural graph capacity:

```text
MAX_NODES = 65536
NATIVE256_FIXUP_CAP = MAX_NODES * 8 = 524288
```

Required gates:

```text
NATIVE256_FIXUP_LEDGER=STRUCTURAL
NATIVE256_FIXUP_LEDGER_SIZING=PASS
NATIVE256_FIXUP_RUNTIME_SELECTOR=0
NATIVE256_FIXUP_SCALAR_FALLBACK=0
NATIVE256_FIXUP_WORKLOAD_ROUTE=0
```

This bookkeeping never enters the user ELF as runtime control logic.

## Clean normal-build authority

All mature native256 transformations execute in the ordinary build path:

```bash
./build.sh
```

The release compiler does not rely on a CI-only second-stage code generation or diagnostic relink.

```text
NATIVE256_NORMAL_BUILD_PRESSURE_MATURITY=PASS
NATIVE256_NORMAL_BUILD_LIVERANGE_MATURITY=PASS
NATIVE256_POST_FINALIZE_BUILD_AUTHORITY=PASS
NATIVE256_NORMAL_BUILD_MATURITY_AUTHORITY=PASS
NATIVE256_SECOND_STAGE_DIAGNOSTIC_INJECTION=0
NATIVE256_SECOND_STAGE_RELINK=0
```

Compiler telemetry remains available for development, but it is outside the release-authority execution chain.

## Coupled high-pressure proof

The canonical coupled fluid-solid structural witness is compiled for AVX2 at executor counts 1, 2, and 4 and compared with the matched expert-C AVX2 reference.

Validated sizes:

```text
N = 4
N = 17
N = 100000
N = 10000000
```

Every Q1/Q2/Q4 combination passes the numeric gate. The canonical N=4 coupled checksum is:

```text
checksum_bits=0x3fb2acf007b0d71c
```

The release also disassembles executable PT_LOAD segments and requires real YMM execution with no ZMM or AVX-512 mask-register state:

```text
NATIVE256_HIGH_PRESSURE_COUPLED_COMPILE=PASS
NATIVE256_HIGH_PRESSURE_AVX2_YMM_ONLY=PASS
NATIVE256_HIGH_PRESSURE_COUPLED_EXECUTION=PASS
```

No new 1.2.8 performance-speed claim is inferred from this correctness gate. Performance claims remain bounded to separately measured benchmark evidence.

## Generic native resource profiles

The structural compiler continues to use generic AOT resource classes:

```text
base
wide
derived
```

The selector examines canonical structure and resource pressure. It does not inspect workload names, solver names, source paths, benchmark identity, runtime timing, or profitability.

The mature native-512 peaks remain protected. Native256 is an additional physical realization rather than a lowest-common-denominator replacement.

## Platform

Current native target: Linux x86-64.

Build-time requirements:

- Python 3 for AOT parsing, proof, and source generation;
- GNU `as`, `ld`, `readelf`, `objcopy`, and related binutils;
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

With four execution slots:

```bash
./wheelchairc program.wh -o program --executors 4
```

## Compile WHEX

```bash
./whexc program.whex -o program
```

To audit a physical ISA ceiling explicitly:

```bash
./whexc program.whex -o program --isa-limit avx2
```

## Inspect structural proof

```bash
./wheelchairc program.wh -o program --semantic-plan plan.json
```

Useful questions include:

- which dependencies are real;
- which objects were erased before runtime;
- which regions or bindings are independent;
- which native resource and physical vector shape was selected;
- whether any synthetic ordering, runtime selector, scalar fallback, or central control appeared.

## Structural execution rules

A WH `for` does not promise a serial machine loop. If points are independent, the semantic object is an axis map and may be realized with vector lanes, masked tails, executor regions, compile-time partitioning, or another proven parallel mapping.

A scalar final reduction value does not imply a scalar execution history. Reduction is represented as dependency topology.

Structural predicates may lower to select/dataflow structure rather than a central dispatcher.

Arbitrary dynamic `while` is not silently converted into a conventional serial backedge. Unsupported recurrence/control topology rejects until a genuine structural realization exists.

## Release evidence

1.2.8 release evidence is documented in:

```text
RELEASE_NOTES_1_2_8.md
RELEASE_PROOF_1_2_8.md
RELEASE_GATES_1_2_8.txt
```

Historical release evidence remains in the repository for audit and comparison.

## Current maturity boundary

Wheelchair 1.2.8 remains an active research language/compiler. It does not claim that every systems-language feature or every possible dynamic topology has a native256 realization.

In particular:

- unsupported structural semantics may reject;
- arbitrary dynamic `while` has no hidden serial fallback;
- general-language memory safety is not formally claimed complete;
- performance evidence is bounded to the explicitly tested hosts and workloads;
- correctness of the 1.2.8 native256 maturity release is bounded by the published structural, ISA, numeric, and regression gates.

The final execution authority is the emitted machine code and proven causal topology, not the appearance of the source syntax.
