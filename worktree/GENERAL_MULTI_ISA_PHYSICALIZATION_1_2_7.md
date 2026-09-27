# Wheelchair 1.2.7 General Multi-ISA Physicalization

Wheelchair 1.2.7 generalizes native physicalization without introducing a workload-specific backend.

## 1. Two orthogonal compile-time dimensions

The AOT compiler binds exactly two independent facts:

1. **Generic graph-resource class**: `base`, `wide`, or `derived`.
2. **Physical vector shape**: `native256`, `split512x256`, or `native512`.

The resulting physicalizer space is the Cartesian product of those dimensions. A program name, source path, benchmark identity, solver name, physics domain, runtime timing, or measured profitability is never a routing key.

## 2. Sovereign hardware authority

`topologyc --silicon-audit` is the hardware authority. Surface drivers may read that native audit during AOT compilation and bind an already-built compiler image, but Python is not the native backend authority and does not emit the user program machine code.

`--isa-limit` is only a compile-time capability ceiling. In particular, `--isa-limit avx2` selects the generic `native256` physicalizer. Higher ceilings never manufacture AVX-512 on hardware whose native audit proves only a 256-bit execution shape.

## 3. Physical shapes

### native256

A first-class AVX2/YMM physicalization with four binary64 lanes. Tail masking, predicates, integer multiply, unsigned minimum, integer/floating conversion, reduction, constants, and cross-vector state are realized by vector-native or vector-synthesized operations. Scalar fallback is forbidden.

### split512x256

The semantic episode may remain 512-bit while the resource scheduler accounts for two 256-bit physical slices. This is a physical execution-shape model, not a workload route.

### native512

The mature AVX-512 physicalizer is retained. Existing qualified 1.2.6 execution bytes are protected by a byte-identity gate where a qualified AVX-512 host is available.

## 4. Parallel execution invariants

The 1.2.6 schedulerless causal and general parallel fabrics remain authoritative. 1.2.7 changes physical vector realization, not the causal execution doctrine.

The following remain forbidden:

- global ready queue;
- root scheduler;
- hidden serial fallback;
- runtime profitability selector;
- workload-specific dispatch;
- benchmark-specific dispatch;
- source-path dispatch;
- work stealing introduced merely to compensate for a centralized scheduler;
- avoidable global phase barriers.

## 5. Technical Peak Preservation Contract

A new physicalizer is admitted only if it does not flatten a mature narrower peak. The native-512 path therefore remains byte-protected against the qualified 1.2.6 implementation, while native256 is added as an independent first-class physical realization instead of replacing the mature 512 path.

Generalization means expanding the set of hardware shapes that can realize the same semantics. It does not mean averaging all hardware into one lowest-common-denominator backend.

## 6. Completion evidence

The 1.2.7 release gate requires all of the following in one validation run:

- base/wide/derived native256 compilers assemble and link as static ELF;
- a workload-neutral WHEX program is AOT-compiled through `native256`;
- the generated ELF executes on real AVX2 hardware for full and partial vector tails;
- the generated native256 ELF contains YMM vector state and no ZMM/opmask state;
- automatic driver selection agrees with the sovereign native silicon audit;
- Intel/AMD synthetic profile classification remains consistent with the native classifier;
- 1.2.6 schedulerless/general-parallel gates remain green;
- qualified native-512 execution bytes remain identical to the protected 1.2.6 path;
- active special-purpose, workload-specific, benchmark-specific, runtime-profitability, and scalar-fallback routes are all zero.
