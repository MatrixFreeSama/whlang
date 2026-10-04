# AVX-512 structural-support pilot

Pinned logical CPU: `0`. Main table: 15 interleaved repetitions. Controls fixed to x86-64-v4.

| workload | implementation | median ms | MAD ms | time/C | speedup/C |
|---|---|---:|---:|---:|---:|
| localized_plasticity | Wheelchair_1.3.127_v4 | 0.863687 | 0.010526 | 0.1088 | 9.1930 |
| localized_plasticity | Wheelchair_1.3.126_v4 | 6.430833 | 0.015013 | 0.8099 | 1.2347 |
| localized_plasticity | GCC_C_v4 | 7.939911 | 0.031297 | 1.0000 | 1.0000 |
| localized_plasticity | GFortran_v4 | 8.207440 | 0.013671 | 1.0337 | 0.9674 |
| localized_plasticity | C_ceiling_v4 | 1.153349 | 0.007661 | 0.1453 | 6.8842 |
| localized_plasticity | Fortran_ceiling_v4 | 1.380247 | 0.031027 | 0.1738 | 5.7525 |
| levelset_two_regions | Wheelchair_1.3.127_v4 | 0.861022 | 0.007742 | 0.0710 | 14.0848 |
| levelset_two_regions | GCC_C_v4 | 12.127308 | 0.022453 | 1.0000 | 1.0000 |
| levelset_two_regions | GFortran_v4 | 10.445283 | 0.029114 | 0.8613 | 1.1610 |
| levelset_two_regions | C_ceiling_v4 | 1.183484 | 0.012819 | 0.0976 | 10.2471 |
| levelset_two_regions | Fortran_ceiling_v4 | 1.378693 | 0.017095 | 0.1137 | 8.7962 |

## Scaling medians

| workload | n | implementation | median ms | MAD ms |
|---|---:|---|---:|---:|
| levelset_two_regions | 4000000 | C_ceiling_v4 | 1.147418 | 0.006911 |
| levelset_two_regions | 4000000 | GCC_C_v4 | 6.639408 | 0.043634 |
| levelset_two_regions | 4000000 | Wheelchair_1.3.127_v4 | 0.862544 | 0.014311 |
| levelset_two_regions | 8000000 | C_ceiling_v4 | 1.164354 | 0.013730 |
| levelset_two_regions | 8000000 | GCC_C_v4 | 12.134021 | 0.023346 |
| levelset_two_regions | 8000000 | Wheelchair_1.3.127_v4 | 0.868173 | 0.017296 |
| levelset_two_regions | 16000000 | C_ceiling_v4 | 1.219997 | 0.010155 |
| levelset_two_regions | 16000000 | GCC_C_v4 | 23.088755 | 0.040610 |
| levelset_two_regions | 16000000 | Wheelchair_1.3.127_v4 | 0.864417 | 0.010746 |
| localized_plasticity | 1000000 | C_ceiling_v4 | 1.118816 | 0.020040 |
| localized_plasticity | 1000000 | GCC_C_v4 | 1.946278 | 0.014461 |
| localized_plasticity | 1000000 | Wheelchair_1.3.126_v4 | 1.536999 | 0.011658 |
| localized_plasticity | 1000000 | Wheelchair_1.3.127_v4 | 0.850978 | 0.005019 |
| localized_plasticity | 4000000 | C_ceiling_v4 | 1.104645 | 0.010726 |
| localized_plasticity | 4000000 | GCC_C_v4 | 4.541984 | 0.019660 |
| localized_plasticity | 4000000 | Wheelchair_1.3.126_v4 | 3.625829 | 0.019489 |
| localized_plasticity | 4000000 | Wheelchair_1.3.127_v4 | 0.858548 | 0.013730 |
| localized_plasticity | 8000000 | C_ceiling_v4 | 1.132136 | 0.011037 |
| localized_plasticity | 8000000 | GCC_C_v4 | 7.904591 | 0.006751 |
| localized_plasticity | 8000000 | Wheelchair_1.3.126_v4 | 6.439400 | 0.025127 |
| localized_plasticity | 8000000 | Wheelchair_1.3.127_v4 | 0.859300 | 0.007501 |
| localized_plasticity | 16000000 | C_ceiling_v4 | 1.179456 | 0.009123 |
| localized_plasticity | 16000000 | GCC_C_v4 | 14.692982 | 0.028553 |
| localized_plasticity | 16000000 | Wheelchair_1.3.126_v4 | 12.028493 | 0.037225 |
| localized_plasticity | 16000000 | Wheelchair_1.3.127_v4 | 0.861452 | 0.011886 |
