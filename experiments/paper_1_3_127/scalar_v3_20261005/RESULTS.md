# Scalar x86-64-v3 negative-control pilot

Pinned logical CPU: `0`. 15 interleaved repetitions. Whole-process wall time.

| workload | implementation | median ms | MAD ms | time/C | speedup/C |
|---|---|---:|---:|---:|---:|
| mass3 | Wheelchair_1.3.127_native256 | 165.984184 | 0.112239 | 1.1272 | 0.8872 |
| mass3 | GCC_C_v3 | 147.256968 | 0.094471 | 1.0000 | 1.0000 |
| mass3 | GFortran_v3 | 147.512257 | 0.110215 | 1.0017 | 0.9983 |
| chem6 | Wheelchair_1.3.127_native256 | 152.947646 | 0.043791 | 1.0167 | 0.9835 |
| chem6 | GCC_C_v3 | 150.430249 | 0.087917 | 1.0000 | 1.0000 |
| chem6 | GFortran_v3 | 150.732452 | 0.086101 | 1.0020 | 0.9980 |
| rigid7 | Wheelchair_1.3.127_native256 | 295.276122 | 0.098920 | 1.2393 | 0.8069 |
| rigid7 | GCC_C_v3 | 238.260244 | 0.076106 | 1.0000 | 1.0000 |
| rigid7 | GFortran_v3 | 238.496993 | 0.117203 | 1.0010 | 0.9990 |
