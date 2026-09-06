# Wheelchair 1.2.8

Wheelchair is an ahead-of-time, native, structure-first programming language project for general programming with HPC and simulation as primary design targets.

## Official release archive

[Download Wheelchair-1.2.8.zip](https://github.com/MatrixFreeSama/whlang/raw/refs/heads/main/dist/Wheelchair-1.2.8.zip) · [Archive SHA-256](https://github.com/MatrixFreeSama/whlang/blob/main/dist/Wheelchair-1.2.8.zip.sha256)

The archive retains the complete release source, benchmarks, assets, and validation workflows from commit `749b12d3a9bfcafa285548018c29c74e4155fc48`. Historical release archives remain in `dist/` in the repository and are not recursively embedded in this ZIP.

The extracted directory contains `worktree/`, `benchmarks/`, `assets/`, the validation workflows, and `release-evidence/`. The bundled `DIST_RELEASE.md` documents provenance, validation, and integrity checks. Use this archive or the `build-1.2.8-native256-maturity` branch for the 1.2.8 source. The archive's root `SHA256SUMS` covers the distribution; older checksum files under `worktree/` are preserved historical records.

Archive SHA-256:

```text
62fc059c4ff0055bbcc532ede7ecb2e940a876316be93f7a8b5d206d4aec1d78
```

[Distribution validation record](dist/Wheelchair-1.2.8.release.json)

## 1.2.8: Native256 maturity

Wheelchair 1.2.8 completes the normal-build AVX2/YMM realization for the admitted structural tensor slice. It retains the native-512 physical peaks and the schedulerless General Parallel Fabric.

The release adds general finite-register transformations, complete 32-byte vector spills, constant-multiply register-lifetime correctness, and a compiler-local fixup ledger sized independently from the 512-entry unique constant pool. These transformations are part of ordinary `build.sh`; release validation requires no diagnostic injection or second-stage relink.

The coupled structural witness passes the AVX2 execution gate at `N = 4, 17, 100000, 10000000` with `Q = 1, 2, 4`. The executable-code audit requires YMM operations and rejects ZMM/opmask state. Three jobs passed on the exact source commit in [release validation run 34017756455](https://github.com/MatrixFreeSama/whlang/actions/runs/34017756455).

See the [1.2.8 release notes](https://github.com/MatrixFreeSama/whlang/blob/749b12d3a9bfcafa285548018c29c74e4155fc48/worktree/RELEASE_NOTES_1_2_8.md) and [release proof](https://github.com/MatrixFreeSama/whlang/blob/749b12d3a9bfcafa285548018c29c74e4155fc48/worktree/RELEASE_PROOF_1_2_8.md). These are correctness and structural checks; no new speedup is inferred from them.

## 1.2.7: General Multi-ISA Physicalization

Wheelchair 1.2.7 makes physical vector width a general AOT property of the target silicon rather than a workload-specific routing decision.

The compiler combines two independent structural dimensions:

```text
native resource profile: base | wide | derived
physical vector shape:   native256 | split512x256 | native512
```

The resulting backend matrix is general:

```text
                    native256   split512x256   native512
base                    yes           yes           yes
wide                    yes           yes           yes
derived                 yes           yes           yes
```

No workload name, benchmark identity, source path, or physics domain is accepted as a backend selector.

The hard 1.2.7 invariants are:

```text
active special-purpose native route   = 0
active workload-specific route        = 0
active benchmark-specific route       = 0
source-path-specific route            = 0
runtime backend selector              = 0
runtime profitability selector        = 0
scalar fallback                       = 0
hidden serial spine                   = 0
```

Physical selection is AOT-only. The sovereign native `topologyc --silicon-audit` classifies the machine shape; the human-facing drivers bind the matching compiler image before the user program is emitted. Python is not the native execution authority.

Current x86-64 physical classes include:

```text
AVX2-only silicon        -> native256
AMD Zen 4 / Zen 4c       -> split512x256
native 512-bit datapath  -> native512
```

Vendor/family information is used only to identify physical datapath shape where ISA presence alone is insufficient. It never selects a workload recipe.

## Real native256 authority

1.2.7 contains a genuine AVX2/YMM tensor physicalizer, not a scalar compatibility mode.

The release gate compiles and executes a neutral structural vector program through the native256 backend, including non-multiple-of-four vector tails. The emitted executable segment is audited directly for YMM state and rejects leaked ZMM/opmask state.

The native256 route is available across the same generic resource classes:

```text
topologyc-native256
topologyc-wide-native256
topologyc-derived-native256
```

No runtime dispatcher is embedded in the emitted user program.

## General parallel execution

Wheelchair retains the schedulerless causal execution architecture introduced in 1.2.6.

The central rule remains:

```text
No dependency edge = no synchronization edge.
```

Independent bindings are represented by causal dependencies rather than source-order serialization. The general parallel fabric does not require a global runnable queue, global ready scan, root scheduler, work stealing, runtime cost selector, or hidden serial fallback.

True recurrence is a causal enclave rather than a global sequential spine.

WH and WHEX both attach the same general parallel semantics, while mature specialized native realizers may remain only when they are semantically equivalent and preserve or improve the earlier technical peak.

## WH and WHEX

Wheelchair has two human-facing source styles over one structural/native core:

- **WH (`.wh`)** is the inference-heavy conventional-looking surface.
- **WHEX (`.whex`)** is the explicit expert semantic surface.

For shared semantics, both converge on the same structural core and general physicalization rules.

```text
WH source                 WHEX source
   |                          |
   | inference                | explicit structure
   v                          v
        Unified Structural Core
                 |
                 | proof + erasure + causal lowering
                 v
      AOT native physicalization
                 |
                 v
          Native x86-64 ELF
```

Wheelchair does not silently rebuild unsupported structural programs as scalar fallback, a hidden global task queue, or a conventional sequential execution spine.

## Preserved technical peaks

1.2.7 retains the mature technical layers rather than flattening them during generalization:

- **1.2.1** Interior Periodic Composition Erasure;
- **1.2.2** proof-gated Rank-N Cartesian-product physicalization;
- **1.2.3** Sparse Causal Expansion;
- **1.2.4** Product-Subtract contraction and Vector Reduction Residency;
- **1.2.5** Shared Dependency Episode;
- **1.2.6** Schedulerless Sparse Causal Execution and General Parallel Fabric.

The qualified native512 gate preserves earlier emitted AVX-512 execution bytes where the host can execute that authority check.

Historical benchmark names remain in the repository only as evidence and regression witnesses. They are not routing keys.

## Platform

The current native toolchain targets Linux x86-64.

Requirements:

- Python 3 for human-facing AOT source processing and compile-time proof;
- GNU `as`, `ld`, `readelf`, `objdump`, and related binutils;
- POSIX shell;
- AVX2 or a supported wider x86 vector shape for structural tensor realization.

The emitted native program does not execute through Python, C, C++, LLVM, or a JIT.

Unsupported hardware or structural graphs reject instead of silently becoming scalar tensor code.

## Build

From the extracted release directory:

```bash
cd worktree
./build.sh
```

A successful build ends with:

```text
WHEELCHAIR_BUILD=PASS
```

## Compile WH

```bash
cd worktree
./wheelchairc program.wh -o program
```

With four executors:

```bash
./wheelchairc program.wh -o program --executors 4
```

## Compile WHEX

```bash
./whexc program.whex -o program
```

For an explicit AOT ISA ceiling during audit/testing:

```bash
./whexc program.whex -o program --isa-limit avx2
```

`--isa-limit` is a compile-time capability ceiling. It is not a runtime selector and does not authorize scalar fallback.

## Inspect structural proof

```bash
./wheelchairc program.wh -o program --semantic-plan plan.json
```

or:

```bash
./whexc program.whex -o program --semantic-plan plan.json
```

The semantic plan exposes questions that matter physically:

- which dependencies are real;
- which objects were erased before runtime;
- which axes survived;
- which regions are independent;
- which native resource class was derived;
- which physical vector shape was selected;
- whether scalar fallback, runtime dispatch, synthetic synchronization, or central control appeared.

## Structural execution rules

A WH `for` does not promise a serial machine loop. If points are independent, the structural object is an axis map and may be realized using the physical vector width available on the target, masked/vectorized tails, executor regions, sparse causal expansion, or another proved general contraction.

A scalar final reduction value does not imply a scalar execution history. Reduction is represented as a dependency topology.

Structural predicates may lower to select/dataflow structure rather than a central dispatcher.

Arbitrary dynamic `while` is not silently converted into a conventional serial backedge. Unsupported recurrence/control topology rejects until a genuine structural realization exists.

## Release philosophy

A general optimization must satisfy:

```text
Generality Gain
+ Measured Physical Gain
+ Existing Peak Preservation
```

The intended direction is:

```text
narrow technical peak
-> identify the structural property
-> promote it into general algebra
-> prove matching programs
-> preserve or improve physical realization
```

Workload-name dispatch is not an accepted substitute for generality.

## Current maturity boundary

Wheelchair 1.2.8 is an active research compiler/language project. It does not claim every systems-language feature is complete.

In particular:

- supported x86 physical shapes are explicitly gated rather than assumed universal;
- arbitrary unsupported topology may reject;
- arbitrary dynamic `while` has no hidden serial fallback;
- general-language memory safety is not formally claimed as complete;
- current authority is CPU/x86-64 evidence, not a universal ranking across every device or workload.

The final execution authority is the emitted machine code, not the appearance of the source syntax.
