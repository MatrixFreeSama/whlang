# Wheelchair 1.2.5

Wheelchair is an ahead-of-time, native, structure-first programming language project for general programming with HPC and simulation as primary design targets.

## Official release archive

```text
dist/Wheelchair-1.2.5.zip
```

SHA-256:

```text
775a6eed0e60aa2cca66a75a37e27422aab4851713f089c9e261af2686d91d4d
```

Historical release archives remain in `dist/`.

Wheelchair has two human-facing source styles over one structural/native core:

- **WH (`.wh`)** is the inference-heavy human surface.
- **WHEX (`.whex`)** is the explicit expert surface.

For shared mature semantics, both surfaces converge on the same structural core and, where the native realizer accepts the graph, the same native image.

```text
WH source                 WHEX source
   |                          |
   | structural recovery      | explicit structure
   v                          v
        Unified Structural Core
                 |
                 | proof + erasure + topology lowering
                 v
          Native x86-64 ELF
```

Wheelchair does not silently rebuild unsupported structural programs as scalar fallback, a hidden global task queue, or a conventional sequential execution spine.

The central rule is:

```text
No dependency edge = no synchronization edge.
```

## 1.2.5: Shared Dependency Episode Physicalization

1.2.5 extends the mature native optimizer from strong single-field episodes toward high-pressure multi-field and multi-channel graphs.

The optimizer does not inspect workload or physics names. It classifies the canonical graph from structural load pressure and dependency topology.

Release witnesses:

```text
Newton/Jv             5 distinct structural loads -> frozen 1.2.4 recipe
global stiffness      6 distinct structural loads -> frozen 1.2.4 recipe
two-field decoupled  11 distinct structural loads -> Shared Dependency Episode wide recipe
two-field coupled    12 distinct structural loads -> Shared Dependency Episode wide recipe
```

Low-pressure mature programs therefore keep the exact 1.2.4 physical recipe. The release gates require native byte identity for Newton/Jv and global stiffness at 1, 2, and 4 executors.

High-pressure graphs may select the wide recipe during AOT compilation. There is no runtime recipe selector.

### Safe AVX-512 ownership

The released wide recipe uses:

```text
ZMM16..ZMM29  shared persistent dependency / CSE ownership
ZMM30..ZMM31  immutable resident constants
ZMM12..ZMM15  runtime-reserved and protected
```

An experimental design that borrowed runtime-reserved registers was rejected after the numerical gate detected corruption. The released design never crosses that ABI boundary.

### Tolerant literal reciprocal erasure

For tolerant FP only, a finite non-zero binary64 literal divisor whose rounded reciprocal is normal may use:

```text
x / c -> x * round_f64(1 / c)
```

The reciprocal is constructed during AOT compilation with canonical `MXCSR=0x1f80`; the host MXCSR is restored afterward.

Strict mode, zero/non-finite divisors, and subnormal-reciprocal cases retain the existing proved vector-division recipe. No scalar fallback is introduced.

### Machine-shape result

For the coupled two-field witness:

```text
1.2.4 hot instructions: 491
1.2.5 hot instructions: 297
1.2.4 VDIVPD: 26
1.2.5 VDIVPD: 0
1.2.5 reachable generated hot CALL edges: 0
```

## Formal multi-host authority

Authority workflow:

```text
Validate Shared Dependency Episode 1.2.5
run 33902157205
```

Two AMD EPYC 9V74 AVX-512-qualified hosts completed the authority suite; no qualified host failed.

Each host compared exact Wheelchair 1.2.4, Wheelchair 1.2.5, and matched Expert C AVX-512 across:

```text
decoupled and coupled two-field witnesses
N = 10,000,000 and 100,000,000
executors = 1, 2, 4
3 warmups
11 shuffled/interleaved measured runs
```

The predeclared release threshold required both median and geometric-mean 1.2.4 -> 1.2.5 speedup to be at least 1.50x.

| Host | Median 1.2.4 -> 1.2.5 | Geomean 1.2.4 -> 1.2.5 | Geomean 1.2.5 / Expert C |
|---|---:|---:|---:|
| EPYC 9V74 slot 2 | **2.4486x** | **2.4478x** | 1.3443x |
| EPYC 9V74 slot 3 | **2.4508x** | **2.4480x** | 1.3445x |

Every tested 1.2.4/1.2.5 two-field checksum was bit-identical.

Expert C remained faster in aggregate on these AMD hosts by about 1.34x geometrically. The 1.2.5 claim is a large general multi-field recovery, not a general C-performance victory.

Full release evidence:

```text
RELEASE_PROOF_1_2_5.md
RELEASE_GATES_1_2_5.txt
MATURE_1_2_5_PROOF.md
SHARED_DEPENDENCY_EPISODE_CHARTER_1_2_5.md
```

## Preserved technical peaks

1.2.5 retains and gates earlier mature layers:

- **1.2.1** Interior Periodic Composition Erasure;
- **1.2.2** proof-gated Rank-N Cartesian-product physicalization;
- **1.2.3** Sparse Causal Expansion;
- **1.2.4** Product-Subtract contraction and Vector Reduction Residency.

The release also preserves the AOT-only native sovereignty contract, zero scalar fallback, zero workload-name dispatch, and the no-hidden-serial rules.

## Platform

The current native toolchain targets Linux x86-64.

Requirements:

- Python 3 for human-facing AOT source processing and compile-time proof;
- GNU `as`, `ld`, `readelf`, and related binutils;
- POSIX shell;
- AVX-512F-class capability for the current 512-bit structural tensor realizer.

The emitted native program does not execute through Python, C, C++, LLVM, or a JIT.

AVX2 exists in the capability model, but 1.2.5 does not claim a complete 256-bit structural tensor backend. Unsupported hardware/graphs reject instead of silently becoming scalar tensor code.

## Build

From the extracted release directory:

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

With four executors:

```bash
./wheelchairc program.wh -o program --executors 4
```

## Compile WHEX

```bash
./whexc program.whex -o program
```

## Inspect structural proof

```bash
./wheelchairc program.wh -o program --semantic-plan plan.json
```

The useful questions are not only what syntax was written, but:

- which dependencies are real;
- which objects were erased before runtime;
- which axes survived;
- which regions are independent;
- which physical recipe was selected;
- whether scalar fallback, runtime dispatch, synthetic synchronization, or central control appeared.

## Structural execution rules

A WH `for` does not promise a serial machine loop. If the points are independent, the structural object is an axis map and may be realized using AVX-512 lanes, masked vector tails, executor regions, boundary/interior specialization, or a Shared Dependency Episode.

A scalar final reduction value does not imply a scalar execution history. Reduction is represented as a dependency topology.

Structural predicates may lower to select/dataflow structure rather than a central dispatcher.

Arbitrary dynamic `while` is not silently converted into a conventional serial backedge. Unsupported recurrence/control topology rejects until a genuine structural realization exists.

## Release philosophy

A generic optimization must satisfy:

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

Wheelchair 1.2.5 is an active research compiler/language project. It does not claim every systems-language feature is complete.

In particular:

- a complete AVX2 structural backend is not claimed;
- arbitrary unsupported topology may reject;
- arbitrary dynamic `while` has no hidden serial fallback;
- general-language memory safety is not formally claimed as complete;
- the 1.2.5 authority is CPU/AVX-512 evidence, not a universal ranking across every device, backend, or workload.

The final execution authority is the emitted machine code, not the appearance of the source syntax.
