# Wheelchair 1.3.98

![Build](https://img.shields.io/badge/build-26%2F26%20PASS-brightgreen) ![Release](https://img.shields.io/badge/release-1.3.98-blue)

Wheelchair is an HPC- and simulation-first general-purpose AOT language built around Rank-N semantics, matrix-free execution, ValueFacts, StateFacts, AddressFacts, RegionFacts, CoordinateFacts, GroupFact, Physical Reality, Traffic Reality, Silicon Domain Graphs, and Physical DAG execution.

The objective is not occupancy. It is convergence of real physical work toward the mathematical-physical lower bound:

```text
physical work / mathematical-physical lower bound -> 1
```

Idle silicon is valid whenever another materialization costs more than the remaining necessary work.


## 1.3.98: constant modulo joins one integer Physical Reality

General no longer abandons its register-native integer DAG when an exact `u64` expression ends in `% const`. Every nonzero compile-time divisor now uses one exact reciprocal relation. Powers of two have no mask compatibility branch, special admission rule, divisor table, runtime selector, workload route, or second backend.

In 21 interleaved 20:1 wait-slow rounds on the same host, 1.3.97 improves from 187.395 ms to **119.934 ms** in 1.3.98, a **1.5625x** throughput gain and **36.0%** lower wall time. The manually asynchronous controls measure 137.212 ms for C and 139.161 ms for Fortran. Existing FP General hot code for `mass3`, `chem6`, and `rigid7` remains byte-identical to 1.3.97.

## 1.3.97: StateFact generations can close onto one carrier authority

General now proves whether a complete resident FP state generation can keep one physical carrier identity across the timestep boundary after whole-episode CSE. Every next-state value must be safe to be born in its own old-state carrier after the final effective consumer, with Strict operation order unchanged. When the complete proof succeeds, the next-to-old transport layer disappears. When it fails, the existing disjoint generation realization is retained unchanged.

The choice is deliberately whole-generation, not a partial hybrid. There is no workload matcher, AMD/Intel route, update reordering backend, runtime allocator, source-visible parallel kernel, worker pool, or second General IR.

In 31 alternating 20M-step Strict rounds, `chem6` improves from 140.167 ms to **125.606 ms** (**1.1165x**) and all six scalar generation transports disappear. `mass3` and `rigid7` fail the complete fixed-point proof and keep 1.3.96 hot code byte-identical.

## 1.3.96: General scalar Physical Reality uses the real register file

General scalar FP now derives its carrier geometry from the compiler-wide ISA capability authority. A target exposing `ISA_CAP_WIDE_REGFILE` makes XMM16..31 ordinary carriers in the same Physical Reality; a narrower target retains the same 16-carrier realization. There is no AMD/Intel backend split, workload route, runtime allocator, source-visible parallel kernel, or second General IR.

The old source-order eight-constant/eight-CSE residency cliffs and the arbitrary two-temporary reserve are removed. Persistent CSE, immutable constants, state authorities and anonymous lifetimes now compete against the same physical carrier budget. Strict operation order and rounding points remain unchanged.

Same-host 20M-step Strict medians on the visible EPYC 9V74 execution set:

| workload | 1.3.95 | 1.3.96 | speedup | C Strict |
|---|---:|---:|---:|---:|
| mass3 | 149.417 ms | **118.921 ms** | **1.256x** | 110.943 ms |
| chem6 | 138.581 ms | **136.311 ms** | **1.017x** | 115.108 ms |
| rigid7 | 240.182 ms | **189.122 ms** | **1.270x** | 179.166 ms |

Raw alternating-run evidence is retained in `devtrash/benchmarks/general_scalar_physical_reality_1396/`. `chem6` deliberately remains a residual compiler probe rather than receiving a workload-specific scheduler.

## 1.3.94: spatial multiplicity and temporal quota are separate facts

A cgroup CPU quota is a time budget, not a proof that an affinity-visible execution context does not exist. 1.3.94 removes the old conversion of `cpu.max` into an integer worker ceiling:

```text
affinity set
    -> x86 execution multiplicity

cpu.max quota / period
    -> temporal budget

cache / NUMA identity
    -> placement and transport
```

All three remain Physical Reality facts. They no longer impersonate one another.

The old power-of-two expansion rule remains deleted. Five admitted contexts mean at most five execution leaves, never eight. There is still no worker pool, ready queue, work stealing, idle-CPU query, runtime silicon scheduler, source-visible parallel kernel, or benchmark-specific route.

## Same-host release A/B

| workload | 1.3.93 | 1.3.94 | speedup |
|---|---:|---:|---:|
| FSI 100M | 111.050 ms | **95.511 ms** | **1.163x** |
| lightweight Tensor 100M | 10.693 ms | **9.049 ms** | **1.182x** |
| dense Rank-3 | 27.886 ms | **23.352 ms** | **1.194x** |
| miniAMR 27-point | 24.160 ms | **19.784 ms** | **1.221x** |
| miniFE heat21 | 20.365 ms | **16.668 ms** | **1.222x** |
| CloverLeaf x-acceleration | 26.550 ms | **20.068 ms** | **1.323x** |

General `mass3 / chem6 / rigid7` remained continuity-level. Raw A/B data is retained in `devtrash/benchmarks/spatial_temporal_quota_1394/`.

## Silicon contract

The current contract is `wheelchair.silicon-reality/10`. It publishes `cpu_quota_usec` and `cpu_period_usec` directly. `execution_admission_capacity` follows the admitted affinity set. Cache-domain identity remains placement authority only.

x86 and reconfigurable fabric remain simultaneous Physical Reality domains, not mutually exclusive language targets. There is no `@fpga`, HLS kernel authority, fixed PE grid, fixed tile size, runtime device selector, or second fabric semantic IR. A real FPGA board bridge, RTL/place-and-route integration, and bitstream emitter are still absent, so no FPGA hardware speedup is claimed.

## Production toolchain

Production compiler/runtime authority remains handwritten x86-64 assembly and direct static ELF emission. The production build does not use C/C++, Rust, LLVM, MLIR, Python, a JIT, bytecode VM, HLS compiler, or FPGA kernel compiler.

```sh
./build.sh

bin/whexc INPUT.whex -o OUTPUT
bin/wheelchairc INPUT.wh -o OUTPUT
bin/topologyc INPUT.whex -o OUTPUT
bin/fieldc INPUT.json -o OUTPUT
```

## Release authority

The current release gate contains **26 tests**. Production authority remains under `compiler/`, `runtime/`, `surface/`, `tools/`, `build.sh`, and generated `bin/` executables. `devtrash/` contains regression, benchmark, historical, and archaeological material only.

See `ARCHITECTURE_AGING_1_3_98.md`, `PERFORMANCE_1_3_98.md`, `TESTING_1_3_98.md`, `PURE_ASSEMBLY_RELEASE_PROOF_1_3_98.md`, `RELEASE_SURFACE_CONVERGENCE_1_3_98.md`, and `WHEELCHAIR_CHARTER_1_3_98.md`.
