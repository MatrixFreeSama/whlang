# Wheelchair 1.2.2 release proof

## Final release target

Wheelchair 1.2.2 is the native Rank-N maturation release. Its release authority is `test_complete_122.sh`, with the dedicated physical gate `test_rank_n_122.sh`.

A release package may be produced only after an AVX-512F-capable x86-64 validation host reports both:

```text
WHEELCHAIR_RANK_N_1_2_2=PASS
WHEELCHAIR_1_2_2_COMPLETE=PASS
```

and the packaging stage subsequently re-extracts the archive and verifies its internal `SHA256SUMS`.

## What changed

- non-erasable supported Rank-N domains can now execute natively;
- source Rank-N semantics remain intact through semantic proof;
- irrelevant axes still disappear mathematically before physical realization;
- remaining supported axes are represented by a bijective Cartesian product token rather than nested loops;
- Rank-N coordinate recovery is emitted into the fused AVX-512 generated RX kernel;
- WH and WHEX use one shared Rank-N product physicalizer;
- old Rank-1 native sources remain byte-frozen and continue to carry the 1.2.1 technical peak.

## Native Rank-N gates

The mature gate requires Rank-2, Rank-3 and Rank-6 exact native references at 1/2/4 executors, plus independent static-axis, dynamic-axis and direct-reduction probes. It also audits the generated RX `PT_LOAD` directly and requires:

```text
RANK_N_GENERATED_RX_CALL_EDGES=0
RANK_N_SCALAR_FALLBACK=0
RANK_N_NO_FAKE_FLATTEN=PASS
```

## Historical Rank-N compatibility

The 1.1.0 rule that an irrelevant extra axis must erase to Rank-1 remains active and byte-identical. The older rule that every genuinely used second axis must reject is not a semantic invariant; it was a physical limitation of the former Rank-1 realizer and is intentionally superseded in 1.2.2.

## Technical-peak protection

The release freezes the exact 1.2.1 source hashes for the mature Rank-1 tensor frontend, topology compiler and runtime before deriving the Rank-N physical lane. It then reruns the mature Interior Periodic Composition and Newton/Jv gates. Rank-N therefore cannot silently rewrite the established Rank-1 hot path.

## Claim boundary

The 1.2.2 native Rank-N admission family currently requires one dynamic `n` axis and positive power-of-two compile-time extra extents within the proven physical point capacity. Dynamic Rank-N `% n` / `periodic(..., n)`, arbitrary non-power-of-two extra extents and multiple dynamic extent families remain explicit rejections.

No release claim is made beyond those proof boundaries.
