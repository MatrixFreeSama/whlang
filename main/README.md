# Wheelchair 1.3.112

![Build](https://img.shields.io/badge/build-29%2F29%20PASS-brightgreen) ![Release](https://img.shields.io/badge/release-1.3.112-blue)

Wheelchair is an HPC- and simulation-first general-purpose AOT language built around Rank-N semantics, matrix-free execution, ValueFacts, StateFacts, AddressFacts, RegionFacts, CoordinateFacts, GroupFact, Physical Reality, Traffic Reality, Silicon Domain Graphs, and Physical DAG execution.

The objective is not occupancy. It is convergence of real physical work toward the mathematical-physical lower bound:

```text
physical work / mathematical-physical lower bound -> 1
```

Idle silicon is valid whenever another materialization costs more than the remaining necessary work.


## 1.3.112: tolerance becomes a proof bound, not a fast mode

For `P > 64`, the existing program-level `tolerance N` contract now reaches Rank-N mathematics as one conservative `ToleranceFact`. Basic `add/sub/mul/div` remain the same strict P-bit operations and still close through the single Strict/RNE authority. Tolerance changes only the stopping proof of convergent relations: `sqrt` uses its Newton update bound, `exp` and `log` use contracted series-tail bounds, and the shared `sin/cos` relation requires both alternating tails to fit a conservatively back-propagated budget before double-angle restoration. If a proof is unavailable, execution falls back to the existing strict convergence condition.

This is not `fast-math`: no precision is silently reduced, no primitive is reassociated, and no tolerant arithmetic backend or selector exists. The previously accepted parameterized type-local form `fpP ~(abs=...,rel=...)` is now rejected because General did not preserve that local error object; the release does not keep a syntax that silently means Strict. Program-level `tolerance N` is the single admitted high-precision tolerance authority in 1.3.112.

Against 1.3.111, whose high-precision tolerant programs were effectively strict, the retained fixed-CPU A/B at tolerance `1e-10` measures about **5.0x-5.6x** for 4096-bit `exp/log/sin/cos`, **12.6x-17.2x** at 8192 bits, and **31.1x-43.1x** at 16384 bits. `sqrt` improves more moderately, about **1.11x / 1.49x / 1.81x** at those precisions. A 240-case exact-rational validation grid has zero bound violations. A longer Strict recheck resolves the earlier short-run noise: representative 4096- and 16384-bit probes remain essentially at 1.3.111 speed while retaining bit-identical results.

## 1.3.111: high precision carries facts, not empty storage

The P>64 Rank-N path is physically older and smaller without adding another arithmetic family. Big/big division now keeps its base-2^32 recurrence in real u32 digits, reuses the quotient high-water fact at the existing StrictClose boundary, and no longer pays for zero-extended qword slots. The historical `512*N+4096` object envelope is gone: PrecisionFact plus the existing Fourier TypePhysicalFact geometry now determine the exact live add/mul/div span used by compiler temporaries, decimal ingress and advanced mathematics.

Direct big/big division improves by roughly 1.17x-1.34x over 1.3.110 in the measured 4096-262144-bit range. Experiments that were mathematically valid but physically regressive were removed rather than retained as alternate paths.

## 1.3.110: Field rank is a fact, not a file width

Field no longer has a semantic Rank-8 ceiling. `WHFLD217` carries one u64 RankFact followed by exactly `rank` extent and stride facts; Surface, canonical Field metadata, AddressFact deltas and runtime hot tables all derive their axis storage from that same invocation RankFact. The historical `FIELD_RUNTIME_RANK_CAP`, fixed 32-byte access delta, fixed `extent[8]/stride[8]`, and `r1..r8` runtime address/load/store families are gone.

Native512 and Native256 now consume one runtime-rank address relation. AVX-512 spare coordinate registers remain physical resources rather than a language width authority. Current release probes execute rank 9, 17 and 33 through the same path, while old `WHFLD216` files are rejected rather than translated. Padded/strided output remains truthful through the unified scatter relation.

A 1,048,576-element strict reduction shows no low-rank tax versus 1.3.109: sampled medians are about **1.039x** at rank 3 on Native512, **1.006x** at rank 3 on Native256, **0.999x** at rank 8 on Native512, and **1.018x** at rank 8 on Native256. These are small measurements, so the release claims structural convergence rather than a broad speedup. The separate signed-dword coordinate/span frontier remains explicit and is not disguised as a rank limit.

No old-format compatibility reader, rank selector, workload route, DSL parallel surface, JIT, scheduler, worker pool, or second Field backend is added.


## 1.3.109: local facts are not rediscovered globally

Rank-N physical aging continues without a second high-precision system. General division now carries geometry already implied by normalized `fpP` and quotient production instead of rescanning U/V/Q. Strict RNE carry-out closes directly from the carry fact rather than shifting the complete P-bit carrier again. Fourier twiddle construction starts from the exact unit value, and the shared `sin/cos` relation keeps disposable sign and exact powers of two local instead of cloning a complete ValueFact or performing an extra high-precision addition.

Seven obsolete carrier/geometry helper authorities are absent from the final General runtime. On the same `sin(fp8192)` generated probe, `.text` contracts from **16605 B to 16029 B (-3.47%)**. Wall-time probes are mostly neutral with low-single-digit movement in both directions, so this release makes no broad speedup claim; an experimentally shorter cross-span pointer-rotation realization was rejected after it increased cache/TLB work.

The current release remains one `fpP`, one Rank-N/PrecisionFact authority and one Strict/RNE closure. No named-width backend, local-float dialect, precision selector, algorithm-threshold tree, JIT, kernel offload, scheduler, worker pool, workload matcher or source-visible parallel mechanism is added.


## 1.3.108: advanced mathematics keeps local facts local

Rank-N advanced relations now stop inflating exact scalar series coefficients into full `fpP` ValueFacts. `exp`, `log`, and the shared `sin/cos` propagation authority consume one shared exact `rankn_fp_div_u64` relation; the quotient is closed through the same strict RNE authority used by the rest of Rank-N. Representation convergence likewise uses one bit-identical ValueFact-silence predicate instead of invoking full numerical ordering.

The compiler-side `fpP` constant/cast regression introduced by the earlier type-physicalization aging is repaired at its root: binding kind is stable local state across inference and Rank-N type materialization rather than a caller-saved register. Shared arithmetic zero identities also close centrally, so `sqrt(0)`, `exp(0)`, `log(1)`, `sin(0)`, and `cos(0)` no longer need or receive per-function compatibility branches.

Same-host whole-process A/B against unmodified 1.3.107 shows the intended high-precision scaling: at 4096 bits, `exp/log/sin/cos` improve about **3.39x / 3.40x / 5.27x / 5.66x**; at 8192 bits, about **4.08x / 4.81x / 9.74x / 11.32x**. `sqrt` remains essentially a control because its dominant relation is true big/big division rather than a scalar series quotient. Representative MPFR RNDN probes at 1024/4096/8192 bits are bit-identical to 1.3.107, so the speedup does not come from relaxing the existing numerical result.

No transcendental width selector, named-precision backend, `localfp` dialect, JIT, kernel offload, scheduler, worker pool, workload matcher, or second math backend is added.


## 1.3.107: Local-Strict becomes physical aging, not a new dialect

Rank-N add/sub now projects each canonical `fpP` operand directly into one operation-local guard/sticky carrier. The old `copy -> <<3 -> exponent shift -> sticky` sequence is gone from the production add/sub core. That carrier never escapes the semantic operation: the result still closes through the single strict normalization/RNE authority, so local representation does not defer rounding across later operations.

The old Local-Strict research prototypes are absorbed only at the level that survives architecture review. Fixed local cell widths, sparse/local alternate representations, and separate numerical modes are not imported. `fpP` remains the only source surface and `PrecisionFact(P)` remains the only semantic precision authority.

Pinned three-run medians versus unmodified 1.3.106 show add speedups of about **1.145x at 4096 bits**, **1.170x at 16384 bits**, **1.237x at 65536 bits**, **1.174x at 524288 bits**, and **1.140x at 1048576 bits**. Small widths improve only a few percent because fixed call overhead dominates. Multiplication and division receive no new algorithm family in this release and remain controls near their previous performance. Wheelchair still does not beat GMP overall in high-precision addition. Exact GMP oracles pass add/sub through 65536 bits and multiplication/RNE through 1048576 bits.

No local-float DSL, precision selector, schoolbook/Karatsuba/Toom threshold tree, JIT, kernel-offload surface, scheduler, worker pool, workload matcher, or source-visible parallel mechanism is added.


## 1.3.106: Rank-N physical work stops repeating itself

High precision keeps one arithmetic authority while redundant physical work is removed around it. Every `fpP` type now owns one AOT `TypePhysicalFact` containing precision and Fourier geometry; numeric ValueFacts no longer carry geometry, and the runtime Fourier planner is gone. Exponent alignment is one word+bit relocation, same-P copies are direct carrier clones, normalized zero tests are O(1), destination initialization occurs only at final RNE commit, and division drops redundant scratch clears.

Decimal ingress now accumulates source digits with the exact integer relation `D = 10D + digit` and normalizes only after the decimal sequence is complete. The old path invoked Rank-N Fourier multiplication for every decimal digit. In an fp4096 diagnostic with two roughly 900-digit inputs, whole-process median wall time falls from 102.55 ms in 1.3.105 to 0.407 ms in 1.3.106, about 252x. Direct arithmetic sees smaller but structural gains: add is about 1.24x to 1.46x faster across the sampled range, and small/mid-width multiplication reaches roughly 2x to 3x versus 1.3.105.

GMP is not globally defeated. Against GMP 6.3.0 `mpf`, the sampled 524288-bit multiplication point is about 1.15x faster, while neighboring 262144-bit and 1048576-bit points remain slower; add and division remain clear frontiers. An independent GMP integer oracle passes exact product/RNE checks from 65 through 1048576 bits. No algorithm threshold tree, named-width backend, JIT, workload route, scheduler, worker pool, or source-visible parallel mechanism is added.


## 1.3.105: Rank-N precision becomes a fact

Parameterized floating precision is no longer packed into the low 30 bits of a semantic type ID. `fpP` now interns one compact type identity while the actual `P` lives in an exact-sized u64 PrecisionFact trailer derived from the represented program. The generated runtime maps that same trailer and copies precision once into the hot Rank-N object header. Limb count is derived from `P`; the duplicate stored limb-count field is gone.

The historical `0x3fffffff` precision ceiling is therefore absent from compiler admission. `fp1073741824`, the first precision beyond the former wall, compiles through the ordinary path without a named-width backend or replacement threshold. Canonical Rank-N output exposes precision itself rather than the compiler-internal interned type identity.

This release does not claim that every arithmetic kernel can physically execute every u64 precision. Local digit/index widths that belong to existing arithmetic realizations remain explicit implementation frontiers and are not promoted into semantic type limits. No JIT, kernel-offload surface, runtime width selector, scheduler, worker pool, or source-visible parallel mechanism is added.


## 1.3.104: capacity follows facts, not magic numbers

Arbitrary capacity tables now age into authorities that already exist. General physical CSE/constant candidates and Tensor profiling/cache facts follow instance-sized arenas instead of 32/16/64-slot tables. Invocation affinity storage grows to the kernel-reported cpuset width instead of assuming 128 bytes, while static placement remains locality-only. The native driver reuses process-start argv and mmap-sizes path storage rather than maintaining fixed copies.

CPUID topology/cache scans now stop on architectural terminators. Structured matrix/vector dimensions leave the old 255-wide tag window, and the AOT-static `zeta`, `polylog`, and `tetration` relations no longer carry 32/16/8 semantic ceilings. None of these changes introduces a workload route, scheduler, worker pool, JIT, source-visible parallel directive, or second backend.

`WHFLD216` rank/geometry remains an explicit format/runtime representation frontier in this release. It is not papered over by increasing `8` to another constant.


## 1.3.103: dead authority becomes the next value

General scalar FP realization now consumes its existing effective last-use frontier when placing a next StateFact. If the old authority is already dead before that update, the next value is born in the dead carrier instead of creating a separate output carrier and copying it back at the timestep boundary. Scalar FP carrier copies also converge onto the existing VEX/EVEX scalar emitter; the duplicate low-register copy encoder is gone.

No dynamics recognizer, timestep heuristic, workload route, scheduler, worker pool, runtime CPU query, source-visible parallel directive, JIT path or second FP backend is introduced. A two-region explicit-dynamics diagnostic with a 10:1 timestep ratio removes four pure carrier transports per timestep in the four-state recurrence. Longer pinned wall-time A/B is neutral within measurement noise, so 1.3.103 makes no speedup claim for that case; the structural reduction is retained because it removes redundant physical work without adding a branch family.

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

The current release gate contains **29 tests**. Production authority remains under `compiler/`, `runtime/`, `surface/`, `tools/`, `build.sh`, and generated `bin/` executables. `devtrash/` contains regression, benchmark, historical, and archaeological material only.

See `ARCHITECTURE_AGING_1_3_105.md`, `PERFORMANCE_1_3_105.md`, `TESTING_1_3_105.md`, `PURE_ASSEMBLY_RELEASE_PROOF_1_3_105.md`, `RELEASE_SURFACE_CONVERGENCE_1_3_105.md`, and `WHEELCHAIR_CHARTER_1_3_105.md`.
