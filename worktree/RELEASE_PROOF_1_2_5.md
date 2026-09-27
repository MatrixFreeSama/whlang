# Wheelchair 1.2.5 Release Proof

## Release identity

- Release: `1.2.5`
- Major native upgrade: **Shared Dependency Episode Physicalization**
- Authority workflow: `Validate Shared Dependency Episode 1.2.5`
- Authority run: `33902157205`
- Authority source commit: `668fa5855fcfb63ff451a12202cdf5f0759c6c2f`
- Qualified AVX-512 hosts: 2
- Qualified failures: 0

## Structural admission

The optimizer does not inspect workload or physics names. It classifies canonical graphs from structural load pressure and dependency topology.

Observed witnesses:

- Newton/Jv: 5 distinct structural loads -> frozen `legacy_1_2_4`
- global stiffness: 6 -> frozen `legacy_1_2_4`
- two-field decoupled witness: 11 -> `shared_dependency_episode_wide_125`
- two-field coupled witness: 12 -> `shared_dependency_episode_wide_125`

The wide recipe uses `ZMM16..ZMM29` for shared persistent dependency/CSE ownership and `ZMM30..ZMM31` for resident constants. Runtime-owned `ZMM12..ZMM15` remain protected.

No runtime recipe selector, scalar fallback, workload-name dispatch, central spawn loop, central wait loop, central reduction loop, or global task queue is introduced.

## Machine-shape authority

Coupled witness, generated hot region:

- 1.2.4 hot instructions: 491
- 1.2.5 hot instructions: 297
- 1.2.4 `VDIVPD`: 26
- 1.2.5 `VDIVPD`: 0
- 1.2.5 reachable `CALL` edges: 0

Tolerant literal reciprocal erasure is admitted only for finite non-zero binary64 literal divisors whose rounded reciprocal is normal. Strict mode and unsupported reciprocal cases retain the existing proved vector division recipe. AOT reciprocal construction uses canonical MXCSR `0x1f80` and restores the host state afterward.

## Numerical and semantic authority

- 1.2.4 -> 1.2.5 FSI witness checksum bits: identical for every tested size/executor case.
- WH/WHEX Shared Dependency Episode semantic plans: equivalent.
- WH/WHEX coupled witness native files: byte-identical.
- Newton/Jv q=1/2/4 native files: byte-identical to the exact 1.2.4 recipe.
- global stiffness q=1/2/4 native files: byte-identical to the exact 1.2.4 recipe.

## Inherited peak protection

The authority run passed:

- Wheelchair 1.0.9 native-sovereignty invariants;
- Interior Periodic 1.2.1 technical peak protection;
- Newton/Jv 1.2.1 technical peak protection;
- Rank-N 1.2.2 complete gates;
- Sparse Causal Expansion 1.2.3 complete gates;
- Product-Subtract contraction and Vector Reduction Residency 1.2.4 gates;
- zero scalar fallback and zero hidden serial fallback requirements.

## Multi-host physical authority

Method per qualified host:

- same CPU and affinity;
- 1.2.4 exact control vs 1.2.5 vs matched Expert C AVX-512;
- decoupled and coupled two-field witnesses;
- `N=10,000,000` and `N=100,000,000`;
- executors `q=1,2,4`;
- 3 warmups;
- 11 shuffled/interleaved measured runs;
- median time per case;
- release gate: median and geometric-mean 1.2.4/1.2.5 speedup >= 1.50x.

### Authority host A, slot 2

AMD EPYC 9V74 80-Core Processor, family 25 model 17, AVX-512F usable.

