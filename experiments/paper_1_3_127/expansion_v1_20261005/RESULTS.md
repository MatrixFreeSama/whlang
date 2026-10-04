# Wheelchair 1.3.127 cross-mechanism paper pilot

Frozen compiler: `Wheelchair 1.3.127`. This expansion batch uses native256 with x86-64-v3 C/Fortran controls throughout. The retained high-entropy case is excluded here because its frozen whexc launcher has path-dependent admission under relocation; the compiler is not modified to make the paper harness accept it.
All timed processes are pinned to logical CPU `0`; C/Fortran OpenMP controls use one thread. Each implementation receives one warm-up and `15` interleaved measured repetitions.

This table deliberately mixes wins and losses only across workloads run on this same hosted runner. It is pilot evidence, not the final fixed-machine submission table.

| mechanism/workload | implementation | median ms | MAD ms | time/C | speedup/C | checksum rel. error vs C |
|---|---|---:|---:|---:|---:|---:|
| miniAMR_27point | Wheelchair_1.3.127_field_native256 | 92.459898 | 3.851267 | 0.5982 | 1.6716 | 2.077e-02 |
| miniAMR_27point | GCC_C_v3 | 154.555957 | 0.262171 | 1.0000 | 1.0000 | 0.000e+00 |
| miniAMR_27point | GFortran_v3 | 275.671965 | 3.054702 | 1.7836 | 0.5607 | 0.000e+00 |
| miniFE_heat21 | Wheelchair_1.3.127_field_native256 | 74.323371 | 0.446075 | 0.7848 | 1.2742 | 7.748e-04 |
| miniFE_heat21 | GCC_C_v3 | 94.700179 | 0.296728 | 1.0000 | 1.0000 | 0.000e+00 |
| miniFE_heat21 | GFortran_v3 | 194.138042 | 0.398884 | 2.0500 | 0.4878 | 0.000e+00 |

## Interpretation guardrails

- The retained high-entropy 1.3.102 witness is not included in this fresh batch because relocated frozen-package admission differs from repository-root admission. That coverage issue is recorded rather than repaired for publication.
- `miniAMR_27point` and `miniFE_heat21` are established public simulation kernels; the same generated WHFLD217 bytes are consumed by Wheelchair, C, and Fortran.
- Deep periodic CoordinateFact is not forced into this native256 batch because the frozen topologyc-native256 entry rejects the retained d23/d40 sources; it is reserved for a separate native whexc/ISA-matched table.
- No compiler source is modified by this experiment. No workload-specific branch is added.
