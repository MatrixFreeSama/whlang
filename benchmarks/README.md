# Benchmarks

This directory contains reproducible benchmark sources, controls, configurations, and measured result summaries for Wheelchair.

## Newton / Jacobian-vector product

`newton_jv/`

A mature compute-heavy benchmark used to compare Wheelchair native realization with matched and explicit AVX-512 expert-C controls.

## Global stiffness degradation resistance

`degradation_resistance_global_stiffness/`

A coordination-heavy matrix-free global-stiffness action used to compare:

- Wheelchair 1.2.4;
- matched expert C;
- Java 25 HotSpot;
- Taichi 1.7.4 CPU.

This benchmark is intentionally useful as a non-ideal or hostile workload rather than a best-case showcase. It studies how much throughput each execution model retains around periodic neighbor coupling, reduction, and global coordination pressure.

See `degradation_resistance_global_stiffness/README.md` for methodology, numerical checks, two-host results, limitations, and the definition of observed degradation resistance.
