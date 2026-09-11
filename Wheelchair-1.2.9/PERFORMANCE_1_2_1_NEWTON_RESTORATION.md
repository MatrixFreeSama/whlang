# Wheelchair 1.2.1 Newton/Jv restoration audit

## Purpose

This audit separates three issues that were previously mixed together:

1. cross-host timing drift;
2. Python human-surface overhead;
3. native structural-code quality.

The workload is the established matrix-free periodic Newton Jacobian-vector product:

```text
u[i]  = 0.25 + ((17*i+3) mod 1024)/1024
v[i]  = -0.5 + ((29*i+7) mod 1024)/1024
jv[i] = (2 + 0.375*u[i]^2)*v[i] - v[i-1] - v[i+1]
```

with periodic boundaries, FP64 tolerant reduction, 65,536-coordinate chunks, four logical accumulation carriers and deterministic causal reduction. Required checksums remain:

```text
10,000,000  -> 0x40a1414a1c4e8000
100,000,000 -> 0x40d591e5093fa000
```

## Python surface is not the runtime cause

For executor counts 1, 2 and 4, the WHEX source was first lowered by the Python surface to canonical `wheelchair.tensor/1` JSON. That canonical graph was then fed directly to the handwritten `topologyc`, bypassing `whexc.py` for native compilation.

The direct-canonical ELF and normal WHEX ELF are byte-identical at every executor count:

```text
DIRECT_CANONICAL_ELF_EQ_E1=PASS
DIRECT_CANONICAL_ELF_EQ_E2=PASS
DIRECT_CANONICAL_ELF_EQ_E4=PASS
```

Therefore Python contributes neither timed runtime work nor a different native image for this workload.

## Same-host backend history diagnostic

The complete 1.0.9 source tree was rebuilt on the same current host and fed the same Newton graph. It is substantially slower than 1.2.0, demonstrating that 1.2.0 is not a regression from the ordinary historical tensor backend. The very fast older Newton result came from a narrower sovereign vertical slice whose structural ideas were not yet all recovered generically.

Representative same-host observations before the 1.2.1 repair included approximately:

```text
10M / 1 executor: 1.0.9 ~165 ms, 1.2.0 ~29 ms
100M / 1 executor: 1.0.9 ~1457 ms, 1.2.0 ~221 ms
```

The missing generic structure was identified in the 1.2.0 proven-interior body: left and right periodic neighbors still rebuilt full dynamic `% n` quotient/correction before applying the downstream affine `v` map.

## 1.2.1 generic repair

1.2.1 adds Interior Periodic Composition Erasure. A dynamic periodic index is normalized to:

```text
c*axis + q*n + d
```

The exact `q*n` term vanishes in the modulo ring. The compiler then composes the remaining affine coordinate with the current logical root and proves that every lane in the already-proven interior vector region lies in `[0,n)`. Only then is physical modulo erased. Boundary vector regions retain the original modulo implementation.

The generated Newton evaluator changed in the intended direction:

```text
VCVTTPD2QQ count: 4 -> 2
VPMULLQ count:    10 -> 6
generated RX:     1305 B -> 1209 B
```

The removed instructions are the two interior-neighbor dynamic-modulo paths. The boundary body still contains the required machinery.

## Same-host 21-run rematch

Host observed during this audit: Intel Xeon Platinum 8370C. Each point used fixed CPU affinity, three warmups, then 21 shuffled/interleaved whole-process measurements per contestant. All contestants returned the required bitwise checksum.

`matched C` is the reconstructed expert formula-fused C implementation. `explicit AVX-512 C` is the stronger hand-written SIMD control.

### N = 10,000,000

| executors / cores | Wheelchair 1.2.0 | Wheelchair 1.2.1 | matched C | explicit AVX-512 C | 1.2.0 -> 1.2.1 |
|---:|---:|---:|---:|---:|---:|
| 1 | 28.311 ms | **15.087 ms** | 20.835 ms | 21.329 ms | **1.877x** |
| 2 | 21.630 ms | **14.430 ms** | 18.768 ms | 18.296 ms | **1.499x** |
| 4 | 15.516 ms | **9.977 ms** | 15.346 ms | 13.118 ms | **1.555x** |

1.2.1 uses 23.1% to 35.0% less median time than matched C, and 21.1% to 29.3% less than the explicit AVX-512 control.

### N = 100,000,000

| executors / cores | Wheelchair 1.2.0 | Wheelchair 1.2.1 | matched C | explicit AVX-512 C | 1.2.0 -> 1.2.1 |
|---:|---:|---:|---:|---:|---:|
| 1 | 217.807 ms | **106.144 ms** | 141.877 ms | 120.285 ms | **2.052x** |
| 2 | 141.114 ms | **63.041 ms** | 88.667 ms | 76.908 ms | **2.238x** |
| 4 | 92.793 ms | **48.754 ms** | 64.366 ms | 56.485 ms | **1.903x** |

1.2.1 uses 24.3% to 28.9% less median time than matched C, and 11.8% to 18.0% less than the explicit AVX-512 control.

Raw 21-run samples were retained as `Newton_Jv_1.2.1_10M_21run.json` and `Newton_Jv_1.2.1_100M_21run.json` during the audit.

## Claim boundary

This is one matrix-free Newton/Jv workload on one virtualized host. It does not establish a universal language ranking. The compiler transformation itself is generic and is separately gated by a non-Newton witness plus an unproved radius-2 control. No compiler dispatch uses Newton, Jacobian, heat, stencil, C, Rust, MoonBit, coefficient, or modulus names.

## Retained evidence

The release tree retains:

```text
benchmarks/newton_jv/mature.whex
benchmarks/newton_jv/10M_21run.json
benchmarks/newton_jv/100M_21run.json
```

The external expert controls used during this audit had SHA-256 identities:

```text
matched expert C:
a9a9d3e908d08983e2c74f99c391e57597e37a5a404bafa153c3c140a06979b2

explicit AVX-512 C:
05e141dff01fcdf04a0821395fe675dc4876dfce1d60115613c18252388701ea
```

They are measurement controls, not Wheelchair backend dependencies and are not shipped as compiler/runtime sources.
