# Wheelchair 1.3.127 strict Field scaling and CPU-set pilot

Allowed CPUs: `[0, 1, 2, 3]`. Sizes: `(128, 192, 256)`. 15 interleaved repetitions per point. Strict Wheelchair/C/Fortran, x86-64-v3/native256.

| workload | n | CPUs | implementation | median ms | MAD ms | speedup/C |
|---|---:|---|---|---:|---:|---:|
| miniAMR_27point | 128 | 1cpu | Wheelchair_1.3.127_strict_native256 | 19.471930 | 0.324163 | 1.0822 |
| miniAMR_27point | 128 | 1cpu | GCC_C_strict_v3 | 21.072581 | 0.217063 | 1.0000 |
| miniAMR_27point | 128 | 1cpu | GFortran_strict_v3 | 37.157195 | 0.389284 | 0.5671 |
| miniAMR_27point | 128 | 4cpu | Wheelchair_1.3.127_strict_native256 | 9.598429 | 0.047779 | 1.0839 |
| miniAMR_27point | 128 | 4cpu | GCC_C_strict_v3 | 10.403583 | 0.054711 | 1.0000 |
| miniAMR_27point | 128 | 4cpu | GFortran_strict_v3 | 16.366296 | 0.058098 | 0.6357 |
| miniAMR_27point | 192 | 1cpu | Wheelchair_1.3.127_strict_native256 | 179.928198 | 0.833563 | 0.3678 |
| miniAMR_27point | 192 | 1cpu | GCC_C_strict_v3 | 66.178753 | 0.134330 | 1.0000 |
| miniAMR_27point | 192 | 1cpu | GFortran_strict_v3 | 116.919940 | 0.880229 | 0.5660 |
| miniAMR_27point | 192 | 4cpu | Wheelchair_1.3.127_strict_native256 | 64.025492 | 0.131996 | 0.4799 |
| miniAMR_27point | 192 | 4cpu | GCC_C_strict_v3 | 30.728402 | 0.056578 | 1.0000 |
| miniAMR_27point | 192 | 4cpu | GFortran_strict_v3 | 49.801687 | 0.079893 | 0.6170 |
| miniAMR_27point | 256 | 1cpu | Wheelchair_1.3.127_strict_native256 | 92.920329 | 0.691731 | 1.6573 |
| miniAMR_27point | 256 | 1cpu | GCC_C_strict_v3 | 154.001221 | 0.335075 | 1.0000 |
| miniAMR_27point | 256 | 1cpu | GFortran_strict_v3 | 279.637613 | 2.903764 | 0.5507 |
| miniAMR_27point | 256 | 4cpu | Wheelchair_1.3.127_strict_native256 | 42.441066 | 0.159807 | 1.6469 |
| miniAMR_27point | 256 | 4cpu | GCC_C_strict_v3 | 69.897247 | 0.035289 | 1.0000 |
| miniAMR_27point | 256 | 4cpu | GFortran_strict_v3 | 114.938485 | 0.156098 | 0.6081 |
| miniFE_heat21 | 128 | 1cpu | Wheelchair_1.3.127_strict_native256 | 16.109125 | 0.219788 | 0.8230 |
| miniFE_heat21 | 128 | 1cpu | GCC_C_strict_v3 | 13.257782 | 0.102220 | 1.0000 |
| miniFE_heat21 | 128 | 1cpu | GFortran_strict_v3 | 26.089951 | 0.088235 | 0.5082 |
| miniFE_heat21 | 128 | 4cpu | Wheelchair_1.3.127_strict_native256 | 8.128836 | 0.037099 | 0.9577 |
| miniFE_heat21 | 128 | 4cpu | GCC_C_strict_v3 | 7.784797 | 0.050964 | 1.0000 |
| miniFE_heat21 | 128 | 4cpu | GFortran_strict_v3 | 14.253467 | 0.052859 | 0.5462 |
| miniFE_heat21 | 192 | 1cpu | Wheelchair_1.3.127_strict_native256 | 146.384691 | 0.842643 | 0.2792 |
| miniFE_heat21 | 192 | 1cpu | GCC_C_strict_v3 | 40.871831 | 0.056476 | 1.0000 |
| miniFE_heat21 | 192 | 1cpu | GFortran_strict_v3 | 82.999483 | 0.278170 | 0.4924 |
| miniFE_heat21 | 192 | 4cpu | Wheelchair_1.3.127_strict_native256 | 51.703317 | 0.067966 | 0.4208 |
| miniFE_heat21 | 192 | 4cpu | GCC_C_strict_v3 | 21.757454 | 0.030172 | 1.0000 |
| miniFE_heat21 | 192 | 4cpu | GFortran_strict_v3 | 42.816654 | 0.018627 | 0.5082 |
| miniFE_heat21 | 256 | 1cpu | Wheelchair_1.3.127_strict_native256 | 74.940691 | 0.336462 | 1.2641 |
| miniFE_heat21 | 256 | 1cpu | GCC_C_strict_v3 | 94.735766 | 0.236431 | 1.0000 |
| miniFE_heat21 | 256 | 1cpu | GFortran_strict_v3 | 193.368270 | 0.353047 | 0.4899 |
| miniFE_heat21 | 256 | 4cpu | Wheelchair_1.3.127_strict_native256 | 36.096985 | 0.188381 | 1.3523 |
| miniFE_heat21 | 256 | 4cpu | GCC_C_strict_v3 | 48.813831 | 0.089900 | 1.0000 |
| miniFE_heat21 | 256 | 4cpu | GFortran_strict_v3 | 98.235345 | 0.097382 | 0.4969 |

No speedup is aggregated across sizes or CPU sets. The 4cpu rows are emitted only if the hosted runner exposes at least four CPUs in its affinity set.
