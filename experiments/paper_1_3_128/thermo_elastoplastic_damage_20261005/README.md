# Localized thermo-elasto-plastic-damage explicit-step benchmark — Wheelchair 1.3.128

One pinned CPU, Strict semantics, 9 interleaved repetitions. The physical event width is fixed while the background domain grows. Natural C/Fortran traverse the full domain; the C ceiling traverses only the mathematically active ~6001-point support and is a lower-bound control, not a natural baseline.

| n | Wheelchair ms | C ms | Fortran ms | C ceiling ms | WH/C | WH/ceiling |
|---:|---:|---:|---:|---:|---:|---:|
| 1,000,000 | 26.482 | 29.687 | 31.745 | 2.758 | 1.121x | 9.6x |
| 4,000,000 | 100.364 | 121.373 | 122.488 | 3.310 | 1.209x | 30.3x |
| 8,000,000 | 199.429 | 241.587 | 245.400 | 3.470 | 1.211x | 57.5x |
| 16,000,000 | 405.266 | 481.671 | 489.355 | 3.284 | 1.189x | 123.4x |

The Wheelchair checksum differs from the sequential C reduction only in final rounding bits; the C active-support ceiling is bit-identical to natural C at every tested size.

This benchmark intentionally retains the negative result: the 1.3.128 Physical DAG does not contract the full coupled support after localized constitutive facts feed periodic stress-divergence and thermal-diffusion relations. Runtime therefore still scales with total domain size instead of the fixed active support.

## Coverage ablation

The same constitutive chain without the periodic stress-divergence and thermal-diffusion fields was also compiled and probed. Wheelchair still scaled approximately linearly with total domain size (median wall time: 21.657 / 78.996 / 156.602 / 310.229 ms for 1M / 4M / 8M / 16M). Therefore the missing contraction begins before the periodic-neighborhood stage; the neighborhood relations are not the sole cause.

A 42-live-Field variant that additionally materialized `temp_next = dtemp + dt*alpha*laptemp + plastic_heat` was rejected by the frozen 1.3.128 sovereign frontend. The benchmark was not used to justify a compiler change; the admitted 41-Field program above is the measured production case.