| mode | N | q | 1.2.4 ms | 1.2.5 ms | Expert C512 ms | 1.2.4 / 1.2.5 | 1.2.5 / C |
|---|---:|---:|---:|---:|---:|---:|---:|
| decoupled | 10M | 1 | 34.810862 | 15.414326 | 12.398190 | 2.2583x | 1.2433x |
| decoupled | 10M | 2 | 35.800105 | 15.339343 | 11.725685 | 2.3339x | 1.3082x |
| decoupled | 10M | 4 | 18.463173 | 8.201470 | 6.532850 | 2.2512x | 1.2554x |
| decoupled | 100M | 1 | 338.440782 | 144.524788 | 113.268219 | 2.3417x | 1.2760x |
| decoupled | 100M | 2 | 349.490063 | 144.132774 | 105.226103 | 2.4248x | 1.3697x |
| decoupled | 100M | 4 | 175.981979 | 72.795836 | 53.390238 | 2.4175x | 1.3635x |
| coupled | 10M | 1 | 46.196663 | 18.600267 | 13.742113 | 2.4837x | 1.3535x |
| coupled | 10M | 2 | 47.390671 | 18.441267 | 13.416711 | 2.5698x | 1.3745x |
| coupled | 10M | 4 | 24.290150 | 9.824352 | 7.406382 | 2.4724x | 1.3265x |
| coupled | 100M | 1 | 450.840639 | 175.174715 | 124.123750 | 2.5737x | 1.4113x |
| coupled | 100M | 2 | 464.787153 | 175.534481 | 122.179407 | 2.6478x | 1.4367x |
| coupled | 100M | 4 | 234.013231 | 88.577818 | 61.938219 | 2.6419x | 1.4301x |

Aggregate:

- median 1.2.4 -> 1.2.5: **2.4486x**
- geomean 1.2.4 -> 1.2.5: **2.4478x**
- median 1.2.5 / Expert C: **1.3585x**
- geomean 1.2.5 / Expert C: **1.3443x**

### Authority host B, slot 3

AMD EPYC 9V74 80-Core Processor, family 25 model 17, AVX-512F usable.

| mode | N | q | 1.2.4 ms | 1.2.5 ms | Expert C512 ms | 1.2.4 / 1.2.5 | 1.2.5 / C |
|---|---:|---:|---:|---:|---:|---:|---:|
| decoupled | 10M | 1 | 34.921144 | 15.436531 | 12.570903 | 2.2622x | 1.2280x |
| decoupled | 10M | 2 | 35.829324 | 15.289544 | 11.723814 | 2.3434x | 1.3041x |
| decoupled | 10M | 4 | 18.476565 | 8.241477 | 6.499708 | 2.2419x | 1.2680x |
| decoupled | 100M | 1 | 338.643806 | 144.651695 | 113.238317 | 2.3411x | 1.2774x |
| decoupled | 100M | 2 | 349.008467 | 144.148799 | 105.275605 | 2.4212x | 1.3693x |
| decoupled | 100M | 4 | 176.089655 | 72.931604 | 53.504536 | 2.4144x | 1.3631x |
| coupled | 10M | 1 | 46.202988 | 18.612340 | 13.683646 | 2.4824x | 1.3602x |
| coupled | 10M | 2 | 47.435693 | 18.476555 | 13.418544 | 2.5673x | 1.3769x |
| coupled | 10M | 4 | 24.341286 | 9.813436 | 7.397012 | 2.4804x | 1.3267x |
| coupled | 100M | 1 | 451.216777 | 175.346106 | 124.166780 | 2.5733x | 1.4122x |
| coupled | 100M | 2 | 464.820079 | 175.531742 | 122.153463 | 2.6481x | 1.4370x |
| coupled | 100M | 4 | 234.314243 | 88.619876 | 61.998120 | 2.6440x | 1.4294x |

Aggregate:

- median 1.2.4 -> 1.2.5: **2.4508x**
- geomean 1.2.4 -> 1.2.5: **2.4480x**
- median 1.2.5 / Expert C: **1.3616x**
- geomean 1.2.5 / Expert C: **1.3445x**

## Release conclusion

All qualified authority hosts passed the structural, numerical, native-sovereignty, inherited-peak, and >=1.50x physical-gain gates.

`WHEELCHAIR_SHARED_DEPENDENCY_EPISODE_1_2_5=PASS`

`WHEELCHAIR_1_2_5_AUTHORITY_QUORUM=PASS`
