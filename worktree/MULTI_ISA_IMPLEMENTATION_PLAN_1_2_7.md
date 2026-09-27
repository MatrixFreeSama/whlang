# 1.2.7 implementation plan

This file intentionally records the implementation sequence so validation can reject partial physicalization.

1. Extend generic ISA capability algebra with physical-width shape bits.
2. Add CPUID-based microarchitecture shape classification independent of workload identity.
3. Add native 256-bit tensor realization for AVX2/FMA hosts.
4. Add split-512-over-256 scheduling shape for Zen 4 class hosts.
5. Preserve 1.2.6 native-512 bytes for native-512 hosts.
6. Add architecture-neutral release gates that verify no workload names or runtime profitability selectors participate in routing.
7. Benchmark Intel AVX2, Intel AVX-512, AMD Zen3, Zen4 and Zen5 witnesses when qualified runners are available.
