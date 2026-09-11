# Wheelchair 1.0.14 ISA Capability Generalization Proof

## Scope

1.0.14 generalizes WHEX ISA-specific strengths into semantic capabilities without introducing workload/solver dispatch and without introducing a scalar fallback for tensor regions. The current physical tensor realizer remains 512-bit; this release does not claim a completed AVX2 256-bit tensor backend.

## Capability algebra

Raw CPUID classes contribute semantic capabilities rather than selecting WHEX semantics directly. The model includes 256/512-bit vector classes, predication, masked tail, broadcast, gather, FMA, i64 vector multiply, i64/f64 conversion, predicate-to-i64-mask materialization, cross-vector persistent state, and reduction-tree support.

The 512-bit tensor gate is `ISA_CAP_TENSOR512_BASE`, not an AVX-512DQ+VL bundle. AVX-512VL is therefore not a semantic requirement for the current 512-bit realizer.

## Promoted AVX-512DQ capabilities

### i64 vector multiply

- Native realization: `VPMULLQ`.
- AVX-512F foundation realization: exact 32-bit decomposition using `VPMULUDQ`, shifts and additions modulo 2^64.

### signed i64 -> f64

- Native realization: `VCVTQQ2PD`.
- AVX-512F foundation realization: signed high 32-bit plus unsigned low 32-bit reconstruction, `VCVTDQ2PD`, exact 2^32 scaling, then one final binary64 addition/rounding point.

### proven nonnegative f64 -> u64 truncation

For the exact-modulo quotient domain already proved nonnegative and bounded, AVX-512F uses truncate-to-integral floating point plus exact-bias bit extraction instead of requiring `VCVTTPD2QQ`. The proof obligation belongs to the expression/property layer; the ISA recipe cannot apply without it.

### predicate -> i64 all-ones/zero

- Native realization: `VPMOVM2Q`.
- AVX-512F foundation realization: load scalar -1 and use predicated zeroing `VPBROADCASTQ zmmDST{k1}{z},rax`.

The final 1.0.14 blocker was a physical EVEX encoding bug in this synthesized predicate recipe. The P0 byte initially encoded only one destination high-register bit. The final implementation encodes both inverted destination extension bits, so ZMM0..31 all preserve the same predicate semantics.

## Differential validation

`test_114.sh` forces both native and `--isa-limit avx512f` realizations and compares output on:

- control-heavy periodic heat/select boundaries;
- sparse nonlinear indexed operators;
- FEM linear aggregation;
- odd/non-aligned extents including 1025, 2049 and 4097 where applicable;
- one-executor and four-executor foundation execution.

The forced AVX-512F generated segment is disassembled and release-gated against DQ-only `VPMULLQ`, `VCVTQQ2PD`, `VCVTTPD2QQ`, and `VPMOVM2Q`. It is also required to contain foundation primitives including `VPMULUDQ`, `VCVTDQ2PD`, and predicated `VPBROADCASTQ`.

## Explicit AVX2 boundary

AVX2 contributes 256-bit FP/integer/gather/masked-memory and synthesis-related capabilities to the model. 1.0.14 does not fabricate a 256-bit tensor backend. `--isa-limit avx2` therefore rejects a tensor512 program explicitly. It does not route to a scalar evaluator.

## Parallelism invariants

Inherited gates remain green:

- `TENSOR_HIDDEN_SCALAR_FALLBACK=0`;
- `PARALLEL_SCALAR_FALLBACK=0`;
- `CENTRAL_SPAWN_LOOP=0`;
- `CENTRAL_WAIT_LOOP=0`;
- `CENTRAL_REDUCTION_LOOP=0`;
- `GLOBAL_TASK_QUEUE=0`;
- fused evaluator episode and cross-vector induction remain active.

## Release-gate results

The 1.0.14 gate reports:

```text
ISA_CAPABILITY_ALGEBRA=PASS
AVX512F_FOUNDATION_NUMERIC=PASS
AVX512F_FOUNDATION_EXECUTOR_EQUIVALENCE=PASS
AVX512VL_NOT_REQUIRED=PASS
AVX512F_RECIPE_AUDIT=PASS
AVX2_NO_SCALAR_EMULATION=PASS
ISA_GENERALIZATION_NO_WORKLOAD_DISPATCH=PASS
ISA_GENERALIZATION_SCALAR_FALLBACK=0
WHEX_ISA_CAPABILITY_GENERALIZATION_1_0_14=PASS
```

The full inherited release composition was re-run component-by-component in the execution environment because the monolithic `test_complete.sh` exceeds one tool invocation window. Every component gate completed with zero exit status; no failed assertion was bypassed.
