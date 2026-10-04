# Field address-path ablation

Wheelchair 1.3.127 Strict native256 vs strict GCC C, CPU `0`, 7 interleaved reps. `central` needs no periodic coordinate remap; `shift_k_plus_1` adds one periodic neighbor.

| case | n | Wheelchair ms | C ms | speedup/C |
|---|---:|---:|---:|---:|
| central | 128 | 1.968378 | 3.914594 | 1.9887 |
| central | 192 | 6.213258 | 11.190883 | 1.8011 |
| central | 256 | 9.191718 | 21.686841 | 2.3594 |
| shift_k_plus_1 | 128 | 2.751778 | 4.007677 | 1.4564 |
| shift_k_plus_1 | 192 | 9.662635 | 10.072419 | 1.0424 |
| shift_k_plus_1 | 256 | 11.824123 | 21.965059 | 1.8576 |
