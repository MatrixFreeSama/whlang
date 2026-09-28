# Wheelchair 1.3.102

![Build](https://img.shields.io/badge/build-27%2F27%20PASS-brightgreen) ![Release](https://img.shields.io/badge/release-1.3.102-blue)

Wheelchair is an HPC- and simulation-first general-purpose AOT language built around Rank-N semantics, matrix-free execution, ValueFacts, StateFacts, AddressFacts, RegionFacts, CoordinateFacts, GroupFact, Physical Reality, Traffic Reality, Silicon Domain Graphs, and Physical DAG execution.

The objective is not occupancy. It is convergence of real physical work toward the mathematical-physical lower bound:

```text
physical work / mathematical-physical lower bound -> 1
```

Idle silicon is valid whenever another materialization costs more than the remaining necessary work.


## 1.3.102: execution admission becomes an invocation fact

Execution expansion no longer treats compiler-host CPU width as permanent image authority. At launch, Wheelchair reads the invocation's admitted affinity domain once; AOT static placement may only intersect that domain, never widen it. Tensor and Field expose arbitrary-cardinality ownership without the old power-of-two launch frontier, while General exposes completion-local ready siblings without adding a global ready queue, worker pool or work stealing.

Strict Tensor arithmetic is now independent of execution cardinality: ownership may change across 1/2/3/4/5 admitted CPUs, but the canonical pairwise reduction tree does not. Tolerance retains its explicit permission to condense arithmetic across ownership regions.

On the Cross-Axis diagnostic, correcting a 5-way compiled admission running inside a 4-CPU invocation raised observed slot occupancy from about **84% to 94%** and cut an intermediate candidate from about **823.7 ms to 751.0 ms** before the final Strict canonical-tree repair. Final Tolerance A/B against 1.3.101 measured about **1.054x** in a five-round paired run. On the low-arithmetic high-entropy permutation probe, a fresh three-round Strict check measured about **71.1 ms** for Wheelchair 1.3.102 versus **181.8 ms C** and **216.9 ms Fortran**, with bit-identical checksums in that run.

No idle-CPU query, workload matcher, source kernel, JIT path, runtime scheduler, worker pool, second Tensor IR, or DSL execution surface is added.

## 1.3.101: fact identity and tolerance realization age into one path

Scaled `CoordinateFact` allocation no longer lets the physical ZMM allocator overwrite the logical fact-table slot. The repair restores the existing ownership pool instead of adding another carrier family. Separately, Tolerance mode now consumes its already-declared permission for division by a finite normal compile-time literal: one reciprocal is formed at AOT time and the existing multiply/FMA path is emitted. Strict never enters this relation and preserves its original rounding boundaries.

On the same 100%-connected `8192 x 127 x 127` Dense Permuted All-Pairs probe, 31 paired four-core Strict rounds show a conservative paired-ratio median of **1.005x** (medians 249.973 -> 243.187 ms). Twenty-five paired Tolerance rounds improve 231.083 -> 221.466 ms with a paired-ratio median of **1.084x**. Single-core medians improve 749.714 -> 740.505 ms in Strict and 757.966 -> 681.198 ms in Tolerance. The Tolerance image's six `vdivpd` instructions fall to zero.

No workload matcher, `fast-math` bundle, source kernel, JIT path, runtime radix selector, worker model, or second Tensor IR is added.

## 1.3.100: mixed-radix CoordinateFacts become packet-persistent

The non-power-of-two coordinate path now keeps a single static mixed-radix carry recurrence across vector packets. Finite digits advance by packet width and exact wrap; outer digits consume the carry fact, and a live quotient reuses the already-owned residue wrap instead of rebuilding division from the physical root. This removes repeated integer reciprocal work without adding a workload matcher, runtime radix selector, alternate tensor IR, or parallel-language mechanism.

On the same 100%-connected `8192 x 127 x 127` Dense Permuted All-Pairs probe, a 21-round four-core Strict A/B improves the median from **267.034 ms** in 1.3.99 to **243.331 ms** in the 1.3.100 candidate (**1.097x**). Fast A/B improves **295.857 ms -> 265.949 ms** (**1.112x**). Generated hot code falls from **5497 B to 5249 B**; static `vpmuludq` count falls **84 -> 75** and ZMM moves **172 -> 153**. Sampled Strict outputs remain bit-identical.

## 1.3.99: mixed-radix CoordinateFacts stop rebuilding coordinates

Tensor/Topology lowering now carries non-power-of-two static coordinates as the same kind of persistent physical fact already used by dense Rank-N execution. Constant `div/mod` in a compile-time-proven `<2^32` domain is realized with exact integer reciprocal-high arithmetic and one correction; the former int-to-float reciprocal round trip disappears from that domain. Literal-scaled coordinates share the existing scaled CoordinateFact ownership table instead of receiving a workload-specific optimizer.

On the dense 100%-connected `8192 x 127 x 127` permuted all-pairs probe, 9 interleaved four-core rounds improve Strict from **641.747 ms** in 1.3.98 to **259.110 ms** in 1.3.99 (**2.477x**, **59.6%** lower wall time), and Fast from **660.481 ms** to **257.937 ms** (**2.561x**, **60.9%** lower wall time). Same-run controls measure 222.339/208.940 ms for C Strict/Fast and 230.461/215.541 ms for Fortran Strict/Fast. The repair changes coordinate materialization, not source semantics; sampled Strict checksums remain bit-identical to 1.3.98.

No benchmark matcher, source kernel, worker model, runtime radix selector, second Tensor IR, or DSL execution surface is added.

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

The current release gate contains **27 tests**. Production authority remains under `compiler/`, `runtime/`, `surface/`, `tools/`, `build.sh`, and generated `bin/` executables. `devtrash/` contains regression, benchmark, historical, and archaeological material only.

See `ARCHITECTURE_AGING_1_3_102.md`, `PERFORMANCE_1_3_102.md`, `TESTING_1_3_102.md`, `PURE_ASSEMBLY_RELEASE_PROOF_1_3_102.md`, `RELEASE_SURFACE_CONVERGENCE_1_3_102.md`, and `WHEELCHAIR_CHARTER_1_3_102.md`.
