# Wheelchair 1.2.5 vs Zig: Fluid-Solid Coupling Authority Benchmark

## Status

**PASS.** The benchmark is numerically gated, boundary-gated, same-host timed, and backed by an AVX-512/ZMM binary witness for the explicit-vector Zig contender.

Final observed ordering on the qualified hosts in the comprehensive authority run:

1. Expert C
2. Expert Zig 0.16.0 with explicit `@Vector(8, f64)` SIMD
3. Wheelchair 1.2.5

This result is intentionally reported as measured data, not as a language-wide performance claim.

## Coupled operator

The three implementations evaluate the same periodic fluid-solid coupling operator and the same checksum:

```text
F_i = rho_i * (2*f_i - f_{i-1} - f_{i+1})
    + mu_i  * (f_{i+1} - f_{i-1})
    + gamma_i * (f_i - u_i)

S_i = E_i * (2*u_i - u_{i-1} - u_{i+1})
    + 0.0625 * (u_{i+1} - u_{i-1})
    + gamma_i * (u_i - f_i)

checksum = sum_i(F_i^2 + S_i^2)
```

All implementations use the same deterministic input formulas, periodic boundaries, 65,536-element chunks, cyclic chunk ownership, and deterministic tree reduction.

## Contenders

- **Wheelchair 1.2.5:** `fsi_coupled.whex`, compiled separately for 1, 2, and 4 executors.
- **Expert C:** `Fluid_Solid_expert_C_matched.c`, compiled with `-O3 -march=native -mtune=native -flto -ffast-math -mprefer-vector-width=512 -pthread`.
- **Expert Zig:** `Fluid_Solid_zig_avx512.zig`, Zig 0.16.0, compiled with `-O ReleaseFast -mcpu=native -fllvm`. The kernel explicitly uses `@Vector(8, f64)` / `@Vector(8, u64)` and four vector accumulators.
- **Scalar Zig diagnostic:** `Fluid_Solid_zig_matched.zig` is retained only as a diagnostic baseline, not as the final Zig authority contender.

Zig 0.16.0 is pinned because it is a stable release. Its official release notes state that LLVM loop vectorization was disabled because of an LLVM 21 regression. Therefore, the final authority contender uses explicit Zig vectors rather than relying on the disabled automatic loop-vectorization path.

Reference: <https://ziglang.org/download/0.16.0/release-notes.html>

## Correctness and edge gates

The explicit-vector Zig implementation must agree with the matched C implementation within relative error `1e-8` before authority timing begins.

The smoke matrix deliberately brackets both SIMD-width and chunk-boundary edges:

```text
N = 4, 31, 32, 33, 4096, 65535, 65536, 65537, 100000
Q = 1, 2, 4
```

This checks short domains, the 32-site vector main-loop boundary, the 65,536-element chunk boundary, and multithreaded reduction behavior.

The formal authority cases are:

```text
N = 10,000,000 and 100,000,000
Q = 1, 2, 4
```

Only runners where Wheelchair's topology probe reports `AVX-512F: usable` are accepted.

## Timing protocol

Each accepted `(N, Q)` case uses:

- identical CPU affinity for all three contenders via `taskset`;
- 3 warm-up executions per contender;
- 11 measured executions per contender;
- deterministically shuffled/interleaved contender order;
- median process wall time in milliseconds;
- same-host ratios only.

A ratio greater than 1 means the numerator consumed more time.

## Comprehensive authority result

Authority workflow run: `33963831258`.

Four AVX-512-qualified hosts completed all six formal cases. The table below reports the geometric mean of the six time ratios on each host.

| Host | Wheelchair / C | Wheelchair / Zig | Zig / C |
|---|---:|---:|---:|
| AMD EPYC 9V74 80-Core | 1.3885x | 1.0739x | 1.2929x |
| Intel Xeon Platinum 8573C | 1.6129x | 1.1899x | 1.3555x |
| Intel Xeon Platinum 8370C | 1.6922x | 1.2628x | 1.3400x |
| Intel Xeon Platinum 8573C | 1.6028x | 1.1859x | 1.3516x |

Cross-host geometric aggregation of those host geometric means:

| Ratio | Result |
|---|---:|
| Wheelchair / Expert C | **1.570x** |
| Wheelchair / Expert Zig | **1.176x** |
| Expert Zig / Expert C | **1.335x** |

In equivalent elapsed-time terms, Wheelchair consumed about 17.6% more time than Expert Zig on this aggregate; Expert Zig consumed about 15.0% less time than Wheelchair.

Expert Zig beat Wheelchair in all 24 individual formal `(host, N, Q)` rows of the comprehensive run. The smallest host-level gap was on AMD EPYC 9V74, where the Wheelchair/Zig geometric mean was about 1.074x.

The full 24-row data set is stored in `authority_results_zig_avx512_1_2_5.csv`.

## ZMM binary witness and reproduction

A later authority rerun added a hard post-build machine-code gate. The final Zig executable is disassembled with `objdump`, and the qualified job fails if the binary contains no `zmm` register instruction.

Witness workflow run: `33964046337`  
Qualified rerun job: `authority (1)`  
Host: AMD EPYC 9V74 80-Core Processor  
Zig source SHA-256: `df403fa190fb572830b4988e8ca29fc57b65ea27f504d08d3ef6011395aad70f`  
Machine-code gate: `ZIG_ZMM_GATE=PASS`

The reproduction produced:

```text
Wheelchair / C   = 1.3890x
Wheelchair / Zig = 1.0745x
Zig / C          = 1.2927x
```

The previous comprehensive run on the same CPU model produced Wheelchair/Zig = `1.0739x`, so the repeated measurement is closely aligned.

The ZMM gate proves ZMM instructions are present in the final Zig binary. It does not by itself claim that every hot-loop instruction is 512-bit SIMD; the explicit `@Vector(8, f64)` source and the binary witness are recorded separately to avoid overstating what the disassembly gate proves.

The preserved machine-code witness is stored in `authority_zmm_witness_1_2_5.txt`.

## Interpretation

This benchmark exposes a concrete optimization target for Wheelchair 1.2.5 rather than a correctness failure. Wheelchair remains substantially closer to the explicit-vector Zig implementation on AMD EPYC 9V74 than on the tested Intel hosts, while Expert C remains the fastest implementation across the measured authority set.

Any subsequent Wheelchair optimization should keep the operator, input generation, error gate, executor counts, CPU affinity, reduction semantics, and timing protocol unchanged so that performance gains cannot be obtained by changing the workload.
