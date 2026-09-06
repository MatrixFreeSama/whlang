# Wheelchair 1.2.7

Wheelchair is an ahead-of-time, native, structure-first programming language project for general programming with HPC and simulation as primary design targets.

Version 1.2.7 promotes multi-ISA physicalization into the general compiler architecture. It does **not** add workload-specific backends. The compiler reasons about program structure and hardware capabilities, then emits a static native x86-64 ELF.

Wheelchair has two human-facing source styles over one structural/native core:

- **WH (`.wh`)** is the inference-heavy human surface.
- **WHEX (`.whex`)** is the explicit expert surface.

For shared semantics, both surfaces converge on the same structural core and the same physicalization rules.

```text
WH source                 WHEX source
   |                          |
   | structural recovery      | explicit structure
   v                          v
        Unified Structural Core
                 |
                 | proof + erasure + causal lowering
                 v
       General Native Physicalizer
                 |
                 v
          Native x86-64 ELF
```

The emitted program does not execute through Python, C, C++, LLVM, a JIT, or a bytecode VM.

The central execution rule remains:

```text
No dependency edge = no synchronization edge.
```

## 1.2.7: General Multi-ISA Physicalization

1.2.7 separates two compile-time dimensions that were previously entangled:

```text
Generic graph-resource class:
    base / wide / derived

Physical vector shape:
    native256 / split512x256 / native512
```

The compiler binds their Cartesian product during AOT compilation.

```text
                         native256   split512x256   native512
base                         yes           yes          yes
wide                         yes           yes          yes
derived                      yes           yes          yes
```

These are structural and physical classes, not benchmark identities.

### No workload-specific routing

The active 1.2.7 release requires all of the following to remain zero:

```text
workload-specific dispatch
benchmark-specific dispatch
source-path dispatch
runtime profitability selection
runtime backend selection
scalar fallback
hidden serial fallback
special-purpose native route
```

A source file is never routed because it contains a solver name, physics name, benchmark name, or known example.

Hardware vendor/family information may be used only to establish physical execution shape. It is not a semantic or workload routing key.

## Physical vector shapes

### `native256`

A first-class AVX2/YMM physicalizer with four binary64 lanes.

It includes vector realizations or vector syntheses for the capabilities required by the current structural tensor backend, including:

- four-lane floating-point and integer arithmetic;
- FMA where available;
- vector tail handling;
- vector predicate synthesis;
- 64-bit integer multiply synthesis;
- unsigned 64-bit minimum synthesis;
- integer/floating conversion synthesis;
- non-negative floating-to-unsigned truncation synthesis;
- cross-vector state;
- resident constants;
- vector reduction;
- resident reduction ABI;
- generic base, wide, and derived resource classes.

There is no scalar tensor fallback when a native256 proof fails. Unsupported structure rejects explicitly.

### `split512x256`

A 512-bit semantic vector episode may be scheduled over two 256-bit physical slices when that matches the audited machine shape.

This keeps semantic width and physical datapath width distinct:

```text
semantic vector width: 512 bits
physical datapath:     256 bits
physical slices:       2
```

The distinction changes AOT resource accounting. It does not create a runtime selector.

### `native512`

The mature AVX-512 physicalizer remains intact for qualified hardware.

1.2.7 does not flatten the mature 512-bit path into a lowest-common-denominator backend. The release gate preserves the qualified 1.2.6 emitted AVX-512 peak by byte identity.

## AOT backend matrix

The sovereign hardware authority is the native compiler itself:

```text
build/topologyc --silicon-audit
```

The WH/WHEX drivers read that native audit during compilation and bind one already-built compiler image.

Python may coordinate this build-time binding, but Python is not the native backend authority and never emits the user program machine code.

The generic compiler-image matrix is:

```text
native256:
    topologyc-native256
    topologyc-wide-native256
    topologyc-derived-native256

split512x256 / native512:
    topologyc
    topologyc-wide
    topologyc-derived
```

`--isa-limit` is an AOT capability ceiling for audit/testing. It is not a runtime switch. For example:

```bash
./whexc program.whex -o program --isa-limit avx2
```

selects the generic native256 physicalizer while still forbidding scalar fallback.

## General parallel execution

1.2.7 preserves the schedulerless causal and general parallel architecture introduced before the multi-ISA layer.

The native execution fabric continues to reject the conventional centralized scheduling spine:

```text
global ready queue           = 0
global ready scan            = 0
root scheduler               = 0
runtime cost selector        = 0
serial fallback              = 0
work stealing                = 0
global phase barrier         = 0 unless semantically necessary
```

Readiness emerges from declared causal dependencies. Completion propagates only through the relevant sparse neighborhood.

A true recurrence may form a causal enclave. It does not become a global sequential spine for otherwise independent work.

## Technical Peak Preservation Contract

Generalization is admitted only when earlier narrow technical peaks remain recoverable.

The release policy is:

```text
Generality Gain
+ Physical Validity
+ Existing Peak Preservation
```

The intended development direction is:

