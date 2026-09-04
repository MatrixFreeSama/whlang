# Shared Dependency Episode 1.2.5 benchmark

This directory contains the public structural witnesses and authority summary for Wheelchair 1.2.5 Shared Dependency Episode Physicalization.

The witness uses a fluid/solid-style two-field operator, but the compiler optimization is not selected by physics or workload names. Admission is based on canonical structural pressure and dependency topology.

```text
Newton/Jv             5 -> legacy_1_2_4
global stiffness      6 -> legacy_1_2_4
decoupled two-field  11 -> shared_dependency_episode_wide_125
coupled two-field    12 -> shared_dependency_episode_wide_125
```

Formal authority run `33902157205` used two AVX-512-qualified AMD EPYC 9V74 hosts with zero qualified failures.

| Host | Median 1.2.4 -> 1.2.5 | Geomean 1.2.4 -> 1.2.5 | Geomean 1.2.5 / Expert C |
|---|---:|---:|---:|
| slot 2 | 2.4486x | 2.4478x | 1.3443x |
| slot 3 | 2.4508x | 2.4480x | 1.3445x |

All tested 1.2.4/1.2.5 two-field checksums were bit-identical. Expert C remained faster in aggregate on these AMD hosts. Coupled witness machine shape: hot instructions 491 -> 297, `VDIVPD` 26 -> 0, reachable generated hot `CALL` edges = 0.

Full proof material is frozen inside `dist/Wheelchair-1.2.5.zip`.
