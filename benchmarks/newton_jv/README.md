# Newton/Jv benchmark evidence for Wheelchair 1.2.1

This directory exposes the mature matrix-free Newton Jacobian-vector workload used as a release-regression and performance-restoration witness for Wheelchair 1.2.1.

The purpose is not to claim that one benchmark ranks all programming languages. The purpose is to bind one performance result to a specific workload, host, compiler state, numerical contract and measurement protocol.

## Workload

```text
u[i]  = 0.25 + ((17*i+3) mod 1024)/1024
v[i]  = -0.5 + ((29*i+7) mod 1024)/1024
jv[i] = (2 + 0.375*u[i]^2)*v[i] - v[i-1] - v[i+1]
```

with periodic boundaries.

The Wheelchair source is [`mature.whex`](mature.whex).

Required checksums:

```text
10,000,000  -> 0x40a1414a1c4e8000
100,000,000 -> 0x40d591e5093fa000
```

## Final audit host and method

- CPU: **Intel Xeon Platinum 8370C @ 2.80 GHz**
- virtualized x86-64 host
- CPUs 0-4 visible on the rematch environment
- sustained cgroup quota: 4 CPUs
- tested widths: 1, 2 and 4 executors/cores
- fixed CPU affinity
- FP64 tolerant reduction
- chunk extent: 65,536 coordinates
- four logical accumulation carriers
- deterministic causal/fixed reduction topology
- three warm-ups per point
- 21 shuffled/interleaved whole-process measurements per contestant
- published statistic: median

See [`CONFIG_1_2_1.md`](CONFIG_1_2_1.md) for the complete configuration.

## Final 21-run medians

### N = 10,000,000

| executors / cores | Wheelchair 1.2.0 | **Wheelchair 1.2.1** | matched expert C | explicit AVX-512 C | 1.2.0 -> 1.2.1 |
|---:|---:|---:|---:|---:|---:|
| 1 | 28.311 ms | **15.087 ms** | 20.835 ms | 21.329 ms | **1.877x** |
| 2 | 21.630 ms | **14.430 ms** | 18.768 ms | 18.296 ms | **1.499x** |
| 4 | 15.516 ms | **9.977 ms** | 15.346 ms | 13.118 ms | **1.555x** |

Wheelchair 1.2.1 uses 23.1% to 35.0% less median wall time than the matched C control and 21.1% to 29.3% less than the explicit AVX-512 C control at these three points.

### N = 100,000,000

| executors / cores | Wheelchair 1.2.0 | **Wheelchair 1.2.1** | matched expert C | explicit AVX-512 C | 1.2.0 -> 1.2.1 |
|---:|---:|---:|---:|---:|---:|
| 1 | 217.807 ms | **106.144 ms** | 141.877 ms | 120.285 ms | **2.052x** |
| 2 | 141.114 ms | **63.041 ms** | 88.667 ms | 76.908 ms | **2.238x** |
| 4 | 92.793 ms | **48.754 ms** | 64.366 ms | 56.485 ms | **1.903x** |

Wheelchair 1.2.1 uses 24.3% to 28.9% less median wall time than the matched C control and 11.8% to 18.0% less than the explicit AVX-512 C control at these three points.

A machine-readable copy of the final medians and provenance is available as [`results_summary_1_2_1.json`](results_summary_1_2_1.json).

## What changed in 1.2.1

Wheelchair 1.2.1 restores the lost Newton/Jv technical peak through a generic compiler rule named **Interior Periodic Composition Erasure**.

For a dynamic periodic coordinate, the compiler normalizes the index relation to an affine form:

```text
c*axis + q*n + d
```

The exact `q*n` term vanishes in the modulo ring. The remaining affine coordinate is composed with the logical root coordinate. Physical dynamic modulo is erased only if the compiler proves that every active lane in the already-proven interior vector region remains inside `[0,n)`.

Boundary vector regions keep exact periodic semantics. An unproved radius-2 control keeps dynamic modulo. There is no Newton- or benchmark-name dispatch.

For the mature one-executor Newton/Jv image, the generated code changed as follows:

```text
VCVTTPD2QQ count:      4 -> 2
VPMULLQ count:         10 -> 6
generated RX payload:  1305 -> 1209 bytes
```

This is the reference case for Wheelchair's **Technical Peak Preservation Contract**: generalization may not flatten an established fast path into a slower common denominator. A lost narrow optimization must be promoted into generic structural algebra and recovered for every program satisfying the same proof.

## Python surface erasure

For executor counts 1, 2 and 4, the audit lowered WHEX through the Python human surface to canonical `wheelchair.tensor/1` JSON and also fed the same canonical graph directly to the handwritten native topology compiler.

The resulting native ELFs were byte-identical:

```text
DIRECT_CANONICAL_ELF_EQ_E1=PASS
DIRECT_CANONICAL_ELF_EQ_E2=PASS
DIRECT_CANONICAL_ELF_EQ_E4=PASS
```

Therefore the Python surface is not timed runtime work and did not create a different native image for this workload.

## External C controls and provenance

The exact two external C controls were measurement controls, not Wheelchair backend dependencies.

Audited identities:

```text
matched expert C:
a9a9d3e908d08983e2c74f99c391e57597e37a5a404bafa153c3c140a06979b2

explicit AVX-512 C:
05e141dff01fcdf04a0821395fe675dc4876dfce1d60115613c18252388701ea
```

Their exact source text was not retained in the 1.2.1 release tree. This repository therefore records the hashes rather than fabricating byte-identical source after the fact. See [`CONTROL_SOURCE_IDENTITIES.md`](CONTROL_SOURCE_IDENTITIES.md).

## Raw 21-run data

The authoritative Wheelchair 1.2.1 release archive already contains the two raw sample files:

```text
benchmarks/newton_jv/10M_21run.json
benchmarks/newton_jv/100M_21run.json
```

Their release-manifest identities are:

```text
9d37bb8279449fc71420092f03544061c888a77ab1b2f607339ee0a02692905e  benchmarks/newton_jv/10M_21run.json
562693eaf2fcf011801dddc3ba63fa25e6414ec9b9f49967f3e03f0160f96894  benchmarks/newton_jv/100M_21run.json
```

Release archive:

```text
8ed8f27125a47d816dbae8d56b6f71060d28e75b33ab76edb664596569884490  dist/Wheelchair-1.2.1.zip
```

The root repository exposes a compact machine-readable summary separately, while the release ZIP remains the cryptographically frozen authority for the full raw 21-run sample population.

## Claim boundary

The defensible statement is narrow and strong:

> On this matrix-free Newton/Jv workload, on the Xeon Platinum 8370C audit host, under the documented numerical and measurement contract, Wheelchair 1.2.1 has a lower 21-run median whole-process wall time than both the matched expert C control and the stronger explicit AVX-512 C control at all six 10M/100M x 1/2/4 points.

It does **not** establish a universal ranking of Wheelchair against C or any other language.
