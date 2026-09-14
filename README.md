# Wheelchair 1.3.25

Wheelchair is an HPC- and simulation-first general-purpose language built around matrix-free execution, Rank-N semantics, AOT compilation, direct x86-64 machine code, ValueFacts, Physical Reality, and Physical DAG execution.

## Latest release

**Wheelchair 1.3.25 — Release Surface Cleanup / Branch-Growth Firewall**

[Download Wheelchair-1.3.25.zip](https://github.com/MatrixFreeSama/whlang/raw/refs/heads/main/dist/Wheelchair-1.3.25.zip)

Archive size: **2,872,770 bytes**

```text
SHA-256
bbab5cc9f15f2a6e5f0ec8f46fdcad8468eecaf99d6adbf7f821c6669811bd39
```

1.3.25 deliberately keeps the production compiler/runtime machine code byte-identical to the final 1.3.24 release while reorganizing the release surface so old experiments cannot quietly regain production authority.

## Release structure

After extracting the ZIP:

```text
Wheelchair-1.3.25/
├── README.md
├── VERSION
├── SHA256SUMS
├── build.sh
├── RELEASE_NOTES_1_3_25.md
├── WHEELCHAIR_CHARTER_1_3_25.md
├── PURE_ASSEMBLY_RELEASE_PROOF_1_3_25.md
├── PERFORMANCE_1_3_25_RELEASE_SURFACE.md
├── PRODUCTION_BIN_SHA256_1_3_25.txt
├── bin/          # sole production executable authority
├── compiler/     # current compiler source authority
├── runtime/      # current runtime source authority
├── surface/      # current language/surface authority
├── tools/        # current production build helpers
└── devtrash/     # non-production tests, benchmarks, history and archaeology
```

`bin/` is the only supported location for production executables. Root-level executable duplicates are forbidden.

`devtrash/` has zero production authority. The release gate physically removes it during a clean production build to prove that `build.sh`, `compiler/`, `runtime/`, `surface/`, and production tools do not depend on archived code.

The permanent rule is:

> Historical evidence may remain in `devtrash/`; historical architecture may not regain production authority from there.

A useful old optimization must be re-expressed as a general capability of the existing ValueFact / Physical Reality / Physical DAG architecture before it can re-enter production source.

## Core architecture

Wheelchair remains:

- matrix-free by default;
- Rank-N oriented;
- AOT only;
- direct x86-64 native code;
- no C, LLVM, MLIR, or JIT production backend;
- WH human surface plus WHEX lower-level semantics;
- strict and tolerant floating-point contracts;
- AVX2 and AVX-512 Tensor/Field paths;
- no work stealing or central runtime scheduler;
- no workload-name optimization routes;
- no private solver/benchmark branches in production source.

The current optimization direction is to remove unnecessary physical work rather than accumulate special cases: repeated computation, state materialization, communication, value transport, predicate evaluation, and branch-shaped compatibility paths are reduced through the same general physical architecture.

## Build and run

```sh
./build.sh

bin/whexc INPUT.whex -o OUTPUT
bin/wheelchairc INPUT.wh -o OUTPUT
bin/topologyc INPUT.whex -o OUTPUT
bin/fieldc INPUT.json -o OUTPUT
```

`build/` is reproducible scratch output and is not part of the release authority.

## Performance status

1.3.25 intentionally carries forward the final 1.3.24 production binaries byte-for-byte. The 1.3.24 branch-extinction work measured, on its validation host, approximately:

- `chem6` 20M: **4.7% faster** than 1.3.23;
- `ring8` 10M: **5.3% faster**;
- FSI 100M whole-process: **5.6% faster**;
- FSI steady-state throughput: approximately **7.6% higher**.

These are host- and workload-specific measurements, not universal superiority claims.

## Repository policy

`main` is intentionally kept small. Full release trees belong inside versioned ZIP archives under `dist/`; they are not expanded into the repository root. Historical source trees, release proofs, regression suites, and benchmarks belong inside the release archive's `devtrash/` rather than growing new active branches in `main`.

Older release archives remain under `dist/` for reproducibility.