```text
narrow technical peak
-> identify the structural property
-> promote it into general algebra
-> prove matching programs
-> preserve or improve physical realization
```

Workload-name dispatch is not an accepted substitute for generality.

## Preserved mature layers

1.2.7 retains and gates earlier mature capabilities, including:

- Interior Periodic Composition Erasure;
- proof-gated Rank-N Cartesian-product physicalization;
- Sparse Causal Expansion;
- Product-Subtract contraction;
- Vector Reduction Residency;
- Shared Dependency Episode resource expansion;
- schedulerless sparse causal execution;
- general binding-level parallel physicalization;
- AOT-only native sovereignty;
- zero hidden scalar fallback.

Historical release evidence remains in the repository, including the 1.2.5 proof and release-gate documents and the 1.2.6 general-parallel/schedulerless gates.

## Release validation

The merged 1.2.7 release tree passed the full authority workflow:

```text
Validate Wheelchair 1.2.7 Multi ISA Physicalization
run: 34008687175
validated commit: a6c0635bbd04febaaccebf020f554c985f87dc59
result: PASS
```

The gate includes:

- static build of all base/wide/derived native256 compiler images;
- real AOT native256 compilation;
- real AVX2/YMM ELF execution;
- full-vector and partial-tail execution cases;
- executable-segment audit showing YMM realization without AVX-512 register state in the native256 witness;
- automatic physical-shape selection equal to the native silicon audit;
- synthetic Intel AVX2 / Intel AVX-512 / AMD Zen3 / Zen4 / Zen5 shape coverage;
- preservation of the 1.2.6 general parallel authority;
- preservation of the 1.2.6 schedulerless causal authority;
- qualified AVX-512 emitted-byte preservation;
- static proof that active workload-specific and benchmark-specific native routes are zero.

Formal 1.2.7 release gates:

```text
worktree/RELEASE_GATES_1_2_7.txt
worktree/GENERAL_MULTI_ISA_PHYSICALIZATION_1_2_7.md
```

## Platform

The current native toolchain targets Linux x86-64.

Build requirements:

- Python 3 for human-facing AOT source processing and compile-time proof/generation;
- GNU `as`, `ld`, `readelf`, `objdump`, and related binutils;
- POSIX shell;
- a supported AVX2 or AVX-512 physical vector shape for the current structural tensor realizer.

The generated user program is a static native ELF.

## Build

From the repository root:

```bash
cd worktree
./build.sh
```

A successful build ends with:

```text
WHEELCHAIR_BUILD=PASS
```

The build produces the generic native physicalizer matrix, including:

```text
build/topologyc
build/topologyc-wide
build/topologyc-derived
build/topologyc-native256
build/topologyc-wide-native256
build/topologyc-derived-native256
build/topology-parallel
```

## Compile WH

```bash
cd worktree
./wheelchairc.py program.wh -o program
```

With four executors:

```bash
./wheelchairc.py program.wh -o program --executors 4
```

With a compile-time AVX2 ceiling:

```bash
./wheelchairc.py program.wh -o program --isa-limit avx2
```

## Compile WHEX

```bash
cd worktree
./whexc.py program.whex -o program
```

With four executors:

```bash
./whexc.py program.whex -o program --executors 4
```

## Inspect semantic and physical proof

```bash
./wheelchairc.py program.wh -o program --semantic-plan plan.json
```

or:

```bash
./whexc.py program.whex -o program --semantic-plan plan.json
```

The plan exposes questions that source syntax alone cannot answer:

- which dependencies are real;
- which objects were erased before runtime;
- which axes survived;
- which regions are independent;
- which generic resource class was selected;
- which physical vector shape was selected;
- which compiler image was bound during AOT compilation;
- whether scalar fallback, runtime dispatch, synthetic synchronization, or central scheduling appeared.

## Structural execution rules

A WH `for` does not promise a serial machine loop. If points are independent, the structural object is an axis map and may be realized through vector lanes, executor regions, sparse causal dependencies, or other proved native structure.

A scalar final reduction value does not imply a scalar execution history. Reduction is represented as dependency topology and native vector/reduction structure.

Structural predicates may lower to select/dataflow structure rather than a central dispatcher.

Arbitrary dynamic `while` is not silently converted into a conventional serial backedge. Unsupported recurrence/control topology rejects until a genuine structural realization exists.

## Current maturity boundary

Wheelchair 1.2.7 is an active research compiler/language project. It does not claim every systems-language feature or every hardware backend is complete.

In particular:

- the current native authority is x86-64 CPU execution;
- supported structural tensor execution currently requires a proven native256, split512x256, or native512 shape;
- arbitrary unsupported topology may reject;
- arbitrary dynamic `while` has no hidden serial fallback;
- general-language memory safety is not formally claimed as complete;
- no universal performance victory over C, C++, Rust, Zig, or every specialized solver is claimed.

The final execution authority is the emitted machine code, not the appearance of the source syntax.

## Historical archives

Historical release archives, including the 1.2.5 packaged archive, remain under `dist/`. They are retained as historical artifacts and are not the 1.2.7 execution authority.
