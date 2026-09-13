# Wheelchair 1.3.6

Wheelchair is an **HPC- and scientific-simulation-first general-purpose language** built around matrix-free execution, Rank-N data semantics, AOT specialization, direct native code generation, and aggressive removal of unnecessary physical machine work.

The current release is **Wheelchair 1.3.6: Global Physical Reality Unification**.

## Latest release

[Download Wheelchair-1.3.6.zip](https://github.com/MatrixFreeSama/whlang/raw/refs/heads/main/dist/Wheelchair-1.3.6.zip) · [SHA-256 file](https://github.com/MatrixFreeSama/whlang/blob/main/dist/Wheelchair-1.3.6.zip.sha256)

Archive size: **4,220,745 bytes**

```text
SHA-256
99e30c7a4a9b9a8ec4049deda7341e3f0a571fa84feffd63e04ef599233ab25d
```

The release archive contains the complete 1.3.6 source tree, native compiler/runtime images, historical regression authority, release proofs, machine-code gates, and the self-checking manifest.

Release authority:

```text
WHEELCHAIR_1_3_6_RELEASE=PASS
```

## What Wheelchair is trying to do

Most compilers begin with a program and ask how to execute its instructions efficiently. Wheelchair tries to move the boundary earlier:

```text
problem structure
    -> semantic facts
    -> true dependency relations
    -> physical facts and lifetimes
    -> ISA-specific realization
    -> native machine code
```

The central rule is simple:

> Source structure is not a reason to preserve machine work. Only semantic, numerical, causal, and hardware necessity justify physical work.

That rule drives several long-lived design constraints:

- matrix-free execution wherever the problem does not require a materialized global matrix;
- Rank-N dataized semantics instead of forcing every problem into scalar control flow;
- AOT specialization rather than JIT specialization;
- direct native x86-64 emission rather than a C, LLVM, MLIR, or JIT production backend;
- strict and tolerant floating-point contracts as separate legal optimization domains;
- no work stealing;
- no global ready queue;
- no central runtime scheduler;
- no post-completion peer query;
- no destination-aware resource handoff;
- no hidden scalar fallback for protected Tensor/Field semantics.

WH and WHEX are two human-facing surfaces over the same underlying semantics. WH may present familiar-looking control syntax, while WHEX exposes the structural form more explicitly. They are not intended to describe two different execution models.

## 1.3.6: Global Physical Reality Unification

1.3.5 introduced **Physical Realization Uniqueness** in the hot Field/native256 path: if a still-valid physical fact had already been realized, the compiler should not pay for the same realization again merely because the source graph mentioned it again.

1.3.6 promotes that idea into a wider compile-time physical-fact system.

### Versioned PhysicalFact authority

The Field physicalizer now distinguishes several kinds of physical fact instead of treating them as one generic load or expression:

```text
AddressFact = where a value lives
LoadFact    = a value read from a particular memory version
ValueFact   = the resulting computational value
```

A store increments only the version of the field actually mutated. Address identity can remain valid while a previous LoadFact becomes invalid. This avoids both unsafe reuse and unnecessary global invalidation.

### Duplicate physical work is canonicalized

Exact duplicate regular addresses can map to one invocation-stable address authority. Generic exact-bit `f32` constants can share one persistent constant fact. Pure work may be reused while the corresponding authority is still valid and physically profitable to retain.

Wheelchair does **not** turn this into a global cache. Retain versus recompute remains a compile-time physical-cost decision. If keeping a cheap fact alive would create more pressure than rebuilding it later, the fact is allowed to die.

### Semantic width no longer equals register width

1.3.5 had a bounded three-output optimized supernode. 1.3.6 removes that semantic ceiling.

A legal cross-output supernode may cover the full supported Field output set. The current AVX2 realization consumes the graph in physical register windows, so a four-output case becomes:

```text
semantic supernode: 4 outputs
physical realization: 3 + 1 accumulator windows
```

The language-level structure is therefore no longer constrained by a hard-coded register-width constant.

### AVX-512 joins the direct fact path

AVX-512 now consumes the same class of physical facts instead of remaining a conservative side path. The 1.3.6 machine-code gate observes, on the canonical high-pressure graph:

```text
AVX-512 high ZMM references:       809
AVX-512 direct stack-memory FMAs:  648
AVX-512 tolerant FMA sites:       2041
AVX2 high YMM references:         1029
strict AVX-512 FMA sites:            0
```

This is important for correctness as well as speed. Strict FP still forbids contraction on the strict release graph, while tolerant FP may use the stronger direct realization when its declared numerical contract permits it.

### No runtime fact manager

Physical Reality is a compile-time contract, not a new runtime scheduler.

1.3.6 still forbids:

```text
runtime fact manager
runtime residency manager
runtime autotuning
work stealing
global ready queue
peer work acquisition
resource-recipient selection
workload-name specialization
benchmark-size specialization
```

The runtime executes the AOT physical plan. It is not asked to rediscover the plan while the program is running.

## 1.3.5 -> 1.3.6 same-host rematch

A post-release 41-round interleaved rematch was run on an **Intel Xeon Platinum 8573C** host with **5 visible vCPUs**, using the same 64^3 tolerant Field workload and one executor for both versions.

| ISA path | Wheelchair 1.3.5 median | Wheelchair 1.3.6 median | Ratio |
|---|---:|---:|---:|
| AVX2 / native256 | 20.738 ms | 20.196 ms | 1.027x |
| AVX-512 | 23.935 ms | **18.146 ms** | **1.319x** |

Interpretation:

- AVX2 is effectively near parity on this already heavily optimized three-output workload. It won 21 of 41 paired rounds, so the small median difference should not be presented as a broad AVX2 speedup claim.
- AVX-512 won 39 of 41 paired rounds. Its median execution time fell by about **24.2%**, corresponding to about **31.9% more throughput** on this workload.
- The fastest route available to 1.3.5 on this host was AVX2 at 20.738 ms. The fastest 1.3.6 route was AVX-512 at 18.146 ms, a best-path ratio of about **1.143x**.
- Compared outputs were byte-identical in this rematch.

These are workload- and host-specific measurements, not a universal language ranking. The important architectural result is that AVX-512 now receives the same PhysicalFact-oriented treatment that previously existed mainly on the AVX2 path.

## Language surface

A periodic Rank-N field kernel can be written directly in human source:

```text
program shift_z
strict

input nx: u64
input ny: u64
input nz: u64

input field a[
    x in nx periodic,
    y in ny periodic,
    z in nz periodic
]: f32

output field out[x in nx, y in ny, z in nz]: f32 =
    a[x,y,z+1]
```

The same underlying Field semantics can be reached from WH or WHEX. The canonical Field format remains:

```text
wheelchair.field/1
```

The native materialized-field storage ABI remains:

```text
WHFLD216
```

Supported Field-side capabilities include dynamic Rank-N extents, periodic boundaries, input/output/inout fields, UTF-8 identifiers, zero-runtime pure-function expansion, strict `f32` semantics, tolerant contracts, AVX2 and AVX-512 native physicalization, and multi-executor execution where the physical proof permits it.

## Compiler architecture

```text
WH / WHEX
   |
   +-> semantic / Rank-N structure
   |
   +-> compile-time Physical Reality contract
   |
   +-> versioned physical facts
   |      AddressFact
   |      LoadFact
   |      ValueFact
   |      exact-bit constants
   |
   +-> dependency and lifetime proof
   |
   +-> physical profitability
   |
   +-> ISA-specific realization
          scalar legality paths
          AVX2 / native256
          AVX-512
   |
   `-> static native ELF
```

The production path does not pass through C, LLVM, MLIR, or a JIT.

## Strict and tolerant floating point

Wheelchair deliberately keeps two different optimization authorities.

### Strict

Strict mode preserves the required arithmetic ordering and rounding structure. Physical identity may still remove redundant address formation or other bit-preserving work, but it does not grant permission to reassociate floating-point arithmetic or contract operations into FMA.

The 1.3.6 release gate requires:

```text
STRICT_FP_FMA_CONTRACTION=0
```

on the canonical strict graph.

### Tolerant

Tolerant mode may use legal reassociation, FMA realization, wider fact reuse, and tree-shaped reductions when those changes remain within the declared numerical contract.

Tolerant is not the default excuse for approximate arithmetic. It is a separate contract.

## Parallel and resource model

Wheelchair does not use work stealing as a hidden load-balancing layer.

A completed execution domain releases its own physical constraints and does not choose where the newly available silicon capacity should go next. The intended model is recipient-blind release:

```text
finish true local work
    -> publish only true causal results
    -> release local resources immediately
    -> do not query peers
    -> do not select a recipient
    -> do not search for more work
```

This rule exists to prevent a nominally parallel runtime from reintroducing global coordination or serial scheduling decisions behind the user's back.

## Build

```sh
./build.sh
```

The production build uses shell plus handwritten native assembly tooling. The release source tree does not require a Python compiler generator.

## Compile

General WH/WHEX:

```sh
./whexc program.whex -o program
./wheelchairc program.wh -o program
```

Explicit Tensor physicalization:

```sh
./topologyc program.whex -o program --executors 256
./topologyc-native256 program.whex -o program-avx2 --executors 256
```

Field:

```sh
./fieldc kernel.whex -o kernel --executors 256
./fieldc-native256 kernel.whex -o kernel-avx2 --executors 256
```

The current implementation accepts up to 256 requested executors, but reachable work may reduce the actual executor geometry. The number 256 is an implementation ceiling, not a language-semantic definition of parallelism.

## Release validation

Inside the 1.3.6 archive:

```sh
./test_global_physical_reality_136.sh
./test_release_native_136.sh
```

The 1.3.6 release authority requires, among other things:

```text
GLOBAL_PHYSICAL_REALITY contract shared by Field/Tensor/General AOT frontends
AddressFact / LoadFact / ValueFact separation
per-field version invalidation
exact duplicate address canonicalization
compile-time retain-vs-recompute authority
four-output optimized oracle
AVX2 high-register/direct-memory fact consumption
AVX-512 high-register/direct-memory fact consumption
strict FP zero FMA contraction
truthful irregular/padded gather fallback
NO runtime fact manager
NO runtime residency manager
NO runtime autotuner
NO global ready queue
NO work stealing
NO resource-recipient selector
complete Wheelchair 1.3.5 historical authority preserved
WHEELCHAIR_1_3_6_RELEASE=PASS
```

The release archive also contains:

```text
WHEELCHAIR_CHARTER_1_3_6.md
RELEASE_NOTES_1_3_6.md
RELEASE_GATES_1_3_6.txt
PURE_ASSEMBLY_RELEASE_PROOF_1_3_6.md
PERFORMANCE_1_3_6_GLOBAL_PHYSICAL_REALITY.md
RELEASE_TEST_LOG_1_3_6.txt
```

## Recent architecture progression

The current compiler line can be summarized as:

```text
1.3.3  Causal Physical Optimization
       Do not preserve machine work that is physically unprofitable.

1.3.4  Physical Regularity
       Once regular structure is proved, do not rediscover it at runtime.

1.3.5  Physical Realization Uniqueness
       Do not recreate a still-valid physical realization.

1.3.6  Global Physical Reality Unification
       Make versioned physical facts, lifetimes, and true dependency relations
       first-class AOT compiler authority across the current architecture.
```

## Claim boundary

Wheelchair is already an aggressive HPC compiler core, but this repository does not claim universal superiority over C, C++, Fortran, CUDA, Julia, Rust, Zig, or other mature HPC ecosystems.

Current strengths are concentrated in structure-aware numerical execution, matrix-free/Rank-N workloads, AOT physical specialization, direct ISA realization, elimination of redundant work, and explicit anti-serialization rules.

Mature HPC ecosystems still have much broader library coverage, tooling, platform support, GPU ecosystems, distributed-memory infrastructure, debuggers, profilers, and decades of production validation.

The project therefore treats benchmark wins as evidence about a specific compiler mechanism and workload, not as permission to erase those boundaries.
