# Wheelchair 1.2.4

## Theme: generic native structural contraction and reduction residency

Wheelchair 1.2.4 is a native-code generation release over the mature Rank-N and Global Coupled Operator / Sparse Causal Expansion architecture.

### Accepted generic upgrades

- Added tolerant-only Product-Subtract Contraction: structurally proven `a - (b * c)` may lower to `VFNMADD231PD` without workload-name dispatch.
- Added Vector Reduction Residency: qualified eight-lane AVX-512 reductions remain in a resident ZMM accumulator across full SIMD blocks and collapse only at chunk completion.
- The global stiffness benchmark is only a validation workload. A mathematically identical synthetic program with non-physical names emits byte-identical native output at 1/2/4 executors.
- The frozen handwritten tensor frontend, topology compiler core, and runtime source remain SHA-protected. 1.2.4 derives its accepted assembly frontend from that frozen base at build time.
- Newton/Jv does not match the new structural recipe and remains byte-identical to the mature baseline at 1/2/4 executors.
- Rank-N 1.2.2 and Sparse Causal Expansion 1.2.3 mature gates are rerun and preserved.
- Generated optimized operator RX contains zero call edges and zero scalar fallback.
- The build-time Python derivation tools are not a user-program backend or runtime; native-sovereignty gates explicitly restrict them to exact hash-protected assembly derivation.

### Performance evidence

The release accepts performance changes only from same-host frozen-baseline versus optimized Wheelchair measurements. Cross-vendor and cross-generation absolute times are recorded as hardware evidence, not used to select the generic backend.

Authority run `33879496682` completed three AVX-512-qualified hosts with no qualified failure. Across 10M/100M points and 1/2/4 executors, the aggregate frozen-baseline to 1.2.4 speedups were:

- AMD EPYC 9V74, family 25/model 17: median 1.1923x, geomean 1.1935x;
- AMD EPYC 9V45, family 26/model 2: median 1.0934x, geomean 1.0930x;
- AMD EPYC 9V74, family 25/model 17: median 1.1907x, geomean 1.1949x.

All authority numerical spreads between baseline, optimized Wheelchair and the matched expert-C control were zero at the reported checksum precision.

### Rejected experiments

The release intentionally does not include several explored recipes that failed the Technical Peak Preservation Contract or did not show stable benefit:

- runtime branch-striped reduction;
- full-block tail-gate fusion as a default recipe;
- 2x static fused-block unroll;
- replacing the mature 512-bit physical lane with a 256-bit lane.

The principle is explicit: a more elaborate implementation is not an upgrade unless it produces demonstrated benefit without degrading established peaks.

### Final gates

```text
GENERIC_NATIVE_NO_WORKLOAD_DISPATCH=PASS
GENERIC_NATIVE_RENAMED_NATIVE_BYTE_EQUIVALENCE=PASS
GENERIC_PRODUCT_SUBTRACT_CONTRACTION=PASS
GENERIC_VECTOR_REDUCTION_RESIDENCY=PASS
GENERIC_NATIVE_GENERATED_CALL_EDGES=0
GENERIC_NATIVE_SCALAR_FALLBACK=0
NEWTON_JV_NATIVE_BYTE_IDENTITY_ON_1_2_4=PASS
RANK_N_1_2_2_TECHNICAL_PEAK_PROTECTED_ON_1_2_4=PASS
SCE_1_2_3_TECHNICAL_PEAK_PROTECTED_ON_1_2_4=PASS
WHEELCHAIR_1_2_4_COMPLETE=PASS
WHEELCHAIR_1_2_4_QUORUM=PASS
```
