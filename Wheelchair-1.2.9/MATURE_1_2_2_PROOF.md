# Wheelchair 1.2.2 maturation proof

## Release thesis

Wheelchair 1.2.2 promotes non-erasable Rank-N structure from compile-time preservation into a proof-gated native Cartesian product realization while preserving the established 1.2.1 Rank-1 technical peaks.

The release does **not** implement Rank-N as nested serial loops and does not authorize a scalar fallback. Source axes survive semantic analysis. Mathematically irrelevant axes are still eliminated first. If a supported non-erasable Rank-N domain remains, the compiler assigns each logical point a unique Cartesian product token `q`; executors partition that point domain directly and the AVX-512 evaluator reconstructs source coordinates from `q`.

## Physical rule

For a mature admitted domain with one dynamic extent `n` and static extra axes,

```text
(i, j, k, ...) <-> q
```

is a bijection over the Cartesian product. `q` is a physical point coordinate, not a sequential loop counter for hidden inner axes.

The current 1.2.2 native admission contract is intentionally conservative:

- exactly one external dynamic extent named `n`;
- exactly one dynamic `n` axis per realized Rank-N binding;
- additional extents must be positive compile-time powers of two;
- the terminal Cartesian point count must fit the existing proven physical-domain capacity;
- dynamic `periodic(..., n)` / `% n` inside a realized Rank-N expression is rejected in 1.2.2 rather than weakening the mature 1.2.1 periodic optimizer or introducing an unproved route.

Unsupported Rank-N shapes reject explicitly. They are never flattened into nested sequential loops and never retried through a scalar/general tensor path.

## Proof ordering

The release preserves the earlier mathematical-erasure law:

1. parse and preserve source Rank-N axes;
2. build Axis / Region / Effect / Ownership / Dependency semantics;
3. erase an axis only when expression independence proves it irrelevant;
4. only if non-erasable Rank-N remains, construct the Cartesian product physical token;
5. erase runtime axis/shape metadata before native execution.

Therefore a source such as

```text
sum total[i in n, j in 4]: f64 = cast(f64, i)
```

still collapses to the same Rank-1 canonical graph and byte-identical native ELF as its manually collapsed form. A genuinely used `j` now proceeds to native Rank-N realization instead of the historical Rank-1-realizer rejection.

## Native evidence

The authoritative `test_rank_n_122.sh` gate has been run on an AVX-512F-capable x86-64 host and reports:

```text
WHEELCHAIR_1_2_1_NATIVE_SOURCE_PEAK_BYTES=PASS
RANK_N_SEMANTIC_PRODUCT_PROOF=PASS
RANK6_GENERIC_SEMANTIC_PROOF=PASS
WH_WHEX_RANK_N_CANONICAL_EQUIVALENCE=PASS
RANK_N_CANONICAL_SINGLE_TOKEN_NO_SERIAL_NEST=PASS
RANK_N_UNPROVEN_LAYOUT_EXPLICIT_REJECTION=PASS
RANK2_STATIC_AXIS_NATIVE_REFERENCE=PASS
RANK2_DYNAMIC_AXIS_NATIVE_REFERENCE=PASS
RANK2_DIRECT_REDUCTION_NATIVE_REFERENCE=PASS
RANK2_NATIVE_CARTESIAN_REFERENCE_1_2_4_EXECUTORS=PASS
RANK3_NATIVE_CARTESIAN_REFERENCE_1_2_4_EXECUTORS=PASS
RANK6_NATIVE_GENERIC_REFERENCE_1_2_4_EXECUTORS=PASS
WH_WHEX_RANK2_NATIVE_EQUIVALENCE=PASS
RANK_N_AVX512_COORDINATE_RECOVERY=PASS
RANK_N_GENERATED_RX_CALL_EDGES=0
RANK_N_SCALAR_FALLBACK=0
WHEX_RANK_N_AXIS_ERASURE=PASS
WHEX_RANK_N_MACHINE_CODE_ERASURE=PASS
RANK_N_ERASURE_PRECEDENCE_NONREGRESSION=PASS
RANK_N_1_1_REJECTION_SUPERSEDED_BY_NATIVE_1_2_2=PASS
RANK_N_NO_FAKE_FLATTEN=PASS
INTERIOR_PERIODIC_1_2_1_TECHNICAL_PEAK_PROTECTED=PASS
NEWTON_JV_1_2_1_TECHNICAL_PEAK_PROTECTED=PASS
WHEELCHAIR_RANK_N_1_2_2=PASS
```

The native reference corpus includes Rank-2, Rank-3 and Rank-6 programs. Rank-2/3/6 are executed with 1, 2 and 4 executors and return the exact expected checksum bits. Rank-6 is evidence that the implementation is driven by generic axis/product algebra rather than a dedicated Rank-2 or Rank-3 workload branch.

## Generated machine-code audit

The final runtime erases ordinary ELF section headers after AOT emission, so the test extracts the third `PT_LOAD`, which `tensor_runtime.ld` defines as the generated RX segment, and disassembles those exact bytes as x86-64.

For the dynamic-axis Rank-2 witness:

```text
RANK_N_AVX512_COORDINATE_RECOVERY=PASS
RANK_N_GENERATED_RX_CALL_EDGES=0
RANK_N_SCALAR_FALLBACK=0
```

The coordinate recovery uses the existing AVX-512F `VPSRLQ` primitive. No generated `CALL` edge is permitted inside the fused evaluator.

## WH / WHEX equivalence

WH and WHEX share the same `rank_n_product` physicalizer. Equivalent Rank-2 WH/WHEX sources produce the same physical canonical graph and the same native result. There is no separate semantic Rank-N implementation hidden behind the easier WH surface.

## Technical Peak Preservation Contract

1.2.2 protects the 1.2.1 native peak in two independent ways.

First, the mature Rank-1 native source triplet is byte-frozen before the Rank-N derived backend is generated:

```text
compiler/tensor_frontend_x86_64.S
compiler/topologyc_x86_64.S
runtime/tensor_runtime_template_x86_64.S
```

Their exact 1.2.1 SHA-256 values are release gates. The Rank-N backend is derived only after those hashes match.

Second, the release reruns both mature 1.2.1 witnesses:

```text
WHEX_INTERIOR_PERIODIC_COMPOSITION_1_2_1=PASS
NEWTON_JV_10M_100M_EXECUTOR_EQUIVALENCE=PASS
```

Thus the Rank-N capability is not purchased by flattening the 1.2.1 Newton/Jv or periodic-neighborhood machine-code peak into a slower common path.

## No hidden Von-Neumann fallback

The 1.2.2 Rank-N proof requires:

```text
serial inner-axis loops = 0
generated RX call edges = 0
scalar tensor fallback = 0
runtime Rank-N shape objects = 0
runtime Rank-N axis metadata objects = 0
```

The executor fabric remains the existing causal binary topology. Rank-N changes the independent point domain presented to that fabric; it does not introduce a master loop, global queue, root spawn-all/wait-all sweep, global barrier, or sequential inner-axis dispatcher.

## Claim boundary

1.2.2 proves the released product-domain family and the tested Rank-2, Rank-3 and Rank-6 native witnesses. It does not claim that every possible dynamic Rank-N shape, arbitrary non-power-of-two extra extent, multiple independent dynamic extents, or Rank-N dynamic-periodic topology is already native. Those cases remain explicit rejections until equally strong physical proofs exist.

The important boundary moved from:

```text
non-erasable Rank-N -> reject
```

to:

```text
non-erasable supported Rank-N -> native Cartesian product topology
unproved Rank-N -> explicit reject
```

without introducing hidden serial execution.
