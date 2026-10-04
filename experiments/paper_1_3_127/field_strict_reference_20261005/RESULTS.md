# Wheelchair 1.3.127 strict Field + numerical reference

Pinned CPU `0`, 15 interleaved repetitions. Wheelchair JSON contract is changed only from `tolerant` to `strict`; C/Fortran use strict floating-point flags. The same deterministic WHFLD217 bytes are shared by all implementations.

| workload | implementation | median ms | MAD ms | time/C | speedup/C | rel. error vs f64 reference |
|---|---|---:|---:|---:|---:|---:|
| miniAMR_27point | Wheelchair_1.3.127_strict_native256 | 75.458362 | 2.712775 | 0.6504 | 1.5375 | 1.395e-04 |
| miniAMR_27point | GCC_C_strict_v3 | 116.017901 | 0.209666 | 1.0000 | 1.0000 | 2.136e-02 |
| miniAMR_27point | GFortran_strict_v3 | 214.509015 | 0.227253 | 1.8489 | 0.5409 | 2.136e-02 |
| miniFE_heat21 | Wheelchair_1.3.127_strict_native256 | 60.756158 | 0.329987 | 0.8017 | 1.2474 | 9.993e-05 |
| miniFE_heat21 | GCC_C_strict_v3 | 75.787965 | 0.288278 | 1.0000 | 1.0000 | 6.744e-04 |
| miniFE_heat21 | GFortran_strict_v3 | 170.287610 | 0.174573 | 2.2469 | 0.4451 | 6.744e-04 |

The f64 oracle preserves each kernel's local `float` arithmetic and changes only the final accumulation to `double`; it is a numerical diagnostic, not a timed competitor.
