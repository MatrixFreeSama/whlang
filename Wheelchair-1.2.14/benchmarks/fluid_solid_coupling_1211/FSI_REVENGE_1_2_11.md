# Wheelchair 1.2.11 vs Expert C: Fluid-Solid Coupling Repair Validation

This benchmark validates the 1.2.11 native resource-profile selector correction.

Both contenders evaluate the same periodic coupled operator and checksum. Expert C is compiled with the historical authority flags:

```text
-O3 -march=native -mtune=native -flto -ffast-math -mprefer-vector-width=512 -pthread
-DCOUPLED_MODE=1
```

Formal timing protocol:

- AMD EPYC 9V74 validation host;
- N = 10,000,000 and 100,000,000;
- Q = 1, 2, 4;
- identical CPU affinity per row;
- 3 warm-up executions per contender;
- 11 measured executions per contender;
- deterministic interleaved order;
- median process wall time.

| N | Q | Wheelchair 1.2.11 ms | Expert C ms | W/C |
|---:|---:|---:|---:|---:|
| 10,000,000 | 1 | 21.254594 | 16.999234 | 1.250327x |
| 10,000,000 | 2 | 12.344704 | 10.834748 | 1.139362x |
| 10,000,000 | 4 | 10.994869 | 9.583461 | 1.147275x |
| 100,000,000 | 1 | 188.322280 | 137.177336 | 1.372838x |
| 100,000,000 | 2 | 99.898511 | 78.911670 | 1.265954x |
| 100,000,000 | 4 | 55.848455 | 62.612500 | 0.891970x |

Six-case geometric mean:

```text
Wheelchair / Expert C = 1.167589x
```

The 100M/Q4 row is a Wheelchair win on this host/run. Wheelchair elapsed time is about 10.8% lower, corresponding to about 12.1% higher throughput relative to C. This is a same-host measured row, not a language-wide performance claim.

Correctness boundary gate:

```text
N = 4, 31, 32, 33, 4096, 65535, 65536, 65537, 100000
Q = 1, 2, 4
27 / 27 PASS
maximum relative error = 1.87e-14
required relative error <= 1e-8
```

Most importantly for the release correction, automatic `whexc` output is byte-identical to explicit `topologyc-wide` output for the coupled FSI source at Q1, Q2, and Q4.
