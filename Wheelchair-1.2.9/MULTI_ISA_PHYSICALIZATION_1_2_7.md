# Wheelchair 1.2.7 Multi-ISA Physicalization Charter

Wheelchair 1.2.7 extends the 1.2.6 General Parallel Fabric down into multiple mature x86 physical execution widths.

## Core rule

General semantics are ISA-neutral. Physical realization is selected from proven hardware capabilities and microarchitectural shape, never workload identity.

## Physical width classes

- `native256`: AVX2/FMA-capable 256-bit execution with complete tensor physicalization.
- `split512x256`: AVX-512 semantics on a physical 2x256 datapath.
- `native512`: AVX-512 semantics on a physical 512-bit datapath.
- `scalar128_compat`: compatibility-only seed/utility lane; it is not a fallback for tensor workloads.

## Initial architecture coverage

- Intel client AVX2-only families: `native256`.
- Intel Xeon AVX-512 families with native 512-bit execution: `native512`.
- AMD Zen 3: `native256`.
- AMD Zen 4 / Zen 4c: `split512x256`.
- AMD Zen 5 / Zen 5c: `native512`.

The implementation may use exact CPUID matches only to establish physical datapath shape. Workload names, benchmark names and source paths are forbidden inputs.

## Red lines

- no runtime profitability selector;
- no scalar fallback for tensor semantics;
- no workload-name fast path;
- no global scheduler resurrection;
- 1.2.6 base/wide/derived AVX-512 execution bytes remain protected when the `native512` profile is selected;
- weaker-width realizers must be real native physicalizers, not rejected stubs.
